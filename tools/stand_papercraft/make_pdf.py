"""Genera Rumbang_Stand_Papercraft.pdf: R partida, 2 portales, dado D12, 2 enemigos y onomatopeyas."""
import importlib.util
import io
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from reportlab.lib.pagesizes import letter
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

from unfold import Mesh, unfold, orient

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = r"C:\Users\cabeu\Downloads\rumbang-0.1-main\rumbang-0.1-main"
OUT_PDF = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "Rumbang_Stand_Papercraft.pdf")

MM = 72 / 25.4
PW, PH = letter[0] / MM, letter[1] / MM          # 215.9 x 279.4 mm
MARGIN = 9.0
HEAD = 13.0                                      # alto de la cabecera
AREA_W = PW - 2 * MARGIN
AREA_H = PH - 2 * MARGIN - HEAD
TAB = 5.5                                        # alto de pestaña (mm)
PAD = TAB + 2.5                                  # separación entre piezas

pdfmetrics.registerFont(TTFont("Impact", r"C:\Windows\Fonts\impact.ttf"))
pdfmetrics.registerFont(TTFont("Arial", r"C:\Windows\Fonts\arial.ttf"))
pdfmetrics.registerFont(TTFont("ArialB", r"C:\Windows\Fonts\arialbd.ttf"))

INK = (0.07, 0.05, 0.09)
LIGHT = np.array([-0.35, -0.75, 0.55])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


# ───────────────────────── utilidades de página
class Doc:
    def __init__(self, path):
        self.c = canvas.Canvas(path, pagesize=letter)
        self.c.setTitle("Rumbang - Stand papercraft")
        self.c.setAuthor("Rumbang")
        self.page = 0

    def new_page(self, title, sub=""):
        if self.page:
            self.c.showPage()
        self.page += 1
        c = self.c
        c.setFillColorRGB(*INK)
        c.rect(MARGIN * MM, (PH - MARGIN - 9) * MM, AREA_W * MM, 9 * MM, stroke=0, fill=1)
        c.setFillColorRGB(1, 0.82, 0.22)
        c.setFont("Impact", 15)
        c.drawString((MARGIN + 3) * MM, (PH - MARGIN - 6.8) * MM, "RUMBANG")
        c.setFillColorRGB(1, 1, 1)
        c.setFont("ArialB", 10)
        c.drawString((MARGIN + 30) * MM, (PH - MARGIN - 6.4) * MM, title)
        c.setFont("Arial", 7.5)
        c.drawRightString((PW - MARGIN - 3) * MM, (PH - MARGIN - 6.2) * MM, "%s   pág. %d" % (sub, self.page))
        # regla de 50 mm para comprobar la escala de impresión
        y = (MARGIN - 4.5) * MM
        x0 = MARGIN * MM
        c.setStrokeColorRGB(*INK)
        c.setLineWidth(0.6)
        c.line(x0, y, x0 + 50 * MM, y)
        for k in range(6):
            c.line(x0 + k * 10 * MM, y, x0 + k * 10 * MM, y + 1.6 * MM)
        c.setFont("Arial", 6)
        c.setFillColorRGB(*INK)
        c.drawString(x0 + 52 * MM, y, "50 mm: mide esta regla. Imprime al 100 % (tamaño real / sin ajustar), papel Carta.")

    def save(self):
        self.c.save()


def P(x, y):
    """mm del área de trabajo (origen abajo-izquierda del área) -> puntos."""
    return (MARGIN + x) * MM, (MARGIN + y) * MM


def poly_path(c, pts, ox, oy):
    p = c.beginPath()
    x, y = P(ox + pts[0][0], oy + pts[0][1])
    p.moveTo(x, y)
    for q in pts[1:]:
        x, y = P(ox + q[0], oy + q[1])
        p.lineTo(x, y)
    p.close()
    return p


def shade(mesh, fi):
    col = np.array(mesh.col[fi])
    if not mesh.shade:
        return tuple(col)
    d = float(np.dot(mesh.n[fi], LIGHT))
    k = 1.0 if d > 0.2 else (0.9 if d > -0.25 else 0.8)      # toon: tres tonos
    return tuple(np.clip(col * k, 0, 1))


