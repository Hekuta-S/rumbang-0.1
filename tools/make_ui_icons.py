"""Iconos DIBUJADOS (estilo cómic: tinta oscura + colores planos) para la UI de supervivencia.

    python tools/make_ui_icons.py

Sale (ver design/ux/level-up-cards.md):
  assets/ui/icons/tags/<etiqueta>.png   128 px, las 5 etiquetas de sinergia (WeaponSynergies.TAG_INFO).
      Cada una con forma propia, no solo color: Filo = rombo, Fuego = llama, Explosivo = estallido,
      Arcano = círculo con espiral, Naturaleza = hoja.
  assets/ui/icons/tomes/<tomo>.png      128 px, los 12 tomos de supervivencia (TomeDB.TOMES): libro del
      color del tomo con su símbolo en la tapa.
  assets/ui/ingame_hub/armas/<arma>.png 648 px, las 7 armas que no tenían imagen, dibujadas sobre el
      marco _marco.png como las demás.

Todo es geometría (polígonos, elipses, trazos) con supermuestreo: el contorno de tinta se dibuja como una
pasada gruesa debajo de cada pieza (rápido, sin filtros de máximo) y cada pieza lleva su propio contorno
fino, como un dibujo entintado.
"""
import math
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAGS_OUT = os.path.join(ROOT, "assets", "ui", "icons", "tags")
TOMES_OUT = os.path.join(ROOT, "assets", "ui", "icons", "tomes")
WEAPONS_OUT = os.path.join(ROOT, "assets", "ui", "ingame_hub", "armas")
FRAME = os.path.join(WEAPONS_OUT, "_marco.png")
INK = (26, 22, 30, 255)
WHITE = (250, 248, 240, 255)


def rgb(r, g, b, a=255):
    return (r, g, b, a)


class Pic:
    """Lienzo con piezas: primero se dibuja la tinta gruesa de todas (silueta), luego los rellenos con su
    contorno fino y por último los trazos de detalle. Coordenadas normalizadas 0..1."""

    def __init__(self, size, ss=4, outer=0.034, inner=0.014):
        self.size = size
        self.n = size * ss
        self.outer = outer
        self.inner = inner
        self.parts = []      # (kind, geom, fill, outline)
        self.details = []    # (pts, width, color)

    def _p(self, pts):
        return [(x * self.n, y * self.n) for x, y in pts]

    def poly(self, pts, fill, outline=True):
        self.parts.append(("poly", self._p(pts), fill, outline))

    def ell(self, cx, cy, rx, ry, fill, outline=True):
        n = self.n
        self.parts.append(("ell", [(cx - rx) * n, (cy - ry) * n, (cx + rx) * n, (cy + ry) * n], fill, outline))

    def rect(self, x0, y0, x1, y1, fill, outline=True):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], fill, outline)

    def line(self, pts, width, fill, outline=True):
        """Trazo grueso con extremos redondos (cuerpo de serpiente, mango, asa)."""
        self.parts.append(("line", (self._p(pts), width * self.n), fill, outline))

    def detail(self, pts, width, color=INK):
        """Trazo encima de todo (pliegues, brillos, venas)."""
        self.details.append((self._p(pts), width * self.n, color))

    @staticmethod
    def _line(d, pts, w, color):
        w = max(1, int(round(w)))
        d.line(pts, fill=color, width=w, joint="curve")
        r = w / 2.0
        for x, y in (pts[0], pts[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=color)

    def render(self):
        img = Image.new("RGBA", (self.n, self.n), INK[:3] + (0,))
        d = ImageDraw.Draw(img)
        o = max(1, int(self.outer * self.n))
        i = max(1, int(self.inner * self.n))
        # 1) silueta de tinta gruesa
        for kind, geom, fill, outline in self.parts:
            if kind == "poly":
                d.polygon(geom, fill=INK, outline=INK, width=o * 2)
            elif kind == "ell":
                x0, y0, x1, y1 = geom
                d.ellipse([x0 - o, y0 - o, x1 + o, y1 + o], fill=INK)
            else:
                pts, w = geom
                self._line(d, pts, w + o * 2, INK)
        # 2) rellenos, cada uno con su contorno fino
        for kind, geom, fill, outline in self.parts:
            if kind == "poly":
                d.polygon(geom, fill=fill)
                if outline:
                    d.line(geom + [geom[0]], fill=INK, width=i, joint="curve")
            elif kind == "ell":
                d.ellipse(geom, fill=fill, outline=INK if outline else None, width=i if outline else 0)
            else:
                pts, w = geom
                if outline:
                    self._line(d, pts, w + i * 2, INK)
                self._line(d, pts, w, fill)
        # 3) detalles
        for pts, w, color in self.details:
            self._line(d, pts, w, color)
        return img.resize((self.size, self.size), Image.LANCZOS)


# ── utilidades de forma ──────────────────────────────────────────────────

def star(cx, cy, r_out, r_in, points, rot=0.0):
    pts = []
    for k in range(points * 2):
        a = rot + k * math.pi / points - math.pi / 2
        r = r_out if k % 2 == 0 else r_in
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def circle_pts(cx, cy, r, steps=40, a0=0.0, a1=math.tau):
    return [(cx + math.cos(a0 + (a1 - a0) * t / steps) * r, cy + math.sin(a0 + (a1 - a0) * t / steps) * r)
            for t in range(steps + 1)]


def lens(p0, p1, half_w, steps=24):
    """Hoja / ojo: forma afilada en los dos extremos entre p0 y p1."""
    (x0, y0), (x1, y1) = p0, p1
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy)
    px, py = -dy / ln, dx / ln
    top, bot = [], []
    for k in range(steps + 1):
        t = k / steps
        w = half_w * math.sin(math.pi * t)
        cx, cy = x0 + dx * t, y0 + dy * t
        top.append((cx + px * w, cy + py * w))
        bot.append((cx - px * w, cy - py * w))
    return top + bot[::-1]


