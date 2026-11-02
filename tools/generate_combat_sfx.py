"""Sintetiza los sonidos de combate de impactos y disparos (assets/sfx/*.wav, 44,1 kHz, mono 16 bits).

Cada sonido se monta por capas, como en una librería de foley:
  transitorio (chasquido) + cuerpo (golpe grave con caída de tono) + textura (ruido filtrado)
  + cola (reverberación corta de mazmorra) y una saturación suave que los "pega".
Los impactos tienen varias variantes (nombre, nombre_2, nombre_3): AudioManager elige una al azar
para que una ráfaga de golpes no suene a la misma muestra repetida.

Sonidos:
  impact_blunt*   golpe seco en carne (puños, polvo, garras, perdigones de esporas)
  impact_pierce*  proyectil/estocada que entra en el cuerpo (lanza, escopeta)
  impact_zap*     descarga eléctrica (railgun)
  impact_fire*    chisporroteo de quemadura (lanzallamas)
  impact_magic*   golpe arcano con brillo (serpientes, elementos, orbes de mago)
  kill_burst*     golpe que mata: más grave, crujido y salpicadura
  hit*            toque corto genérico (modo hordas)
  shot_shotgun*   escopeta: chasquido + estampido + cola
  shot_rail       railgun: chasquido + barrido láser + chisporroteo
  shot_launcher*  bazuca de esporas: "thoomp" de tubo + soplido
  orb_cast        lanzamiento de orbe mágico (magos y nigromante)
  proj_hit_wall*  proyectil contra pared o suelo
  spore_burst     cápsula de esporas que revienta

Semilla fija: los ficheros salen siempre iguales.
Uso: python tools/generate_combat_sfx.py   (Godot reimporta los .wav al abrir el proyecto)
"""

import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")
rng = np.random.default_rng(90211)


# ───────────────────────────── utilidades ─────────────────────────────

def n_of(dur):
    return int(dur * RATE)


def tvec(dur):
    return np.arange(n_of(dur)) / RATE


def noise(dur):
    return rng.uniform(-1.0, 1.0, n_of(dur))


def pad(x, dur):
    out = np.zeros(n_of(dur))
    m = min(len(x), len(out))
    out[:m] = x[:m]
    return out


def delay(x, sec):
    return np.concatenate([np.zeros(n_of(sec)), x])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def env_exp(dur, decay, attack=0.001):
    t = tvec(dur)
    a = np.clip(t / max(attack, 1e-5), 0.0, 1.0)
    return a * np.exp(-t * decay)


def biquad(x, kind, fc, q=0.707):
    """Filtro RBJ (lowpass / highpass / bandpass). `fc` puede ser un número o un array (barrido)."""
    fcs = np.broadcast_to(np.asarray(fc, dtype=float), x.shape)
    y = np.empty_like(x)
    x1 = x2 = y1 = y2 = 0.0
    cache_f = None
    b0 = b1 = b2 = a1 = a2 = 0.0
    for i in range(len(x)):
        f = fcs[i]
        if f != cache_f:
            cache_f = f
            w0 = 2.0 * np.pi * min(f, RATE * 0.45) / RATE
            cw, sw = np.cos(w0), np.sin(w0)
            alpha = sw / (2.0 * q)
            a0 = 1.0 + alpha
            if kind == "lp":
                b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
            elif kind == "hp":
                b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
            else:  # bp, ganancia de pico constante
                b0, b1, b2 = alpha, 0.0, -alpha
            b0, b1, b2 = b0 / a0, b1 / a0, b2 / a0
            a1, a2 = -2 * cw / a0, (1 - alpha) / a0
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def sweep_sine(dur, f0, f1, curve=0.06):
    """Seno cuyo tono cae (o sube) exponencialmente de f0 a f1 con constante `curve` (s)."""
    t = tvec(dur)
    f = f1 + (f0 - f1) * np.exp(-t / curve)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE)


