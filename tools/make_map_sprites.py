"""Árboles y marcas del suelo DIBUJADOS (cómic 2D horneado) para el mapa de Supervivencia.

    python tools/make_map_sprites.py [hoja_de_revision.png]

Mismo lienzo entintado que los iconos y las armas 2D (tools/make_ui_icons.py: Pic). Sale en assets/textures/toon/:

  props/arboles.png   VARIANTS columnas x 3 filas, celdas cuadradas de CELL px. Base del tronco en (0,5, BASE_Y).
                      Fila 0 = árbol entero, fila 1 = tocón (lo que queda al talarlo, corte irregular a CUT_Y),
                      fila 2 = la parte de arriba (lo que cae). Las filas 1 y 2 encajan: juntas son la fila 0.
  fx/marcas.png       4 celdas en fila, vistas desde arriba: 0-1 cráter de explosión, 2-3 mancha de tinta.

TreeField (scripts/world/tree_field.gd) y MapMarks (scripts/world/map_marks.gd) leen estas constantes: si cambian
aquí, cambian allí.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_ui_icons import INK, Pic, rgb, circle_pts  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS_OUT = os.path.join(ROOT, "assets", "textures", "toon", "props")
FX_OUT = os.path.join(ROOT, "assets", "textures", "toon", "fx")
CELL = 384
VARIANTS = 4
BASE_Y = 0.97
STUMP_HALF = 0.13    ## media anchura (normalizada) de la franja del tocón
CUT_Y = 0.83          ## altura del corte (normalizada desde arriba): tocón de ~0,9 m en un sprite de 6 m
BARK = rgb(96, 82, 74)
BARK_DK = rgb(58, 48, 46)
BARK_LT = rgb(150, 132, 118)
WOOD_IN = rgb(214, 176, 120)
WOOD_RING = rgb(160, 118, 72)


def _pic(size):
    return Pic(size, ss=4, outer=0.012, inner=0.0045)


# ── árbol muerto ─────────────────────────────────────────────────────────

def _tapered(pts, widths):
    """Polígono de un trazo que se estrecha (sin costuras entre tramos, a diferencia de varios Pic.line)."""
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        h = widths[i] * 0.5
        left.append((x + nx * h, y + ny * h))
        right.append((x - nx * h, y - ny * h))
    return left + right[::-1]


def _grow(rnd, x, y, ang, length, width, segs, bend, taper):
    pts = [(x, y)]
    ws = [width]
    for k in range(segs):
        ang += rnd.uniform(-bend, bend)
        ang = max(-math.pi + 0.35, min(-0.35, ang))      # nunca hacia abajo
        x, y = x + math.cos(ang) * length / segs, y + math.sin(ang) * length / segs
        width *= taper
        pts.append((x, y))
        ws.append(width)
    return pts, ws, ang


def _branch(rnd, x, y, ang, length, width, depth, out):
    pts, ws, ang = _grow(rnd, x, y, ang, length, width, 4, 0.28, 0.8)
    out.append((pts, ws))
    x, y = pts[-1]
    w = ws[-1]
    if depth <= 0 or w < 0.006:
        return
    for k in range(rnd.choice([2, 2, 3])):
        spread = rnd.uniform(0.3, 0.65) * (1 if k % 2 == 0 else -1)
        _branch(rnd, x, y, ang + spread, length * rnd.uniform(0.55, 0.72), w * 0.95, depth - 1, out)


def tree(size, seed):
    rnd = random.Random(seed)
    for attempt in range(40):
        p = _pic(size)
        parts = []
        # tronco: de la base a la copa, algo torcido
        trunk, tws, ang = _grow(rnd, 0.5, BASE_Y, -math.pi / 2 + rnd.uniform(-0.1, 0.1), rnd.uniform(0.34, 0.4),
                                rnd.uniform(0.085, 0.1), 6, 0.1, 0.9)
        parts.append((trunk, tws))
        for k in range(2, 6):
            if rnd.random() < 0.7:
                side = 1 if rnd.random() < 0.5 else -1
                x, y = trunk[k]
                _branch(rnd, x, y, -math.pi / 2 + side * rnd.uniform(0.6, 1.0), rnd.uniform(0.12, 0.17), tws[k] * 0.55, 2, parts)
        x, y = trunk[-1]
        for k in range(rnd.choice([2, 3])):
            _branch(rnd, x, y, ang + rnd.uniform(-0.55, 0.55), rnd.uniform(0.13, 0.19), tws[-1] * 0.8, 2, parts)
        allx = [q[0] for pts, _ in parts for q in pts]
        ally = [q[1] for pts, _ in parts for q in pts]
        if min(allx) > 0.06 and max(allx) < 0.94 and min(ally) > 0.04:
            break
    # raíces que asoman
    for side in (-1, 1):
        dx = side * rnd.uniform(0.06, 0.09)
        p.poly([(0.5 + side * 0.02, BASE_Y - 0.07), (0.5 + dx + side * 0.025, BASE_Y + 0.005),
                (0.5 + dx * 0.4, BASE_Y + 0.008), (0.5, BASE_Y - 0.02)], BARK_DK)
    for pts, ws in parts:
        p.poly(_tapered(pts, ws), BARK)
    # corteza: brillo a un lado y vetas oscuras en los tramos gruesos
    for pts, ws in parts:
        for i in range(len(pts) - 1):
            w = ws[i]
            if w < 0.03:
                continue
            (ax, ay), (bx, by) = pts[i], pts[i + 1]
            dx, dy = bx - ax, by - ay
            ln = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / ln, dx / ln
            p.detail([(ax - nx * w * 0.28, ay - ny * w * 0.28), (bx - nx * w * 0.28, by - ny * w * 0.28)], w * 0.14, BARK_LT)
            if rnd.random() < 0.6:
                off = rnd.uniform(-0.1, 0.25) * w
                mx, my = (ax + bx) * 0.5, (ay + by) * 0.5
                p.detail([(mx + nx * off - dx * 0.3, my + ny * off - dy * 0.3), (mx + nx * off + dx * 0.2, my + ny * off + dy * 0.2)],
                         w * 0.07, BARK_DK)
    p.ell(trunk[2][0], trunk[2][1], 0.013, 0.019, BARK_DK)
    return p


def _cut_line(rnd, width_px, cut_px):
    """Corte irregular (dientes de astilla) de izquierda a derecha a la altura cut_px."""
    pts = []
    x = 0
    while x <= width_px:
        pts.append((x, cut_px + rnd.uniform(-0.022, 0.022) * width_px))
        x += width_px * rnd.uniform(0.012, 0.022)
    pts.append((width_px, cut_px))
    return pts


def split_tree(img, seed):
    """Tocón y parte de arriba a partir del árbol entero, con el corte entintado y la madera clara del corte."""
    rnd = random.Random(seed * 7 + 3)
    w, h = img.size
    cut = _cut_line(rnd, w, CUT_Y * h)
    below = [(0, h)] + cut + [(w, h)]
    above = [(0, 0)] + cut + [(w, 0)]
    # El tocón es solo el tronco (franja central): una rama que cruce el corte cae con la parte de arriba
    mask_low = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask_low).polygon(below, fill=255)
    band = Image.new("L", img.size, 0)
    ImageDraw.Draw(band).rectangle([int(w * (0.5 - STUMP_HALF)), 0, int(w * (0.5 + STUMP_HALF)), h], fill=255)
    mask_low = Image.composite(mask_low, Image.new("L", img.size, 0), band)
    mask_up = mask_low.point(lambda v: 255 - v)
    clear = Image.new("RGBA", img.size, INK[:3] + (0,))
    stump = Image.composite(img, clear, mask_low)
    top = Image.composite(img, clear, mask_up)
    # Corte: franja de madera clara con borde de tinta, solo donde hay tronco
    alpha = img.getchannel("A")
    for part, sign in ((stump, -1), (top, 1)):
        d = ImageDraw.Draw(part)
        band = max(2, int(h * 0.012))
        for (x0, y0), (x1, y1) in zip(cut[:-1], cut[1:]):
            xm = int((x0 + x1) * 0.5)
            ym = int((y0 + y1) * 0.5)
            inside = abs(xm / w - 0.5) < STUMP_HALF
            if inside and 0 <= xm < w and 0 <= ym < h and alpha.getpixel((xm, min(h - 1, ym))) > 128:
                d.line([(x0, y0), (x1, y1)], fill=INK, width=max(2, int(h * 0.008)))
                d.line([(x0, y0 + sign * band), (x1, y1 + sign * band)], fill=WOOD_IN, width=band)
    return stump, top


# ── marcas del suelo (vistas desde arriba) ──────────────────────────────

def crater(size, seed):
    rnd = random.Random(seed)
    p = Pic(size, ss=4, outer=0.02, inner=0.008)
    # tierra levantada alrededor
    ring = []
    for k in range(28):
        a = k / 28 * math.tau
        r = 0.4 + rnd.uniform(-0.04, 0.05)
        ring.append((0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r))
    p.poly(ring, rgb(92, 70, 52))
    hole = []
    for k in range(24):
        a = k / 24 * math.tau
        r = 0.26 + rnd.uniform(-0.03, 0.03)
        hole.append((0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r))
    p.poly(hole, rgb(34, 26, 24))
    p.ell(0.5, 0.5, 0.12, 0.11, rgb(18, 14, 14), outline=False)
    # grietas hacia fuera
    for k in range(7):
        a = rnd.uniform(0, math.tau)
        r0 = 0.27
        pts = [(0.5 + math.cos(a) * r0, 0.5 + math.sin(a) * r0)]
        r = r0
        for s in range(3):
            r += rnd.uniform(0.04, 0.07)
            a += rnd.uniform(-0.25, 0.25)
            pts.append((0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r))
        p.detail(pts, 0.012)
    # chamuscado: arco claro arriba a la izquierda
    p.detail(circle_pts(0.5, 0.5, 0.33, 16, math.radians(190), math.radians(260)), 0.02, rgb(140, 110, 80))
    return p


def ink_splat(size, seed):
    rnd = random.Random(seed)
    p = Pic(size, ss=4, outer=0.0, inner=0.0)
    ink = rgb(20, 16, 26)
    blob = []
    n = 22
    for k in range(n):
        a = k / n * math.tau
        r = 0.2 + rnd.uniform(-0.03, 0.06)
        blob.append((0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r))
    p.poly(blob, ink, outline=False)
    # salpicaduras: lenguas y gotas
    for k in range(9):
        a = rnd.uniform(0, math.tau)
        l0 = 0.18
        l1 = rnd.uniform(0.28, 0.42)
        p.line([(0.5 + math.cos(a) * l0, 0.5 + math.sin(a) * l0), (0.5 + math.cos(a) * l1, 0.5 + math.sin(a) * l1)],
               rnd.uniform(0.02, 0.04), ink, outline=False)
        r = rnd.uniform(0.015, 0.035)
        d = l1 + rnd.uniform(0.03, 0.07)
        p.ell(0.5 + math.cos(a) * d, 0.5 + math.sin(a) * d, r, r, ink, outline=False)
    # brillo húmedo
    p.detail(circle_pts(0.47, 0.46, 0.1, 10, math.radians(200), math.radians(260)), 0.018, rgb(90, 84, 110))
    return p


def main():
    os.makedirs(PROPS_OUT, exist_ok=True)
    os.makedirs(FX_OUT, exist_ok=True)
    sheet = Image.new("RGBA", (CELL * VARIANTS, CELL * 3), INK[:3] + (0,))
    for v in range(VARIANTS):
        full = tree(CELL, 101 + v * 13).render()
        stump, top = split_tree(full, v)
        sheet.paste(full, (v * CELL, 0))
        sheet.paste(stump, (v * CELL, CELL))
        sheet.paste(top, (v * CELL, CELL * 2))
    sheet.save(os.path.join(PROPS_OUT, "arboles.png"))
    marks = Image.new("RGBA", (256 * 4, 256), INK[:3] + (0,))
    marks.paste(crater(256, 5).render(), (0, 0))
    marks.paste(crater(256, 9).render(), (256, 0))
    marks.paste(ink_splat(256, 3).render(), (512, 0))
    marks.paste(ink_splat(256, 8).render(), (768, 0))
    marks.save(os.path.join(FX_OUT, "marcas.png"))
    if len(sys.argv) > 1:
        rev = Image.new("RGBA", (sheet.width, sheet.height + 256), (200, 190, 170, 255))
        rev.alpha_composite(sheet, (0, 0))
        rev.alpha_composite(marks, (0, sheet.height))
        rev.save(sys.argv[1])
    print("ok", os.path.join(PROPS_OUT, "arboles.png"), os.path.join(FX_OUT, "marcas.png"))


if __name__ == "__main__":
    main()
