"""Sintetiza el sonido ambiente de los mapas (assets/sfx/amb_*.wav y reacciones del mundo, mono 16 bits).

Tres familias (las usa MapAmbience y MapReactions):
  Camas en bucle (22,05 kHz, 8 s): ruido filtrado en frecuencia, así que el final empalma con el principio.
    amb_wind_day     viento abierto de día (supervivencia)
    amb_wind_night   viento más grave con grillos (supervivencia, de noche)
    amb_cave         aire de cueva: rumor grave y soplo lejano (Cavernas)
    amb_sewer        agua corriendo y zumbido de tubería (Cloacas)
  Emisores en bucle (22,05 kHz, 4 s), se oyen en 3D cerca de su fuente:
    amb_fire         crepitar de antorcha, brasero u hoguera
    amb_mush_hum     zumbido suave de los hongos luminosos
  Sueltos (44,1 kHz), suenan al azar alrededor del jugador:
    amb_crow*  amb_owl  amb_creak  amb_gust          supervivencia
    amb_drip*  amb_rockfall  amb_chain               cavernas
    amb_drip*  amb_chain  amb_pipe_groan  amb_squeak cloacas
  Reacciones del mundo (fase 2):
    water_step*   chapoteo al andar por el agua
    grass_rustle* roce de la hierba al cruzarla
    spore_puff    hongo golpeado que suelta esporas
    fire_whoosh   llama que se agita con una ráfaga

Semilla fija: los ficheros salen siempre iguales.
Uso: python tools/generate_ambient_sfx.py   (Godot reimporta los .wav al abrir el proyecto)
"""

import os
import wave

import numpy as np

RATE = 44100
BED_RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")
rng = np.random.default_rng(41177)


# ───────────────────────────── utilidades ─────────────────────────────

def tvec(dur, rate=RATE):
    return np.arange(int(dur * rate)) / rate


def band_noise(dur, lo, hi, rate=RATE, slope=0.0):
    """Ruido limitado a [lo, hi] Hz. Se filtra en frecuencia: el resultado es periódico (bucle sin costura).
    slope > 0 inclina el espectro hacia los graves (1 ≈ ruido rosa)."""
    n = int(dur * rate)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / rate)
    mask = 1.0 / (1.0 + (lo / np.maximum(f, 1e-6)) ** 6) / (1.0 + (f / hi) ** 6)
    if slope > 0.0:
        mask *= 1.0 / np.maximum(f, lo * 0.5) ** (slope * 0.5)
    x = np.fft.irfft(spec * mask, n)
    return x / (np.max(np.abs(x)) + 1e-9)


def loop_lfo(dur, cycles, rate=RATE, phase=0.0):
    """Seno con un número entero de ciclos en `dur`: modula sin romper el bucle."""
    return np.sin(2.0 * np.pi * cycles * tvec(dur, rate) / dur + phase)


def env_exp(dur, decay, attack=0.002, rate=RATE):
    t = tvec(dur, rate)
    return np.minimum(t / attack, 1.0) * np.exp(-t / decay)


def reverb(x, sec=0.9, mix=0.3, rate=RATE, tone=3500.0):
    """Cola de cueva: convolución con ruido que decae."""
    n = int(sec * rate)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (sec * rate * 0.22))
    spec = np.fft.rfft(ir)
    f = np.fft.rfftfreq(n, 1.0 / rate)
    ir = np.fft.irfft(spec / (1.0 + (f / tone) ** 2), n)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    size = len(x) + n
    wet = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)
    dry = np.concatenate([x, np.zeros(n)])
    return dry * (1.0 - mix) + wet * mix


def place(buf, x, at, rate=RATE):
    i = max(int(at * rate), 0)
    m = min(len(x), len(buf) - i)
    if m > 0:
        buf[i:i + m] += x[:m]


def place_wrap(buf, x, at, rate=RATE):
    """Como place, pero lo que se sale por el final entra por el principio (para bucles)."""
    i = int(at * rate) % len(buf)
    idx = (i + np.arange(len(x))) % len(buf)
    np.add.at(buf, idx, x)


