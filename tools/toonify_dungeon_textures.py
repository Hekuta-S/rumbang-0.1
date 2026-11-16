"""Pasa las texturas repetibles de la mazmorra a estilo cartoon con la TINTA HORNEADA en el albedo.

    python tools/toonify_dungeon_textures.py [nombre1,nombre2]

Para cada assets/textures/dungeon/<nombre>_albedo.png (con su <nombre>_normal.png):
  - aplana el color en bandas (posterizado suave, sin el grano de la foto);
  - hornea el relieve del normal map como luz/sombra en bandas (luz desde arriba a la izquierda);
  - dibuja tinta donde el relieve cambia de golpe (bordes de grietas, piedras y vetas) y en los huecos;
  - conserva el brillo medio (los shaders compensan con tint_gain) y la repetición (todo el filtrado va
    por FFT, que es periódica).
El original se guarda una vez en assets/textures/dungeon/orig/ (con .gdignore) y siempre se parte de él,
así que se puede repetir cambiando parámetros. Los normal maps no se tocan.
"""
import os
import shutil
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets", "textures", "dungeon")
ORIG = os.path.join(TEX, "orig")
INK = np.array([0.055, 0.045, 0.07], dtype=np.float32)

# nombre: (bandas de color, cantidad de tinta 0..1, grosor de trazo en px a 1024)
PRESETS = {
    "rock": (5, 0.075, 1.8),
    "ground": (5, 0.07, 1.8),
    "wood": (4, 0.045, 1.6),
    "stone": (4, 0.07, 1.8),
    "brick": (4, 0.085, 2.0),
    "flagstone": (4, 0.075, 2.0),
    "straw": (4, 0.06, 1.5),
    "hide": (4, 0.035, 1.6),
    "bark": (4, 0.08, 1.7),
    "cave_scan": (5, 0.05, 3.2),
}


def blur(a, sigma):
    """Desenfoque gaussiano periódico (FFT): no rompe la repetición."""
    if sigma <= 0:
        return a
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    if a.ndim == 2:
        return np.fft.irfft2(np.fft.rfft2(a) * g, s=(h, w)).astype(np.float32)
    return np.stack([blur(a[..., c], sigma) for c in range(a.shape[2])], axis=2)


def smooth(a, lo, hi):
    t = np.clip((a - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def srgb_to_lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def toonify(name):
    bands, ink_amount, stroke = PRESETS[name]
    os.makedirs(ORIG, exist_ok=True)
    open(os.path.join(ORIG, ".gdignore"), "a").close()
    dst = os.path.join(TEX, name + "_albedo.png")
    src = os.path.join(ORIG, name + "_albedo.png")
    if not os.path.exists(src):
        shutil.copy2(dst, src)
    a = np.asarray(Image.open(src).convert("RGB"), dtype=np.float32) / 255.0
    n_img = Image.open(os.path.join(TEX, name + "_normal.png")).convert("RGB").resize((a.shape[1], a.shape[0]), Image.BILINEAR)
    n = np.asarray(n_img, dtype=np.float32) / 255.0 * 2.0 - 1.0
    k = a.shape[0] / 1024.0                                   # escala de los radios según el tamaño

    # ── color en bandas: luminancia posterizada sobre un color suavizado
    soft = blur(a, 2.0 * k)
    wide = blur(a, 5.0 * k)
    L = lum(soft)
    qs = np.quantile(L, [(i + 1) / bands for i in range(bands - 1)])
    idx = np.digitize(L, qs)
    target = np.zeros_like(L)
    for b in range(bands):
        m = idx == b
        if m.any():
            target[m] = L[m].mean()
    target = blur(target, 0.7 * k)                            # borde de banda sin dientes
    col = wide * (target / np.maximum(lum(wide), 1e-4))[..., None]

    # ── relieve horneado: luz desde arriba-izquierda en tres bandas
    d = blur(-n[..., 0] * 0.6 + n[..., 1] * 0.8, 1.2 * k)
    hi_t = np.quantile(d, 0.86)
    lo_t = np.quantile(d, 0.14)
    shade = 1.0 + 0.16 * smooth(d, hi_t * 0.8, hi_t) - 0.2 * smooth(-d, -lo_t * 0.8, -lo_t)
    col = col * shade[..., None]

    # ── tinta: saltos de relieve + huecos oscuros, consolidada en trazos
    slope = blur(np.hypot(n[..., 0], n[..., 1]), 1.0 * k)
    e = smooth(slope, np.quantile(slope, 1.0 - ink_amount * 1.6), np.quantile(slope, 1.0 - ink_amount * 0.5))
    dark = 1.0 - smooth(L, np.quantile(L, ink_amount * 0.25), np.quantile(L, ink_amount * 0.7))
    ink = np.maximum(e, dark)
    ink = smooth(blur(ink, stroke * k), 0.34, 0.52)
    ink = blur(ink, 0.6 * k)
    out = col * (1.0 - ink[..., None]) + INK * ink[..., None]

    # ── mismo brillo medio (lineal) que el original
    gain = srgb_to_lin(a).mean() / max(srgb_to_lin(np.clip(out, 0, 1)).mean(), 1e-5)
    out = np.clip(out, 0, 1)
    lin = srgb_to_lin(out) * gain
    out = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.clip(lin, 0, None) ** (1 / 2.4) - 0.055)
    Image.fromarray((np.clip(out, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGB").save(dst)
    print("toon", name, a.shape[:2], "tinta %.1f%%" % (ink.mean() * 100.0))


if __name__ == "__main__":
    names = sys.argv[1].split(",") if len(sys.argv) > 1 else list(PRESETS)
    for nm in names:
        toonify(nm)