def heart(cx, cy, s, steps=48):
    pts = []
    for k in range(steps):
        t = k / steps * math.tau
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x / 17.0 * s, cy - y / 17.0 * s))
    return pts


class Axis:
    """Ejes de un objeto en diagonal: u a lo largo (0 = mango, 1 = punta), v de lado."""

    def __init__(self, p0, p1):
        self.p0 = p0
        self.dx, self.dy = p1[0] - p0[0], p1[1] - p0[1]
        ln = math.hypot(self.dx, self.dy)
        self.px, self.py = -self.dy / ln, self.dx / ln
        self.len = ln

    def __call__(self, u, v):
        return (self.p0[0] + self.dx * u + self.px * v * self.len,
                self.p0[1] + self.dy * u + self.py * v * self.len)

    def pts(self, uvs):
        return [self(u, v) for u, v in uvs]

    def rect(self, u0, u1, v0, v1):
        return self.pts([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])


# ── etiquetas de sinergia ────────────────────────────────────────────────

def tag_filo():
    p = Pic(128)
    p.poly([(0.5, 0.04), (0.96, 0.5), (0.5, 0.96), (0.04, 0.5)], rgb(217, 230, 255))
    p.poly([(0.5, 0.17), (0.57, 0.28), (0.57, 0.6), (0.43, 0.6), (0.43, 0.28)], rgb(150, 165, 200))
    p.detail([(0.5, 0.24), (0.5, 0.56)], 0.022, rgb(245, 248, 255))
    p.rect(0.33, 0.6, 0.67, 0.67, rgb(120, 80, 50))
    p.rect(0.46, 0.67, 0.54, 0.79, rgb(70, 50, 40))
    p.ell(0.5, 0.82, 0.045, 0.045, rgb(200, 60, 60))
    return p


def tag_fuego():
    p = Pic(128)
    p.poly([(0.5, 0.03), (0.62, 0.22), (0.79, 0.16), (0.77, 0.38), (0.92, 0.56), (0.86, 0.8), (0.68, 0.95),
            (0.32, 0.95), (0.14, 0.8), (0.08, 0.56), (0.23, 0.37), (0.21, 0.15), (0.38, 0.25)], rgb(255, 128, 51))
    p.poly([(0.5, 0.36), (0.63, 0.55), (0.68, 0.74), (0.58, 0.87), (0.42, 0.87), (0.32, 0.74), (0.37, 0.55)],
           rgb(255, 214, 90))
    p.ell(0.5, 0.76, 0.06, 0.08, WHITE, outline=False)
    return p


def tag_explosivo():
    p = Pic(128)
    p.poly(star(0.5, 0.5, 0.48, 0.3, 8, rot=0.2), rgb(255, 204, 64))
    p.poly(star(0.5, 0.5, 0.27, 0.15, 8, rot=0.0), rgb(235, 70, 45))
    p.ell(0.5, 0.5, 0.08, 0.08, WHITE)
    return p