def grains(dur, density, decay):
    """Chasquidos sueltos (crujidos, gravilla, chispas): impulsos aleatorios cada vez más escasos."""
    n = n_of(dur)
    t = np.arange(n) / RATE
    prob = density / RATE * np.exp(-t * decay)
    hits = rng.random(n) < prob
    x = np.zeros(n)
    x[hits] = rng.uniform(0.4, 1.0, hits.sum()) * rng.choice([-1, 1], hits.sum())
    # cada grano dura ~1 ms
    k = np.exp(-np.arange(int(0.0015 * RATE)) / (0.0004 * RATE))
    return np.convolve(x, k)[:n]


def room(x, mix_amt=0.15, size=1.0, damp=3500.0):
    """Reverberación corta de sala de piedra: peines con realimentación + paso bajo."""
    tail = n_of(0.45 * size)
    src = np.concatenate([x, np.zeros(tail)])
    wet = np.zeros_like(src)
    for ms, fb in ((29.7, 0.55), (37.1, 0.5), (41.1, 0.48), (43.7, 0.45)):
        d = int(ms * size * RATE / 1000)
        buf = src.copy()
        for i in range(d, len(buf)):
            buf[i] += fb * buf[i - d]
        wet += buf - src
    wet = biquad(wet / 4.0, "lp", damp)
    return src + wet * mix_amt


