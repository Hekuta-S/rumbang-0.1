"""Tema adaptativo de SUPERVIVENCIA: empieza chill y se vuelve hard con el tiempo de partida.

Genera 4 pistas (stems) de la MISMA canción, misma duración y tempo, que el juego reproduce a la vez con
AudioStreamSynchronized y va subiendo una a una (scripts/core/survival_music.gd):
  0 base   (chill)  pads cálidos, piano eléctrico FM, sub bajo y campana con el motivo
  1 groove          bombo lo-fi, aro, charles en corcheas y arpegio pulsado
  2 drive           bajo pulsado en semicorcheas, palmas, charles abierto y melodía principal
  3 hard            riff distorsionado (quintas), bombo a negras, platos, semicorcheas y redobles

Re menor, 110 BPM, 32 compases (~70 s) en bucle perfecto: notas, eco y reverb se envuelven circularmente,
así que el final empalma con el principio sin clic. Las 4 pistas se normalizan JUNTAS (la mezcla completa
llega a -1 dBFS) para que al sumarlas en el juego suenen como una sola canción.

Uso:  python tools/generate_survival_soundtrack.py   (después: godot --headless --path . --import)
Salida: assets/audio/survival/surv_{0_base,1_groove,2_drive,3_hard}.wav (estéreo, 32 kHz, 16 bits)
Solo necesita numpy.
"""
import os
import wave

import numpy as np

RATE = 32000
BPM = 110.0
BEAT = 60.0 / BPM
BAR = BEAT * 4.0
BARS = 32
N = int(round(BAR * BARS * RATE))
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "survival")
STEMS = ["surv_0_base", "surv_1_groove", "surv_2_drive", "surv_3_hard"]

rng = np.random.default_rng(1107)

# acorde: [raíz del bajo (MIDI), voces del pad]
CH = {
    "Dm": [38, [62, 65, 69, 72]],   # Dm7
    "Bb": [34, [58, 62, 65, 69]],   # Bbmaj7
    "F": [41, [57, 60, 65, 69]],
    "C": [36, [55, 60, 64, 67]],
    "Gm": [43, [55, 58, 62, 65]],   # Gm7
    "A": [45, [57, 61, 64, 67]],    # A7 (la sensible C# vuelve a Re)
}
PROG = ["Dm", "Dm", "Bb", "Bb", "F", "F", "C", "C",
        "Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A",
        "Bb", "C", "Dm", "Dm", "Bb", "C", "A", "A",
        "Gm", "Bb", "Dm", "C", "Bb", "Gm", "A", "A"]

# [MIDI, corcheas]; 0 = silencio. Campana (base) en los compases 0-15, melodía (drive) en 16-31.
BELL = [
    [[69, 3], [72, 1], [74, 4]], [[0, 8]], [[70, 3], [69, 1], [65, 4]], [[0, 8]],
    [[69, 3], [72, 1], [77, 4]], [[76, 4], [72, 4]], [[74, 6], [72, 2]], [[0, 8]],
    [[69, 3], [72, 1], [74, 4]], [[0, 8]], [[70, 3], [69, 1], [65, 4]], [[0, 8]],
    [[70, 3], [69, 1], [67, 4]], [[0, 8]], [[69, 2], [73, 2], [76, 4]], [[0, 8]],
]
LEAD = [
    [[74, 2], [77, 2], [74, 2], [72, 2]], [[72, 3], [70, 1], [67, 4]],
    [[69, 2], [74, 2], [77, 2], [81, 2]], [[79, 4], [77, 2], [76, 2]],
    [[74, 2], [77, 2], [74, 2], [72, 2]], [[76, 3], [77, 1], [79, 4]],
    [[81, 4], [79, 2], [76, 2]], [[73, 6], [76, 2]],
    [[79, 2], [77, 2], [74, 2], [70, 2]], [[74, 3], [77, 1], [74, 4]],
    [[81, 2], [77, 2], [74, 2], [77, 2]], [[76, 4], [72, 4]],
    [[74, 2], [70, 2], [74, 2], [77, 2]], [[79, 4], [82, 4]],
    [[81, 3], [79, 1], [76, 4]], [[73, 4], [76, 2], [81, 2]],
]


def freq(m):
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


