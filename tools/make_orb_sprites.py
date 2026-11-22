"""Orbes elementales DIBUJADOS (cómic 2D horneado) para el Ciclo Elemental de Saimon.

    python tools/make_orb_sprites.py

Sale assets/textures/toon/fx/orbs.png: rejilla de 2 columnas (fotogramas) x 5 filas (elementos), celdas de
128 px. Orden de filas = ElementalOrbs.ELEMENT_NAMES: aire, fuego, agua, tierra, naturaleza.
Cada orbe va ya pintado con sus colores (no se tiñe): relleno plano, banda de sombra cel abajo a la derecha,
brillo duro arriba a la izquierda, contorno de tinta y los detalles del elemento (remolinos, lenguas de fuego,
gota, grietas y piedras, hojas). Los dos fotogramas se alternan en el juego para que el dibujo "hierva".
"""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "toon", "fx")
CELL = 128
SS = 4
N = CELL * SS
C = N / 2
INK = (26, 22, 30)
R = N * 0.27                 # radio de la bola central
LINE = int(N * 0.028)        # grosor del contorno


def _blank():
    return Image.new("L", (N, N), 0)


def _ball(mask_draw, cx=C, cy=C, r=R):
    mask_draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)


def _ink_lines(img, clip, lines, width):
    """Trazos de tinta interiores (lista de polilíneas), recortados a `clip`."""
    m = _blank()
    d = ImageDraw.Draw(m)
    for pts in lines:
        d.line(pts, fill=255, width=width, joint="curve")
    img.paste(Image.new("RGBA", (N, N), INK + (255,)), (0, 0), ImageChops.multiply(m, clip))


def _compose(sil, base, shade, light, inner=None):
    """Silueta -> dibujo: contorno de tinta, relleno, sombra cel (lo que no cubre la silueta movida hacia
    arriba a la izquierda) y brillo duro. `inner` = máscara opcional que se pinta encima con su color."""
    img = Image.new("RGBA", (N, N), INK + (0,))
    img.paste(Image.new("RGBA", (N, N), INK + (255,)), (0, 0), sil.filter(ImageFilter.MaxFilter(LINE * 2 + 1)))
    img.paste(Image.new("RGBA", (N, N), base + (255,)), (0, 0), sil)
    sh = ImageChops.subtract(sil, ImageChops.offset(sil, int(N * 0.05), int(N * 0.06)))
    img.paste(Image.new("RGBA", (N, N), shade + (255,)), (0, 0), sh)
    if inner is not None:
        for mask, col in inner:
            img.paste(Image.new("RGBA", (N, N), col + (255,)), (0, 0), ImageChops.multiply(mask, sil))
    hl = _blank()
    ImageDraw.Draw(hl).ellipse([C - R * 0.62, C - R * 0.72, C - R * 0.22, C - R * 0.36], fill=255)
    img.paste(Image.new("RGBA", (N, N), light + (255,)), (0, 0), ImageChops.multiply(hl, sil))
    return img


def _spiral(cx, cy, r0, r1, turns, phase, steps=40):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a = phase + t * turns * math.tau
        r = r0 + (r1 - r0) * t
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.9))
    return pts


def aire(frame):
    sil = _blank()
    d = ImageDraw.Draw(sil)
    _ball(d)
    # colas de viento que salen de la bola (dos jirones curvos)
    ph = frame * 0.5
    for k, side in ((0, 1), (1, -1)):
        a0 = ph + k * math.pi
        pts = []
        for i in range(24):
            t = i / 23
            a = a0 + t * 1.6 * side
            rr = R * (0.95 + 0.4 * t)
            pts.append((C + math.cos(a) * rr, C + math.sin(a) * rr))
        d.line(pts, fill=255, width=int(N * 0.045), joint="curve")
    img = _compose(sil, (224, 242, 250), (160, 198, 222), (255, 255, 255))
    core = sil.filter(ImageFilter.MinFilter(LINE * 2 + 1))
    _ink_lines(img, core, [
        _spiral(C, C, R * 0.08, R * 0.75, 1.15, ph * 2.0),
        _spiral(C + R * 0.1, C + R * 0.05, R * 0.5, R * 0.95, 0.35, ph * 2.0 + 2.6),
    ], int(N * 0.018))
    return img


