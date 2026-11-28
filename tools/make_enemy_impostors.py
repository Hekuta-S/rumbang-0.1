"""Impostores de los enemigos (sprites 2D de móvil) en estilo cartoon (paso 2 de 2; el 1 es
tools/bake_enemy_impostors.gd).

Lee las tiras crudas de assets/vat/raw/ (color iluminado, normales de cara y profundidad, RENDER px por celda)
y por cada celda:
  - sombreado cel: la luz del render se aplana en bandas (mismos colores)
  - tinta en las ARISTAS: donde la normal de la superficie cambia de golpe (pliegues, orejas, nariz, dedos)
  - tinta en los SOLAPES: donde la profundidad salta (un brazo delante del cuerpo, la cabeza sobre el hombro)
  - contorno de tinta por fuera de la silueta
  - reducción a la mitad (bordes suaves) y alfa duro (el shader recorta en 0,5)
Después recorta todas las celdas a la caja común que ocupa la silueta (no se guardan píxeles vacíos) y monta
assets/vat/<clave>_impostor.png (filas = ángulos, columnas = idle + caminar) y <clave>_impostor.json.

Las criaturas de las cloacas (tools/bake_creature_sprites.gd) pasan por lo mismo: argumento "creatures" (o sus
claves con el prefijo "c:"); su atlas es assets/creatures/<clave>_sprites.png y se completa su .json.

Uso: python tools/make_enemy_impostors.py [clave | creatures | c:clave ...]   (después: godot --headless --path . --import)
"""
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VAT = os.path.join(ROOT, "assets", "vat")
RAW = os.path.join(VAT, "raw")
KEYS = ["normal", "bruto", "magoblin", "zombie"]
CREATURES = os.path.join(ROOT, "assets", "creatures")
CREATURE_KEYS = ["rat", "rat_big", "slug", "bloater"]