class Stem:
    """Bus estéreo con envíos de eco y reverb; todo se suma con índice circular (bucle sin costura)."""

    def __init__(self):
        self.L = np.zeros(N)
        self.R = np.zeros(N)
        self.rev = np.zeros(N)
        self.dly = np.zeros(N)

    def add(self, t, sig, pan=0.0, rev=0.0, dly=0.0):
        i0 = int(round(t * RATE)) % N
        gl = np.sqrt(0.5 * (1.0 - pan)) * 1.414
        gr = np.sqrt(0.5 * (1.0 + pan)) * 1.414
        for buf, g in ((self.L, gl), (self.R, gr), (self.rev, rev), (self.dly, dly)):
            if g:
                _wrap_add(buf, i0, sig * g)

    def render(self, rev_mix, dly_beats=0.75, dly_fb=0.42):
        L, R = self.L.copy(), self.R.copy()
        if np.any(self.dly):
            d = int(BEAT * dly_beats * RATE)
            tap = _lowpass(self.dly, 3500.0)
            for k in range(1, 6):          # eco ping-pong: impares a la izquierda, pares a la derecha
                g = dly_fb ** k * 0.7
                (L if k % 2 else R)[:] += np.roll(tap, k * d) * g
        if np.any(self.rev):
            L += _circ_conv(self.rev, IR_L) * rev_mix
            R += _circ_conv(self.rev, IR_R) * rev_mix
        return L, R


def _wrap_add(buf, i0, sig):
    """Suma `sig` desde `i0`; lo que se pasa del final entra por el principio (bucle sin costura).
    Por tramos y no con np.add.at: mucho más rápido (la primera versión tardaba 24 min)."""
    pos = 0
    while pos < len(sig):
        start = (i0 + pos) % N
        take = min(len(sig) - pos, N - start)
        buf[start:start + take] += sig[pos:pos + take]
        pos += take


