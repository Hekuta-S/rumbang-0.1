"""Efectos DIBUJADOS de los objetos de supervivencia (ItemEffects), estilo cómic entintado.

    python tools/make_item_fx.py [hoja_revision.png]

Sale assets/textures/toon/fx/objetos.png: rejilla 4×4 de 256 px (ToonFX.ITEM_FX_*):
  fila 0: trompo girando (4 fotogramas)
  fila 1: enredadera A, enredadera B (vistas desde arriba), remolino (desde arriba), tajo del machete
  fila 2: campana, cruz de cura, fantasma de la Llorona, pata de la Patasola
  fila 3: moneda ×2, marca de furia, nota y ondas del silbido, ojo de candileja
Después: Godot --headless --import.
"""
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_ui_icons import INK, WHITE, ROOT, Pic, Axis, circle_pts, lens, rgb, star  # noqa: E402

OUT = os.path.join(ROOT, "assets", "textures", "toon", "fx", "objetos.png")
CELL = 256
GOLD = rgb(235, 185, 60)
GOLD_D = rgb(170, 120, 35)


def _pic():
    return Pic(CELL, outer=0.026, inner=0.011)


def trompo(frame):
    """Trompo de lado; la franja y las rayas se desplazan con el fotograma (parece girar)."""
    p = _pic()
    p.poly([(0.18, 0.34), (0.82, 0.34), (0.53, 0.86), (0.47, 0.86)], rgb(210, 55, 45))
    p.ell(0.5, 0.34, 0.32, 0.09, rgb(240, 95, 70))
    p.rect(0.45, 0.12, 0.55, 0.3, rgb(110, 70, 40))
    p.line([(0.47, 0.86), (0.5, 0.95)], 0.02, rgb(150, 155, 170))
    # franja amarilla
    p.poly([(0.23, 0.44), (0.77, 0.44), (0.72, 0.52), (0.28, 0.52)], rgb(250, 205, 70), outline=False)
    # rayas verticales que corren hacia un lado
    for k in range(3):
        x = 0.28 + ((k * 0.16 + frame * 0.04) % 0.48)
        w = 0.5 - abs(x - 0.5)
        p.detail([(x, 0.38), (x + (0.5 - x) * 0.6, 0.78)], 0.012 + 0.012 * w, rgb(150, 30, 30))
    # líneas de velocidad
    for k, y in enumerate((0.3, 0.5, 0.66)):
        off = 0.03 * ((frame + k) % 2)
        p.detail([(0.04 + off, y), (0.14 + off, y)], 0.014, INK)
        p.detail([(0.86 - off, y + 0.04), (0.96 - off, y + 0.04)], 0.014, INK)
    return p


def enredadera(variant):
    p = _pic()
    rnd = [0.0, 0.7, 1.4, 2.1, 2.8, 3.5, 4.2, 4.9, 5.6]
    for k, a0 in enumerate(rnd):
        a = a0 + variant * 0.35
        pts = []
        for t in range(9):
            r = 0.06 + t * 0.045
            pts.append((0.5 + math.cos(a + t * 0.18) * r, 0.5 + math.sin(a + t * 0.18) * r))
        p.line(pts, 0.022, rgb(70, 130, 50))
        tip = pts[-1]
        p.poly(lens(pts[5], (tip[0] + math.cos(a + 1.9) * 0.08, tip[1] + math.sin(a + 1.9) * 0.08), 0.035),
               rgb(110, 195, 80) if k % 2 else rgb(80, 165, 65))
    if variant:
        for x, y in ((0.32, 0.3), (0.7, 0.66)):
            p.ell(x, y, 0.035, 0.035, rgb(230, 80, 120))
    p.ell(0.5, 0.5, 0.06, 0.06, rgb(90, 60, 35))
    return p


def remolino():
    p = _pic()
    for k in range(3):
        a0 = k * math.tau / 3
        pts = [(0.5 + math.cos(a0 + t * 0.3) * (0.06 + t * 0.03), 0.5 + math.sin(a0 + t * 0.3) * (0.06 + t * 0.03))
               for t in range(15)]
        p.line(pts, 0.05 - k * 0.005, rgb(245, 235, 200))
        p.detail(pts[3:], 0.012, rgb(190, 175, 130))
    return p


