"""Rumbang_Stand.pdf: R en pixel art (entera y partida), portales planos, dado D12 en pepakura,
enemigos (sprites del juego) y onomatopeyas. Todo para imprimir en Carta.

Uso: python tools/stand_papercraft/stand_pdf.py [salida.pdf]
"""
import io
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from reportlab.lib.utils import ImageReader

import make_pdf as M
from make_pdf import P, MM, INK, AREA_W, AREA_H, line

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "stand", "Rumbang_Stand.pdf")

# ───────────────────────── R en pixel art
R_ROWS = [
    "##########...",
    "###########..",
    "############.",
    "#####...#####",
    "#####...#####",
    "#####...#####",
    "#####...#####",
    "############.",
    "###########..",
    "##########...",
    "#####.#####..",
    "#####..#####.",
    "#####..#####.",
    "#####...#####",
    "#####...#####",
    "#####...#####",
]
YEL = (1.0, 0.82, 0.22)
YEL_HI = (1.0, 0.95, 0.62)
YEL_SH = (0.95, 0.6, 0.15)
EXTR = (0.86, 0.38, 0.1)
EXTR_D = (0.62, 0.22, 0.08)
WHITE = (1, 1, 1)


def r_pixels():
    """Devuelve {(x, y): color} con y hacia abajo: relleno, extrusión 3D, contorno de tinta."""
    S = {(x, y) for y, row in enumerate(R_ROWS) for x, ch in enumerate(row) if ch == "#"}
    S = {(x + 1, y + 1) for x, y in S}                 # deja sitio al contorno
    E1 = {(x + 1, y + 1) for x, y in S} - S
    E2 = set()
    body = S | E1 | E2
    ink = set()
    for x, y in body:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q not in body:
                    ink.add(q)
    px = {}
    for q in ink:
        px[q] = INK
    for q in E2:
        px[q] = EXTR_D
    for q in E1:
        px[q] = EXTR
    for x, y in S:
        c = YEL
        if (x, y + 1) not in S or (x + 1, y) not in S:
            c = YEL_SH
        if (x, y - 1) not in S:
            c = YEL_HI
        px[(x, y)] = c
    # brillos
    for q in [(2, 2), (3, 2), (2, 3), (8, 2)]:
        if q in S:
            px[q] = WHITE
    return px


def draw_pixels(c, px, size, ox, oy, xmin=None, xmax=None):
    """Dibuja los píxeles (y hacia abajo) con origen arriba-izquierda en (ox, oy) mm del área."""
    xs = [x for x, _ in px]
    ys = [y for _, y in px]
    x0 = min(xs) if xmin is None else xmin
    for (x, y), col in px.items():
        if xmin is not None and x < xmin:
            continue
        if xmax is not None and x > xmax:
            continue
        c.setFillColorRGB(*col)
        c.setStrokeColorRGB(*col)
        c.setLineWidth(0.2)
        c.rect(*P(ox + (x - x0) * size, oy - (y + 1) * size), size * MM, size * MM, stroke=1, fill=1)


def px_bounds(px):
    xs = [x for x, _ in px]
    ys = [y for _, y in px]
    return min(xs), max(xs), min(ys), max(ys)


def r_full_page(doc):
    doc.new_page("LA R - ENTERA (pixel art)", "R entera")
    px = r_pixels()
    x0, x1, y0, y1 = px_bounds(px)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    size = min((AREA_W - 6) / w, (AREA_H - 12) / h)
    ox = (AREA_W - w * size) / 2
    oy = AREA_H - 4
    draw_pixels(doc.c, px, size, ox, oy)
    doc.c.setFont("ArialB", 8)
    doc.c.setFillColorRGB(*INK)
    doc.c.drawString(*P(0, 1), "Recorta por el borde negro. Pega sobre foam o cartón. Píxel de %.1f mm: escala a lo que quieras con impresión póster." % size)


CUT_COL = 9          # columna (en coordenadas de r_pixels) donde se parte la R