# ───────────────────────── dibujo de un modelo desdoblado
def draw_model(doc, mesh, title, sub, max_w=None, max_h=None, split_colors=False):
    max_w = max_w or AREA_W - 2 * PAD
    max_h = max_h or AREA_H - 2 * PAD
    islands = unfold(mesh, max_w, max_h, split_colors=split_colors)
    for isl in islands:
        orient(isl, max_w, max_h)
    face_isl = {}
    for k, isl in enumerate(islands):
        for fi in isl.pos:
            face_isl[fi] = k
    # numeración de aristas cortadas y a qué cara va la pestaña
    cut_id, tab_on = {}, {}
    nid = 1
    for key in sorted(mesh.edges):
        occ = mesh.edges[key]
        if len(occ) != 2:
            continue
        (f1, _), (f2, _) = occ
        if face_isl[f1] == face_isl[f2] and key in islands[face_isl[f1]].joined:
            continue
        cut_id[key] = nid
        nid += 1
        # pestaña en la cara de la isla más grande (se pega sobre la pieza suelta)
        tab_on[key] = f1 if len(islands[face_isl[f1]].pos) >= len(islands[face_isl[f2]].pos) else f2
    # empaquetado: primer hueco libre (abajo-izquierda) en las hojas ya abiertas
    order = sorted(range(len(islands)), key=lambda k: -float(np.prod(islands[k].size)))
    pages, rects = [], []
    for k in order:
        w, h = islands[k].size + 2 * PAD
        spot = None
        for pi in range(len(pages)):
            spot = free_spot(rects[pi], w, h)
            if spot:
                break
        if not spot:
            pages.append([])
            rects.append([])
            pi = len(pages) - 1
            spot = (0.0, 0.0)
        x, y = spot
        rects[pi].append((x, y, w, h))
        pages[pi].append((k, x + PAD, AREA_H - y - h + PAD))
    for pi, items in enumerate(pages):
        doc.new_page(title, "%s - hoja %d/%d" % (sub, pi + 1, len(pages)))
        c = doc.c
        for k, ox, oy in items:
            draw_island(c, mesh, islands[k], k, ox, oy, cut_id, tab_on, face_isl)
    return len(islands), len(pages), nid - 1


def free_spot(rects, w, h):
    xs = sorted({0.0} | {r[0] + r[2] for r in rects})
    ys = sorted({0.0} | {r[1] + r[3] for r in rects})
    for y in ys:
        if y + h > AREA_H + 1e-6:
            break
        for x in xs:
            if x + w > AREA_W + 1e-6:
                break
            if all(x >= r[0] + r[2] - 1e-6 or x + w <= r[0] + 1e-6 or y >= r[1] + r[3] - 1e-6 or y + h <= r[1] + 1e-6 for r in rects):
                return (x, y)
    return None


def draw_island(c, mesh, isl, k, ox, oy, cut_id, tab_on, face_isl):
    # 1) pestañas (debajo de todo)
    for fi, pts in isl.pos.items():
        f = mesh.f[fi]
        for i in range(len(f)):
            key = (min(f[i], f[(i + 1) % len(f)]), max(f[i], f[(i + 1) % len(f)]))
            if tab_on.get(key) != fi:
                continue
            p, q = pts[i], pts[(i + 1) % len(f)]
            d = q - p
            ln = float(np.hypot(*d))
            if ln < 1e-6:
                continue
            u = d / ln
            out = np.array([u[1], -u[0]])              # cara en sentido antihorario: fuera = derecha
            h = min(TAB, ln * 0.45)
            ins = min(h * 0.9, ln * 0.3)
            tab = [p, p + u * ins + out * h, q - u * ins + out * h, q]
            c.setFillColorRGB(0.9, 0.9, 0.88)
            c.setStrokeColorRGB(*INK)
            c.setLineWidth(0.45)
            c.setDash()
            c.drawPath(poly_path(c, tab, ox, oy), stroke=1, fill=1)
            m = (p + q) / 2 + out * h * 0.48
            fs = min(6.0, h * 1.1, ln * 0.9)
            if fs >= 2.5:
                c.setFillColorRGB(0.45, 0.45, 0.45)
                c.setFont("ArialB", fs)
                c.saveState()
                x, y = P(ox + m[0], oy + m[1])
                c.translate(x, y)
                c.rotate(math.degrees(math.atan2(u[1], u[0])))
                c.drawCentredString(0, -fs * 0.35, str(cut_id[key]))
                c.restoreState()
    # 2) caras rellenas
    for fi, pts in isl.pos.items():
        col = shade(mesh, fi)
        c.setFillColorRGB(*col)
        c.setStrokeColorRGB(*col)
        c.setLineWidth(0.35)
        c.setDash()
        c.drawPath(poly_path(c, pts, ox, oy), stroke=1, fill=1)
    # 3) etiquetas de cara (números del dado, etc.)
    for fi, pts in isl.pos.items():
        lab = mesh.labels.get(fi)
        if lab:
            draw_face_label(c, lab, pts, ox, oy)
    # 4) líneas: pliegues y cortes
    drawn = set()
    for fi, pts in isl.pos.items():
        f = mesh.f[fi]
        for i in range(len(f)):
            a, b = f[i], f[(i + 1) % len(f)]
            key = (min(a, b), max(a, b))
            p, q = pts[i], pts[(i + 1) % len(f)]
            occ = mesh.edges[key]
            if key in isl.joined:
                if key in drawn:
                    continue
                drawn.add(key)
                g = occ[0][0] if occ[0][0] != fi else occ[1][0]
                ang = mesh.dihedral(fi, g)
                if ang < 1.5:
                    continue
                line(c, p, q, ox, oy, "monte" if mesh.convex(fi, g) else "valle")
            else:
                if tab_on.get(key) == fi:
                    line(c, p, q, ox, oy, "monte" if len(occ) == 2 and mesh.convex(occ[0][0], occ[1][0]) else "valle")
                else:
                    line(c, p, q, ox, oy, "corte")
                if key in cut_id:
                    edge_number(c, p, q, cut_id[key], ox, oy, shade(mesh, fi))


