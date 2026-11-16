"""Pasa los IMPOSTORES de los enemigos (los sprites 2D que se usan en móvil, ver EnemyVisuals) a estilo cartoon
con la tinta HORNEADA en el atlas: contorno de tinta alrededor de la silueta, líneas de tinta en los cambios
fuertes de luz y color (bordes de ropa, cara, brazos) y sombreado cel suave (bandas). Mismos colores.

    python tools/toonify_enemy_impostors.py
    godot --headless --path . --script tools/crop_enemy_impostors.gd    (recalcula el recorte: el contorno
                                                                         sale un poco por fuera de la silueta)

Lee el original de assets/vat/orig/<clave>_impostor.png (lo copia ahí la primera vez, con .gdignore) y
escribe assets/vat/<clave>_impostor.png, así se puede repetir con otros parámetros.
"""
import json
import os
import shutil

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VAT = os.path.join(ROOT, "assets", "vat")
ORIG = os.path.join(VAT, "orig")
KEYS = ["normal", "bruto", "magoblin", "zombie"]
INK = np.array([0.04, 0.03, 0.06], np.float32)
OUTLINE_PX = 2            # contorno por fuera de la silueta (celda de 128 px)
BANDS = 4                 # bandas del sombreado cel
CEL_MIX = 0.6             # cuánto se aplana la luz (0 = como estaba, 1 = bandas puras)
EDGE_TOP = 0.05           # fracción de píxeles de la silueta con más contraste que llevan línea interior


def lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def blur(a, r):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0


def toonify(key):
    os.makedirs(ORIG, exist_ok=True)
    open(os.path.join(ORIG, ".gdignore"), "a").close()
    dst = os.path.join(VAT, key + "_impostor.png")
    src = os.path.join(ORIG, key + "_impostor.png")
    if not os.path.exists(src):
        shutil.copy2(dst, src)
    rgba = np.asarray(Image.open(src).convert("RGBA"), np.float32) / 255.0
    rgb, alpha = rgba[..., :3], rgba[..., 3]
    solid = alpha > 0.5
    info = json.load(open(os.path.join(VAT, key + "_impostor.json"), encoding="utf-8"))
    cell = int(info["cell"])

    # ── sombreado cel: luminancia en bandas (cuantiles de la silueta), mezclada con la original
    L = lum(rgb)
    qs = np.quantile(L[solid], [(i + 1) / BANDS for i in range(BANDS - 1)])
    idx = np.digitize(L, qs)
    target = np.zeros_like(L)
    for b in range(BANDS):
        m = (idx == b) & solid
        if m.any():
            target[m] = L[m].mean()
    target = np.where(solid, target, L)
    flat = rgb * (target / np.maximum(L, 1e-4))[..., None]
    col = rgb * (1 - CEL_MIX) + flat * CEL_MIX

    # ── líneas interiores: saltos fuertes de luz/color dentro de la silueta
    soft = np.stack([blur(rgb[..., c], 0.6) for c in range(3)], axis=2)
    gx = np.abs(np.roll(soft, -1, 1) - np.roll(soft, 1, 1)).sum(2)
    gy = np.abs(np.roll(soft, -1, 0) - np.roll(soft, 1, 0)).sum(2)
    g = np.hypot(gx, gy)
    inner = solid & (g > np.quantile(g[solid], 1.0 - EDGE_TOP))
    inner_s = blur(inner.astype(np.float32), 0.5)
    col = col * (1 - inner_s[..., None] * 0.85) + INK * inner_s[..., None] * 0.85

    # ── contorno: silueta engordada OUTLINE_PX (sin cruzar de una celda a otra)
    mask = Image.fromarray((solid * 255).astype(np.uint8))
    grown = np.asarray(mask.filter(ImageFilter.MaxFilter(OUTLINE_PX * 2 + 1)), np.float32) / 255.0 > 0.5
    h, w = solid.shape
    yy, xx = np.mgrid[0:h, 0:w]
    border = (xx % cell < OUTLINE_PX) | (xx % cell >= cell - OUTLINE_PX) | (yy % cell < OUTLINE_PX) | (yy % cell >= cell - OUTLINE_PX)
    ring = grown & ~solid & ~border
    # el borde de dentro de la silueta también en tinta (1 px): el contorno se lee aunque el sprite se vea pequeño
    eroded = np.asarray(mask.filter(ImageFilter.MinFilter(3)), np.float32) / 255.0 > 0.5
    rim = solid & ~eroded
    out_rgb = np.where((ring | rim)[..., None], INK, col)
    out_a = np.where(ring, 1.0, alpha)
    out = np.concatenate([np.clip(out_rgb, 0, 1), out_a[..., None]], axis=2)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA").save(dst)
    print("toon", key, rgba.shape[1], "x", rgba.shape[0], "· contorno %d px" % OUTLINE_PX)


if __name__ == "__main__":
    for k in KEYS:
        if os.path.exists(os.path.join(VAT, k + "_impostor.png")):
            toonify(k)