def r_half_page(doc, side, size):
    title = "LA R - MITAD QUE ENTRA (portal naranja)" if side == "izq" else "LA R - MITAD QUE SALE (portal verde)"
    doc.new_page(title, "R " + side)
    c = doc.c
    px = r_pixels()
    x0, x1, y0, y1 = px_bounds(px)
    if side == "izq":
        part = {q: v for q, v in px.items() if q[0] < CUT_COL}
    else:
        part = {q: v for q, v in px.items() if q[0] >= CUT_COL}
    px0, px1, _, _ = px_bounds(part)
    w = (px1 - px0 + 1) * size
    h = (y1 - y0 + 1) * size
    tab = 12.0
    ox = (AREA_W - w - tab) / 2 + (tab if side == "der" else 0)
    oy = AREA_H - 10
    # pestaña en el lado del corte (se pega detrás del portal)
    tx = ox + w if side == "izq" else ox - tab
    top = oy - (1 + 1) * size
    bot = oy - (y1 - y0) * size
    c.setFillColorRGB(0.9, 0.9, 0.88)
    c.setStrokeColorRGB(*INK)
    c.setLineWidth(0.6)
    c.rect(*P(tx, bot), tab * MM, (top - bot) * MM, stroke=1, fill=1)
    c.setFillColorRGB(0.45, 0.45, 0.45)
    c.setFont("ArialB", 7)
    c.saveState()
    c.translate(*P(tx + tab / 2, (top + bot) / 2))
    c.rotate(90)
    c.drawCentredString(0, -2.5, "PEGA DETRÁS DEL PORTAL")
    c.restoreState()
    draw_pixels(c, part, size, ox, oy, xmin=px0)
    edge_x = ox + w if side == "izq" else ox
    line(c, np.array([edge_x, bot]), np.array([edge_x, top]), 0, 0, "valle")
    c.setFont("ArialB", 8)
    c.setFillColorRGB(*INK)
    c.drawString(*P(0, 1), "Misma escala que el portal. Recorta, dobla la pestaña gris y pégala por detrás del borde del portal %s." %
                 ("NARANJA" if side == "izq" else "VERDE"))


# ───────────────────────── portal plano
def portal_page(doc, color, name, diam):
    doc.new_page("PORTAL %s" % name, "portal")
    c = doc.c
    px = 8
    R = diam / 2
    S = int(diam * px)
    o = S / 2
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ink = (18, 12, 22, 255)
    ri = R * 0.78
    deep = tuple(int(v * 255 * 0.22) for v in color) + (255,)
    # remolino
    d.ellipse([o - ri * px, o - ri * px, o + ri * px, o + ri * px], fill=deep)
    for arm in range(5):
        for s in range(300):
            t = s / 300
            ang = arm * 2 * math.pi / 5 + t * 3.4 * math.pi
            r = (0.04 + 0.96 * t) * ri * px
            w = (1.5 + 8 * t) * px * 0.5
            k = 0.35 + 0.65 * (1 - t)
            col = tuple(int(255 * min(1, cc * (0.6 + 0.6 * k) + 0.35 * k)) for cc in color) + (255,)
            x, y = o + math.cos(ang) * r, o + math.sin(ang) * r
            d.ellipse([x - w, y - w, x + w, y + w], fill=col)
    d.ellipse([o - 8 * px, o - 8 * px, o + 8 * px, o + 8 * px], fill=(255, 255, 240, 255))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([o - ri * px, o - ri * px, o + ri * px, o + ri * px], fill=255)
    swirl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    swirl.paste(img, (0, 0), mask)
    # anillo de piedra: 16 bloques con contorno de tinta y sombra dura
    ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    n = 16
    ro = R - 1.5
    stones = [(92, 84, 108), (78, 72, 94), (100, 92, 118)]
    for k in range(n):
        a0 = 2 * math.pi * k / n + 0.012
        a1 = 2 * math.pi * (k + 1) / n - 0.012
        pts = []
        for a in np.linspace(a0, a1, 8):
            pts.append((o + math.cos(a) * ro * px, o + math.sin(a) * ro * px))
        for a in np.linspace(a1, a0, 8):
            pts.append((o + math.cos(a) * (ri - 0.5) * px, o + math.sin(a) * (ri - 0.5) * px))
        rd.polygon(pts, fill=stones[k % 3] + (255,), outline=ink, width=int(1.1 * px))
        # luz del portal en el canto interior
        glow = [(o + math.cos(a) * (ri + 2.2) * px, o + math.sin(a) * (ri + 2.2) * px) for a in np.linspace(a0, a1, 8)]
        rd.line(glow, fill=tuple(int(v * 255) for v in color) + (255,), width=int(2.2 * px))
        # grieta
        am = (a0 + a1) / 2
        rd.line([(o + math.cos(am) * (ro - 3) * px, o + math.sin(am) * (ro - 3) * px),
                 (o + math.cos(am + 0.04) * (ro - 7) * px, o + math.sin(am + 0.04) * (ro - 7) * px)], fill=ink, width=int(0.6 * px))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.alpha_composite(swirl)
    out.alpha_composite(ring)
    rd = ImageDraw.Draw(out)
    rd.ellipse([o - ri * px, o - ri * px, o + ri * px, o + ri * px], outline=ink, width=int(1.1 * px))
    rd.ellipse([o - ro * px, o - ro * px, o + ro * px, o + ro * px], outline=ink, width=int(1.3 * px))
    buf = io.BytesIO()
    out.save(buf, "PNG")
    buf.seek(0)
    x = (AREA_W - diam) / 2
    y = AREA_H - diam - 6
    c.drawImage(ImageReader(buf), *P(x, y), diam * MM, diam * MM, mask="auto")
    c.setFont("ArialB", 8)
    c.setFillColorRGB(*INK)
    c.drawString(*P(0, 1), "Recorta por el borde exterior. Pega sobre foam o cartón. Ø %.0f mm." % diam)