def line(c, p, q, ox, oy, kind):
    x1, y1 = P(ox + p[0], oy + p[1])
    x2, y2 = P(ox + q[0], oy + q[1])
    if kind == "corte":
        c.setStrokeColorRGB(*INK)
        c.setLineWidth(0.7)
        c.setDash()
    elif kind == "monte":
        c.setStrokeColorRGB(0.18, 0.14, 0.2)
        c.setLineWidth(0.4)
        c.setDash([3.2, 1.4])
    else:  # valle
        c.setStrokeColorRGB(0.05, 0.25, 0.75)
        c.setLineWidth(0.45)
        c.setDash([3.2, 1.2, 0.8, 1.2])
    c.line(x1, y1, x2, y2)
    c.setDash()


def edge_number(c, p, q, n, ox, oy, bg):
    d = q - p
    ln = float(np.hypot(*d))
    if ln < 3:
        return
    u = d / ln
    inw = np.array([-u[1], u[0]])
    fs = min(5.5, ln * 0.7)
    m = (p + q) / 2 + inw * (fs * 0.45 + 0.5)
    lum = 0.3 * bg[0] + 0.59 * bg[1] + 0.11 * bg[2]
    if lum > 0.45:
        c.setFillColorRGB(0.75, 0.05, 0.1)
    else:
        c.setFillColorRGB(1, 0.95, 0.6)
    c.setFont("ArialB", fs)
    c.saveState()
    x, y = P(ox + m[0], oy + m[1])
    c.translate(x, y)
    c.rotate(math.degrees(math.atan2(u[1], u[0])))
    c.drawCentredString(0, -fs * 0.35, str(n))
    c.restoreState()


def draw_face_label(c, lab, pts, ox, oy):
    cen = pts.mean(axis=0)
    up = pts[lab.get("up", 0)] - cen
    ang = math.degrees(math.atan2(up[1], up[0])) - 90
    x, y = P(ox + cen[0], oy + cen[1])
    c.saveState()
    c.translate(x, y)
    c.rotate(ang)
    img, wmm, hmm = label_image(lab)
    c.drawImage(ImageReader(img), -wmm / 2 * MM, -hmm / 2 * MM, wmm * MM, hmm * MM, mask="auto")
    c.restoreState()


_label_cache = {}


def label_image(lab):
    """Número de cómic: Impact, contorno de tinta redondo, sombra dura y subtítulo."""
    key = (lab["text"], lab.get("sub"), lab["color"], lab["size"])
    if key in _label_cache:
        return _label_cache[key]
    from PIL import ImageFont
    px = 16                                         # px por mm
    fs_mm = lab["size"] / MM
    font = ImageFont.truetype(r"C:\Windows\Fonts\impact.ttf", int(fs_mm * px))
    sw = max(2, int(fs_mm * px * 0.07))
    sub_font = ImageFont.truetype(r"C:\Windows\Fonts\impact.ttf", int(lab.get("sub_size", 8) / MM * px))
    W = int(fs_mm * px * 2.4)
    H = int(fs_mm * px * 1.9)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ink = (18, 12, 22, 255)
    col = tuple(int(v * 255) for v in lab["color"]) + (255,)
    cy = H * 0.42
    sh = sw * 0.9
    d.text((W / 2 + sh, cy + sh), lab["text"], font=font, anchor="mm", fill=ink, stroke_width=sw, stroke_fill=ink)
    d.text((W / 2, cy), lab["text"], font=font, anchor="mm", fill=col, stroke_width=sw, stroke_fill=ink)
    if lab.get("sub"):
        ssw = max(1, int(sub_font.size * 0.12))
        d.text((W / 2, H * 0.86), lab["sub"], font=sub_font, anchor="mm", fill=col, stroke_width=ssw, stroke_fill=ink)
    buf = io.BytesIO()
    im.save(buf, "PNG")
    buf.seek(0)
    _label_cache[key] = (buf, W / px, H / px)
    return _label_cache[key]