def tag_arcano():
    p = Pic(128)
    p.ell(0.5, 0.5, 0.45, 0.45, rgb(179, 128, 255))
    spiral = []
    for k in range(80):
        t = k / 79
        a = t * math.tau * 2.1
        r = 0.03 + 0.3 * t
        spiral.append((0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r))
    p.line(spiral, 0.06, rgb(240, 232, 255))
    for a in (0.6, 2.4, 4.3):
        x, y = 0.5 + math.cos(a) * 0.38, 0.5 + math.sin(a) * 0.38
        p.ell(x, y, 0.025, 0.025, WHITE, outline=False)
    return p


def tag_naturaleza():
    p = Pic(128)
    p.line([(0.14, 0.88), (0.26, 0.76)], 0.05, rgb(70, 140, 60))
    p.poly(lens((0.22, 0.8), (0.88, 0.12), 0.26), rgb(115, 225, 100))
    p.detail([(0.26, 0.76), (0.82, 0.18)], 0.024, rgb(40, 110, 40))
    for t in (0.35, 0.55, 0.72):
        cx, cy = 0.26 + (0.82 - 0.26) * t, 0.76 + (0.18 - 0.76) * t
        p.detail([(cx, cy), (cx - 0.13, cy - 0.04)], 0.016, rgb(40, 110, 40))
        p.detail([(cx, cy), (cx + 0.04, cy + 0.13)], 0.016, rgb(40, 110, 40))
    return p


TAGS = {"filo": tag_filo, "fuego": tag_fuego, "explosivo": tag_explosivo, "arcano": tag_arcano,
        "naturaleza": tag_naturaleza}


# ── tomos ────────────────────────────────────────────────────────────────

def book(cover, symbol):
    """Libro de frente: páginas color crema detrás, tapa del color del tomo con lomo y bandas doradas, y el
    símbolo en el centro de la tapa (symbol(p, cx, cy, s))."""
    p = Pic(128, outer=0.03, inner=0.013)
    p.rect(0.22, 0.12, 0.88, 0.93, rgb(245, 235, 205))
    for y in (0.86, 0.89):
        p.detail([(0.3, y), (0.86, y)], 0.008, rgb(190, 175, 140))
    dark = tuple(int(c * 0.62) for c in cover[:3]) + (255,)
    p.rect(0.12, 0.06, 0.8, 0.84, cover)
    p.rect(0.12, 0.06, 0.22, 0.84, dark)
    gold = rgb(240, 200, 80)
    p.detail([(0.27, 0.13), (0.75, 0.13)], 0.018, gold)
    p.detail([(0.27, 0.77), (0.75, 0.77)], 0.018, gold)
    symbol(p, 0.51, 0.45, 0.22)
    return p


def sym_poder(p, cx, cy, s):
    p.poly([(cx, cy - s), (cx + s * 0.85, cy), (cx + s * 0.35, cy), (cx + s * 0.35, cy + s),
            (cx - s * 0.35, cy + s), (cx - s * 0.35, cy), (cx - s * 0.85, cy)], WHITE)


def sym_celeridad(p, cx, cy, s):
    p.poly([(cx - s * 0.7, cy - s), (cx + s * 0.7, cy - s), (cx, cy), (cx + s * 0.7, cy + s),
            (cx - s * 0.7, cy + s), (cx, cy)], rgb(225, 235, 250))
    p.poly([(cx - s * 0.35, cy + s * 0.5), (cx + s * 0.35, cy + s * 0.5), (cx + s * 0.6, cy + s * 0.9),
            (cx - s * 0.6, cy + s * 0.9)], rgb(245, 205, 90), outline=False)
    p.rect(cx - s * 0.85, cy - s * 1.12, cx + s * 0.85, cy - s * 0.95, rgb(150, 100, 60))
    p.rect(cx - s * 0.85, cy + s * 0.95, cx + s * 0.85, cy + s * 1.12, rgb(150, 100, 60))


def sym_area(p, cx, cy, s):
    p.ell(cx, cy, s, s, WHITE)
    p.ell(cx, cy, s * 0.66, s * 0.66, rgb(230, 70, 60))
    p.ell(cx, cy, s * 0.33, s * 0.33, WHITE)


def sym_multiplicidad(p, cx, cy, s):
    for dx, dy in ((0, -0.55), (-0.6, 0.45), (0.6, 0.45)):
        x, y = cx + dx * s, cy + dy * s
        p.poly([(x, y - s * 0.45), (x + s * 0.3, y), (x, y + s * 0.45), (x - s * 0.3, y)], WHITE)