def save(name, x, rate=RATE, peak=0.8, fade=0.004):
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    if fade > 0.0:
        k = int(fade * rate)
        x[:k] *= np.linspace(0.0, 1.0, k)
        x[-k:] *= np.linspace(1.0, 0.0, k)
    data = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data.tobytes())
    print("%-18s %5.2f s  %4d KB" % (name, len(x) / rate, len(data) * 2 // 1024))


def save_loop(name, x, rate=BED_RATE, peak=0.7):
    save(name, x, rate, peak, fade=0.0)


# ───────────────────────────── camas en bucle ─────────────────────────────

def wind(dur, lo, hi, gusts, rate=BED_RATE):
    body = band_noise(dur, lo, hi, rate, slope=1.0)
    swell = 0.6 + 0.25 * loop_lfo(dur, gusts, rate) + 0.15 * loop_lfo(dur, gusts * 2 + 1, rate, 1.3)
    whistle = band_noise(dur, hi * 1.2, hi * 2.2, rate) * (0.5 + 0.5 * loop_lfo(dur, gusts + 1, rate, 2.1)) ** 2
    return body * swell + whistle * 0.12


def bed_wind_day():
    return wind(8.0, 180.0, 900.0, 2)


def bed_wind_night():
    dur = 8.0
    x = wind(dur, 110.0, 520.0, 1) * 0.9
    # Grillos: trenes de pulsos agudos, dos "cantores" a distinto ritmo
    for freq, rate_hz, gain, phase in [(4300.0, 3.0, 0.05, 0.0), (4900.0, 2.0, 0.035, 0.4)]:
        t = tvec(dur, BED_RATE)
        chirp = np.sin(2.0 * np.pi * freq * t) * (np.sin(2.0 * np.pi * 38.0 * t) > 0.2)
        gate = (np.sin(2.0 * np.pi * rate_hz * t + phase) > 0.55).astype(float)
        k = int(0.01 * BED_RATE)
        gate = np.convolve(np.concatenate([gate[-k:], gate, gate[:k]]), np.ones(k) / k, "same")[k:-k]
        x += chirp * gate * gain
    return x


def bed_cave():
    dur = 8.0
    rumble = band_noise(dur, 35.0, 130.0, BED_RATE) * (0.7 + 0.3 * loop_lfo(dur, 1, BED_RATE))
    air = band_noise(dur, 300.0, 1400.0, BED_RATE, slope=1.0) * (0.5 + 0.3 * loop_lfo(dur, 2, BED_RATE, 0.9))
    t = tvec(dur, BED_RATE)
    drone = np.sin(2.0 * np.pi * 55.0 * t) * 0.5 + np.sin(2.0 * np.pi * 82.5 * t) * 0.25
    return rumble * 0.8 + air * 0.22 + drone * (0.25 + 0.1 * loop_lfo(dur, 1, BED_RATE, 2.0))


def bed_sewer():
    dur = 8.0
    flow = band_noise(dur, 450.0, 3200.0, BED_RATE, slope=0.6)
    burble = np.zeros(int(dur * BED_RATE))
    for _ in range(90):                                   # burbujas: pitidos cortos que suben
        d = rng.uniform(0.03, 0.08)
        t = tvec(d, BED_RATE)
        f0 = rng.uniform(350.0, 1100.0)
        blip = np.sin(2.0 * np.pi * (f0 * t + f0 * 2.5 * t * t)) * np.sin(np.pi * t / d) ** 2
        place_wrap(burble, blip * rng.uniform(0.2, 0.7), rng.uniform(0.0, dur), BED_RATE)
    t = tvec(dur, BED_RATE)
    hum = np.sin(2.0 * np.pi * 50.0 * t) + 0.4 * np.sin(2.0 * np.pi * 100.0 * t)
    return flow * (0.55 + 0.15 * loop_lfo(dur, 3, BED_RATE)) + burble * 0.5 + hum * 0.16 \
        + band_noise(dur, 40.0, 110.0, BED_RATE) * 0.3


# ───────────────────────────── emisores en bucle ─────────────────────────────

def loop_fire():
    dur = 4.0
    n = int(dur * BED_RATE)
    roar = band_noise(dur, 90.0, 700.0, BED_RATE, slope=1.0) * (0.6 + 0.25 * loop_lfo(dur, 5, BED_RATE) + 0.15 * loop_lfo(dur, 13, BED_RATE, 1.0))
    crackle = np.zeros(n)
    for _ in range(70):                                   # chasquidos de leña
        d = rng.uniform(0.004, 0.02)
        click = band_noise(d, 1500.0, 7000.0, BED_RATE) * env_exp(d, d * 0.3, 0.0005, BED_RATE)
        place_wrap(crackle, click * rng.uniform(0.25, 1.0) ** 2, rng.uniform(0.0, dur), BED_RATE)
    return roar * 0.6 + crackle * 0.75


def loop_mush_hum():
    dur = 4.0
    t = tvec(dur, BED_RATE)
    x = np.zeros(len(t))
    for f, g in [(196.0, 1.0), (294.0, 0.55), (392.25, 0.35), (588.5, 0.18)]:   # frecuencias con ciclos enteros en 4 s
        x += np.sin(2.0 * np.pi * f * t) * g
    shimmer = band_noise(dur, 2500.0, 6000.0, BED_RATE) * (0.5 + 0.5 * loop_lfo(dur, 3, BED_RATE)) * 0.05
    return x * (0.7 + 0.3 * loop_lfo(dur, 2, BED_RATE)) + shimmer


# ───────────────────────────── sueltos ─────────────────────────────

def crow(pitch=1.0, caws=2):
    out = np.zeros(int(1.4 * RATE))
    for i in range(caws):
        d = rng.uniform(0.22, 0.3)
        t = tvec(d)
        f = (640.0 - 150.0 * t / d) * pitch
        ph = 2.0 * np.pi * np.cumsum(f) / RATE
        voice = np.sign(np.sin(ph)) * 0.5 + np.sin(ph * 2.0) * 0.3 + np.sin(ph * 3.0) * 0.2
        rasp = 0.6 + 0.4 * np.sign(np.sin(2.0 * np.pi * 62.0 * t))            # el graznido "roto"
        grit = band_noise(d, 1200.0, 3800.0) * 0.5
        caw = (voice * rasp + grit) * np.sin(np.pi * t / d) ** 0.6
        place(out, caw, 0.05 + i * 0.36)
    spec = np.fft.rfft(out)
    f = np.fft.rfftfreq(len(out), 1.0 / RATE)
    out = np.fft.irfft(spec * np.exp(-((f - 1700.0 * pitch) / 1300.0) ** 2), len(out))   # formante nasal
    return reverb(out, 0.7, 0.22)


def owl():
    out = np.zeros(int(1.6 * RATE))
    for at, d, f0 in [(0.05, 0.22, 395.0), (0.42, 0.16, 400.0), (0.66, 0.5, 385.0)]:
        t = tvec(d)
        f = f0 * (1.0 - 0.06 * t / d)
        ph = 2.0 * np.pi * np.cumsum(f) / RATE
        place(out, (np.sin(ph) + 0.15 * np.sin(2.0 * ph)) * np.sin(np.pi * t / d) ** 1.5, at)
    return reverb(out, 1.1, 0.35)


def creak():
    d = 0.9
    t = tvec(d)
    f = 150.0 + 90.0 * np.sin(2.0 * np.pi * 1.1 * t) + 40.0 * t
    ph = 2.0 * np.pi * np.cumsum(f) / RATE
    stick = (np.sin(2.0 * np.pi * 27.0 * t + 3.0 * np.sin(2.0 * np.pi * 3.0 * t)) > 0.1).astype(float)   # roce a tirones
    x = (np.sign(np.sin(ph)) * 0.4 + np.sin(ph * 3.0) * 0.3 + np.sin(ph * 5.2) * 0.2) * stick
    return reverb(x * np.sin(np.pi * t / d) ** 0.8, 0.5, 0.2)


def gust():
    d = 3.2
    x = band_noise(d, 160.0, 1100.0, RATE, slope=1.0) + band_noise(d, 1200.0, 2600.0) * 0.15
    t = tvec(d)
    return x * np.sin(np.pi * t / d) ** 2.2


def drip(f0=1150.0):
    d = 0.11
    t = tvec(d)
    f = f0 * (1.0 + 0.9 * np.exp(-t / 0.012))
    ph = 2.0 * np.pi * np.cumsum(f) / RATE
    plink = np.sin(ph) * env_exp(d, 0.03, 0.001)
    tail = np.sin(2.0 * np.pi * f0 * 0.52 * t) * env_exp(d, 0.05, 0.02) * 0.3
    return reverb(plink + tail, 1.3, 0.45)


def rockfall():
    out = np.zeros(int(1.6 * RATE))
    at = 0.02
    for i in range(14):
        d = rng.uniform(0.012, 0.04)
        f0 = rng.uniform(500.0, 2200.0)
        knock = (band_noise(d, f0, f0 * 2.5) + np.sin(2.0 * np.pi * f0 * 0.5 * tvec(d))) * env_exp(d, d * 0.3, 0.0005)
        place(out, knock * rng.uniform(0.3, 1.0) * (1.0 - i / 20.0), at)
        at += rng.uniform(0.02, 0.14) * (1.0 + i * 0.08)
    return reverb(out, 1.4, 0.4)


def chain():
    out = np.zeros(int(1.3 * RATE))
    at = 0.02
    for _ in range(9):
        d = rng.uniform(0.05, 0.12)
        t = tvec(d)
        base = rng.uniform(1800.0, 3200.0)
        link = sum(np.sin(2.0 * np.pi * base * r * t + rng.uniform(0, 6.28)) * g
                   for r, g in [(1.0, 1.0), (1.47, 0.7), (2.09, 0.5), (2.83, 0.35), (3.71, 0.2)])
        place(out, link * env_exp(d, 0.025, 0.0005) * rng.uniform(0.3, 1.0), at)
        at += rng.uniform(0.04, 0.16)
    return reverb(out, 1.0, 0.3)


def pipe_groan():
    d = 2.4
    t = tvec(d)
    f = 62.0 + 9.0 * np.sin(2.0 * np.pi * 0.7 * t) - 6.0 * t / d
    ph = 2.0 * np.pi * np.cumsum(f) / RATE
    x = np.sin(ph) + 0.6 * np.sin(ph * 2.02) + 0.4 * np.sin(ph * 3.07) + 0.25 * np.sin(ph * 5.11)
    x = np.tanh(x * 1.6) + band_noise(d, 300.0, 900.0) * 0.08
    return reverb(x * np.sin(np.pi * t / d) ** 1.3, 1.5, 0.4, tone=1800.0)


def squeak():
    out = np.zeros(int(0.5 * RATE))
    for at, d, f0 in [(0.01, 0.07, 3400.0), (0.13, 0.05, 3900.0), (0.22, 0.09, 3100.0)]:
        t = tvec(d)
        f = f0 * (1.0 + 0.18 * np.sin(np.pi * t / d))
        ph = 2.0 * np.pi * np.cumsum(f) / RATE
        place(out, (np.sin(ph) + 0.3 * np.sin(2.0 * ph)) * np.sin(np.pi * t / d), at)
    return reverb(out, 0.6, 0.25)


# ───────────────────────────── reacciones del mundo ─────────────────────────────

def water_step(seed_pitch=1.0):
    d = 0.42
    slap = band_noise(0.05, 250.0, 1400.0) * env_exp(0.05, 0.012, 0.001)
    spray = band_noise(d, 1800.0 * seed_pitch, 7000.0) * env_exp(d, 0.09, 0.012)
    out = np.zeros(int(d * RATE))
    place(out, slap, 0.0)
    place(out, spray * 0.55, 0.01)
    for _ in range(4):                                    # gotas que vuelven a caer
        bd = rng.uniform(0.02, 0.05)
        t = tvec(bd)
        f0 = rng.uniform(500.0, 1300.0) * seed_pitch
        place(out, np.sin(2.0 * np.pi * (f0 * t + f0 * 3.0 * t * t)) * np.sin(np.pi * t / bd) ** 2 * 0.3, rng.uniform(0.08, 0.3))
    return out


def grass_rustle(tilt=1.0):
    d = 0.3
    t = tvec(d)
    x = band_noise(d, 2200.0 * tilt, 8000.0) * (0.5 + 0.5 * np.sin(2.0 * np.pi * 17.0 * t + rng.uniform(0, 6.28))) ** 2
    return x * np.sin(np.pi * t / d) ** 1.4


def spore_puff():
    d = 0.5
    t = tvec(d)
    thump = np.sin(2.0 * np.pi * (140.0 * t - 160.0 * t * t)) * env_exp(d, 0.05, 0.002)
    puff = band_noise(d, 500.0, 3500.0, RATE, slope=0.6) * env_exp(d, 0.11, 0.015)
    sparkle = np.sin(2.0 * np.pi * 2600.0 * t) * env_exp(d, 0.14, 0.03) * 0.12
    return reverb(thump * 0.7 + puff * 0.6 + sparkle, 0.6, 0.22)


def fire_whoosh():
    d = 0.6
    t = tvec(d)
    x = band_noise(d, 140.0, 1500.0, RATE, slope=1.0) * (0.6 + 0.4 * np.sin(2.0 * np.pi * 21.0 * t))
    return x * np.sin(np.pi * t / d) ** 1.6


# ───────────────────────────── fauna y rutinas de enemigos ─────────────────────────────

def wing_flap(beats=5, rate=11.0):
    """Aleteo que se aleja: soplos cortos de aire, cada uno más flojo."""
    out = np.zeros(int((beats / rate + 0.25) * RATE))
    for i in range(beats):
        d = 0.07
        t = tvec(d)
        puff = band_noise(d, 180.0, 1600.0, RATE, slope=0.8) * np.sin(np.pi * t / d) ** 1.5
        place(out, puff * (1.0 - i / (beats + 2.0)), i / rate + rng.uniform(-0.006, 0.006))
    return out


def bat_screech(pitch=1.0):
    out = np.zeros(int(0.45 * RATE))
    at = 0.01
    for _ in range(5):
        d = rng.uniform(0.025, 0.05)
        t = tvec(d)
        f = 6200.0 * pitch * (1.0 - 0.25 * t / d)
        ph = 2.0 * np.pi * np.cumsum(f) / RATE
        place(out, (np.sin(ph) + 0.4 * np.sin(2.0 * ph)) * np.sin(np.pi * t / d), at)
        at += d + rng.uniform(0.01, 0.04)
    return reverb(out, 0.5, 0.3, tone=6000.0)


def snore():
    """Ronquido: inspiración rasposa (ruido grave a pulsos) y soplido de salida."""
    d_in, d_out = 0.9, 0.8
    t = tvec(d_in)
    rattle = 0.55 + 0.45 * np.sign(np.sin(2.0 * np.pi * (26.0 + 6.0 * t) * t))
    breath_in = band_noise(d_in, 90.0, 520.0, RATE, slope=1.0) * rattle * np.sin(np.pi * t / d_in) ** 1.2
    t2 = tvec(d_out)
    breath_out = band_noise(d_out, 300.0, 1500.0, RATE, slope=0.8) * np.sin(np.pi * t2 / d_out) ** 2 * 0.35
    out = np.zeros(int((d_in + d_out + 0.1) * RATE))
    place(out, breath_in, 0.0)
    place(out, breath_out, d_in + 0.05)
    return out


def chatter(syllables=5, base=210.0):
    """Parloteo goblin: sílabas guturales con dos formantes que cambian (no dice nada, pero suena a charla)."""
    out = np.zeros(int((syllables * 0.19 + 0.3) * RATE))
    at = 0.02
    for _ in range(syllables):
        d = rng.uniform(0.09, 0.16)
        t = tvec(d)
        f0 = base * rng.uniform(0.8, 1.3) * (1.0 + 0.12 * np.sin(np.pi * t / d))
        ph = 2.0 * np.pi * np.cumsum(f0) / RATE
        voice = np.sign(np.sin(ph)) * 0.6 + np.sin(ph * 2.0) * 0.4
        spec = np.fft.rfft(voice)
        f = np.fft.rfftfreq(len(voice), 1.0 / RATE)
        f1, f2 = rng.uniform(450.0, 900.0), rng.uniform(1200.0, 2300.0)
        voice = np.fft.irfft(spec * (np.exp(-((f - f1) / 180.0) ** 2) + 0.6 * np.exp(-((f - f2) / 260.0) ** 2)), len(voice))
        place(out, voice * np.sin(np.pi * t / d) ** 0.7, at)
        at += d + rng.uniform(0.01, 0.07)
    return reverb(out, 0.5, 0.18)


def alert_sting():
    """Golpe de alarma: dos notas agudas a la quinta con ataque seco."""
    d = 0.5
    t = tvec(d)
    x = np.zeros(len(t))
    for f, at in [(880.0, 0.0), (1318.5, 0.07)]:
        tt = np.maximum(t - at, 0.0)
        x += (np.sin(2.0 * np.pi * f * tt) + 0.4 * np.sin(2.0 * np.pi * f * 2.0 * tt)) * np.exp(-tt / 0.11) * (t >= at)
    click = np.zeros(len(t))
    place(click, band_noise(0.02, 2000.0, 8000.0) * env_exp(0.02, 0.006, 0.0005), 0.0)
    return reverb(x + click * 0.6, 0.6, 0.2)


def main():
    os.makedirs(OUT, exist_ok=True)
    save("wing_flap", wing_flap(5, 11.0), peak=0.6)
    save("wing_flap_2", wing_flap(7, 13.0), peak=0.6)
    save("bat_screech", bat_screech(1.0), peak=0.5)
    save("bat_screech_2", bat_screech(1.18), peak=0.5)
    save("goblin_snore", snore(), peak=0.6)
    save("goblin_chatter", chatter(5, 210.0), peak=0.6)
    save("goblin_chatter_2", chatter(4, 180.0), peak=0.6)
    save("goblin_chatter_3", chatter(6, 240.0), peak=0.6)
    save("alert_sting", alert_sting(), peak=0.7)
    save_loop("amb_wind_day", bed_wind_day())
    save_loop("amb_wind_night", bed_wind_night())
    save_loop("amb_cave", bed_cave())
    save_loop("amb_sewer", bed_sewer())
    save_loop("amb_fire", loop_fire())
    save_loop("amb_mush_hum", loop_mush_hum(), peak=0.5)
    save("amb_crow", crow(1.0, 2))
    save("amb_crow_2", crow(0.88, 3))
    save("amb_owl", owl(), peak=0.6)
    save("amb_creak", creak(), peak=0.6)
    save("amb_gust", gust(), fade=0.05)
    save("amb_drip", drip(1150.0))
    save("amb_drip_2", drip(1480.0))
    save("amb_drip_3", drip(890.0))
    save("amb_rockfall", rockfall())
    save("amb_chain", chain(), peak=0.6)
    save("amb_pipe_groan", pipe_groan(), fade=0.03)
    save("amb_squeak", squeak(), peak=0.5)
    save("water_step", water_step(1.0))
    save("water_step_2", water_step(0.85))
    save("water_step_3", water_step(1.2))
    save("grass_rustle", grass_rustle(1.0), peak=0.6)
    save("grass_rustle_2", grass_rustle(0.8), peak=0.6)
    save("spore_puff", spore_puff())
    save("fire_whoosh", fire_whoosh(), peak=0.7)


if __name__ == "__main__":
    main()