def fuego(frame):
    rnd = random.Random(31 + frame * 7)
    sil = _blank()
    d = ImageDraw.Draw(sil)
    _ball(d, cy=C + R * 0.12, r=R * 0.95)
    # corona de lenguas de fuego hacia arriba
    count = 5
    for i in range(count):
        t = (i + 0.5) / count
        a = math.pi + t * math.pi                       # de izquierda a derecha por arriba
        base = (C + math.cos(a) * R * 0.75, C + R * 0.12 + math.sin(a) * R * 0.75)
        h = R * (0.5 + 0.32 * math.sin(t * math.pi)) * rnd.uniform(0.8, 1.1)
        lean = (t - 0.5) * 0.9 + rnd.uniform(-0.15, 0.15) + (0.12 if frame else -0.12)
        w = R * 0.32
        tip = (base[0] + lean * h * 0.6, base[1] - h)
        d.polygon([(base[0] - w, base[1] + w * 0.3), (base[0] + w, base[1] + w * 0.3), tip], fill=255)
    core = _blank()
    cd = ImageDraw.Draw(core)
    cr = R * 0.5
    cd.ellipse([C - cr, C + R * 0.2 - cr * 0.8, C + cr, C + R * 0.2 + cr * 1.1], fill=255)
    cd.polygon([(C - cr * 0.8, C + R * 0.1), (C + cr * 0.8, C + R * 0.1),
                (C + (0.15 if frame else -0.15) * R, C - R * 0.75)], fill=255)
    mid = core.filter(ImageFilter.MaxFilter(int(N * 0.05) * 2 + 1))
    img = _compose(sil, (238, 84, 26), (176, 34, 18), (255, 236, 150),
                   inner=[(mid, (255, 160, 40)), (core, (255, 232, 120))])
    return img


def agua(frame):
    sil = _blank()
    d = ImageDraw.Draw(sil)
    _ball(d, cy=C + R * 0.15)
    # punta de gota hacia arriba (se balancea un poco entre fotogramas)
    sway = (0.12 if frame else -0.12) * R
    d.polygon([(C - R * 0.72, C - R * 0.35), (C + R * 0.72, C - R * 0.35), (C + sway, C - R * 1.35)], fill=255)
    wave = _blank()
    wd = ImageDraw.Draw(wave)
    pts = []
    for i in range(41):
        t = i / 40
        x = C - R * 1.1 + t * R * 2.2
        y = C + R * 0.45 + math.sin(t * math.tau * 1.5 + frame * 1.4) * R * 0.1
        pts.append((x, y))
    wd.polygon(pts + [(C + R * 1.2, C + R * 1.4), (C - R * 1.2, C + R * 1.4)], fill=255)
    img = _compose(sil, (40, 140, 240), (18, 70, 180), (235, 250, 255), inner=[(wave, (24, 96, 210))])
    core = sil.filter(ImageFilter.MinFilter(LINE * 2 + 1))
    _ink_lines(img, core, [pts[4:37]], int(N * 0.016))
    # burbujas
    bd = ImageDraw.Draw(img)
    for bx, by, br in ((0.35, 0.05, 0.1), (0.15, -0.25, 0.06)):
        x, y, rr = C + bx * R + (frame * 0.05 * R), C + by * R - frame * 0.08 * R, br * R
        bd.ellipse([x - rr, y - rr, x + rr, y + rr], outline=INK + (255,), width=int(N * 0.012),
                   fill=(200, 236, 255, 255))
    return img