def sym_iman(p, cx, cy, s):
    u = circle_pts(cx, cy - s * 0.1, s * 0.62, 24, 0.0, math.pi)
    u = [(cx + s * 0.62, cy - s * 0.85)] + u + [(cx - s * 0.62, cy - s * 0.85)]
    p.line(u, 0.1, rgb(220, 50, 50))
    p.detail([(cx + s * 0.62, cy - s * 0.88), (cx + s * 0.62, cy - s * 0.55)], 0.085, WHITE)
    p.detail([(cx - s * 0.62, cy - s * 0.88), (cx - s * 0.62, cy - s * 0.55)], 0.085, WHITE)


def sym_vitalidad(p, cx, cy, s):
    p.poly(heart(cx, cy, s * 1.05), rgb(235, 45, 70))
    p.ell(cx - s * 0.42, cy - s * 0.38, s * 0.14, s * 0.1, WHITE, outline=False)


def sym_regeneracion(p, cx, cy, s):
    a, b = s * 0.32, s * 0.95
    p.poly([(cx - a, cy - b), (cx + a, cy - b), (cx + a, cy - a), (cx + b, cy - a), (cx + b, cy + a), (cx + a, cy + a),
            (cx + a, cy + b), (cx - a, cy + b), (cx - a, cy + a), (cx - b, cy + a), (cx - b, cy - a), (cx - a, cy - a)],
           WHITE)


def sym_armadura(p, cx, cy, s):
    p.poly([(cx - s * 0.85, cy - s * 0.9), (cx + s * 0.85, cy - s * 0.9), (cx + s * 0.8, cy + s * 0.1),
            (cx, cy + s * 1.05), (cx - s * 0.8, cy + s * 0.1)], rgb(215, 222, 235))
    p.poly([(cx - s * 0.18, cy - s * 0.9), (cx + s * 0.18, cy - s * 0.9), (cx + s * 0.18, cy + s * 0.85),
            (cx, cy + s * 1.0), (cx - s * 0.18, cy + s * 0.85)], rgb(70, 110, 200), outline=False)


def sym_zancada(p, cx, cy, s):
    p.poly([(cx - s * 0.5, cy - s), (cx + s * 0.1, cy - s), (cx + s * 0.15, cy + s * 0.25), (cx + s * 0.95, cy + s * 0.45),
            (cx + s * 0.95, cy + s * 0.95), (cx - s * 0.55, cy + s * 0.95)], rgb(150, 95, 55))
    p.detail([(cx - s * 0.55, cy + s * 0.8), (cx + s * 0.95, cy + s * 0.8)], 0.02, rgb(70, 45, 30))
    p.poly([(cx - s * 0.5, cy - s * 0.55), (cx - s * 1.15, cy - s * 0.95), (cx - s * 1.0, cy - s * 0.5),
            (cx - s * 1.2, cy - s * 0.3), (cx - s * 0.5, cy - s * 0.15)], WHITE)


def sym_suerte(p, cx, cy, s):
    p.line([(cx, cy + s * 0.2), (cx + s * 0.2, cy + s * 1.05)], 0.04, rgb(60, 150, 60))
    for dx, dy in ((0, -0.5), (0.5, 0), (0, 0.5), (-0.5, 0)):
        p.ell(cx + dx * s, cy + dy * s, s * 0.45, s * 0.45, rgb(110, 210, 90))
    p.ell(cx, cy, s * 0.14, s * 0.14, rgb(60, 150, 60), outline=False)


def sym_avaricia(p, cx, cy, s):
    p.ell(cx + s * 0.25, cy + s * 0.35, s * 0.75, s * 0.75, rgb(215, 170, 40))
    p.ell(cx - s * 0.15, cy - s * 0.15, s * 0.75, s * 0.75, rgb(250, 210, 60))
    p.detail(circle_pts(cx - s * 0.15, cy - s * 0.15, s * 0.52, 40), 0.014, rgb(170, 120, 20))
    p.detail([(cx - s * 0.15, cy - s * 0.48), (cx - s * 0.15, cy + s * 0.18)], 0.03, rgb(170, 120, 20))


def sym_saber(p, cx, cy, s):
    p.poly(lens((cx - s * 1.05, cy), (cx + s * 1.05, cy), s * 0.62), WHITE)
    p.ell(cx, cy, s * 0.42, s * 0.42, rgb(70, 160, 230))
    p.ell(cx, cy, s * 0.18, s * 0.18, INK, outline=False)
    p.ell(cx - s * 0.12, cy - s * 0.14, s * 0.07, s * 0.07, WHITE, outline=False)