# ───────────────────────── modelos
def load_json_mesh(name, path, shade_on=True, flip=False):
    m = json.load(open(path))
    faces = [list(reversed(f)) for f in m["faces"]] if flip else m["faces"]
    return Mesh(name, m["verts"], faces, m["colors"], shade=shade_on)


def dodecahedron(edge):
    phi = (1 + 5 ** 0.5) / 2
    pts = []
    for x in (-1, 1):
        for y in (-1, 1):
            for z in (-1, 1):
                pts.append((x, y, z))
    for a in (-1, 1):
        for b in (-1, 1):
            pts.append((0, a / phi, b * phi))
            pts.append((a / phi, b * phi, 0))
            pts.append((a * phi, 0, b / phi))
    v = np.array(pts, dtype=float)
    v *= edge / (2 / phi)
    # caras: los 12 centros = direcciones (0, ±1, ±phi) cíclicas
    centers = []
    for a in (-1, 1):
        for b in (-1, 1):
            centers += [(0, a * phi, b), (a * phi, b, 0), (b, 0, a * phi)]
    faces = []
    for cdir in centers:
        cdir = np.array(cdir, dtype=float)
        cdir /= np.linalg.norm(cdir)
        d = v @ cdir
        idx = list(np.argsort(-d)[:5])
        cen = v[idx].mean(axis=0)
        # ordenar en sentido antihorario visto desde fuera
        u = v[idx[0]] - cen
        u /= np.linalg.norm(u)
        w = np.cross(cdir, u)
        idx.sort(key=lambda i: math.atan2(np.dot(v[i] - cen, w), np.dot(v[i] - cen, u)))
        faces.append(idx)
    # pares opuestos suman 13 como en un dado de verdad
    order = list(range(12))
    nums = [0] * 12
    used = set()
    k = 1
    cn = [np.array(cc, dtype=float) for cc in centers]
    for i in order:
        if i in used:
            continue
        j = min((jj for jj in order if jj not in used and jj != i), key=lambda jj: np.dot(cn[i], cn[jj]))
        nums[i], nums[j] = k, 13 - k
        used.update((i, j))
        k += 1
    return v, faces, nums


D12_INFO = {
    1: ("¡CATÁSTROFE!", False), 2: ("¡EMBOSCADA!", False), 3: ("¡MALDICIÓN!", False), 4: ("¡HERIDA!", False),
    5: ("BOLSA DE ORO", True), 6: ("¡REGALO!", True), 7: ("¡FURIA!", True), 8: ("¡CURA!", True),
    9: ("¡TESORO!", True), 10: ("¡LLUVIA DE XP!", True), 11: ("¡BENDICIÓN!", True), 12: ("¡¡JACKPOT!!", True),
}


def d12_mesh(edge):
    v, faces, nums = dodecahedron(edge)
    face_a, face_b = (0.36, 0.17, 0.62), (0.27, 0.12, 0.5)
    cols, labels = [], {}
    for i, n in enumerate(nums):
        cols.append(face_a if n % 2 else face_b)
        title, good = D12_INFO[n]
        col = (1.0, 0.55, 0.95) if n == 12 else ((1.0, 0.86, 0.35) if good else (1.0, 0.36, 0.3))
        labels[i] = dict(text=str(n) + ("." if n in (6, 9) else ""), color=col, size=edge * 0.62 * MM * (1 if n < 10 else 0.8),
                         sub=title, sub_size=edge * 0.1 * MM, sub_color=col, up=0)
    m = Mesh("D12", v, faces, cols, labels, shade=False)
    return m


def ring_mesh(ri, ro, depth, n, front, inner, outer):
    v, f, col = [], [], []
    for k in range(n):
        t = 2 * math.pi * (k + 0.5) / n
        cx, cz = math.cos(t), math.sin(t)
        for r in (ri, ro):
            for y in (-depth / 2, depth / 2):
                v.append((r * cx, y, r * cz))
    # índice: k*4 + (0: ri,-y) (1: ri,+y) (2: ro,-y) (3: ro,+y);  frente = -y
    for k in range(n):
        a, b = k * 4, ((k + 1) % n) * 4
        f.append([a + 0, b + 0, b + 2, a + 2]); col.append(front)        # frente (-y)
        f.append([a + 1, a + 3, b + 3, b + 1]); col.append(front)        # detrás (+y)
        f.append([a + 2, b + 2, b + 3, a + 3]); col.append(outer)        # banda exterior
        f.append([a + 0, a + 1, b + 1, b + 0]); col.append(inner)        # banda interior
    m = Mesh("anillo", v, f, col)
    # comprobar normales hacia fuera; si no, invertir
    bad = 0
    for fi in range(len(m.f)):
        cen = m.centroid(fi)
        if fi % 4 == 0 and m.n[fi][1] > 0:
            bad += 1
    if bad:
        f = [list(reversed(x)) for x in f]
        m = Mesh("anillo", v, f, col)
    # bandas: la interior debe mirar al centro
    return m