# ───────────────────────── enemigos con sus sprites
def sprite(key, row):
    im = Image.open(os.path.join(ROOT, "assets", "creatures", "%s_sprites.png" % key)).convert("RGBA")
    cell = im.crop((0, row * 96, 96, row * 96 + 96))
    a = cell.split()[3].point(lambda v: 255 if v > 100 else 0)
    cell.putalpha(a)
    cell = cell.crop(a.getbbox())
    return cell


def enemy_page(doc, key, row, name, width_mm):
    doc.new_page("ENEMIGO - %s" % name, key)
    c = doc.c
    sp = sprite(key, row)
    k = max(1, int(1800 / sp.width))
    big = sp.resize((sp.width * k, sp.height * k), Image.NEAREST)
    cut = M.cut_border(big, int(k * 2.2))
    w = width_mm
    h = w * cut.height / cut.width
    if h > AREA_H - 12:
        h = AREA_H - 12
        w = h * cut.width / cut.height
    buf = io.BytesIO()
    cut.save(buf, "PNG")
    buf.seek(0)
    c.drawImage(ImageReader(buf), *P((AREA_W - w) / 2, AREA_H - h - 10), w * MM, h * MM, mask="auto")
    c.setFont("ArialB", 8)
    c.setFillColorRGB(*INK)
    c.drawString(*P(0, 1), "Sprite del juego (%d px de ancho). Recorta por la línea negra exterior y pega sobre foam. Ponle un soporte." % sp.width)