TOMES = {
    "poder": (rgb(200, 50, 50), sym_poder),
    "celeridad": (rgb(60, 110, 210), sym_celeridad),
    "area": (rgb(40, 165, 165), sym_area),
    "multiplicidad": (rgb(225, 125, 40), sym_multiplicidad),
    "iman": (rgb(110, 115, 135), sym_iman),
    "vitalidad": (rgb(225, 90, 140), sym_vitalidad),
    "regeneracion": (rgb(55, 165, 80), sym_regeneracion),
    "armadura": (rgb(95, 105, 125), sym_armadura),
    "zancada": (rgb(215, 180, 50), sym_zancada),
    "suerte": (rgb(35, 125, 60), sym_suerte),
    "avaricia": (rgb(190, 140, 30), sym_avaricia),
    "saber": (rgb(75, 60, 165), sym_saber),
}


# ── armas (sobre el marco) ───────────────────────────────────────────────

def weapon_pic():
    return Pic(648, ss=2, outer=0.011, inner=0.005)


def w_energy_sword():
    p = weapon_pic()
    a = Axis((0.25, 0.77), (0.8, 0.22))
    p.poly(a.pts([(0.3, -0.07), (0.9, -0.07), (1.0, 0.0), (0.9, 0.07), (0.3, 0.07)]), rgb(90, 220, 255))
    p.detail([a(0.34, 0.0), a(0.9, 0.0)], 0.018, WHITE)
    p.poly(a.rect(0.25, 0.3, -0.17, 0.17), rgb(70, 70, 95))
    p.poly(a.rect(0.06, 0.25, -0.045, 0.045), rgb(45, 45, 60))
    for u in (0.1, 0.15, 0.2):
        p.detail([a(u, -0.045), a(u + 0.03, 0.045)], 0.006, rgb(110, 110, 140))
    p.ell(*a(0.03, 0.0), 0.04, 0.04, rgb(150, 90, 255))
    return p


def w_katana():
    p = weapon_pic()
    a = Axis((0.22, 0.8), (0.82, 0.2))
    blade_top = [(u, -0.035 + 0.035 * math.sin(math.pi * (u - 0.3) / 0.7)) for u in [0.3 + 0.7 * k / 16 for k in range(17)]]
    blade_bot = [(u, 0.035 + 0.035 * math.sin(math.pi * (u - 0.3) / 0.7) * 1.0) for u in [0.3 + 0.7 * k / 16 for k in range(17)]]
    tip = [(1.0, 0.012)]
    p.poly(a.pts(blade_top + tip + blade_bot[::-1]), rgb(225, 230, 240))
    p.detail(a.pts([(u, 0.015 + 0.035 * math.sin(math.pi * (u - 0.3) / 0.7)) for u in [0.32 + 0.6 * k / 12 for k in range(13)]]),
             0.008, rgb(170, 180, 200))
    p.detail(a.pts([(0.86, 0.04), (0.97, 0.03)]), 0.012, rgb(200, 30, 40))
    p.ell(*a(0.29, 0.0), 0.05, 0.05, rgb(215, 170, 60))
    p.poly(a.rect(0.06, 0.27, -0.04, 0.04), rgb(175, 30, 40))
    for k in range(5):
        u = 0.09 + k * 0.04
        p.detail([a(u, -0.035), a(u + 0.02, 0.0), a(u, 0.035)], 0.006, WHITE)
    return p


def w_railgun():
    p = weapon_pic()
    a = Axis((0.18, 0.72), (0.86, 0.3))
    p.poly(a.rect(0.32, 0.62, 0.08, 0.3), rgb(55, 55, 70))
    p.poly(a.rect(0.5, 1.0, -0.11, -0.05), rgb(95, 95, 115))
    p.poly(a.rect(0.5, 1.0, 0.05, 0.11), rgb(95, 95, 115))
    p.poly(a.rect(0.08, 0.66, -0.13, 0.13), rgb(75, 75, 95))
    for u in (0.36, 0.48, 0.6):
        p.poly(a.rect(u, u + 0.05, -0.17, 0.17), rgb(170, 90, 255))
        p.detail([a(u + 0.025, -0.15), a(u + 0.025, 0.15)], 0.006, rgb(225, 195, 255))
    p.poly(a.pts([(0.0, 0.0), (0.06, -0.09), (0.12, 0.0), (0.06, 0.09)]), rgb(200, 140, 255))
    p.detail([a(0.62, 0.0), a(0.98, 0.0)], 0.01, rgb(200, 140, 255))
    return p


