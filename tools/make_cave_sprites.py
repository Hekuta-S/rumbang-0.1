"""Rocas de las Cavernas como dibujos cartoon horneados (paso 2 de 2; el 1 es tools/bake_cave_sprites.gd).

Lee las tiras crudas de assets/textures/toon/props/cave_raw/ (color sin luz + normales de vista + brillo en las
hojas que lo tienen, ANGLES celdas por pieza) y por cada celda:
  - sombreado cel en 3 bandas con una luz fija de arriba a la izquierda (no depende de la cámara del juego)
  - tinta interior donde la normal cambia de golpe (aristas marcadas de la roca)
  - contorno de tinta por fuera de la silueta
  - reducción a la mitad (bordes suaves de la tinta) y alfa duro (el shader recorta en 0,5)
Escribe assets/textures/toon/props/<hoja>.png (filas = piezas, columnas = ángulos), <hoja>.json y, si la hoja
tiene brillo (hongos, brasas), <hoja>_glow.png (máscara en gris).
Hojas: cave_rocks, cave_decor (= SHEETS de tools/bake_cave_sprites.gd).
Uso: python tools/make_cave_sprites.py [hoja ...]   (después: godot --headless --path . --import)
"""
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "assets", "textures", "toon", "props", "cave_raw")
OUT = os.path.join(ROOT, "assets", "textures", "toon", "props")

LIGHT = np.array([-0.45, 0.65, 0.6])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
BANDS = [(-1.0, 0.52), (0.12, 0.78), (0.5, 1.0)]     # (desde ndl, brillo)
INK = np.array([22, 15, 24], dtype=np.float32)
INNER_EDGE = 0.42        # 1 - cos(ángulo) entre normales vecinas a partir del que se dibuja tinta (~55°)
OUTLINE_PX = 6           # a la resolución cruda (512): ~3 px en el atlas


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def shift(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    xs0, xs1 = max(0, dx), min(w, w + dx)
    ys0, ys1 = max(0, dy), min(h, h + dy)
    out[ys0:ys1, xs0:xs1] = a[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
    return out


def process_cell(col, nrm):
    alpha = col[..., 3] > 127
    rgb = col[..., :3].astype(np.float32)
    n = srgb_to_linear(nrm[..., :3].astype(np.float32) / 255.0) * 2.0 - 1.0
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-5)
    ndl = n @ LIGHT
    shade = np.full(ndl.shape, BANDS[0][1], dtype=np.float32)
    for lo, b in BANDS[1:]:
        shade[ndl >= lo] = b
    out = rgb * shade[..., None]
    # tinta interior: salto de normal con un vecino (solo dentro de la silueta)
    edge = np.zeros(alpha.shape, dtype=bool)
    for dx, dy in ((1, 0), (0, 1), (2, 0), (0, 2)):
        nb = shift(n, dx, dy)
        na = shift(alpha, dx, dy)
        d = 1.0 - np.sum(n * nb, axis=-1)
        edge |= (d > INNER_EDGE) & alpha & na
    # dos píxeles de grosor a 512 (uno en el atlas)
    edge = edge | shift(edge, 1, 0) | shift(edge, 0, 1)
    out[edge & alpha] = INK
    # contorno exterior: dilatar la silueta con un disco
    dil = alpha.copy()
    r = OUTLINE_PX
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r + 1 and (dx or dy):
                dil |= shift(alpha, dx, dy)
    ring = dil & ~alpha
    out[ring] = INK
    a = dil.astype(np.float32)
    out[~dil] = INK                   # fondo con el color de la tinta: sin halo claro con los mipmaps
    img = np.dstack([np.clip(out, 0, 255), a * 255.0]).astype(np.uint8)
    half = Image.fromarray(img, "RGBA").resize((img.shape[1] // 2, img.shape[0] // 2), Image.BOX)
    h = np.array(half)
    h[..., 3] = np.where(h[..., 3] >= 128, 255, 0)
    return h


def glow_cell(glow, col):
    """Máscara de brillo reducida a la mitad (solo dentro de la silueta)."""
    g = glow[..., 0].astype(np.float32) * (col[..., 3] > 127)
    half = Image.fromarray(g.astype(np.uint8), "L").resize((g.shape[1] // 2, g.shape[0] // 2), Image.BOX)
    return np.array(half)


def make_sheet(sheet):
    meta = json.load(open(os.path.join(RAW, sheet + "_meta.json"), encoding="utf-8"))
    cell = int(meta["cell"])
    angles = int(meta["angles"])
    kinds = meta["kinds"]
    has_glow = bool(meta.get("glow", False))
    oc = cell // 2
    atlas = np.zeros((oc * len(kinds), oc * angles, 4), dtype=np.uint8)
    atlas[..., :3] = INK.astype(np.uint8)
    glow_atlas = np.zeros((oc * len(kinds), oc * angles), dtype=np.uint8)
    info = {"cell": oc, "angles": angles, "glow": has_glow, "kinds": {}}
    for row, k in enumerate(kinds):
        name = k["kind"]
        col = np.array(Image.open(os.path.join(RAW, name + "_color.png")).convert("RGBA"))
        nrm = np.array(Image.open(os.path.join(RAW, name + "_normal.png")).convert("RGBA"))
        glow = None
        if has_glow:
            glow = np.array(Image.open(os.path.join(RAW, name + "_glow.png")).convert("RGBA"))
        for a in range(angles):
            sl = slice(a * cell, (a + 1) * cell)
            atlas[row * oc:(row + 1) * oc, a * oc:(a + 1) * oc] = process_cell(col[:, sl], nrm[:, sl])
            if glow is not None:
                glow_atlas[row * oc:(row + 1) * oc, a * oc:(a + 1) * oc] = glow_cell(glow[:, sl], col[:, sl])
        info["kinds"][name] = {"row": row, "span": k["span"], "u0": k["u0"], "v0": k["v0"]}
        print("pieza", name)
    Image.fromarray(atlas, "RGBA").save(os.path.join(OUT, sheet + ".png"), optimize=True)
    if has_glow:
        Image.fromarray(glow_atlas, "L").save(os.path.join(OUT, sheet + "_glow.png"), optimize=True)
    with open(os.path.join(OUT, sheet + ".json"), "w", encoding="utf-8") as f:
        json.dump(info, f, indent="	")
    print("atlas", sheet, atlas.shape)


if __name__ == "__main__":
    for name in (sys.argv[1:] or ["cave_rocks", "cave_decor"]):
        make_sheet(name)