def tajo():
    p = _pic()
    pts_top = [(0.04, 0.6), (0.3, 0.46), (0.6, 0.4), (0.96, 0.42)]
    pts_bot = [(0.96, 0.46), (0.6, 0.52), (0.3, 0.6), (0.04, 0.6)]
    p.poly(pts_top + pts_bot, rgb(210, 235, 255))
    p.detail([(0.2, 0.56), (0.6, 0.46), (0.92, 0.44)], 0.012, WHITE)
    p.poly([(0.5, 0.18), (0.64, 0.18), (0.56, 0.32), (0.7, 0.32), (0.46, 0.6), (0.52, 0.4), (0.4, 0.4)],
           rgb(255, 225, 60))
    for y in (0.7, 0.78):
        p.detail([(0.16, y), (0.5, y - 0.06)], 0.012, INK)
    return p


def campana():
    p = _pic()
    p.poly([(0.38, 0.18), (0.62, 0.18), (0.68, 0.5), (0.84, 0.74), (0.16, 0.74), (0.32, 0.5)], GOLD)
    p.rect(0.14, 0.72, 0.86, 0.8, GOLD_D)
    p.ell(0.5, 0.86, 0.07, 0.06, rgb(120, 90, 40))
    p.line([(0.44, 0.18), (0.5, 0.08), (0.56, 0.18)], 0.03, rgb(110, 80, 40))
    p.detail([(0.38, 0.28), (0.32, 0.64)], 0.02, rgb(255, 238, 160))
    # rayitas de sonido a los lados
    for s in (-1, 1):
        for k in range(3):
            x = 0.5 + s * (0.36 + k * 0.04)
            y = 0.3 + k * 0.12
            p.detail([(x, y), (x + s * 0.08, y - 0.04)], 0.02, rgb(120, 220, 255))
    return p


def cruz_cura():
    p = _pic()
    p.poly([(0.38, 0.12), (0.62, 0.12), (0.62, 0.38), (0.88, 0.38), (0.88, 0.62), (0.62, 0.62), (0.62, 0.88),
            (0.38, 0.88), (0.38, 0.62), (0.12, 0.62), (0.12, 0.38), (0.38, 0.38)], rgb(90, 220, 100))
    p.poly([(0.43, 0.18), (0.5, 0.18), (0.5, 0.44), (0.43, 0.44)], rgb(190, 255, 190), outline=False)
    p.poly(star(0.82, 0.16, 0.08, 0.03, 4), WHITE)
    return p


def fantasma():
    p = _pic()
    body = [(0.5, 0.08)]
    for t in range(1, 12):
        a = math.pi + t / 12 * math.pi
        body.append((0.5 + math.cos(a) * 0.3, 0.38 + math.sin(a) * 0.3))
    body[0] = (0.2, 0.38)
    body += [(0.8, 0.38), (0.84, 0.86), (0.72, 0.78), (0.6, 0.9), (0.5, 0.8), (0.4, 0.9), (0.28, 0.78), (0.16, 0.86)]
    p.poly(body, rgb(200, 225, 250))
    p.ell(0.4, 0.38, 0.06, 0.08, INK, outline=False)
    p.ell(0.6, 0.38, 0.06, 0.08, INK, outline=False)
    p.ell(0.5, 0.58, 0.07, 0.1, INK, outline=False)
    p.poly([(0.36, 0.48), (0.4, 0.48), (0.39, 0.62), (0.35, 0.6)], rgb(110, 200, 255))
    for k in range(3):
        p.detail([(0.86, 0.3 + k * 0.1), (0.96, 0.26 + k * 0.1)], 0.014, rgb(110, 200, 255))
    return p