def w_serpents():
    p = weapon_pic()
    body = []
    for k in range(40):
        t = k / 39
        x = 0.22 + 0.5 * t
        y = 0.78 - 0.5 * t + 0.11 * math.sin(t * math.tau * 1.1)
        body.append((x, y))
    p.line(body, 0.085, rgb(85, 175, 75))
    p.detail(body[3:-2], 0.03, rgb(190, 225, 120))
    hx, hy = body[-1]
    p.ell(hx + 0.035, hy - 0.02, 0.085, 0.06, rgb(85, 175, 75))
    p.ell(hx + 0.06, hy - 0.04, 0.022, 0.022, rgb(250, 220, 60))
    p.ell(hx + 0.065, hy - 0.04, 0.008, 0.016, INK, outline=False)
    p.detail([(hx + 0.115, hy - 0.005), (hx + 0.17, hy + 0.01), (hx + 0.19, hy - 0.01)], 0.008, rgb(220, 40, 50))
    p.detail([(hx + 0.17, hy + 0.01), (hx + 0.19, hy + 0.035)], 0.008, rgb(220, 40, 50))
    for k in range(6, 36, 6):
        x, y = body[k]
        p.ell(x, y, 0.016, 0.016, rgb(50, 120, 50), outline=False)
    return p


def w_spinning_axe():
    p = weapon_pic()
    a = Axis((0.3, 0.82), (0.64, 0.26))
    p.line([a(0.0, 0.0), a(1.0, 0.0)], 0.038, rgb(130, 80, 45))
    for side in (1, -1):
        p.poly(a.pts([(0.72, 0.0), (0.66, side * 0.1), (0.58, side * 0.42), (0.78, side * 0.5),
                      (0.98, side * 0.42), (0.92, side * 0.1), (0.86, 0.0)]), rgb(240, 60, 150))
        p.detail(a.pts([(0.62, side * 0.38), (0.78, side * 0.46), (0.94, side * 0.38)]), 0.01, rgb(255, 190, 225))
    p.ell(*a(0.79, 0.0), 0.035, 0.035, rgb(90, 90, 110))
    for r, a0 in ((0.36, 3.6), (0.4, 0.4)):
        p.detail(circle_pts(0.5, 0.5, r, 16, a0, a0 + 1.3), 0.012)
    return p


def w_zombie_arm():
    p = weapon_pic()
    p.ell(0.5, 0.86, 0.3, 0.09, rgb(110, 80, 50))
    p.poly([(0.41, 0.86), (0.59, 0.86), (0.57, 0.5), (0.43, 0.5)], rgb(135, 175, 95))
    p.poly([(0.39, 0.86), (0.61, 0.86), (0.6, 0.72), (0.55, 0.75), (0.5, 0.7), (0.45, 0.75), (0.4, 0.72)],
           rgb(90, 70, 110))
    p.ell(0.5, 0.44, 0.1, 0.09, rgb(135, 175, 95))
    for k, (x, top) in enumerate(((0.43, 0.2), (0.48, 0.16), (0.53, 0.17), (0.58, 0.22))):
        p.line([(x, 0.42), (x + (k - 1.5) * 0.012, top)], 0.034, rgb(135, 175, 95))
    p.line([(0.41, 0.47), (0.33, 0.37)], 0.034, rgb(135, 175, 95))
    p.detail([(0.45, 0.6), (0.55, 0.6)], 0.006)
    for x in (0.47, 0.5, 0.53):
        p.detail([(x, 0.575), (x, 0.625)], 0.005)
    p.detail([(0.46, 0.36), (0.5, 0.39)], 0.007, rgb(80, 120, 60))
    return p


def w_fists():
    p = weapon_pic()
    p.poly([(0.32, 0.72), (0.68, 0.72), (0.66, 0.9), (0.34, 0.9)], WHITE)
    for y in (0.77, 0.82, 0.87):
        p.detail([(0.33, y), (0.67, y + 0.01)], 0.005, rgb(180, 175, 165))
    p.poly([(0.24, 0.36), (0.76, 0.36), (0.78, 0.66), (0.66, 0.75), (0.34, 0.75), (0.22, 0.66)], rgb(235, 190, 150))
    for k in range(4):
        x = 0.31 + k * 0.127
        p.ell(x, 0.37, 0.064, 0.06, rgb(240, 200, 160))
    for k in range(3):
        x = 0.37 + k * 0.127
        p.detail([(x, 0.4), (x, 0.52)], 0.006)
    p.poly([(0.24, 0.5), (0.52, 0.53), (0.56, 0.6), (0.3, 0.64), (0.22, 0.6)], rgb(225, 180, 140))
    for (x0, y0, x1, y1) in ((0.16, 0.24, 0.1, 0.17), (0.5, 0.18, 0.5, 0.09), (0.84, 0.24, 0.9, 0.17)):
        p.detail([(x0, y0), (x1, y1)], 0.014)
    return p