def box_mesh(w, d, h, col_top, col_side):
    x, y = w / 2, d / 2
    v = [(-x, -y, 0), (x, -y, 0), (x, y, 0), (-x, y, 0), (-x, -y, h), (x, -y, h), (x, y, h), (-x, y, h)]
    f = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
    col = [col_side, col_top, col_side, col_side, col_side, col_side]
    return Mesh("base", v, f, col)


def portal_disc(doc, color, title, sub, ri, n, label):
    """Membrana del portal: polígono de n lados con remolino y pestañas."""
    doc.new_page(title, sub)
    c = doc.c
    # radio del polígono = circunradio del anillo interior (vértices en ri)
    R = ri
    cx, cy = AREA_W / 2, AREA_H / 2 + 8
    px = 6                                          # px por mm del raster
    S = int((2 * R + 2) * px)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    o = S / 2
    deep = tuple(int(v * 255 * 0.22) for v in color)
    d.ellipse([0, 0, S, S], fill=deep + (255,))
    # brazos del remolino
    arms = 5
    for arm in range(arms):
        for s in range(260):
            t = s / 260
            ang = arm * 2 * math.pi / arms + t * 3.4 * math.pi
            r = (0.04 + 0.98 * t) * R * px
            w = (1.5 + 9 * t) * px * 0.55
            k = 0.35 + 0.65 * (1 - t)
            col = tuple(int(255 * min(1, cc * (0.6 + 0.6 * k) + 0.35 * k)) for cc in color)
            x, y = o + math.cos(ang) * r, o + math.sin(ang) * r
            d.ellipse([x - w, y - w, x + w, y + w], fill=col + (255,))
    # trama de puntos en tinta
    step = 3.2 * px
    j = 0
    yy = 0.0
    while yy < S:
        xx = (step / 2) * (j % 2)
        while xx < S:
            r = math.hypot(xx - o, yy - o) / (R * px)
            rad = step * 0.36 * max(0, r - 0.55) / 0.45
            if rad > 0.5:
                d.ellipse([xx - rad, yy - rad, xx + rad, yy + rad], fill=deep + (255,))
            xx += step
        yy += step
        j += 1
    # centro brillante
    d.ellipse([o - 9 * px, o - 9 * px, o + 9 * px, o + 9 * px], fill=(255, 255, 240, 255))
    img = img.filter(ImageFilter.SMOOTH)
    # recorte al polígono
    mask = Image.new("L", (S, S), 0)
    poly = [(o + math.cos(2 * math.pi * (k + 0.5) / n) * R * px, o - math.sin(2 * math.pi * (k + 0.5) / n) * R * px) for k in range(n)]
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    img.putalpha(mask)
    buf = io.BytesIO()
    img.save(buf, "PNG")
    buf.seek(0)
    # pestañas
    pts = [np.array([cx + math.cos(2 * math.pi * (k + 0.5) / n) * R, cy + math.sin(2 * math.pi * (k + 0.5) / n) * R]) for k in range(n)]
    for k in range(n):
        p, q = pts[k], pts[(k + 1) % n]
        u = (q - p) / np.linalg.norm(q - p)
        out = np.array([u[1], -u[0]])
        h, ins = 7.0, 4.0
        tab = [p, p + u * ins + out * h, q - u * ins + out * h, q]
        c.setFillColorRGB(0.9, 0.9, 0.88)
        c.setStrokeColorRGB(*INK)
        c.setLineWidth(0.45)
        c.drawPath(poly_path(c, tab, 0, 0), stroke=1, fill=1)
    x, y = P(cx - (R + 1), cy - (R + 1))
    c.drawImage(ImageReader(buf), x, y, S / px * MM, S / px * MM, mask="auto")
    for k in range(n):
        line(c, pts[k], pts[(k + 1) % n], 0, 0, "valle")
    c.setFont("ArialB", 8)
    c.setFillColorRGB(*INK)
    c.drawString(*P(0, 2), label)


