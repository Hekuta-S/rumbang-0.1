"""Sonidos con identidad propia para las armas cuerpo a cuerpo y las voces de los enemigos de la mazmorra
(assets/sfx/*.wav, 44,1 kHz, mono 16 bits).

Antes, espada, espadón, dagas y maza compartían los mismos cuatro silbidos con otro tono, y zombi, bruto, mago
y nigromante usaban la voz del goblin más grave o más aguda. Aquí cada arma y cada criatura tiene su material:

  Armas (silbido + impacto propios)
    dagger_swing* dagger_spin* dagger_dash* impact_dagger*   hoja corta: seca, aguda, rápida
    sword_swing*  sword_heavy*              impact_sword*    acero fino: silbido limpio con canto de hoja
    great_swing*  great_heavy*              impact_great*    espadón: masa de aire grave, tajo con crujido
    mace_swing*   mace_spin*  mace_ground*  impact_mace*     maza: bufido romo, hueso y metal sordo
    spear_thrust*                                            estocada de la espalanza

  Voces (fuente glotal + formantes: cada criatura con su tamaño de garganta, tono y aspereza)
    goblin_warn* goblin_swing* goblin_hurt* goblin_die*      pequeño, nasal, rasposo
    zombie_warn* zombie_swing* zombie_hurt* zombie_die* zombie_rise   gemido roto, con aire
    brute_warn*  brute_swing*  brute_hurt*  brute_die*       rugido grave de pecho
    mage_warn*   mage_hurt*    mage_die*                     voz limpia con brillo arcano
    necro_warn*  necro_hurt*   necro_die    necro_summon     susurro coral, hueco, con cola larga
    player_hurt*                                             quejido del personaje al recibir un golpe

Técnicas: ruido con filtro de banda barrido (banco de bandas), síntesis modal para el metal, granos para lo
húmedo y el hueso, fuente glotal con jitter/subarmónicos + formantes que cambian de vocal, y reverberación por
convolución (sala de piedra). Solo numpy. Semilla fija: los ficheros salen siempre iguales.

Uso: python tools/generate_identity_sfx.py [prefijo ...]   (sin argumentos: todos)
"""

import os
import sys
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sfx")
rng = np.random.default_rng(417)
TAU = 2.0 * np.pi


# ───────────────────────────── utilidades ─────────────────────────────

def n_of(dur):
    return max(int(dur * RATE), 1)


def tvec(dur):
    return np.arange(n_of(dur)) / RATE


def white(dur):
    return rng.uniform(-1.0, 1.0, n_of(dur))


def j(x, pct=0.08):
    """Valor con variación aleatoria de ±pct."""
    return x * rng.uniform(1.0 - pct, 1.0 + pct)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def delay(x, sec):
    return np.concatenate([np.zeros(n_of(sec)), x]) if sec > 0.0 else x


def pad_to(x, dur):
    out = np.zeros(n_of(dur))
    m = min(len(x), len(out))
    out[:m] = x[:m]
    return out


def spec_filter(x, gain):
    """Filtro de fase cero en frecuencia; `gain(f)` da la ganancia por frecuencia."""
    n = len(x)
    m = n + n_of(0.05)          # margen: lo que el filtro adelanta no vuelve por el principio
    spec = np.fft.rfft(x, m)
    f = np.fft.rfftfreq(m, 1.0 / RATE)
    return np.fft.irfft(spec * gain(f), m)[:n]


def lp(x, fc, order=2):
    return spec_filter(x, lambda f: 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)))