WEAPONS = {
    "espada_energia": w_energy_sword,
    "katana": w_katana,
    "railgun": w_railgun,
    "serpientes": w_serpents,
    "hacha_giratoria": w_spinning_axe,
    "brazo_zombi": w_zombie_arm,
    "punos": w_fists,
}


# ── bolsa de cuero (panel de tomos y objetos del HUD) ────────────────────

HUD_OUT = os.path.join(ROOT, "assets", "ui", "hud")
BAG_W, BAG_H = 320, 520
BAG_FLAP = 104         ## alto de la solapa (margen superior del 9-slice en BagPanel)
BAG_SIDE = 34          ## margen lateral / inferior del 9-slice


def _leather_grain(img, box, base, seed):
    """Grano de cuero: motas claras y oscuras y algún arañazo, dentro de `box` (en el lienzo supermuestreado)."""
    import random
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    area = (x1 - x0) * (y1 - y0)
    for _ in range(area // 900):
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        r = rnd.uniform(1.5, 5.0)
        k = rnd.uniform(-0.18, 0.14)
        c = tuple(max(0, min(255, int(v * (1.0 + k)))) for v in base[:3]) + (255,)
        d.ellipse([x - r, y - r, x + r, y + r], fill=c)
    for _ in range(14):
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        a = rnd.uniform(0, math.tau)
        ln = rnd.uniform(20, 70)
        c = tuple(int(v * 0.8) for v in base[:3]) + (255,)
        d.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=c, width=2)


def _stitches(d, pts, dash, gap, width, color):
    """Costura discontinua a lo largo de una polilínea cerrada."""
    segs = list(zip(pts, pts[1:] + pts[:1]))
    on = True
    left = dash
    for (ax, ay), (bx, by) in segs:
        ln = math.hypot(bx - ax, by - ay)
        t = 0.0
        while t < ln:
            step = min(left, ln - t)
            if on:
                p0 = (ax + (bx - ax) * t / ln, ay + (by - ay) * t / ln)
                p1 = (ax + (bx - ax) * (t + step) / ln, ay + (by - ay) * (t + step) / ln)
                d.line([p0, p1], fill=color, width=width)
            t += step
            left -= step
            if left <= 0:
                on = not on
                left = dash if on else gap


def _round_rect_pts(x0, y0, x1, y1, r, steps=6):
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -math.pi / 2), (x1 - r, y1 - r, 0.0),
                       (x0 + r, y1 - r, math.pi / 2), (x0 + r, y0 + r, math.pi)):
        for k in range(steps + 1):
            a = a0 + (math.pi / 2) * k / steps
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def leather_bag():
    """Fondo del panel "Bolsa": cuero marrón con grano, costura clara, borde de tinta, solapa más oscura con
    costura propia y un botón de latón. Hecho para estirarse en 9 partes (BAG_FLAP arriba, BAG_SIDE al resto)."""
    ss = 2
    w, h = BAG_W * ss, BAG_H * ss
    img = Image.new("RGBA", (w, h), INK[:3] + (0,))
    d = ImageDraw.Draw(img)
    body = rgb(122, 74, 42)
    o = 5 * ss
    d.rounded_rectangle([o, o, w - o, h - o], radius=22 * ss, fill=INK)
    d.rounded_rectangle([o + 4 * ss, o + 4 * ss, w - o - 4 * ss, h - o - 4 * ss], radius=18 * ss, fill=body)
    _leather_grain(img, (o + 8 * ss, o + 8 * ss, w - o - 8 * ss, h - o - 8 * ss), body, 7)
    # sombra interior en los bordes
    for k, a in ((10, 60), (16, 35)):
        d.rounded_rectangle([o + k * ss, o + k * ss, w - o - k * ss, h - o - k * ss], radius=14 * ss,
                            outline=(50, 28, 16, a), width=3 * ss)
    _stitches(d, _round_rect_pts(20 * ss, 20 * ss, w - 20 * ss, h - 20 * ss, 14 * ss), 9 * ss, 6 * ss, 2 * ss,
              rgb(225, 185, 125))
    # solapa
    flap = rgb(96, 56, 30)
    fh = BAG_FLAP * ss
    fpts = [(o + 2 * ss, o + 2 * ss), (w - o - 2 * ss, o + 2 * ss), (w - o - 2 * ss, fh - 26 * ss)]
    for k in range(17):
        t = k / 16
        fpts.append((w - o - 2 * ss - (w - 2 * o - 4 * ss) * t, fh - 26 * ss + math.sin(math.pi * t) * 24 * ss))
    d.polygon(fpts, fill=flap)
    d.line(fpts[2:] + [fpts[0]], fill=INK, width=4 * ss)
    _leather_grain(img, (o + 10 * ss, o + 10 * ss, w - o - 10 * ss, fh - 32 * ss), flap, 11)
    inner = [(x, y) for x, y in fpts[2:]]
    _stitches(d, [(o + 16 * ss, o + 16 * ss), (w - o - 16 * ss, o + 16 * ss)] +
              [(x - (8 * ss if x > w / 2 else -8 * ss), y - 12 * ss) for x, y in inner], 9 * ss, 6 * ss, 2 * ss,
              rgb(215, 170, 110))
    # botón de latón
    bx, by, br = w / 2, fh - 6 * ss, 15 * ss
    d.ellipse([bx - br - 3 * ss, by - br - 3 * ss, bx + br + 3 * ss, by + br + 3 * ss], fill=INK)
    d.ellipse([bx - br, by - br, bx + br, by + br], fill=rgb(205, 160, 60))
    d.ellipse([bx - br * 0.55, by - br * 0.55, bx + br * 0.55, by + br * 0.55], outline=rgb(140, 100, 30), width=2 * ss)
    d.ellipse([bx - br * 0.5, by - br * 0.75, bx - br * 0.1, by - br * 0.4], fill=rgb(250, 225, 140))
    return img.resize((BAG_W, BAG_H), Image.LANCZOS)


