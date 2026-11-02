"""Sintetiza las voces de los enemigos de las cloacas (assets/sfx/*.wav, 44,1 kHz, mono 16 bits).

Usa las utilidades de generate_combat_sfx.py (filtros, sala, saturación, escritura) y añade una
"voz" de roedor: un tono con armónicos, contorno de tono y vibrato.

Sonidos (con variantes nombre_2, nombre_3 que AudioManager elige al azar):
  rat_squeak*   chillido corto de aviso (anticipación de la rata)
  rat_bite*     chasquido de dientes (golpe de la rata)
  rat_hurt*     chillido que cae
  rat_die*      chillido largo que se apaga
  slug_gurgle*  borboteo grave (anticipación de la babosa)
  slug_splat*   panzazo húmedo (golpe de la babosa)
  slug_hurt*    chapoteo
  slug_die      se deshincha con burbujas
  slug_spit     escupitajo: "ptú" + siseo húmedo
  king_screech* chillido enorme del Rey Rata (anticipaciones, llamada, rugido)
  king_die      chillido largo que se quiebra

Semilla fija: los ficheros salen siempre iguales.
Uso: python tools/generate_sewer_sfx.py   (Godot reimporta los .wav al abrir el proyecto)
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_combat_sfx import (OUT, RATE, biquad, env_exp, grains, mix, noise, room, sat, tvec,  # noqa: E402
                                 var, write)

rng = np.random.default_rng(31337)


def voice(dur, f0, f1, curve, harm=(1.0, 0.5, 0.25), vib=(28.0, 0.04), rough=0.0):
    """Tono de garganta: f va de f0 a f1 con constante `curve` (s), vibrato (Hz, fracción) y aspereza."""
    t = tvec(dur)
    f = f1 + (f0 - f1) * np.exp(-t / curve)
    f = f * (1.0 + vib[1] * np.sin(2 * np.pi * vib[0] * t))
    if rough > 0.0:
        f = f * (1.0 + rough * biquad(rng.uniform(-1, 1, len(t)), "lp", 60.0) * 6.0)
    ph = 2 * np.pi * np.cumsum(f) / RATE
    return sum(a * np.sin((k + 1) * ph) for k, a in enumerate(harm))


def shape(dur, attack, release):
    t = tvec(dur)
    a = np.clip(t / attack, 0, 1)
    r = np.clip((dur - t) / release, 0, 1)
    return a * r


# ───────────────────────────── rata ─────────────────────────────

def rat_squeak(v):
    d = 0.2 * v
    x = voice(d, 2600 * v, 3900 * v, 0.05, vib=(34, 0.05)) * shape(d, 0.008, 0.06)
    x = mix(x, biquad(noise(d), "bp", 5000, 2.0) * shape(d, 0.004, 0.1) * 0.15)
    return room(biquad(x, "hp", 900), 0.1, 0.6)


def rat_bite(v):
    d = 0.16
    t = tvec(d)
    clack = biquad(noise(d), "bp", 3200 * v, 3.0) * np.exp(-t * 90)
    clack2 = np.concatenate([np.zeros(int(0.045 * RATE)), clack[: -int(0.045 * RATE)]]) * 0.6
    tick = np.sin(2 * np.pi * 1800 * v * t) * np.exp(-t * 160)
    return room(sat(mix(clack, clack2, tick * 0.5), 1.8), 0.08, 0.5)


def rat_hurt(v):
    d = 0.24 * v
    x = voice(d, 3800 * v, 2100 * v, 0.09, vib=(42, 0.07), rough=0.02) * shape(d, 0.005, 0.08)
    return room(biquad(sat(x, 1.6), "hp", 800), 0.1, 0.6)


def rat_die(v):
    d = 0.55 * v
    x = voice(d, 3400 * v, 1100 * v, 0.22, vib=(18, 0.09), rough=0.04) * shape(d, 0.01, 0.25)
    gurgle = biquad(grains(d, 260, 4), "lp", 1200) * 0.4
    return room(biquad(sat(mix(x, gurgle), 1.5), "hp", 500), 0.14, 0.7)


# ───────────────────────────── babosa ─────────────────────────────

def bubbles(dur, density, lo, hi):
    """Burbujas: pitidos cortos cuyo tono sube (el "blup" de un líquido espeso)."""
    n = int(dur * RATE)
    out = np.zeros(n)
    count = int(dur * density)
    for _ in range(count):
        at = rng.integers(0, max(1, n - int(0.08 * RATE)))
        bd = rng.uniform(0.03, 0.07)
        f = rng.uniform(lo, hi)
        t = tvec(bd)
        b = np.sin(2 * np.pi * np.cumsum(f * (1 + 2.5 * t / bd)) / RATE) * np.exp(-t * 45)
        out[at: at + len(b)] += b[: n - at] * rng.uniform(0.4, 1.0)
    return out


def slug_gurgle(v):
    d = 0.6
    t = tvec(d)
    low = np.sin(2 * np.pi * np.cumsum(110 * v + 25 * np.sin(2 * np.pi * 7 * t)) / RATE) * shape(d, 0.06, 0.2)
    x = mix(low * 0.7, bubbles(d, 22, 180 * v, 420 * v) * 0.6, biquad(noise(d), "lp", 500) * shape(d, 0.1, 0.2) * 0.3)
    return room(sat(x, 1.4), 0.15, 0.8)


def slug_splat(v):
    d = 0.4
    t = tvec(d)
    thump = np.sin(2 * np.pi * np.cumsum(120 * v * (1 + 1.5 * np.exp(-t / 0.02))) / RATE) * np.exp(-t * 14)
    wet = biquad(noise(d), "lp", 1800 * v) * np.exp(-t * 18)
    drops = bubbles(d, 18, 300, 700) * 0.35
    return room(sat(mix(thump, wet * 0.9, drops), 2.0), 0.15, 0.8)


def slug_hurt(v):
    d = 0.3
    t = tvec(d)
    f = 900 * v * np.exp(-t / 0.08) + 180
    sq = biquad(noise(d), "bp", f, 4.0) * shape(d, 0.01, 0.12) * 2.0
    return room(sat(mix(sq, bubbles(d, 12, 200, 500) * 0.4), 1.5), 0.12, 0.7)


def slug_die():
    d = 1.0
    t = tvec(d)
    hiss = biquad(noise(d), "lp", 2200 * np.exp(-t / 0.35) + 150) * shape(d, 0.02, 0.4)
    low = voice(d, 140, 70, 0.4, harm=(1.0, 0.4), vib=(9, 0.1)) * shape(d, 0.05, 0.4) * 0.5
    return room(sat(mix(hiss, low, bubbles(d, 30, 150, 450) * 0.5), 1.4), 0.18, 0.9)


def slug_spit():
    d = 0.45
    t = tvec(d)
    pop = np.sin(2 * np.pi * np.cumsum(500 * np.exp(-t / 0.015) + 140) / RATE) * np.exp(-t * 40)
    hiss = biquad(noise(d), "hp", 2500) * np.clip(t / 0.03, 0, 1) * np.exp(-t * 7)
    return room(sat(mix(pop, hiss * 0.4, bubbles(d, 10, 400, 900) * 0.3), 1.8), 0.12, 0.7)


# ───────────────────────────── Rey Rata ─────────────────────────────

def king_screech(v):
    d = 0.7 * v
    hi = voice(d, 1700 * v, 2500 * v, 0.12, vib=(22, 0.06), rough=0.05) * shape(d, 0.02, 0.25)
    growl = voice(d, 140 * v, 110 * v, 0.2, harm=(1.0, 0.7, 0.5, 0.3), vib=(31, 0.12), rough=0.15) * shape(d, 0.04, 0.3)
    x = mix(biquad(hi, "hp", 600), growl * 0.6, biquad(noise(d), "bp", 3000, 1.0) * shape(d, 0.01, 0.3) * 0.12)
    return room(sat(x, 2.2), 0.3, 1.4)


def king_die():
    d = 1.6
    t = tvec(d)
    x = voice(d, 2400, 500, 0.6, vib=(14, 0.1), rough=0.08) * shape(d, 0.02, 0.7)
    crack = (np.sin(2 * np.pi * 9 * t) > 0.6) * 0.5 + 0.5          # la voz se quiebra al final
    x = x * np.where(t > 0.9, crack, 1.0)
    growl = voice(d, 120, 60, 0.7, harm=(1.0, 0.6, 0.4), vib=(25, 0.15), rough=0.2) * shape(d, 0.05, 0.6) * 0.6
    return room(sat(mix(biquad(x, "hp", 400), growl), 1.8), 0.35, 1.6)


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Generando voces de las cloacas en", OUT)
    for base, fn, count in (
        ("rat_squeak", rat_squeak, 3),
        ("rat_bite", rat_bite, 2),
        ("rat_hurt", rat_hurt, 3),
        ("rat_die", rat_die, 2),
        ("slug_gurgle", slug_gurgle, 2),
        ("slug_splat", slug_splat, 2),
        ("slug_hurt", slug_hurt, 3),
        ("king_screech", king_screech, 2),
    ):
        for i in range(1, count + 1):
            write(base if i == 1 else f"{base}_{i}", fn(var(i)))
    write("slug_die", slug_die())
    write("slug_spit", slug_spit(), 0.85)
    write("king_die", king_die())


if __name__ == "__main__":
    main()