# ───────────────────────── onomatopeyas
def load_words_module():
    spec = importlib.util.spec_from_file_location("mcw", os.path.join(ROOT, "tools", "make_comic_words.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def word_image(mod, group, idx):
    text, top, bottom, bcol, kill = mod.WORDS[group][idx]
    mod.SS = 10
    orig = Image.Image.resize

    def fake(self, size, *a, **k):
        if size == (mod.W, mod.H) and self.width > mod.W * 4:
            return self
        return orig(self, size, *a, **k)

    Image.Image.resize = fake
    try:
        img = mod.make(text, top, bottom, bcol, kill, 1000 + idx * 37 + len(group))
    finally:
        Image.Image.resize = orig
    img = img.resize((img.width // 3, img.height // 3), Image.LANCZOS)      # ~1700 px de ancho
    return text, img


def cut_border(img, border_px):
    """Añade borde blanco y línea de corte de tinta alrededor de la silueta."""
    a = img.split()[3].point(lambda v: 255 if v > 30 else 0)
    pad = border_px * 3
    W, H = img.width + 2 * pad, img.height + 2 * pad
    big = Image.new("L", (W, H), 0)
    big.paste(a, (pad, pad))
    grown = big.filter(ImageFilter.GaussianBlur(border_px * 0.55)).point(lambda v: 255 if v > 8 else 0)
    grown = grown.filter(ImageFilter.GaussianBlur(3)).point(lambda v: 255 if v > 128 else 0)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (W, H), (255, 255, 255, 255)), (0, 0), grown)
    edge = ImageChops.subtract(grown, grown.filter(ImageFilter.MinFilter(5)))
    out.paste(Image.new("RGBA", (W, H), (20, 15, 25, 255)), (0, 0), edge)
    out.alpha_composite(img, (pad, pad))
    bb = grown.getbbox()
    return out.crop(bb)


def words_pages(doc, supports=True):
    mod = load_words_module()
    picks = [("sword", 0), ("mace", 0), ("mace", 2), ("fist", 1), ("mace", 5), ("fist", 5)]
    imgs = []
    for g, i in picks:
        text, img = word_image(mod, g, i)
        imgs.append((text, cut_border(img, 22)))
        print("palabra", text, img.size)
    per = 2
    for pg in range(0, len(imgs), per):
        doc.new_page("ONOMATOPEYAS", "carteles %d-%d" % (pg + 1, min(pg + per, len(imgs))))
        c = doc.c
        for j, (text, im) in enumerate(imgs[pg:pg + per]):
            w = AREA_W - 16
            h = min(w * im.height / im.width, AREA_H / per - 6)
            w = h * im.width / im.height
            y = AREA_H - (j + 1) * (AREA_H / per) + (AREA_H / per - h) / 2
            buf = io.BytesIO()
            im.save(buf, "PNG")
            buf.seek(0)
            c.drawImage(ImageReader(buf), *P((AREA_W - w) / 2, y), w * MM, h * MM, mask="auto")
    # soportes (atriles) para pararlas
    if not supports:
        return
    doc.new_page("ONOMATOPEYAS", "soportes (6)")
    c = doc.c
    for k in range(6):
        col, row = k % 3, k // 3
        ox, oy = 8 + col * 64, AREA_H - 20 - (row + 1) * 110
        # pieza: pestaña pegable 45x18 | pliegue | pata 45x70 | pliegue | pie 45x20
        rects = [(0, 0, 45, 20, "pie"), (0, 20, 45, 70, "pata"), (0, 90, 45, 18, "pega al cartel")]
        for x, y, w, h, t in rects:
            c.setFillColorRGB(0.98, 0.86, 0.35) if t == "pata" else c.setFillColorRGB(0.92, 0.92, 0.9)
            c.setStrokeColorRGB(*INK)
            c.setLineWidth(0.7)
            c.rect(*P(ox + x, oy + y), w * MM, h * MM, stroke=0, fill=1)
            c.setFillColorRGB(*INK)
            c.setFont("ArialB", 7)
            c.drawCentredString(*P(ox + x + w / 2, oy + y + h / 2 - 1), t.upper())
        c.setLineWidth(0.7)
        c.rect(*P(ox, oy), 45 * MM, 108 * MM, stroke=1, fill=0)
        line(c, np.array([0, 20]), np.array([45, 20]), ox, oy, "valle")
        line(c, np.array([0, 90]), np.array([45, 90]), ox, oy, "valle")
        c.setFont("Impact", 14)
        c.setFillColorRGB(*INK)
        c.drawCentredString(*P(ox + 22.5, oy + 66), "RUMBANG")


# ───────────────────────── portada e instrucciones
def cover(doc):
    doc.new_page("PAPERCRAFT DEL STAND", "portada")
    c = doc.c
    c.setFillColorRGB(*INK)
    c.setFont("Impact", 64)
    c.drawCentredString(*P(AREA_W / 2, AREA_H - 38), "RUMBANG")
    c.setFont("Impact", 22)
    c.setFillColorRGB(0.93, 0.45, 0.12)
    c.drawCentredString(*P(AREA_W / 2, AREA_H - 52), "PAPERCRAFT PARA EL STAND")
    y = AREA_H - 70
    c.setFillColorRGB(*INK)
    c.setFont("ArialB", 11)
    c.drawString(*P(6, y), "Qué trae")
    c.setFont("Arial", 9.5)
    rows = [
        "1. La R, partida en dos: la mitad que ENTRA (portal naranja) y la que SALE (portal verde).",
        "2. Dos portales: anillo de piedra, membrana con remolino y base. Naranja = Cavernas, verde = Cloacas.",
        "3. Dado del destino de 12 caras con los resultados del modo supervivencia.",
        "4. Dos enemigos de las Cloacas: la rata y el hinchado.",
        "5. Seis onomatopeyas de cómic con su soporte.",
    ]
    for r in rows:
        y -= 6
        c.drawString(*P(9, y), r)
    y -= 12
    c.setFont("ArialB", 11)
    c.drawString(*P(6, y), "Material")
    c.setFont("Arial", 9.5)
    for r in [
        "Cartulina de 180-220 g para las piezas 3D (papel normal se arruga).",
        "Cúter, regla de metal, punzón o bolígrafo sin tinta para marcar pliegues, pegamento blanco o en barra fuerte.",
        "Cartón o foamboard de 3-5 mm para la membrana de los portales y las onomatopeyas.",
        "Imprime al 100 % (\"tamaño real\"). Mide la regla de 50 mm del pie de cada hoja.",
    ]:
        y -= 6
        c.drawString(*P(9, y), r)
    # leyenda
    y -= 14
    c.setFont("ArialB", 11)
    c.drawString(*P(6, y), "Leyenda de líneas")
    y -= 8
    for kind, txt in [("corte", "Línea continua negra: CORTAR."),
                      ("monte", "Rayas grises: pliegue de MONTE (la cara impresa queda por fuera, hacia ti)."),
                      ("valle", "Raya-punto azul: pliegue de VALLE (la cara impresa queda por dentro).")]:
        line(c, np.array([9, y + 1]), np.array([30, y + 1]), 0, 0, kind)
        c.setFont("Arial", 9.5)
        c.setFillColorRGB(*INK)
        c.drawString(*P(34, y), txt)
        y -= 7
    c.setFillColorRGB(0.9, 0.9, 0.88)
    c.setStrokeColorRGB(*INK)
    c.rect(*P(9, y - 1), 21 * MM, 4.5 * MM, stroke=1, fill=1)
    c.setFillColorRGB(0.45, 0.45, 0.45)
    c.setFont("ArialB", 6)
    c.drawCentredString(*P(19.5, y + 0.3), "12")
    c.setFillColorRGB(*INK)
    c.setFont("Arial", 9.5)
    c.drawString(*P(34, y), "Pestaña gris con número: se pega bajo la arista roja con el MISMO número.")
    y -= 14
    c.setFont("ArialB", 11)
    c.drawString(*P(6, y), "Consejos")
    c.setFont("Arial", 9.5)
    for r in [
        "Marca todos los pliegues con la regla ANTES de recortar. Recorta las pestañas al final.",
        "Arma cada pieza de dentro hacia fuera; deja para el final las aristas que cierran el volumen.",
        "Cada modelo usa su propia numeración (la arista 5 del dado no tiene que ver con la 5 de la rata).",
        "¿Más grande? Imprime con \"póster / mosaico\" (Adobe Reader: Imprimir > Póster) al 200-400 %.",
        "Para el stand de tamaño real usa estas piezas como maqueta y patrón para cortar en foam o MDF.",
    ]:
        y -= 6
        c.drawString(*P(9, y), r)


def instructions(doc, info):
    doc.new_page("CÓMO ARMAR EL STAND", "instrucciones")
    c = doc.c
    y = AREA_H - 6
    blocks = [
        ("LA R QUE ATRAVIESA LOS PORTALES", [
            "La R mide 16 cm de alto y 3,5 cm de grosor. Está cortada en dos por un plano vertical.",
            "La cara del corte va impresa en morado oscuro: es la que se pega sobre la membrana del portal.",
            "Mitad izquierda (el palo de la R) -> pégala en el centro de la membrana NARANJA: es la R que entra.",
            "Mitad derecha (el bucle y la pata) -> pégala en la membrana VERDE: es la R que sale.",
            "Pon los portales separados (en extremos de la mesa) y a la misma altura: la R parece viajar de uno al otro.",
        ]),
        ("PORTALES (uno naranja, uno verde)", [
            "Anillo de 16 lados: diámetro interior 17,2 cm, exterior 21,2 cm, 3 cm de fondo. Sale en varias piezas.",
            "Arma el anillo cerrando primero las bandas interior y exterior, luego las caras de delante y detrás.",
            "Membrana: pega la hoja sobre cartón, recorta el polígono con sus pestañas y pliégalas hacia atrás.",
            "Mete la membrana en el anillo a media profundidad y pega las pestañas a la banda interior.",
            "Base: caja de 13 x 5 x 2 cm. Pégala bajo el anillo para que el portal quede de pie.",
        ]),
        ("DADO DEL DESTINO (D12)", [
            "Dodecaedro de %.0f mm de arista (unos %.0f cm de diámetro). Caras opuestas suman 13." % (info["d12_edge"], info["d12_diam"] / 10),
            "1-4 son las caras malas (número rojo), 5-11 buenas (dorado) y 12 el ¡¡JACKPOT!! (rosa).",
            "Truco: pega todo menos la última cara; mete una bola de papel o un peso para que ruede mejor.",
        ]),
        ("ENEMIGOS", [
            "Rata (%.0f cm de largo con la cola) y hinchado (%.0f cm de alto), del mapa Cloacas." % (info["rata"] / 10, info["hinchado"] / 10),
            "Son modelos del juego simplificados (low poly): ~300 triángulos. Ten paciencia con las piezas pequeñas.",
            "Los ojos y dientes van pintados sobre la superficie. Empieza por el cuerpo y deja cola, orejas y patas al final.",
        ]),
        ("ONOMATOPEYAS", [
            "Pega cada hoja sobre foamboard o cartón y recorta por la línea negra exterior (el borde blanco queda como marco).",
            "Pega el soporte por detrás: la parte \"pega al cartel\" en la espalda, dobla la pata y el pie.",
            "Cuélgalas también con hilo de pescar sobre la mesa o pégalas en los portales.",
        ]),
    ]
    for head, rows in blocks:
        c.setFillColorRGB(0.93, 0.45, 0.12)
        c.setFont("Impact", 14)
        c.drawString(*P(4, y), head)
        y -= 6
        c.setFillColorRGB(*INK)
        c.setFont("Arial", 9)
        for r in rows:
            c.drawString(*P(7, y), "- " + r)
            y -= 5.2
        y -= 5
    c.setFont("ArialB", 9)
    c.drawString(*P(4, y), "Hojas: " + info["sumario"])


# ───────────────────────── main
def main():
    doc = Doc(OUT_PDF)
    cover(doc)
    ins_page_holder = None
    # tamaños
    d12_edge = 40.0
    info = {"d12_edge": d12_edge}
    # pasamos una vez para saber medidas; se dibujan después de las instrucciones
    rata = load_json_mesh("rata", os.path.join(HERE, "rata.json"))
    hinch = load_json_mesh("hinchado", os.path.join(HERE, "hinchado.json"))
    info["rata"] = float(np.ptp(rata.v, axis=0).max())
    info["hinchado"] = float(np.ptp(hinch.v, axis=0).max())
    d12 = d12_mesh(d12_edge)
    info["d12_diam"] = float(np.linalg.norm(d12.v, axis=1).max() * 2)
    info["sumario"] = "portada, instrucciones, R, portales, dado, enemigos, onomatopeyas."
    instructions(doc, info)

    stats = []
    for side, name in (("izq", "R - MITAD QUE ENTRA (izquierda)"), ("der", "R - MITAD QUE SALE (derecha)")):
        m = load_json_mesh("R_" + side, os.path.join(HERE, "R_%s.json" % side), shade_on=False, flip=True)
        stats.append((name, draw_model(doc, m, name, "R %s" % side, split_colors=True)))
    stone = (0.36, 0.33, 0.42)
    stone_dark = (0.24, 0.22, 0.29)
    for nm, col in (("NARANJA", (1.0, 0.55, 0.2)), ("VERDE", (0.45, 1.0, 0.3))):
        ring = ring_mesh(86.0, 106.0, 30.0, 16, stone, col, stone_dark)
        stats.append(("anillo " + nm, draw_model(doc, ring, "PORTAL %s - ANILLO" % nm, "anillo", split_colors=True)))
        portal_disc(doc, col, "PORTAL %s - MEMBRANA" % nm, "membrana", 86.0, 16,
                    "Pega sobre cartón, recorta con pestañas. Aquí se pega la %s de la R." %
                    ("mitad izquierda" if nm == "NARANJA" else "mitad derecha"))
        base = box_mesh(130, 50, 20, stone, stone_dark)
        stats.append(("base " + nm, draw_model(doc, base, "PORTAL %s - BASE" % nm, "base")))
    stats.append(("D12", draw_model(doc, d12, "DADO DEL DESTINO - D12", "dado")))
    stats.append(("rata", draw_model(doc, rata, "ENEMIGO - RATA DE CLOACA", "rata")))
    stats.append(("hinchado", draw_model(doc, hinch, "ENEMIGO - HINCHADO", "hinchado")))
    words_pages(doc)
    doc.save()
    for s in stats:
        print(s)
    print("PAGINAS", doc.page, OUT_PDF)


if __name__ == "__main__":
    main()