INK = np.array([14, 10, 20], dtype=np.float32)
CREASE = 0.3             # 1 - cos(ángulo) entre normales vecinas a partir del que hay tinta (~45°)
DEPTH_JUMP = 0.06        # m de salto de profundidad entre vecinos que marcan un solape
OUTLINE_PX = 5           # a la resolución del render (2,5 px en el atlas)
BANDS = 3                # bandas del sombreado cel
CEL_MIX = 0.55           # cuánto se aplana la luz (0 = como sale del render, 1 = bandas puras)
MARGIN = 2               # px de margen del recorte (en el atlas)


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def shift(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    out[max(0, dy):min(h, h + dy), max(0, dx):min(w, w + dx)] = \
        a[max(0, -dy):min(h, h - dy), max(0, -dx):min(w, w - dx)]
    return out


def dilate(mask, r):
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if (dx or dy) and dx * dx + dy * dy <= r * r + 1:
                out |= shift(mask, dx, dy)
    return out


def ink_strip(col, nrm, dep, depth_range):
    """Entinta una tira entera (todas las celdas de un ángulo a la vez: los bordes de celda están vacíos)."""
    alpha = col[..., 3] > 127
    rgb = col[..., :3].astype(np.float32) / 255.0
    # cel: luminancia en bandas por cuantiles de la silueta, mezclada con la original (mismos colores)
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    if alpha.any():
        qs = np.quantile(lum[alpha], [(i + 1) / BANDS for i in range(BANDS - 1)])
        idx = np.digitize(lum, qs)
        target = lum.copy()
        for b in range(BANDS):
            m = (idx == b) & alpha
            if m.any():
                target[m] = lum[m].mean()
        new_l = lum * (1.0 - CEL_MIX) + target * CEL_MIX
        rgb = rgb * (new_l / np.maximum(lum, 1e-4))[..., None]
    out = np.clip(rgb, 0.0, 1.0) * 255.0
    # normales de cara (vista) y profundidad (m)
    n = srgb_to_linear(nrm[..., :3].astype(np.float32) / 255.0) * 2.0 - 1.0
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-5)
    hi = np.round(srgb_to_linear(dep[..., 0].astype(np.float32) / 255.0) * 32.0)
    lo = srgb_to_linear(dep[..., 1].astype(np.float32) / 255.0)
    d = (hi + lo) / 32.0 * depth_range
    ink = np.zeros(alpha.shape, dtype=bool)
    for dx, dy in ((1, 0), (0, 1), (1, 1), (1, -1)):
        na = shift(alpha, dx, dy) & alpha
        crease = (1.0 - np.sum(n * shift(n, dx, dy), axis=-1)) > CREASE
        # solape: se marca el lado de DELANTE (el más cercano), así la línea queda sobre la pieza que tapa
        dd = shift(d, dx, dy) - d
        ink |= na & (crease | (dd > DEPTH_JUMP))
        ink |= shift(na & (-dd > DEPTH_JUMP), -dx, -dy) & alpha
    ink = ink | shift(ink, 1, 0) | shift(ink, 0, 1)   # ~3 px a la resolución del render (1,5 px en el atlas)
    out[ink] = INK
    sil = dilate(alpha, OUTLINE_PX)
    out[sil & ~alpha] = INK
    out[~sil] = INK                       # fondo con el color de la tinta: sin halo claro con los mipmaps
    rgba = np.dstack([out, sil.astype(np.float32) * 255.0]).astype(np.uint8)
    h, w = rgba.shape[:2]
    half = np.array(Image.fromarray(rgba, "RGBA").resize((w // 2, h // 2), Image.BOX))
    half[..., 3] = np.where(half[..., 3] >= 128, 255, 0)
    return half


def crop_atlas(strips, cols, cell):
    """Recorta todas las celdas a la caja común de la silueta y las monta (filas = ángulos)."""
    x0, y0, x1, y1 = cell, cell, -1, -1
    for s in strips:
        a = s[..., 3] > 0
        for c in range(cols):
            ys, xs = np.nonzero(a[:, c * cell:(c + 1) * cell])
            if xs.size:
                x0, x1 = min(x0, int(xs.min())), max(x1, int(xs.max()))
                y0, y1 = min(y0, int(ys.min())), max(y1, int(ys.max()))
    x0, y0 = max(0, x0 - MARGIN), max(0, y0 - MARGIN)
    x1, y1 = min(cell, x1 + MARGIN + 1), min(cell, y1 + MARGIN + 1)
    cw, ch = x1 - x0, y1 - y0
    atlas = np.zeros((ch * len(strips), cw * cols, 4), dtype=np.uint8)
    for row, s in enumerate(strips):
        for c in range(cols):
            atlas[row * ch:(row + 1) * ch, c * cw:(c + 1) * cw] = s[y0:y1, c * cell + x0:c * cell + x1]
    return atlas, (x0, y0, x1, y1), cw, ch


def ink_rows(raw_dir, key, angles, depth_range):
    strips = []
    for row in range(angles):
        load = lambda p: np.array(Image.open(os.path.join(raw_dir, "%s_%s_%d.png" % (key, p, row))).convert("RGBA"))
        strips.append(ink_strip(load("color"), load("normal"), load("depth"), depth_range))
    return strips


def make(key):
    info = json.load(open(os.path.join(RAW, key + "_raw.json"), encoding="utf-8"))
    angles, cols, render = int(info["angles"]), int(info["cols"]), int(info["render"])
    cell = render // 2
    strips = ink_rows(RAW, key, angles, float(info["depth_range"]))
    atlas, (x0, y0, x1, y1), cw, ch = crop_atlas(strips, cols, cell)
    Image.fromarray(atlas, "RGBA").save(os.path.join(VAT, key + "_impostor.png"), optimize=True)
    elev = np.radians(float(info["elevation_deg"]))
    span = float(info["span"])
    out = {
        "angles": angles, "cols": cols, "cell": cell, "cell_w": cw, "cell_h": ch,
        "idle_sprites": info["idle_sprites"], "walk_sprites": info["walk_sprites"],
        "idle_fps": info["idle_fps"], "walk_fps": info["walk_fps"],
        # el cuadrado entero (celda sin recortar) en el mundo; crop = la parte que se guarda y se dibuja
        "quad_w": span, "quad_h": span / float(np.cos(elev)), "center_y": info["center_y"],
        "crop": [x0 / cell, y0 / cell, x1 / cell, y1 / cell],
        "elevation_deg": info["elevation_deg"],
    }
    with open(os.path.join(VAT, key + "_impostor.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent="	")
    print("%s: atlas %dx%d, celda %dx%d" % (key, atlas.shape[1], atlas.shape[0], cw, ch))


def make_creature(key):
    path = os.path.join(CREATURES, key + "_sprites.json")
    info = json.load(open(path, encoding="utf-8"))
    cell = int(info["render"]) // 2
    strips = ink_rows(os.path.join(CREATURES, "raw"), key, int(info["angles"]), float(info["depth_range"]))
    atlas, (x0, y0, x1, y1), cw, ch = crop_atlas(strips, int(info["cols"]), cell)
    Image.fromarray(atlas, "RGBA").save(os.path.join(CREATURES, key + "_sprites.png"), optimize=True)
    info.update({"cell": cell, "cell_w": cw, "cell_h": ch, "crop": [x0 / cell, y0 / cell, x1 / cell, y1 / cell]})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(info, f, indent="	")
    print("%s: atlas %dx%d, celda %dx%d" % (key, atlas.shape[1], atlas.shape[0], cw, ch))


if __name__ == "__main__":
    for k in (sys.argv[1:] or KEYS):
        if k == "creatures":
            for c in CREATURE_KEYS:
                make_creature(c)
        elif k.startswith("c:"):
            make_creature(k[2:])
        else:
            make(k)