# ───────────────────────── portada e instrucciones
def cover(doc, d12_edge, d12_diam):
    doc.new_page("STAND", "portada")
    c = doc.c
    px = r_pixels()
    draw_pixels(c, px, 3.2, AREA_W / 2 - 25, AREA_H - 4)
    c.setFillColorRGB(*INK)
    c.setFont("Impact", 48)
    c.drawCentredString(*P(AREA_W / 2, AREA_H - 92), "RUMBANG")
    c.setFont("Impact", 18)
    c.setFillColorRGB(0.93, 0.45, 0.12)
    c.drawCentredString(*P(AREA_W / 2, AREA_H - 103), "RECORTABLES PARA EL STAND")
    y = AREA_H - 118
    blocks = [
        ("QUÉ TRAE", [
            "La R en pixel art: entera (una hoja) y partida en dos para los portales.",
            "Dos portales planos: naranja (Cavernas) y verde (Cloacas).",
            "Dado del destino de 12 caras para armar (pepakura), con los resultados del modo supervivencia.",
            "Rata y hinchado con sus sprites del juego. Seis onomatopeyas de cómic. Soportes para pararlo todo.",
        ]),
        ("IMPRESIÓN", [
            "Papel Carta al 100 % (\"tamaño real\"). Mide la regla de 50 mm del pie de cada hoja.",
            "Recortables planos: papel normal o fotográfico pegado sobre foamboard o cartón de 3-5 mm.",
            "Dado: cartulina de 180-220 g.",
            "¿Más grande? Adobe Reader > Imprimir > Póster, al 200-400 %. La R es vectorial: no pierde calidad.",
        ]),
        ("LA R ATRAVESANDO LOS PORTALES", [
            "Pon los dos portales separados y a la misma altura.",
            "La mitad izquierda de la R se pega por detrás del borde DERECHO del portal naranja: parece que entra.",
            "La mitad derecha se pega por detrás del borde IZQUIERDO del portal verde: parece que sale.",
        ]),
        ("DADO DEL DESTINO (D12)", [
            "Arista de %.0f mm, unos %.0f cm de diámetro. Caras opuestas suman 13." % (d12_edge, d12_diam / 10),
            "Rayas grises = pliegue de monte. Pestaña gris numerada = pega bajo la arista con el MISMO número.",
            "Marca los pliegues con regla antes de recortar. Cierra al final; mete un peso para que ruede mejor.",
        ]),
    ]
    for head, rows in blocks:
        c.setFillColorRGB(0.93, 0.45, 0.12)
        c.setFont("Impact", 12)
        c.drawString(*P(4, y), head)
        y -= 5.5
        c.setFillColorRGB(*INK)
        c.setFont("Arial", 8.8)
        for r in rows:
            c.drawString(*P(7, y), "- " + r)
            y -= 4.8
        y -= 4


def supports_page(doc, n_pages=2):
    for pg in range(n_pages):
        doc.new_page("SOPORTES", "6 por hoja")
        c = doc.c
        for k in range(6):
            col, row = k % 3, k // 3
            ox, oy = 8 + col * 64, AREA_H - 20 - (row + 1) * 112
            for x, y, w, h, t in [(0, 0, 45, 20, "pie"), (0, 20, 45, 70, "pata"), (0, 90, 45, 18, "pega detrás")]:
                c.setFillColorRGB(*((0.98, 0.86, 0.35) if t == "pata" else (0.92, 0.92, 0.9)))
                c.rect(*P(ox + x, oy + y), w * MM, h * MM, stroke=0, fill=1)
                c.setFillColorRGB(*INK)
                c.setFont("ArialB", 7)
                c.drawCentredString(*P(ox + w / 2, oy + y + (h / 2 - 1 if t != "pata" else 8)), t.upper())
            c.setStrokeColorRGB(*INK)
            c.setLineWidth(0.7)
            c.rect(*P(ox, oy), 45 * MM, 108 * MM, stroke=1, fill=0)
            line(c, np.array([0, 20]), np.array([45, 20]), ox, oy, "monte")
            line(c, np.array([0, 90]), np.array([45, 90]), ox, oy, "valle")
            draw_pixels(c, r_pixels(), 1.9, ox + 7.5, oy + 85)


def main():
    doc = M.Doc(OUT)
    d12_edge = 40.0
    d12 = M.d12_mesh(d12_edge)
    cover(doc, d12_edge, float(np.linalg.norm(d12.v, axis=1).max() * 2))
    r_full_page(doc)
    portal_diam = 190.0
    half_px = 150.0 / 20                     # la R de los portales mide unos 15 cm de alto
    portal_page(doc, (1.0, 0.55, 0.2), "NARANJA (la R entra)", portal_diam)
    r_half_page(doc, "izq", half_px)
    portal_page(doc, (0.45, 1.0, 0.3), "VERDE (la R sale)", portal_diam)
    r_half_page(doc, "der", half_px)
    M.draw_model(doc, d12, "DADO DEL DESTINO - D12 (pepakura)", "dado")
    enemy_page(doc, "rat", 2, "RATA DE CLOACA", AREA_W - 10)
    enemy_page(doc, "bloater", 3, "HINCHADO", AREA_W - 30)
    M.words_pages(doc, supports=False)
    supports_page(doc)
    doc.save()
    print("PAGINAS", doc.page, OUT)


if __name__ == "__main__":
    main()