def pata():
    p = _pic()
    p.poly([(0.42, 0.06), (0.6, 0.06), (0.58, 0.6), (0.72, 0.72), (0.78, 0.86), (0.4, 0.88), (0.42, 0.6)],
           rgb(120, 190, 110))
    p.poly([(0.4, 0.06), (0.62, 0.06), (0.6, 0.2), (0.42, 0.2)], rgb(90, 60, 110))
    for k in range(4):
        p.detail([(0.45 + k * 0.08, 0.88), (0.46 + k * 0.08, 0.94)], 0.016, INK)
    p.poly(star(0.2, 0.3, 0.1, 0.04, 4), rgb(180, 255, 190))
    p.poly(star(0.82, 0.4, 0.08, 0.03, 4), rgb(180, 255, 190))
    return p


def moneda():
    p = _pic()
    p.ell(0.38, 0.56, 0.26, 0.26, GOLD)
    p.ell(0.38, 0.56, 0.17, 0.17, rgb(250, 215, 100), outline=False)
    p.poly([(0.38, 0.42), (0.46, 0.56), (0.38, 0.7), (0.3, 0.56)], GOLD_D)
    # "x2" dibujado
    p.line([(0.6, 0.26), (0.72, 0.4)], 0.035, WHITE)
    p.line([(0.72, 0.26), (0.6, 0.4)], 0.035, WHITE)
    p.line([(0.78, 0.2), (0.86, 0.15), (0.94, 0.2), (0.78, 0.42), (0.95, 0.42)], 0.035, rgb(255, 225, 90))
    return p


def furia():
    """Marca de enfado de manga: cuatro arcos que se curvan hacia el centro."""
    p = _pic()
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        cx, cy = 0.5 + sx * 0.36, 0.5 + sy * 0.36
        mid = math.atan2(-sy, -sx)                     # mira hacia el centro
        p.line(circle_pts(cx, cy, 0.24, 10, mid - 0.62, mid + 0.62), 0.065, rgb(235, 45, 40))
    return p


def silbido():
    p = _pic()
    p.ell(0.36, 0.7, 0.12, 0.09, rgb(120, 220, 255))
    p.line([(0.46, 0.7), (0.46, 0.2), (0.7, 0.28)], 0.035, rgb(120, 220, 255))
    p.ell(0.66, 0.62, 0.1, 0.08, rgb(120, 220, 255))
    p.line([(0.75, 0.62), (0.75, 0.3)], 0.03, rgb(120, 220, 255))
    for r in (0.12, 0.22):
        p.detail(circle_pts(0.22, 0.4, r, 8, math.radians(160), math.radians(250)), 0.018, WHITE)
    return p


def candileja():
    p = _pic()
    p.poly([(0.5, 0.04), (0.66, 0.24), (0.84, 0.18), (0.82, 0.42), (0.94, 0.62), (0.8, 0.86), (0.5, 0.96),
            (0.2, 0.86), (0.06, 0.62), (0.18, 0.42), (0.16, 0.18), (0.34, 0.24)], rgb(255, 128, 40))
    p.poly(lens((0.2, 0.6), (0.8, 0.6), 0.18), rgb(255, 230, 120))
    p.ell(0.5, 0.6, 0.12, 0.12, rgb(220, 40, 20))
    p.poly([(0.5, 0.49), (0.53, 0.6), (0.5, 0.71), (0.47, 0.6)], INK)
    return p


def main():
    cells = [trompo(0), trompo(1), trompo(2), trompo(3),
             enredadera(0), enredadera(1), remolino(), tajo(),
             campana(), cruz_cura(), fantasma(), pata(),
             moneda(), furia(), silbido(), candileja()]
    sheet = Image.new("RGBA", (CELL * 4, CELL * 4), INK[:3] + (0,))
    for k, pic in enumerate(cells):
        sheet.paste(pic.render(), ((k % 4) * CELL, (k // 4) * CELL))
    sheet.save(OUT)
    print("guardado", os.path.relpath(OUT, ROOT))
    if len(sys.argv) > 1:
        bg = Image.new("RGBA", sheet.size, (110, 104, 92, 255))
        bg.alpha_composite(sheet)
        bg.save(sys.argv[1])
        print("hoja", sys.argv[1])


if __name__ == "__main__":
    main()