def hp(x, fc, order=2):
    return spec_filter(x, lambda f: 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bp(x, fc, q=2.0):
    return spec_filter(x, lambda f: 1.0 / np.sqrt(1.0 + (q * (f / fc - fc / np.maximum(f, 1e-3))) ** 2))


def logcurve(dur, pts):
    """Curva por puntos [(t 0..1, valor)] interpolada en escala logarítmica (frecuencias)."""
    xs = [p[0] for p in pts]
    ys = np.log([p[1] for p in pts])
    return np.exp(np.interp(np.linspace(0.0, 1.0, n_of(dur)), xs, ys))


def lincurve(dur, pts):
    return np.interp(np.linspace(0.0, 1.0, n_of(dur)), [p[0] for p in pts], [p[1] for p in pts])


def bell(dur, pk=0.45, rise=2.0, fall=1.6):
    """Envolvente de campana asimétrica: sube hasta `pk` (0..1) y cae."""
    t = np.linspace(0.0, 1.0, n_of(dur))
    up = (np.clip(t / pk, 0.0, 1.0)) ** rise
    down = (np.clip((1.0 - t) / (1.0 - pk), 0.0, 1.0)) ** fall
    return np.where(t < pk, up, down)


def env_exp(dur, decay, attack=0.001):
    t = tvec(dur)
    return np.clip(t / max(attack, 1e-5), 0.0, 1.0) * np.exp(-t * decay)


def smooth_noise(n, rate_hz):
    """Ruido lento en [-1, 1] (deriva de tono, temblor)."""
    k = max(int(n * rate_hz / RATE) + 2, 2)
    return np.interp(np.linspace(0.0, k - 1.0, n), np.arange(k), rng.uniform(-1.0, 1.0, k))


def swept_noise(dur, fc, width=0.5, bands=26, lo=50.0, hi=16000.0):
    """Ruido por un filtro de banda que se mueve: `fc` (Hz, número o curva) y `width` en octavas."""
    n = n_of(dur)
    spec = np.fft.rfft(rng.uniform(-1.0, 1.0, n))
    lf = np.log2(np.maximum(np.fft.rfftfreq(n, 1.0 / RATE), 1.0))
    centers = np.linspace(np.log2(lo), np.log2(hi), bands)
    step = centers[1] - centers[0]
    lfc = np.log2(np.clip(np.broadcast_to(np.asarray(fc, dtype=float), (n,)), lo, hi))
    out = np.zeros(n)
    for c in centers:
        w = np.exp(-0.5 * ((lfc - c) / width) ** 2)
        if w.max() < 1e-3:
            continue
        out += np.fft.irfft(spec * np.exp(-0.5 * ((lf - c) / (step * 0.6)) ** 2), n) * w
    return out / (np.max(np.abs(out)) + 1e-9)


BLADE = [1.0, 1.47, 2.09, 2.56, 3.39, 4.16]       # parciales inarmónicos de una hoja de acero
BLUNT = [1.0, 2.32, 3.87, 5.1]                    # masa de metal sorda (cabeza de maza)


def ring(dur, base, ratios=BLADE, decay=9.0, damp=1.0, twin=0.006):
    """Síntesis modal: parciales que decaen (los agudos antes), cada uno con un gemelo desafinado (brillo)."""
    t = tvec(dur)
    out = np.zeros(len(t))
    for i, r in enumerate(ratios):
        f = base * r * rng.uniform(0.985, 1.015)
        if f > 17000.0:
            continue
        a = 1.0 / (1.0 + i * 0.7)
        d = decay * (1.0 + damp * i * 0.6)
        for ff in (f, f * (1.0 + twin * rng.uniform(0.5, 1.5))):
            out += a * np.sin(TAU * ff * t + rng.uniform(0.0, TAU)) * np.exp(-t * d)
    return out / (np.max(np.abs(out)) + 1e-9)


def thump(dur, f0, f1, decay, curve=0.03):
    """Golpe grave: seno con caída de tono."""
    t = tvec(dur)
    f = f1 + (f0 - f1) * np.exp(-t / curve)
    return np.sin(TAU * np.cumsum(f) / RATE) * env_exp(dur, decay, 0.002)


def squelch(dur, grains, lo, hi):
    """Lo húmedo: burbujas cortas con deslizamiento de tono."""
    out = np.zeros(n_of(dur))
    for _ in range(grains):
        gd = rng.uniform(0.012, 0.04)
        t = tvec(gd)
        f0 = rng.uniform(lo, hi)
        f1 = f0 * (rng.uniform(1.3, 2.2) if rng.random() < 0.6 else rng.uniform(0.5, 0.8))
        g = np.sin(TAU * np.cumsum(f0 * (f1 / f0) ** (t / gd)) / RATE) * np.sin(np.pi * t / gd) ** 2
        at = int(rng.beta(1.2, 2.5) * max(len(out) - len(g), 1))
        out[at: at + len(g)] += g[: len(out) - at] * rng.uniform(0.4, 1.0)
    return out


def crunch(dur, clicks, lo, hi, spread=(1.2, 2.5)):
    """Crujido (hueso, piedra): chasquidos de ruido filtrado repartidos en el tiempo."""
    out = np.zeros(n_of(dur))
    for _ in range(clicks):
        cd = rng.uniform(0.004, 0.012)
        g = bp(white(cd), rng.uniform(lo, hi), 1.6) * env_exp(cd, rng.uniform(250.0, 600.0), 0.0004)
        at = int(rng.beta(*spread) * max(len(out) - len(g), 1))
        out[at: at + len(g)] += g[: len(out) - at] * rng.uniform(0.4, 1.0)
    return out


_ir_cache = {}


def _ir(rt, bright):
    key = (rt, bright)
    if key not in _ir_cache:
        g = np.random.default_rng(int(rt * 1000) + int(bright))
        n = n_of(rt * 1.2)
        t = np.arange(n) / RATE
        tail = g.uniform(-1.0, 1.0, n) * np.exp(-6.9 * t / rt)
        tail = lp(tail, bright, 1) * np.clip(t / 0.012, 0.0, 1.0)      # la cola entra tras las primeras reflexiones
        for _ in range(7):                                             # primeras reflexiones: paredes cercanas
            at = int(g.uniform(0.006, 0.045) * RATE)
            tail[at] += g.uniform(0.5, 1.0) * g.choice([-1.0, 1.0])
        _ir_cache[key] = tail / np.sqrt(np.sum(tail ** 2))
    return _ir_cache[key]


def reverb(x, amount=0.12, rt=0.45, bright=4200.0):
    """Sala de piedra por convolución con una respuesta sintética."""
    ir = _ir(rt, bright)
    n = len(x) + len(ir) - 1
    wet = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    return mix(x, amount * wet)


def sat(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def finish(x, rev=(0.12, 0.45, 4200.0), drive=0.0, peak=0.95, low_cut=35.0):
    x = hp(x, low_cut, 1)
    x = x / (np.max(np.abs(x)) + 1e-9)
    if drive > 0.0:
        x = sat(x, drive)
    if rev:
        x = reverb(x, *rev)
    idx = np.nonzero(np.abs(x) > 0.002 * np.max(np.abs(x)))[0]
    x = x[: idx[-1] + 1] if len(idx) else x
    k = min(n_of(0.02), len(x))
    x = x.copy()
    x[-k:] *= np.linspace(1.0, 0.0, k)
    return x * (peak / (np.max(np.abs(x)) + 1e-9))


def write(name, x):
    data = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print("  %-18s %.2f s" % (name, len(x) / RATE))


# ───────────────────────────── armas: silbidos ─────────────────────────────

def whoosh(dur, f0, fpk, f1, pk=0.45, width=0.45, shape=(2.0, 1.6), air=0.3, body=0.0):
    """Silbido de un arma: banda de ruido que sube y baja con el paso de la hoja."""
    fc = logcurve(dur, [(0.0, f0), (pk, fpk), (1.0, f1)])
    e = bell(dur, pk, *shape)
    x = swept_noise(dur, fc, width) * e
    if air > 0.0:
        x += air * swept_noise(dur, np.minimum(fc * 2.8, 15000.0), 0.6) * e ** 1.5
    if body > 0.0:
        x += body * swept_noise(dur, fc * 0.3, 0.5) * e
    return x


def blade_sing(dur, base, start, decay=10.0):
    """Canto de la hoja al cortar el aire: entra con el pico del silbido y se apaga."""
    r = ring(dur, base, BLADE, decay, 0.8)
    return delay(r * np.clip(tvec(dur) / 0.03, 0.0, 1.0), start)


def dagger_swing():
    d = j(0.14)
    x = whoosh(d, j(1800), j(5400), j(2600), 0.4, 0.4, (2.4, 1.8), 0.5)
    return finish(mix(x, 0.05 * blade_sing(0.12, j(5200), d * 0.35, 28.0)), (0.06, 0.3, 5000.0))


def dagger_spin():
    a = whoosh(j(0.15), 1500, j(4800), 2200, 0.4, 0.4, (2.2, 1.6), 0.5)
    b = whoosh(j(0.16), 1300, j(4300), 1900, 0.45, 0.4, (2.2, 1.6), 0.5)
    c = whoosh(j(0.2), 1100, j(3600), 1400, 0.4, 0.5, (2.0, 1.3), 0.4)
    x = mix(a, delay(0.9 * b, j(0.085)), delay(0.8 * c, j(0.17)))
    return finish(mix(x, 0.06 * blade_sing(0.2, j(4800), 0.06, 16.0)), (0.08, 0.3, 5000.0))


def dagger_dash():
    d = j(0.34)
    rip = whoosh(d, 700, j(4200), 1100, 0.3, 0.7, (1.4, 1.2), 0.6, 0.3)
    kick = 0.5 * thump(0.12, 150, 60, 30.0)                     # el empujón del arranque
    cut = delay(0.5 * whoosh(0.12, 2500, j(6500), 3000, 0.4, 0.35, (2.4, 1.8), 0.4), d * 0.4)
    return finish(mix(rip, kick, cut), (0.1, 0.4, 4500.0))


def sword_swing():
    d = j(0.26)
    x = whoosh(d, j(700), j(2700), j(1100), 0.45, 0.42, (2.2, 1.7), 0.35)
    return finish(mix(x, 0.1 * blade_sing(0.3, j(2650), d * 0.4, 11.0)), (0.08, 0.4, 4500.0))


def sword_heavy():
    d = j(0.38)
    x = whoosh(d, j(480), j(2200), j(800), 0.5, 0.5, (2.4, 1.5), 0.35, 0.3)
    return finish(mix(x, 0.16 * blade_sing(0.42, j(2300), d * 0.45, 8.0)), (0.1, 0.45, 4500.0))


def great_swing():
    d = j(0.44)
    x = whoosh(d, j(220), j(1100), j(360), 0.5, 0.6, (2.2, 1.5), 0.2, 0.6)
    sub = 0.3 * np.sin(TAU * j(68) * tvec(d)) * bell(d, 0.5, 2.5, 2.0)      # masa de aire que empuja
    return finish(mix(x, sub, 0.06 * blade_sing(0.35, j(950), d * 0.45, 9.0)), (0.1, 0.5, 3800.0), low_cut=28.0)


def great_heavy():
    d = j(0.56)
    x = whoosh(d, j(170), j(900), j(240), 0.55, 0.65, (2.6, 1.4), 0.2, 0.8)
    sub = 0.42 * np.sin(TAU * j(58) * tvec(d)) * bell(d, 0.55, 2.5, 2.0)
    return finish(mix(x, sub, 0.08 * blade_sing(0.4, j(820), d * 0.5, 8.0)), (0.12, 0.55, 3600.0), low_cut=28.0)


def chain_rattle(dur, clinks):
    out = np.zeros(n_of(dur))
    for _ in range(clinks):
        g = ring(0.05, rng.uniform(1700.0, 3400.0), BLUNT, 70.0, 0.5)
        at = int(rng.uniform(0.1, 0.8) * (len(out) - len(g)))
        out[at: at + len(g)] += g * rng.uniform(0.4, 1.0)
    return out


def mace_swing():
    d = j(0.42)
    x = whoosh(d, j(150), j(760), j(250), 0.5, 0.7, (2.0, 1.4), 0.12, 0.7)
    sub = 0.35 * np.sin(TAU * j(60) * tvec(d)) * bell(d, 0.5, 2.5, 2.0)
    return finish(mix(x, sub, 0.07 * chain_rattle(d, 6)), (0.1, 0.5, 3500.0), low_cut=28.0)


def mace_spin():
    d = j(0.72)
    fc = logcurve(d, [(0.0, 150), (0.3, j(700)), (0.5, 330), (0.72, j(780)), (1.0, 200)])
    turn = 0.35 + 0.65 * np.sin(np.pi * 2.0 * np.linspace(0.0, 1.0, n_of(d))) ** 2     # dos pasadas de la cabeza
    e = bell(d, 0.5, 1.2, 1.2) * turn
    x = swept_noise(d, fc, 0.7) * e + 0.7 * swept_noise(d, fc * 0.3, 0.5) * e
    sub = 0.3 * np.sin(TAU * j(56) * tvec(d)) * e
    return finish(mix(x, sub, 0.06 * chain_rattle(d, 9)), (0.12, 0.55, 3500.0), low_cut=28.0)


def mace_ground():
    """La maza contra el suelo: golpe grave, piedra que se parte, metal sordo y cascotes."""
    boom = thump(0.6, j(82), j(36), 7.0, 0.05)
    crack = 0.7 * crunch(0.12, 14, 300, 2600, (1.0, 3.0))
    clang = 0.4 * ring(0.4, j(410), BLUNT, 14.0, 1.2)
    slap = 0.6 * lp(white(0.08), 1400) * env_exp(0.08, 45.0)
    debris = delay(0.25 * crunch(0.6, 26, 500, 3800, (1.0, 1.8)) * lincurve(0.6, [(0, 1), (1, 0.1)]), 0.07)
    return finish(mix(boom, crack, clang, slap, debris), (0.2, 0.7, 3200.0), drive=2.2, low_cut=24.0)


def spear_thrust():
    d = j(0.2)
    x = whoosh(d, j(1100), j(4300), j(1700), 0.3, 0.38, (2.6, 1.5), 0.45)
    shaft = 0.35 * bp(white(0.06), j(320), 1.5) * env_exp(0.06, 60.0, 0.004)      # el asta al empujar
    return finish(mix(x, shaft, 0.07 * blade_sing(0.2, j(3500), d * 0.3, 18.0)), (0.08, 0.35, 4800.0))


# ───────────────────────────── armas: impactos ─────────────────────────────

def cut_noise(dur, f0, f1, width=0.5):
    """El filo atravesando: ruido que baja de tono muy rápido."""
    return swept_noise(dur, logcurve(dur, [(0.0, f0), (1.0, f1)]), width) * env_exp(dur, 4.5 / dur, 0.0008)


def impact_sword():
    cut = cut_noise(0.07, j(6500), j(1700))
    body = 0.8 * thump(0.2, j(150), j(68), 32.0)
    wet = 0.3 * squelch(0.12, 5, 500, 1800)
    steel = 0.24 * ring(0.4, j(2750), BLADE, 10.0, 0.9)
    return finish(mix(cut, body, wet, steel), (0.12, 0.45, 4500.0), drive=1.6)


def impact_great():
    cut = 0.9 * cut_noise(0.1, j(3600), j(650), 0.6)
    body = thump(0.4, j(112), j(44), 15.0, 0.04)
    bone = 0.5 * crunch(0.07, 7, 1200, 4200)
    wet = 0.3 * squelch(0.16, 6, 300, 1200)
    steel = 0.3 * ring(0.5, j(790), BLADE, 8.0, 1.0)
    return finish(mix(cut, body, bone, wet, steel), (0.16, 0.55, 3800.0), drive=2.2, low_cut=28.0)


def impact_dagger():
    tick = 0.7 * hp(white(0.006), 3000) * env_exp(0.006, 700.0, 0.0003)
    stab = 0.9 * cut_noise(0.035, j(7500), j(2800), 0.4)
    body = 0.55 * thump(0.1, j(230), j(110), 60.0, 0.015)
    wet = 0.35 * squelch(0.07, 3, 900, 2600)
    steel = 0.1 * ring(0.12, j(5200), BLADE, 30.0, 0.6)
    return finish(mix(tick, stab, body, wet, steel), (0.07, 0.3, 5000.0), drive=1.4)


def impact_mace():
    body = thump(0.45, j(96), j(40), 13.0, 0.045)
    smack = 0.7 * bp(white(0.05), j(900), 1.2) * env_exp(0.05, 70.0, 0.0006)
    bone = 0.65 * crunch(0.09, 10, 1400, 4800)
    bonk = 0.38 * ring(0.3, j(310), BLUNT, 18.0, 1.3)
    wet = 0.2 * squelch(0.12, 4, 250, 900)
    return finish(mix(body, smack, bone, bonk, wet), (0.16, 0.55, 3500.0), drive=2.6, low_cut=26.0)


# ───────────────────────────── voces ─────────────────────────────

VOWELS = {
    "A": (730, 1090, 2440), "E": (530, 1840, 2480), "I": (270, 2290, 3010), "O": (570, 840, 2410),
    "U": (300, 870, 2240), "UH": (640, 1190, 2390), "AE": (660, 1720, 2410),
}
F_BW = (70.0, 95.0, 130.0, 190.0, 240.0)
F_AMP = (1.0, 0.63, 0.35, 0.2, 0.1)


def glottal(dur, f0, jitter=0.02, shimmer=0.08, sub=0.0, growl=None, breath=0.1, drop=0.0, tilt=2600.0):
    """Fuente de la voz: pulsos de las cuerdas vocales.
    jitter/shimmer = irregularidad de tono/volumen; sub = un pulso de cada dos más débil (voz rota);
    growl = (Hz, profundidad) de gruñido; drop = pulsos que fallan (voz frita); breath = aire."""
    n = n_of(dur)
    f = np.broadcast_to(np.asarray(f0, dtype=float), (n,)) * (
        1.0 + jitter * smooth_noise(n, 35.0) + 0.5 * jitter * smooth_noise(n, 6.0))
    phase = np.cumsum(f) / RATE
    cyc = np.floor(phase).astype(int)
    ph = phase - cyc
    src = (2.0 * ph - 1.0) - 0.3 * np.sin(TAU * ph)            # apertura suave, cierre brusco
    amp = 1.0 + shimmer * rng.standard_normal(cyc[-1] + 2)
    if sub > 0.0:
        amp[1::2] *= 1.0 - sub
    if drop > 0.0:
        amp[rng.random(len(amp)) < drop] *= 0.15
    src = src * amp[cyc]
    if growl:
        gph = np.cumsum(growl[0] * (1.0 + 0.15 * smooth_noise(n, 9.0))) / RATE
        src = src * (1.0 - growl[1] * (0.5 + 0.5 * np.sin(TAU * gph)) ** 2)
    src = lp(src, tilt, 1)
    if breath > 0.0:
        src = src + 0.5 * breath * hp(rng.uniform(-1.0, 1.0, n), 1800.0) * (0.6 + 0.4 * (1.0 - ph))
    return src


def formants(src, vowel, size=1.0, bw=1.0):
    freqs = [x * size for x in VOWELS[vowel]] + [3500.0 * size, 4500.0 * size]

    def gain(f):
        g = np.full_like(f, 0.012)
        for fi, bi, ai in zip(freqs, F_BW, F_AMP):
            g += ai / np.sqrt(1.0 + ((f - fi) / (bi * bw)) ** 2)
        return g
    return spec_filter(src, gain)


def vocal(src, path, size=1.0, bw=1.0):
    """Tracto vocal: pasa por las vocales de `path` [(t 0..1, vocal)]; `size` < 1 = garganta grande (grave)."""
    n = len(src)
    t = np.linspace(0.0, 1.0, n)
    xs = [p[0] for p in path]
    done = {}
    out = np.zeros(n)
    for i, (_, v) in enumerate(path):
        if v not in done:
            done[v] = formants(src, v, size, bw)
        w = np.interp(t, xs, [1.0 if k == i else 0.0 for k in range(len(path))])
        out += done[v] * w
    return out


def breath_out(dur, fc, decay):
    return bp(white(dur), fc, 0.8) * env_exp(dur, decay, 0.03)


# Goblin: garganta pequeña, voz aguda y rasposa.
GOB = dict(jitter=0.045, shimmer=0.15, sub=0.35, breath=0.25, tilt=3200.0)


def goblin_warn():
    d = j(0.5)
    f0 = logcurve(d, [(0.0, j(230)), (0.55, j(390)), (1.0, j(320))])
    v = vocal(glottal(d, f0, growl=(j(58), 0.6), **GOB), [(0.0, "UH"), (0.5, "E"), (1.0, "AE")], 1.3, 1.3)
    return finish(v * bell(d, 0.6, 1.3, 1.2), (0.12, 0.45, 4200.0), drive=3.0)


def goblin_swing():
    d = j(0.26)
    f0 = logcurve(d, [(0.0, j(430)), (1.0, j(290))])
    v = vocal(glottal(d, f0, growl=(j(62), 0.45), **GOB), [(0.0, "I"), (0.35, "A"), (1.0, "A")], 1.3, 1.3)
    v = v / np.max(np.abs(v)) * bell(d, 0.2, 1.0, 1.6)
    air = 0.45 * whoosh(0.22, 600, j(2300), 900, 0.45, 0.45, (2.0, 1.6), 0.3)       # el tajo de su arma
    return finish(mix(v, delay(air, 0.05)), (0.1, 0.4, 4200.0), drive=2.6)


def goblin_hurt():
    d = j(0.3)
    f0 = logcurve(d, [(0.0, j(540)), (0.3, j(470)), (1.0, j(320))])
    v = vocal(glottal(d, f0, growl=(j(70), 0.35), **GOB), [(0.0, "E"), (0.5, "AE"), (1.0, "A")], 1.3, 1.3)
    return finish(v * bell(d, 0.12, 0.8, 1.5), (0.1, 0.4, 4200.0), drive=2.8)


def goblin_die():
    d = j(0.85)
    f0 = logcurve(d, [(0.0, j(480)), (0.25, j(400)), (0.6, j(250)), (1.0, j(130))])
    f0 = f0 * (1.0 + 0.05 * np.sin(TAU * j(11) * tvec(d)) * lincurve(d, [(0, 0), (1, 1)]))    # temblor al apagarse
    g = glottal(d, f0, growl=(j(46), 0.7), jitter=0.06, shimmer=0.2, sub=0.5, breath=0.35, drop=0.08, tilt=3000.0)
    v = vocal(g, [(0.0, "AE"), (0.3, "A"), (0.65, "UH"), (1.0, "O")], 1.3, 1.3)
    v = v / np.max(np.abs(v)) * bell(d, 0.1, 0.8, 1.1)
    gurgle = delay(0.3 * squelch(0.35, 9, 250, 900), d * 0.55)
    return finish(mix(v, gurgle), (0.14, 0.5, 4000.0), drive=3.0)


# Zombi: voz rota, lenta, con mucho aire.
ZOM = dict(jitter=0.09, shimmer=0.25, sub=0.6, breath=0.6, drop=0.12, tilt=1900.0)


def zombie_warn():
    d = j(0.85)
    f0 = logcurve(d, [(0.0, j(84)), (0.5, j(108)), (1.0, j(78))])
    v = vocal(glottal(d, f0, growl=(j(27), 0.6), **ZOM), [(0.0, "U"), (0.5, "O"), (1.0, "UH")], 0.92, 1.5)
    return finish(v * bell(d, 0.45, 1.5, 1.3), (0.16, 0.6, 3200.0), drive=2.0)


def zombie_swing():
    d = j(0.36)
    f0 = logcurve(d, [(0.0, j(120)), (1.0, j(86))])
    v = vocal(glottal(d, f0, growl=(j(32), 0.5), **ZOM), [(0.0, "UH"), (1.0, "A")], 0.92, 1.5)
    v = v / np.max(np.abs(v)) * bell(d, 0.2, 1.0, 1.4)
    air = 0.35 * whoosh(0.28, 250, j(900), 380, 0.45, 0.6, (2.0, 1.5), 0.15, 0.4)   # el brazo que cae
    return finish(mix(v, delay(air, 0.06)), (0.14, 0.55, 3200.0), drive=2.0)


def zombie_hurt():
    d = j(0.4)
    f0 = logcurve(d, [(0.0, j(135)), (1.0, j(88))])
    v = vocal(glottal(d, f0, growl=(j(30), 0.5), **ZOM), [(0.0, "A"), (1.0, "UH")], 0.92, 1.5)
    return finish(v * bell(d, 0.1, 0.8, 1.4), (0.14, 0.55, 3200.0), drive=2.2)


def zombie_die():
    d = j(1.1)
    f0 = logcurve(d, [(0.0, j(118)), (0.4, j(90)), (1.0, j(55))])
    g = glottal(d, f0, growl=(j(22), 0.75), jitter=0.1, shimmer=0.3, sub=0.7, breath=0.8, drop=0.2, tilt=1700.0)
    v = vocal(g, [(0.0, "A"), (0.4, "O"), (1.0, "U")], 0.92, 1.5)
    v = v / np.max(np.abs(v)) * bell(d, 0.12, 0.8, 1.0)
    return finish(mix(v, delay(0.35 * breath_out(0.6, 700.0, 5.0), d * 0.5)), (0.18, 0.7, 3000.0), drive=2.0)


def zombie_rise():
    """Se vuelve a levantar: gemido que sube."""
    d = 0.95
    f0 = logcurve(d, [(0.0, 62), (0.7, 104), (1.0, 122)])
    g = glottal(d, f0, growl=(24, 0.7), **ZOM)
    v = vocal(g, [(0.0, "U"), (0.6, "O"), (1.0, "A")], 0.92, 1.5)
    return finish(v * bell(d, 0.75, 1.6, 1.0), (0.18, 0.7, 3000.0), drive=2.4)


# Bruto: pecho enorme, rugido grave.
BRU = dict(jitter=0.05, shimmer=0.18, sub=0.5, breath=0.3, tilt=2200.0)


def chest(dur, f, e):
    """Resonancia de pecho por debajo de la voz."""
    return 0.45 * lp(np.sin(TAU * np.cumsum(f * 0.5) / RATE) * e, 160.0)


def brute_warn():
    d = j(0.9)
    f0 = logcurve(d, [(0.0, j(66)), (0.4, j(98)), (1.0, j(72))])
    e = bell(d, 0.4, 1.4, 1.2)
    v = vocal(glottal(d, f0, growl=(j(37), 0.75), **BRU), [(0.0, "O"), (0.45, "A"), (1.0, "O")], 0.68, 1.4)
    v = v / np.max(np.abs(v)) * e
    return finish(mix(v, chest(d, f0, e)), (0.2, 0.75, 3000.0), drive=3.6, low_cut=28.0)


def brute_swing():
    d = j(0.46)
    f0 = logcurve(d, [(0.0, j(112)), (1.0, j(70))])
    e = bell(d, 0.18, 1.0, 1.4)
    v = vocal(glottal(d, f0, growl=(j(42), 0.6), **BRU), [(0.0, "UH"), (0.4, "A"), (1.0, "O")], 0.68, 1.4)
    v = v / np.max(np.abs(v)) * e
    air = 0.5 * whoosh(0.4, 160, j(700), 240, 0.5, 0.7, (2.0, 1.4), 0.1, 0.7)
    return finish(mix(v, chest(d, f0, e), delay(air, 0.06)), (0.16, 0.65, 3000.0), drive=3.2, low_cut=28.0)


def brute_hurt():
    d = j(0.42)
    f0 = logcurve(d, [(0.0, j(128)), (1.0, j(80))])
    e = bell(d, 0.1, 0.8, 1.4)
    v = vocal(glottal(d, f0, growl=(j(45), 0.55), **BRU), [(0.0, "A"), (1.0, "UH")], 0.68, 1.4)
    v = v / np.max(np.abs(v)) * e
    return finish(mix(v, chest(d, f0, e)), (0.16, 0.65, 3000.0), drive=3.4, low_cut=28.0)


def brute_die():
    d = j(1.3)
    f0 = logcurve(d, [(0.0, j(110)), (0.3, j(88)), (1.0, j(42))])
    e = bell(d, 0.1, 0.8, 1.0)
    g = glottal(d, f0, growl=(j(30), 0.8), jitter=0.07, shimmer=0.25, sub=0.65, breath=0.5, drop=0.1, tilt=2000.0)
    v = vocal(g, [(0.0, "A"), (0.35, "O"), (1.0, "U")], 0.68, 1.4)
    v = v / np.max(np.abs(v)) * e
    fall = delay(0.6 * thump(0.4, 70, 34, 9.0, 0.05), d * 0.8)                    # el cuerpo al caer
    return finish(mix(v, chest(d, f0, e), fall), (0.2, 0.8, 2900.0), drive=3.4, low_cut=26.0)


# Mago: voz limpia y un brillo de cristal que acompaña al hechizo.
MAG = dict(jitter=0.015, shimmer=0.05, breath=0.2, tilt=3000.0)


def sparkle(dur, base, rising=True):
    out = np.zeros(n_of(dur))
    for i in range(9):
        k = i / 8.0
        g = ring(0.16, base * 2.0 ** ((k if rising else 1.0 - k) * 1.2), [1.0, 2.01, 3.03], 26.0, 0.4)
        at = int(k * 0.8 * (len(out) - len(g)))
        out[at: at + len(g)] += g * (0.5 + 0.5 * k if rising else 1.0 - 0.6 * k)
    return out


def mage_warn():
    d = j(0.6)
    f0 = logcurve(d, [(0.0, j(176)), (0.7, j(236)), (1.0, j(262))])
    v = vocal(glottal(d, f0, **MAG), [(0.0, "U"), (0.5, "O"), (1.0, "A")], 1.0, 1.0)
    v = v / np.max(np.abs(v)) * bell(d, 0.75, 1.5, 1.0)
    return finish(mix(v, 0.3 * sparkle(d, j(1500), True)), (0.22, 0.8, 5200.0), drive=1.2)


def mage_hurt():
    d = j(0.3)
    f0 = logcurve(d, [(0.0, j(300)), (1.0, j(205))])
    v = vocal(glottal(d, f0, breath=0.4, jitter=0.03, shimmer=0.1, tilt=3000.0), [(0.0, "A"), (1.0, "UH")], 1.0, 1.0)
    v = v / np.max(np.abs(v)) * bell(d, 0.1, 0.8, 1.5)
    return finish(mix(v, 0.14 * ring(0.2, j(2400), [1.0, 2.01, 3.03], 22.0, 0.4)), (0.16, 0.6, 5000.0), drive=1.4)


def mage_die():
    d = j(0.9)
    f0 = logcurve(d, [(0.0, j(270)), (0.4, j(215)), (1.0, j(120))])
    g = glottal(d, f0, breath=0.5, jitter=0.04, shimmer=0.12, sub=0.2, tilt=2800.0)
    v = vocal(g, [(0.0, "A"), (0.5, "O"), (1.0, "U")], 1.0, 1.0)
    v = v / np.max(np.abs(v)) * bell(d, 0.1, 0.8, 1.2)
    fizz = 0.3 * swept_noise(d, logcurve(d, [(0.0, 6000), (1.0, 500)]), 0.5) * bell(d, 0.3, 1.0, 1.5)   # el poder se disipa
    return finish(mix(v, fizz, 0.25 * sparkle(d, j(2600), False)), (0.24, 0.9, 5000.0), drive=1.3)


# Nigromante: no habla, susurra; un coro hueco por debajo y cola larga.
def choir(dur, f0, vowels):
    out = np.zeros(n_of(dur))
    for k in (1.0, 1.012, 0.991, 1.498):
        out += vocal(glottal(dur, f0 * k, jitter=0.012, shimmer=0.04, breath=0.0, tilt=1500.0), vowels, 0.85, 0.9)
    return out / np.max(np.abs(out))


def whisper(dur, vowels):
    return vocal(hp(white(dur), 500.0), vowels, 0.85, 1.6)


def necro_warn():
    d = j(0.95)
    vow = [(0.0, "O"), (0.5, "U"), (1.0, "I")]
    f0 = logcurve(d, [(0.0, j(104)), (1.0, j(118))])
    e = bell(d, 0.7, 1.8, 1.0)
    w = whisper(d, vow)
    x = mix(0.8 * w / np.max(np.abs(w)) * e * (0.7 + 0.3 * smooth_noise(n_of(d), 14.0)), 0.6 * choir(d, f0, vow) * e)
    return finish(x, (0.35, 1.2, 3600.0), drive=1.2)


def necro_hurt():
    d = j(0.45)
    w = whisper(d, [(0.0, "I"), (1.0, "A")])
    f0 = logcurve(d, [(0.0, j(150)), (1.0, j(100))])
    e = bell(d, 0.08, 0.8, 1.4)
    x = mix(w / np.max(np.abs(w)) * e, 0.45 * choir(d, f0, [(0.0, "A"), (1.0, "O")]) * e)
    return finish(x, (0.3, 1.0, 3800.0), drive=1.4)


def necro_die():
    d = 1.5
    vow = [(0.0, "A"), (0.4, "O"), (1.0, "U")]
    f0 = logcurve(d, [(0.0, 190), (0.3, 150), (1.0, 62)])
    f0 = f0 * (1.0 + 0.03 * np.sin(TAU * 6.0 * tvec(d)))
    e = bell(d, 0.12, 0.8, 1.2)
    w = whisper(d, vow)
    x = mix(choir(d, f0, vow) * e, 0.6 * w / np.max(np.abs(w)) * e)
    return finish(x, (0.4, 1.6, 3400.0), drive=1.3)


def necro_summon():
    """Levanta a los muertos: zumbido grave que crece, susurros y huesos que se recolocan."""
    d = 1.2
    e = bell(d, 0.8, 2.2, 0.8)
    f0 = logcurve(d, [(0.0, 55), (1.0, 82)])
    w = whisper(d, [(0.0, "U"), (0.6, "O"), (1.0, "A")])
    bones = 0.35 * crunch(d, 22, 900, 3200, (2.5, 1.2))
    x = mix(0.8 * choir(d, f0, [(0.0, "U"), (1.0, "O")]) * e, 0.5 * w / np.max(np.abs(w)) * e, bones)
    return finish(x, (0.35, 1.3, 3400.0), drive=1.4, low_cut=28.0)


def player_hurt():
    """Quejido corto del personaje (antes era el del goblin más grave)."""
    d = j(0.24)
    f0 = logcurve(d, [(0.0, j(190)), (1.0, j(128))])
    g = glottal(d, f0, jitter=0.03, shimmer=0.1, sub=0.15, breath=0.4, tilt=2400.0)
    v = vocal(g, [(0.0, "UH"), (1.0, "A")], 1.0, 1.1)
    v = v / np.max(np.abs(v)) * bell(d, 0.12, 0.8, 1.6)
    body = 0.7 * thump(0.14, 140, 62, 34.0)                                        # el golpe en el cuerpo
    return finish(mix(v, body), (0.08, 0.4, 4000.0), drive=1.8)


# ───────────────────────────── salida ─────────────────────────────

SOUNDS = [   # (nombre, función, variantes)
    ("dagger_swing", dagger_swing, 3), ("dagger_spin", dagger_spin, 2), ("dagger_dash", dagger_dash, 2),
    ("sword_swing", sword_swing, 3), ("sword_heavy", sword_heavy, 2),
    ("great_swing", great_swing, 3), ("great_heavy", great_heavy, 2),
    ("mace_swing", mace_swing, 3), ("mace_spin", mace_spin, 2), ("mace_ground", mace_ground, 2),
    ("spear_thrust", spear_thrust, 3),
    ("impact_sword", impact_sword, 3), ("impact_great", impact_great, 3),
    ("impact_dagger", impact_dagger, 3), ("impact_mace", impact_mace, 3),
    ("goblin_warn", goblin_warn, 2), ("goblin_swing", goblin_swing, 3),
    ("goblin_hurt", goblin_hurt, 3), ("goblin_die", goblin_die, 3),
    ("zombie_warn", zombie_warn, 2), ("zombie_swing", zombie_swing, 2),
    ("zombie_hurt", zombie_hurt, 3), ("zombie_die", zombie_die, 2), ("zombie_rise", zombie_rise, 1),
    ("brute_warn", brute_warn, 2), ("brute_swing", brute_swing, 2),
    ("brute_hurt", brute_hurt, 3), ("brute_die", brute_die, 2),
    ("mage_warn", mage_warn, 2), ("mage_hurt", mage_hurt, 2), ("mage_die", mage_die, 2),
    ("necro_warn", necro_warn, 2), ("necro_hurt", necro_hurt, 2),
    ("necro_die", necro_die, 1), ("necro_summon", necro_summon, 1),
    ("player_hurt", player_hurt, 3),
]


def main():
    only = sys.argv[1:]
    for name, fn, count in SOUNDS:
        for i in range(count):
            x = fn()            # siempre se sintetiza: la semilla avanza igual aunque se filtre por prefijo
            if not only or any(name.startswith(p) for p in only):
                write(name if i == 0 else "%s_%d" % (name, i + 1), x)


if __name__ == "__main__":
    main()