def tierra(frame):
    rnd = random.Random(53)
    sil = _blank()
    d = ImageDraw.Draw(sil)
    # roca facetada (polígono irregular) en vez de bola lisa
    pts = []
    for i in range(9):
        a = i * math.tau / 9 + rnd.uniform(-0.12, 0.12)
        rr = R * rnd.uniform(0.92, 1.08)
        pts.append((C + math.cos(a) * rr, C + math.sin(a) * rr))
    d.polygon(pts, fill=255)
    # piedrecitas que orbitan (cambian de sitio entre fotogramas)
    pebbles = []
    for k in range(3):
        a = k * math.tau / 3 + 0.6 + frame * 0.45
        rr = R * 1.42
        x, y = C + math.cos(a) * rr, C + math.sin(a) * rr * 0.75
        s = R * (0.2 + 0.05 * k)
        poly = [(x + math.cos(j * math.tau / 5 + k) * s, y + math.sin(j * math.tau / 5 + k) * s) for j in range(5)]
        d.polygon(poly, fill=255)
        pebbles.append(poly)
    img = _compose(sil, (166, 112, 62), (104, 64, 34), (222, 184, 128))
    core = sil.filter(ImageFilter.MinFilter(LINE * 2 + 1))
    _ink_lines(img, core, [
        [(C - R * 0.2, C - R * 0.75), (C - R * 0.05, C - R * 0.25), (C - R * 0.3, C + R * 0.1)],
        [(C - R * 0.05, C - R * 0.25), (C + R * 0.45, C - R * 0.05), (C + R * 0.55, C + R * 0.4)],
        [(C - R * 0.55, C + R * 0.45), (C - R * 0.1, C + R * 0.6)],
    ], int(N * 0.016))
    # musgo arriba
    mo = _blank()
    ImageDraw.Draw(mo).ellipse([C - R * 0.9, C - R * 1.3, C + R * 0.5, C - R * 0.55], fill=255)
    img.paste(Image.new("RGBA", (N, N), (110, 150, 60, 255)), (0, 0), ImageChops.multiply(mo, core))
    return img


def _leaf(d, base, ang, length, width):
    ca, sa = math.cos(ang), math.sin(ang)
    pts = []
    for i in range(21):
        t = i / 20
        w = math.sin(math.pi * t) * width
        pts.append((t * length, w))
    for i in range(20, -1, -1):
        t = i / 20
        w = math.sin(math.pi * t) * width
        pts.append((t * length, -w))
    poly = [(base[0] + x * ca - y * sa, base[1] + x * sa + y * ca) for x, y in pts]
    d.polygon(poly, fill=255)
    tip = (base[0] + length * 0.85 * ca, base[1] + length * 0.85 * sa)
    return [(base[0] + length * 0.15 * ca, base[1] + length * 0.15 * sa), tip]


def naturaleza(frame):
    sil = _blank()
    d = ImageDraw.Draw(sil)
    _ball(d)
    wig = 0.12 if frame else -0.12
    veins = []
    for ang in (-2.2 + wig, -0.95 - wig, 0.55 + wig, 2.5 - wig):
        base = (C + math.cos(ang) * R * 0.7, C + math.sin(ang) * R * 0.7)
        veins.append(_leaf(d, base, ang, R * 0.95, R * 0.3))
    img = _compose(sil, (92, 196, 64), (40, 120, 40), (210, 255, 160))
    core = sil.filter(ImageFilter.MinFilter(LINE * 2 + 1))
    # brote con espiral en el centro + venas de las hojas
    _ink_lines(img, core, veins + [_spiral(C + R * 0.05, C + R * 0.05, R * 0.06, R * 0.4, 0.9, 1.0 + frame * 0.6)],
               int(N * 0.015))
    return img


ELEMENTS = [aire, fuego, agua, tierra, naturaleza]


def main():
    os.makedirs(OUT, exist_ok=True)
    sheet = Image.new("RGBA", (CELL * 2, CELL * len(ELEMENTS)), INK + (0,))
    for row, fn in enumerate(ELEMENTS):
        for frame in range(2):
            sheet.paste(fn(frame).resize((CELL, CELL), Image.LANCZOS), (frame * CELL, row * CELL))
    path = os.path.join(OUT, "orbs.png")
    sheet.save(path)
    print("guardado", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