def bag_tab():
    """Saquito cerrado (botón de la bolsa plegada)."""
    p = Pic(96, outer=0.04, inner=0.016)
    p.poly([(0.3, 0.32), (0.7, 0.32), (0.86, 0.6), (0.82, 0.86), (0.18, 0.86), (0.14, 0.6)], rgb(122, 74, 42))
    p.poly([(0.36, 0.14), (0.64, 0.14), (0.6, 0.32), (0.4, 0.32)], rgb(96, 56, 30))
    p.rect(0.3, 0.29, 0.7, 0.36, rgb(205, 160, 60))
    p.detail([(0.22, 0.62), (0.32, 0.8)], 0.012, rgb(225, 185, 125))
    p.detail([(0.78, 0.62), (0.68, 0.8)], 0.012, rgb(225, 185, 125))
    p.detail([(0.5, 0.36), (0.42, 0.52), (0.5, 0.5)], 0.02, rgb(205, 160, 60))
    return p


def main():
    os.makedirs(TAGS_OUT, exist_ok=True)
    os.makedirs(HUD_OUT, exist_ok=True)
    leather_bag().save(os.path.join(HUD_OUT, "bolsa_cuero.png"))
    bag_tab().render().save(os.path.join(HUD_OUT, "bolsa_cerrada.png"))
    print("guardado", os.path.relpath(os.path.join(HUD_OUT, "bolsa_cuero.png"), ROOT))
    print("guardado", os.path.relpath(os.path.join(HUD_OUT, "bolsa_cerrada.png"), ROOT))
    os.makedirs(TOMES_OUT, exist_ok=True)
    made = []
    for name, fn in TAGS.items():
        path = os.path.join(TAGS_OUT, name + ".png")
        fn().render().save(path)
        made.append(path)
    for name, (cover, sym) in TOMES.items():
        path = os.path.join(TOMES_OUT, name + ".png")
        book(cover, sym).render().save(path)
        made.append(path)
    frame = Image.open(FRAME).convert("RGBA")
    for name, fn in WEAPONS.items():
        obj = fn().render()
        if obj.size != frame.size:
            obj = obj.resize(frame.size, Image.LANCZOS)
        out = Image.alpha_composite(frame, obj)
        path = os.path.join(WEAPONS_OUT, name + ".png")
        out.save(path)
        made.append(path)
    for path in made:
        print("guardado", os.path.relpath(path, ROOT))
    # Hoja de contacto opcional para revisar: python tools/make_ui_icons.py <ruta.png>
    if len(sys.argv) > 1:
        tiles = [Image.open(p_).convert("RGBA").resize((128, 128), Image.LANCZOS) for p_ in made]
        cols = 8
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * 136, rows * 136), (110, 104, 92, 255))
        for k, t in enumerate(tiles):
            sheet.alpha_composite(t, ((k % cols) * 136 + 4, (k // cols) * 136 + 4))
        sheet.save(sys.argv[1])
        print("hoja", sys.argv[1])


if __name__ == "__main__":
    main()