def sat(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def fade_out(x, sec=0.01):
    m = min(len(x), n_of(sec))
    x = x.copy()
    x[-m:] *= np.linspace(1.0, 0.0, m)
    return x


def trim_silence(x, thresh=0.0015):
    idx = np.nonzero(np.abs(x) > thresh)[0]
    return x[: idx[-1] + 1] if len(idx) else x


def normalize(x, peak=0.95):
    return x / max(np.max(np.abs(x)), 1e-6) * peak


def write(name, x, peak=0.95):
    x = fade_out(trim_silence(normalize(x, peak)))
    x = normalize(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"  {name}.wav  {len(x) / RATE:.2f}s")


def var(i):
    """Pequeñas diferencias entre variantes (tono y color)."""
    return 1.0 + (i - 1) * 0.09 * (1 if i % 2 else -1) + rng.uniform(-0.03, 0.03)


# ───────────────────────────── impactos ─────────────────────────────

def blunt(v):
    d = 0.4
    thump = sweep_sine(d, 170 * v, 52 * v, 0.035) * env_exp(d, 26, 0.0015)
    slap = biquad(noise(d), "bp", 900 * v, 1.1) * env_exp(d, 42)
    crunch = biquad(grains(d, 1800, 30) + noise(d) * 0.25, "bp", 2400 * v, 1.6) * env_exp(d, 55)
    click = biquad(noise(0.004), "hp", 3500) * np.linspace(1, 0, n_of(0.004))
    x = mix(thump * 1.0, slap * 1.6, crunch * 0.9, click * 0.5)
    return room(sat(x, 2.2), 0.12)


def pierce(v):
    d = 0.32
    tick = biquad(noise(0.005), "hp", 3000) * np.linspace(1, 0, n_of(0.005))
    thwack = biquad(noise(d), "bp", 1500 * v, 1.4) * env_exp(d, 65)
    thump = sweep_sine(d, 240 * v, 85 * v, 0.025) * env_exp(d, 38, 0.001)
    wet = biquad(noise(d), "bp", np.linspace(650, 380, n_of(d)) * v, 2.5) * env_exp(d, 22, 0.004)
    tear = biquad(grains(d, 900, 40), "bp", 3200 * v, 2.0) * env_exp(d, 35)
    x = mix(tick * 1.2, thwack * 1.6, thump * 0.75, wet * 0.9, tear * 0.5)
    return room(sat(x, 2.0), 0.1)


def zap(v):
    d = 0.5
    snap = biquad(noise(0.006), "hp", 2500) * np.linspace(1, 0, n_of(0.006))
    crackle = biquad(grains(d, 3500, 9), "hp", 1800)
    t = tvec(d)
    f = 95 * v * (1 + 0.15 * np.sin(2 * np.pi * 31 * t) + 0.25 * rng.uniform(-1, 1, len(t)))
    buzz = np.sign(np.sin(2 * np.pi * np.cumsum(f) / RATE)) * 0.5
    buzz = biquad(buzz, "lp", 2800) * env_exp(d, 11, 0.002)
    thump = sweep_sine(d, 180 * v, 60, 0.03) * env_exp(d, 30)
    x = mix(snap * 1.0, crackle * 1.3, buzz * 0.7, thump * 0.6)
    return room(sat(x, 1.8), 0.14)


def fire(v):
    d = 0.32
    whump = biquad(noise(d), "lp", 380 * v) * env_exp(d, 18, 0.01)
    sizzle = biquad(noise(d) * (0.4 + grains(d, 2500, 4)), "hp", 3200 * v) * env_exp(d, 9, 0.004)
    pop = biquad(grains(d, 400, 6), "bp", 1400 * v, 1.2)
    x = mix(whump * 2.2, sizzle * 0.9, pop * 0.8)
    return room(sat(x, 1.5), 0.08)


def magic(v):
    d = 0.75
    thump = sweep_sine(d, 200 * v, 70 * v, 0.04) * env_exp(d, 22, 0.002)
    t = tvec(d)
    shimmer = np.zeros(len(t))
    for k, (fr, dec) in enumerate(((880, 7), (1318, 9), (1767, 11), (2637, 14), (3520, 18))):
        fr = fr * v * (1 + 0.004 * k)
        shimmer += np.sin(2 * np.pi * fr * t + k) * np.exp(-t * dec) / (1 + k * 0.4)
    shimmer *= (1 + 0.35 * np.sin(2 * np.pi * 13 * t)) * np.clip(t / 0.006, 0, 1)
    swish = biquad(noise(d), "bp", 1200 + 3200 * np.exp(-t / 0.06), 2.0) * env_exp(d, 16)
    x = mix(thump * 1.0, shimmer * 0.35, swish * 1.2)
    return room(sat(x, 1.6), 0.25, 1.2)


def kill(v):
    d = 0.9
    thump = sweep_sine(d, 130 * v, 38 * v, 0.06) * env_exp(d, 11, 0.002)
    crunch = biquad(grains(d, 4000, 22) + noise(d) * 0.2, "bp", 1900 * v, 1.3) * env_exp(d, 18)
    t = tvec(d)
    splat = biquad(noise(d), "bp", 900 * v * np.exp(-t / 0.15) + 350, 1.8) * env_exp(d, 14, 0.003)
    debris = delay(biquad(grains(0.45, 220, 5), "lp", 3500) * 0.6, 0.05)
    click = biquad(noise(0.005), "hp", 3000) * np.linspace(1, 0, n_of(0.005))
    x = mix(thump * 1.2, crunch * 1.1, splat * 1.4, debris, click * 0.6)
    return room(sat(x, 2.4), 0.2)


def soft_hit(v):
    d = 0.18
    thump = sweep_sine(d, 200 * v, 90 * v, 0.02) * env_exp(d, 40)
    slap = biquad(noise(d), "bp", 1100 * v, 1.3) * env_exp(d, 60)
    return sat(mix(thump * 0.8, slap * 1.3), 1.6)


# ───────────────────────────── disparos ─────────────────────────────

def shotgun(v):
    d = 1.1
    crack = sat(noise(0.012) * np.exp(-np.arange(n_of(0.012)) / (0.003 * RATE)), 3.0)
    boom = sweep_sine(d, 120 * v, 42 * v, 0.05) * env_exp(d, 9, 0.001)
    t = tvec(d)
    body = biquad(noise(d), "lp", 600 + 3500 * np.exp(-t / 0.03)) * env_exp(d, 14, 0.001)
    tail = biquad(noise(d), "lp", 450) * env_exp(d, 4.5, 0.02)
    rattle = delay(biquad(grains(0.25, 300, 12), "bp", 2600, 1.5) * 0.25, 0.03)
    x = mix(crack * 1.3, boom * 1.3, body * 1.6, tail * 0.5, rattle)
    return room(sat(x, 2.8), 0.3, 1.3, 2800)


def railgun():
    d = 0.8
    t = tvec(d)
    snap = sat(noise(0.006) * np.linspace(1, 0, n_of(0.006)), 3.0)
    f = 280 + 4800 * np.exp(-t / 0.05)
    ph = 2 * np.pi * np.cumsum(f) / RATE
    laser = (np.sin(ph) + 0.4 * np.sin(2 * ph + 0.5)) * env_exp(d, 7, 0.001)
    laser *= 1 + 0.3 * biquad(noise(d), "lp", 80)
    sizzle = biquad(noise(d) * (0.3 + grains(d, 3000, 6)), "hp", 3500) * env_exp(d, 6, 0.002)
    thump = sweep_sine(d, 110, 45, 0.05) * env_exp(d, 12)
    x = mix(snap * 1.2, laser * 0.55, sizzle * 0.6, thump * 1.0)
    return room(sat(x, 2.0), 0.3, 1.4, 3000)


def launcher(v):
    d = 0.75
    t = tvec(d)
    pop = biquad(noise(0.015), "lp", 2200) * np.exp(-np.arange(n_of(0.015)) / (0.004 * RATE))
    tube = sweep_sine(d, 150 * v, 62 * v, 0.07) * env_exp(d, 8, 0.003)
    whoosh_env = np.clip(t / 0.06, 0, 1) * np.exp(-t * 6)
    whoosh = biquad(noise(d), "bp", 450 + 1500 * np.clip(t / 0.3, 0, 1), 1.5) * whoosh_env
    gas = biquad(noise(d), "hp", 2500) * env_exp(d, 9, 0.01)
    x = mix(pop * 1.4, tube * 1.4, whoosh * 1.3, gas * 0.25)
    return room(sat(x, 2.2), 0.2, 1.2, 3000)


def orb_cast():
    d = 0.55
    t = tvec(d)
    env = np.clip(t / 0.08, 0, 1) * np.exp(-np.clip(t - 0.08, 0, None) * 7)
    whoosh = biquad(noise(d), "bp", 500 + 2600 * np.clip(t / 0.22, 0, 1), 2.2) * env
    f = 320 + 380 * np.clip(t / 0.2, 0, 1) + 18 * np.sin(2 * np.pi * 9 * t)
    tone = np.sin(2 * np.pi * np.cumsum(f) / RATE + 2.0 * np.sin(2 * np.pi * f * 1.5 * t)) * env
    x = mix(whoosh * 1.3, tone * 0.45)
    return room(x, 0.3, 1.2)


def wall_hit(v):
    d = 0.3
    tick = biquad(noise(0.004), "hp", 4000) * np.linspace(1, 0, n_of(0.004))
    thunk = biquad(noise(d), "bp", 850 * v, 1.6) * env_exp(d, 55)
    stone = sweep_sine(d, 320 * v, 160 * v, 0.02) * env_exp(d, 45)
    gravel = delay(biquad(grains(0.2, 600, 14), "bp", 3800 * v, 1.2) * 0.5, 0.01)
    x = mix(tick * 1.0, thunk * 1.4, stone * 0.4, gravel)
    return room(sat(x, 1.8), 0.18)


def spore_burst():
    d = 0.9
    t = tvec(d)
    pop = sweep_sine(d, 320, 75, 0.03) * env_exp(d, 22, 0.001)
    wet = biquad(noise(d), "bp", 700 * np.exp(-t / 0.1) + 300, 1.5) * env_exp(d, 16, 0.002)
    hiss = biquad(noise(d), "hp", 2800) * np.clip(t / 0.03, 0, 1) * np.exp(-t * 4.5)
    blobs = biquad(grains(0.5, 180, 6), "lp", 1500)
    x = mix(pop * 1.2, wet * 1.5, hiss * 0.35, blobs * 0.5)
    return room(sat(x, 2.0), 0.2)


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Generando sonidos de combate en", OUT)
    for base, fn, count in (
        ("impact_blunt", blunt, 3),
        ("impact_pierce", pierce, 3),
        ("impact_zap", zap, 2),
        ("impact_fire", fire, 2),
        ("impact_magic", magic, 2),
        ("kill_burst", kill, 2),
        ("hit", soft_hit, 3),
        ("shot_shotgun", shotgun, 2),
        ("shot_launcher", launcher, 2),
        ("proj_hit_wall", wall_hit, 3),
    ):
        for i in range(1, count + 1):
            write(base if i == 1 else f"{base}_{i}", fn(var(i)))
    write("shot_rail", railgun())
    write("orb_cast", orb_cast(), 0.8)
    write("spore_burst", spore_burst())


if __name__ == "__main__":
    main()