def _lowpass(x, fc):
    """Paso bajo de fase cero por FFT (circular, como todo lo demás)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    return np.fft.irfft(X / np.sqrt(1.0 + (f / fc) ** 4), len(x))


def _highpass(x, fc):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    h = (f / fc) ** 2 / np.sqrt(1.0 + (f / fc) ** 4)
    return np.fft.irfft(X * h, len(x))


def _make_ir(seed, secs=2.2):
    r = np.random.default_rng(seed)
    t = np.arange(int(secs * RATE)) / RATE
    ir = r.standard_normal(len(t)) * np.exp(-t * 3.2)
    ir[: int(0.012 * RATE)] = 0.0       # pre-delay
    full = np.zeros(N)
    full[: len(ir)] = ir
    full = _lowpass(full, 5000.0)
    return np.fft.rfft(full / np.sqrt(np.sum(full ** 2)))


IR_L = _make_ir(11)
IR_R = _make_ir(29)


def _circ_conv(x, IR):
    return np.fft.irfft(np.fft.rfft(x) * IR, N)


def tt(dur):
    return np.arange(int(dur * RATE)) / RATE


def env_ad(t, dur, att=0.005, rel=0.05):
    a = np.minimum(t / att, 1.0)
    r = np.clip((dur - t) / rel, 0.0, 1.0)
    return a * r


def noise(n):
    return rng.uniform(-1.0, 1.0, n)


def saw_add(f, t, max_h=40, cutoff=6000.0, decay_k=None):
    """Sierra aditiva limitada en banda; `decay_k` cierra el "filtro" con el tiempo (armónicos altos caen antes)."""
    s = np.zeros(len(t))
    for k in range(1, max_h + 1):
        fk = f * k
        if fk > min(cutoff, RATE * 0.45):
            break
        a = 1.0 / k
        if decay_k is not None:
            a = a * np.exp(-t * decay_k * (k - 1))
        s += a * np.sin(2 * np.pi * fk * t)
    return s


# ───────────────────────────── STEM 0: base (chill) ─────────────────────────────

def stem_base():
    st = Stem()
    for b, ch in enumerate(PROG):
        t0 = b * BAR
        root, notes = CH[ch]
        # pad: sierra suave desafinada, ataque lento
        if b == 0 or PROG[b - 1] != ch:
            span = 1
            while b + span < BARS and PROG[b + span] == ch:
                span += 1
            dur = span * BAR + 0.25
            t = tt(dur)
            e = np.minimum(t / 0.8, 1.0) * np.clip((dur - t) / 0.6, 0, 1)
            for j, m in enumerate(notes):
                f = freq(m)
                s = saw_add(f * 0.997, t, 14, 1300.0) + saw_add(f * 1.004, t, 14, 1300.0)
                st.add(t0, s * e * 0.030, pan=-0.5 if j % 2 else 0.5, rev=0.05)
            # sub bajo largo
            fb = freq(root)
            s = np.sin(2 * np.pi * fb * t) + 0.18 * np.sin(4 * np.pi * fb * t)
            st.add(t0, s * np.minimum(t / 0.05, 1) * np.clip((dur - 0.2 - t) / 0.3, 0, 1) * 0.20)
        # piano eléctrico FM: acorde sincopado (tiempo 1 y "y" del 2)
        for hit_t, vel in ((0.0, 1.0), (1.5 * BEAT, 0.7), (3.0 * BEAT, 0.5)):
            dur = BEAT * 1.6
            t = tt(dur)
            for m in notes[:3]:
                f = freq(m)
                mod = 1.6 * np.exp(-t * 6.0) * np.sin(2 * np.pi * f * t)
                s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 2.4) * env_ad(t, dur, 0.003, 0.1)
                st.add(t0 + hit_t, s * 0.040 * vel, pan=0.15, rev=0.06, dly=0.05)
        # vinilo: crujido y siseo muy bajo
        t = tt(BAR)
        hiss = _bandnoise(len(t), 3000.0) * 0.004
        st.add(t0, hiss, pan=0.0)
        for _ in range(rng.integers(2, 6)):
            st.add(t0 + rng.uniform(0, BAR), noise(40) * np.exp(-np.arange(40) / 8.0) * 0.04, pan=rng.uniform(-0.6, 0.6))
    # campana con el motivo (primera mitad)
    for bi, bar_notes in enumerate(BELL):
        t = bi * BAR
        for m, eighths in bar_notes:
            d = eighths * BEAT / 2.0
            if m:
                _bell(st, t, m, 0.06)
            t += d
    L, R = st.render(rev_mix=0.55, dly_fb=0.45)
    return L, R


def _bandnoise(n, fc):
    x = noise(n)
    return np.diff(np.concatenate([[0.0], x])) * 0.5 if fc > 1000 else x


def _bell(st, t0, m, vol):
    dur = 2.2
    t = tt(dur)
    f = freq(m)
    mod = 2.0 * np.exp(-t * 3.0) * np.sin(2 * np.pi * f * 3.5 * t)
    s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 1.6) * env_ad(t, dur, 0.002, 0.3)
    st.add(t0, s * vol, pan=-0.2, rev=0.25, dly=0.25)


# ───────────────────────────── percusión común ─────────────────────────────

def kick(st, t0, vol, punch=1.0, length=0.38):
    t = tt(length)
    f = 46.0 + 95.0 * punch * np.exp(-t * 32.0)
    ph = 2 * np.pi * np.cumsum(f) / RATE
    s = np.sin(ph) * np.exp(-t * (7.0 + 3.0 * punch))
    click = noise(len(t)) * np.exp(-t * 400.0) * 0.25 * punch
    st.add(t0, (s + click) * vol)


def snare(st, t0, vol, tone=185.0, rev=0.12):
    t = tt(0.25)
    nz = np.diff(np.concatenate([[0.0], noise(len(t))])) * np.exp(-t * 16.0)
    body = np.sin(2 * np.pi * tone * t) * np.exp(-t * 22.0)
    st.add(t0, (nz * 0.55 + body * 0.6) * vol, pan=0.05, rev=rev)


def rim(st, t0, vol):
    t = tt(0.06)
    s = (np.sin(2 * np.pi * 1700 * t) + 0.6 * np.sin(2 * np.pi * 820 * t)) * np.exp(-t * 90.0)
    st.add(t0, s * vol, pan=0.2, rev=0.1)


def hat(st, t0, vol, length=0.045, pan=0.3):
    t = tt(length)
    x = noise(len(t) + 2)
    hp = x[2:] - 2 * x[1:-1] + x[:-2]
    st.add(t0, hp * 0.25 * np.exp(-t * (6.0 / length)) * vol, pan=pan)


def clap(st, t0, vol):
    t = tt(0.3)
    x = np.diff(np.concatenate([[0.0], noise(len(t))]))
    e = np.zeros(len(t))
    for off in (0.0, 0.011, 0.023):
        e += np.where(t >= off, np.exp(-(t - off) * 70.0), 0.0) * 0.5
    e += np.exp(-t * 14.0) * 0.6
    st.add(t0, x * e * vol, pan=-0.05, rev=0.25)


def crash(st, t0, vol):
    t = tt(2.4)
    x = noise(len(t) + 2)
    hp = x[2:] - 2 * x[1:-1] + x[:-2]
    st.add(t0, hp * 0.2 * np.exp(-t * 1.6) * vol, pan=-0.3, rev=0.15)


def tom(st, t0, vol, f0):
    t = tt(0.35)
    f = f0 * (1.0 + 0.6 * np.exp(-t * 25.0))
    s = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 9.0)
    st.add(t0, s * vol, pan=rng.uniform(-0.4, 0.4), rev=0.12)


# ───────────────────────────── STEM 1: groove ─────────────────────────────

def stem_groove():
    st = Stem()
    for b, ch in enumerate(PROG):
        t0 = b * BAR
        # bombo lo-fi (1 y "y" del 3), aro en 2 y 4, charles en corcheas con swing
        kick(st, t0, 0.55, punch=0.6)
        kick(st, t0 + 2.5 * BEAT, 0.45, punch=0.6)
        if b % 4 == 3:
            kick(st, t0 + 3.5 * BEAT, 0.35, punch=0.5)
        rim(st, t0 + BEAT, 0.20)
        rim(st, t0 + 3 * BEAT, 0.20)
        for e in range(8):
            sw = 0.06 * BEAT if e % 2 else 0.0
            hat(st, t0 + e * BEAT / 2 + sw, 0.32 if e % 2 == 0 else 0.20)
        # arpegio pulsado (triángulo) en corcheas
        notes = CH[ch][1]
        tones = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24]
        pat = [0, 1, 2, 3, 2, 1, 2, 1]
        for e in range(8):
            m = tones[pat[e]]
            dur = BEAT * 0.9
            t = tt(dur)
            f = freq(m)
            tri = np.zeros(len(t))
            for k in (1, 3, 5, 7):
                tri += ((-1) ** ((k - 1) // 2)) / (k * k) * np.sin(2 * np.pi * f * k * t)
            s = tri * np.exp(-t * 5.0) * env_ad(t, dur, 0.003, 0.05)
            st.add(t0 + e * BEAT / 2, s * 0.055, pan=-0.35 if e % 2 == 0 else 0.35, rev=0.08, dly=0.3)
    return st.render(rev_mix=0.4, dly_fb=0.4)


# ───────────────────────────── STEM 2: drive ─────────────────────────────

def _duck_env(depth=0.55):
    """Envolvente de "sidechain": se agacha en cada negra (el bombo del hard / el pulso del drive)."""
    t = (np.arange(N) / RATE) % BEAT
    return 1.0 - depth * np.exp(-t * 11.0)


def stem_drive():
    st = Stem()
    for b, ch in enumerate(PROG):
        t0 = b * BAR
        root = CH[ch][0]
        # bajo pulsado en semicorcheas, "filtro" que se cierra en cada nota
        for s16 in range(16):
            m = root + (12 if s16 % 4 == 2 else 0)
            dur = BEAT / 4 * 0.92
            t = tt(dur)
            s = saw_add(freq(m), t, 24, 3000.0, decay_k=9.0) * env_ad(t, dur, 0.002, 0.02)
            st.add(t0 + s16 * BEAT / 4, s * 0.10)
        # palmas en 2 y 4, charles abierto a contratiempo
        clap(st, t0 + BEAT, 0.35)
        clap(st, t0 + 3 * BEAT, 0.35)
        for q in range(4):
            hat(st, t0 + q * BEAT + BEAT / 2, 0.30, length=0.18, pan=-0.25)
        # primera mitad: arpegio de sierra en semicorcheas (anticipa la melodía)
        if b < 16:
            notes = CH[ch][1]
            seq = [notes[0] + 12, notes[2] + 12, notes[1] + 12, notes[3] + 12]
            for s16 in range(16):
                if s16 % 2 and b % 2 == 0:
                    continue
                dur = BEAT / 4 * 0.8
                t = tt(dur)
                s = saw_add(freq(seq[s16 % 4]), t, 12, 4500.0, decay_k=14.0) * env_ad(t, dur, 0.002, 0.02)
                st.add(t0 + s16 * BEAT / 4, s * 0.028, pan=0.4 if s16 % 2 else -0.4, dly=0.35)
    # melodía principal (segunda mitad): sierra con vibrato, doblada a la octava
    for bi, bar_notes in enumerate(LEAD):
        t = (16 + bi) * BAR
        for m, eighths in bar_notes:
            d = eighths * BEAT / 2.0
            if m:
                _lead(st, t, d * 0.95, m, 0.075)
            t += d
    L, R = st.render(rev_mix=0.35, dly_fb=0.38)
    duck = _duck_env(0.35)
    return L * duck, R * duck


def _lead(st, t0, dur, m, vol):
    t = tt(dur + 0.25)
    f = freq(m)
    vib = 1.0 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.minimum(t / 0.3, 1.0)
    ph = 2 * np.pi * np.cumsum(f * vib) / RATE
    s = np.zeros(len(t))
    for k in range(1, 16):
        s += np.sin(ph * k) / k * (0.85 ** k)
    s += 0.35 * np.sin(ph * 0.5)
    e = np.minimum(t / 0.015, 1.0) * np.where(t < dur, 1.0, np.clip(1.0 - (t - dur) / 0.25, 0, 1))
    st.add(t0, s * e * vol, pan=0.0, rev=0.2, dly=0.3)


# ───────────────────────────── STEM 3: hard ─────────────────────────────

def stem_hard():
    st = Stem()
    riff = [1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1]   # palm-mute en semicorcheas
    for b, ch in enumerate(PROG):
        t0 = b * BAR
        root = CH[ch][0] + 12
        # bombo a negras con pegada + doble bombo al final de cada 4 compases
        for q in range(4):
            kick(st, t0 + q * BEAT, 0.75, punch=1.3, length=0.3)
        if b % 4 == 3:
            for s16 in (13, 14, 15):
                kick(st, t0 + s16 * BEAT / 4, 0.5, punch=1.2, length=0.2)
        snare(st, t0 + BEAT, 0.5, tone=200.0, rev=0.15)
        snare(st, t0 + 3 * BEAT, 0.5, tone=200.0, rev=0.15)
        for s16 in range(16):
            hat(st, t0 + s16 * BEAT / 4, 0.22 if s16 % 2 == 0 else 0.13, length=0.03, pan=0.35)
        if b % 4 == 0:
            crash(st, t0, 0.55)
        if b % 8 == 7:      # redoble de toms antes de cada sección
            for k, f0 in enumerate((210, 180, 150, 120)):
                tom(st, t0 + (12 + k) * BEAT / 4, 0.45, f0)
        # riff: quinta (raíz + 5ª + octava), sierra distorsionada; la última nota del compás se alarga
        for s16, on in enumerate(riff):
            if not on:
                continue
            long_note = s16 == 15
            dur = BEAT / 4 * (2.2 if long_note else 0.75)
            t = tt(dur)
            s = np.zeros(len(t))
            for iv in (0, 7, 12):
                s += saw_add(freq(root + iv) * (1.0 + 0.002 * iv), t, 30, 5000.0,
                             decay_k=None if long_note else 4.0)
            s = np.tanh(s * 3.2) * env_ad(t, dur, 0.002, 0.03)
            st.add(t0 + s16 * BEAT / 4, s * 0.075, pan=-0.45 if s16 % 2 else 0.45)
        # gruñido de sub una octava por debajo
        t = tt(BAR)
        fb = freq(CH[ch][0] - 12)
        g = np.tanh(np.sin(2 * np.pi * fb * t) * 2.5) * 0.10
        st.add(t0, g * env_ad(t, BAR, 0.01, 0.05))
    # melodía doblada una octava arriba con la sierra (segunda mitad), más fina
    for bi, bar_notes in enumerate(LEAD):
        t = (16 + bi) * BAR
        for m, eighths in bar_notes:
            d = eighths * BEAT / 2.0
            if m:
                _lead(st, t, d * 0.95, m + 12, 0.035)
            t += d
    L, R = st.render(rev_mix=0.25, dly_fb=0.3)
    duck = _duck_env(0.5)
    # el riff y el sub se agachan con el bombo; la percusión ya pega por sí sola
    return L * duck, R * duck


# ───────────────────────────── mezcla y escritura ─────────────────────────────

def write_wav(path, L, R):
    data = np.empty(N * 2, dtype=np.int16)
    data[0::2] = np.clip(L, -1, 1) * 32767
    data[1::2] = np.clip(R, -1, 1) * 32767
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Generando %d compases a %.0f BPM (%.1f s)…" % (BARS, BPM, N / RATE))
    stems = []
    for name, fn in zip(STEMS, (stem_base, stem_groove, stem_drive, stem_hard)):
        L, R = fn()
        L = _highpass(L, 28.0)      # fuera el DC / subgrave inútil
        R = _highpass(R, 28.0)
        stems.append((L, R))
        print("  %s  pico %.2f" % (name, max(np.abs(L).max(), np.abs(R).max())))
    # ganancia común: la mezcla completa (las 4) llega a -1 dBFS; cada stem conserva su peso relativo
    fullL = sum(s[0] for s in stems)
    fullR = sum(s[1] for s in stems)
    g = 0.89 / max(np.abs(fullL).max(), np.abs(fullR).max())
    for name, (L, R) in zip(STEMS, stems):
        write_wav(os.path.join(OUT_DIR, name + ".wav"), L * g, R * g)
    print("Ganancia común %.2f. Escrito en %s" % (g, os.path.normpath(OUT_DIR)))


if __name__ == "__main__":
    main()
