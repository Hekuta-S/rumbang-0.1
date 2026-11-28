"""Texturas de suelo estilo cartoon con la TINTA HORNEADA (líneas dibujadas en la propia textura, sin
shader de contorno). Todas son repetibles (tileables) y se dibujan al doble de tamaño para suavizar.

    python tools/make_toon_textures.py [salida]      (por defecto assets/textures/toon)

Salida (512 px, RGBA):
    toon_grass.png      hierba con matas entintadas        A = relieve (rompe las transiciones)
    toon_dirt.png       tierra con guijarros y grietas     A = relieve
    toon_rock.png       roca tallada en facetas (acantilados, proyección lateral)
    toon_flagstone.png  losas de la cripta                 A = venas arcanas (emisión)
    toon_sewer_{cobble,mud,brick,tile}.png  las mismas ranuras para el mapa de Cloacas (make_sewer_*;
                        python tools/make_toon_textures.py assets/textures/toon sewer_cobble,sewer_mud,sewer_brick,sewer_tile)
    (y "cave": assets/textures/dungeon/cave_toon_{albedo,normal}.png, roca de las Cavernas; ver make_cave)
Las usa assets/shaders/toon_ground.gdshader (ProceduralMap).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024          # tamaño de trabajo (se reduce a OUT_SIZE)
OUT_SIZE = 512
INK = (16, 13, 20)


# ───────────────────────────── utilidades repetibles ─────────────────────────────

def _grid(n=S):
    v = (np.arange(n, dtype=np.float32) + 0.5) / n
    return np.meshgrid(v, v)                      # x, y en [0, 1)


def vnoise(cells, rng, x=None, y=None):
    """Ruido de valor periódico (cells celdas por lado)."""
    if x is None:
        x, y = _grid()
    g = rng.random((cells, cells), dtype=np.float32)
    fx = (x * cells) % cells
    fy = (y * cells) % cells
    ix = np.floor(fx).astype(np.int32)
    iy = np.floor(fy).astype(np.int32)
    tx = fx - ix
    ty = fy - iy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    ix1 = (ix + 1) % cells
    iy1 = (iy + 1) % cells
    a = g[iy, ix] * (1 - tx) + g[iy, ix1] * tx
    b = g[iy1, ix] * (1 - tx) + g[iy1, ix1] * tx
    return a * (1 - ty) + b * ty


def fbm(cells, octaves, rng, x=None, y=None):
    out = 0.0
    amp = 0.5
    tot = 0.0
    for o in range(octaves):
        out = out + amp * vnoise(cells * (2 ** o), rng, x, y)
        tot += amp
        amp *= 0.5
    return out / tot


def warped(rng, amp, cells=4):
    """Coordenadas deformadas (pulso de dibujo a mano), siguen siendo periódicas."""
    x, y = _grid()
    return (x + (fbm(cells, 2, rng) - 0.5) * amp) % 1.0, (y + (fbm(cells, 2, rng) - 0.5) * amp) % 1.0


def voronoi(pts, x, y, stretch=(1.0, 1.0)):
    """F1, F2 e índice de la celda más cercana, con envoltura. pts en [0,1)."""
    n = x.shape[0]
    offs = np.array([(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1)], dtype=np.float32)
    allp = (pts[None, :, :] + offs[:, None, :]).reshape(-1, 2).astype(np.float32)
    ids = np.tile(np.arange(len(pts)), 9)
    f1 = np.empty((n, n), np.float32)
    f2 = np.empty((n, n), np.float32)
    idx = np.empty((n, n), np.int32)
    step = 32
    for r in range(0, n, step):
        px = x[r:r + step].reshape(-1, 1)
        py = y[r:r + step].reshape(-1, 1)
        d = ((px - allp[None, :, 0].reshape(1, -1)) * stretch[0]) ** 2 + ((py - allp[None, :, 1].reshape(1, -1)) * stretch[1]) ** 2
        part = np.argpartition(d, 1, axis=1)[:, :2]
        rows = np.arange(d.shape[0])
        d0 = d[rows, part[:, 0]]
        d1 = d[rows, part[:, 1]]
        swap = d1 < d0
        first = np.where(swap, part[:, 1], part[:, 0])
        lo = np.minimum(d0, d1)
        hi = np.maximum(d0, d1)
        f1[r:r + step] = np.sqrt(lo).reshape(-1, n)
        f2[r:r + step] = np.sqrt(hi).reshape(-1, n)
        idx[r:r + step] = ids[first].reshape(-1, n)
    return f1, f2, idx


def jittered(n_side, rng, jitter=0.8):
    pts = []
    for j in range(n_side):
        for i in range(n_side):
            pts.append(((i + 0.5 + (rng.random() - 0.5) * jitter) / n_side, (j + 0.5 + (rng.random() - 0.5) * jitter) / n_side))
    return np.array(pts, dtype=np.float32) % 1.0


def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def posterize(n, levels):
    """Bandas planas con bordes limpios: índice de tono 0..levels-1."""
    q = np.quantile(n, [(i + 1) / levels for i in range(levels - 1)])
    return np.digitize(n, q)


def tones(idx, palette):
    pal = np.array(palette, dtype=np.float32) / 255.0
    return pal[idx]


class Layer:
    """Capa RGBA de PIL donde cada trazo se repite en las 9 copias vecinas (envoltura)."""

    def __init__(self):
        self.img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def _each(self, pts, pad):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for ox in (-S, 0, S):
            if max(xs) + ox < -pad or min(xs) + ox > S + pad:
                continue
            for oy in (-S, 0, S):
                if max(ys) + oy < -pad or min(ys) + oy > S + pad:
                    continue
                yield [(p[0] + ox, p[1] + oy) for p in pts]

    def poly(self, pts, fill):
        for q in self._each(pts, 4):
            self.d.polygon(q, fill=fill)

    def stroke(self, pts, width, fill=INK + (255,), taper=True):
        """Trazo de tinta: grueso en el centro y fino en las puntas (pincel)."""
        n = len(pts)
        for q in self._each(pts, width + 2):
            for i in range(n - 1):
                t = (i + 0.5) / (n - 1)
                w = width * (0.35 + 0.65 * math.sin(math.pi * t)) if taper else width
                w = max(1.0, w)
                self.d.line([q[i], q[i + 1]], fill=fill, width=int(round(w)))
                r = w / 2.0
                self.d.ellipse([q[i][0] - r, q[i][1] - r, q[i][0] + r, q[i][1] + r], fill=fill)

    def ellipse(self, c, rx, ry, fill=None, outline=None, width=1):
        box = [(c[0] - rx, c[1] - ry), (c[0] + rx, c[1] + ry)]
        for q in self._each(box, width + 2):
            self.d.ellipse([q[0][0], q[0][1], q[1][0], q[1][1]], fill=fill, outline=outline, width=width)

    def over(self, rgb):
        """Compone la capa sobre una imagen float (H, W, 3) en 0..1."""
        a = np.asarray(self.img, dtype=np.float32) / 255.0
        return rgb * (1 - a[..., 3:4]) + a[..., :3] * a[..., 3:4]


def curve(p0, p1, bend, n=10):
    """Curva cuadrática de p0 a p1 con comba lateral."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    mx, my = (p0[0] + p1[0]) / 2 - dy * bend, (p0[1] + p1[1]) / 2 + dx * bend
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(((1 - t) ** 2 * p0[0] + 2 * t * (1 - t) * mx + t * t * p1[0],
                    (1 - t) ** 2 * p0[1] + 2 * t * (1 - t) * my + t * t * p1[1]))
    return out


def leaf(center_line, width):
    """Polígono de hoja: ancho en la base, punta afilada."""
    left, right = [], []
    n = len(center_line)
    for i, (x, y) in enumerate(center_line):
        a = center_line[min(i + 1, n - 1)]
        b = center_line[max(i - 1, 0)]
        tx, ty = a[0] - b[0], a[1] - b[1]
        ln = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / ln, tx / ln
        t = i / (n - 1)
        w = width * (1.0 - t) ** 0.7 * (0.55 + 0.45 * math.sin(math.pi * min(t * 1.6, 1.0)))
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]


def save(name, rgb, alpha, out_dir, out_size=None):
    if out_size is not None:
        global OUT_SIZE
        prev, OUT_SIZE = OUT_SIZE, out_size
        try:
            return save(name, rgb, alpha, out_dir)
        finally:
            OUT_SIZE = prev
    # color y alfa se reducen por separado: PIL premultiplica el RGBA al reescalar y el alfa aquí es un dato
    col = Image.fromarray((np.clip(rgb, 0, 1) * 255.0 + 0.5).astype(np.uint8), "RGB").resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
    alp = Image.fromarray((np.clip(alpha, 0, 1) * 255.0 + 0.5).astype(np.uint8), "L").resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
    img = col.convert("RGBA")
    img.putalpha(alp)
    path = os.path.join(out_dir, name + ".png")
    img.save(path)
    print("guardado", path)


def ink_mask(rgb, mask, strength=1.0):
    ink = np.array(INK, dtype=np.float32) / 255.0
    m = np.clip(mask * strength, 0, 1)[..., None]
    return rgb * (1 - m) + ink * m


# ───────────────────────────── texturas ─────────────────────────────

def make_grass(out_dir):
    rng = np.random.default_rng(11)
    wx, wy = warped(rng, 0.06)
    base = fbm(3, 3, rng, wx, wy)
    rgb = tones(posterize(base, 3), [(52, 78, 40), (66, 96, 46), (84, 114, 52)])
    # manchas secas (paja) en pocas zonas
    dry = fbm(5, 2, rng, wx, wy)
    rgb = np.where((dry > np.quantile(dry, 0.9))[..., None], np.array([118, 116, 60], np.float32) / 255.0, rgb)
    lay = Layer()
    pr = np.random.default_rng(5)
    # motas oscuras
    for _ in range(260):
        c = (pr.random() * S, pr.random() * S)
        r = pr.uniform(3, 7)
        lay.ellipse(c, r, r * pr.uniform(0.5, 1.0), fill=(38, 60, 32, 255))
    # matas: abanico de hojas con relleno claro y contorno de tinta
    for p in jittered(9, pr, 0.9):
        cx, cy = p[0] * S, p[1] * S
        blades = int(pr.integers(3, 6))
        spread = pr.uniform(0.9, 1.5)
        lean = pr.uniform(-0.35, 0.35)
        scale = pr.uniform(0.75, 1.3)
        fill = [(108, 140, 58, 255), (126, 156, 62, 255), (92, 128, 54, 255)][int(pr.integers(0, 3))]
        order = list(range(blades))
        for k in order:
            a = -math.pi / 2 + lean + ((k + 0.5) / blades - 0.5) * spread
            ln = pr.uniform(62, 104) * scale * (1.0 - 0.35 * abs((k + 0.5) / blades - 0.5) * 2)
            p0 = (cx + (k - blades / 2) * 5 * scale, cy)
            p1 = (p0[0] + math.cos(a) * ln, p0[1] + math.sin(a) * ln)
            cl = curve(p0, p1, pr.uniform(-0.28, 0.28), 9)
            shape = leaf(cl, pr.uniform(8, 12) * scale)
            lay.poly(shape, fill)
            lay.stroke(shape + [shape[0]], 4.0, taper=False)
            lay.stroke(cl[1:7], 2.5, fill=(52, 84, 40, 255))
        # tinta de sombra al pie de la mata
        lay.stroke([(cx - 16 * scale, cy + 5), (cx, cy + 9), (cx + 18 * scale, cy + 4)], 7.0)
    # ticks sueltos de tinta ("v" pequeñas)
    for _ in range(90):
        c = (pr.random() * S, pr.random() * S)
        h = pr.uniform(14, 24)
        lay.stroke([(c[0] - h * 0.45, c[1] - h), (c[0], c[1]), (c[0] + h * 0.5, c[1] - h * 0.9)], 4.0)
    rgb = lay.over(rgb)
    a = np.asarray(lay.img, np.float32)[..., 3] / 255.0
    height = np.clip(base * 0.7 + a * 0.5, 0, 1)
    save("toon_grass", rgb, height, out_dir)


def make_dirt(out_dir):
    rng = np.random.default_rng(23)
    wx, wy = warped(rng, 0.07)
    base = fbm(3, 3, rng, wx, wy)
    rgb = tones(posterize(base, 3), [(82, 58, 43), (93, 67, 49), (104, 77, 55)])
    lay = Layer()
    pr = np.random.default_rng(9)
    # grietas
    for _ in range(11):
        p = np.array([pr.random() * S, pr.random() * S])
        ang = pr.uniform(0, math.tau)
        pts = [tuple(p)]
        for _ in range(int(pr.integers(5, 9))):
            ang += pr.uniform(-0.7, 0.7)
            p = p + np.array([math.cos(ang), math.sin(ang)]) * pr.uniform(26, 48)
            pts.append(tuple(p))
        lay.stroke(pts, 6.5)
        if pr.random() < 0.6:                       # ramal
            k = int(pr.integers(1, len(pts) - 1))
            a2 = ang + pr.choice([-1.2, 1.2])
            q = np.array(pts[k])
            lay.stroke([tuple(q), tuple(q + np.array([math.cos(a2), math.sin(a2)]) * 40),
                        tuple(q + np.array([math.cos(a2 + 0.4), math.sin(a2 + 0.4)]) * 78)], 4.5)
    # guijarros con contorno, luz arriba y sombra abajo
    for p in jittered(7, pr, 0.95):
        if pr.random() < 0.5:
            continue
        c = (p[0] * S, p[1] * S)
        rx = pr.uniform(13, 34)
        ry = rx * pr.uniform(0.6, 0.9)
        col = [(128, 116, 104, 255), (146, 132, 114, 255), (110, 100, 96, 255)][int(pr.integers(0, 3))]
        lay.ellipse((c[0] + 3, c[1] + 6), rx, ry, fill=INK + (255,))            # sombra de contacto
        lay.ellipse(c, rx, ry, fill=col, outline=INK + (255,), width=5)
        lay.stroke(curve((c[0] - rx * 0.55, c[1] - ry * 0.25), (c[0] + rx * 0.35, c[1] - ry * 0.55), -0.25, 5), 3.5,
                   fill=(206, 194, 170, 255))
    # punteado de tinta
    for _ in range(240):
        c = (pr.random() * S, pr.random() * S)
        r = pr.uniform(2.0, 4.5)
        lay.ellipse(c, r, r, fill=(48, 32, 28, 255))
    rgb = lay.over(rgb)
    a = np.asarray(lay.img, np.float32)[..., 3] / 255.0
    save("toon_dirt", rgb, np.clip(base * 0.8 + a * 0.3, 0, 1), out_dir)


def make_rock(out_dir):
    rng = np.random.default_rng(31)
    wx, wy = warped(rng, 0.035, 5)
    pr = np.random.default_rng(3)
    pts = jittered(5, pr, 0.95)
    # estratos: celdas anchas y bajas
    f1, f2, idx = voronoi(pts, wx, wy, (1.0, 1.7))
    tone_of = pr.integers(0, 4, len(pts))
    pal = [(74, 74, 88), (92, 92, 106), (110, 110, 124), (128, 126, 138)]
    rgb = tones(tone_of[idx], pal)
    edge = f2 - f1
    # cara inferior de cada faceta en sombra y filo superior con luz (leído desplazando el índice)
    up = np.roll(idx, 14, axis=0)
    dn = np.roll(idx, -14, axis=0)
    rgb = np.where((up != idx)[..., None], np.clip(rgb * 1.22 + 0.02, 0, 1), rgb)
    rgb = np.where((dn != idx)[..., None], rgb * 0.72, rgb)
    # rayado de sombra en algunas facetas
    hatch_cells = pr.random(len(pts)) < 0.4
    x, y = _grid()
    stripes = (np.sin((x * 1.0 + y * 0.9) * math.tau * 34) > 0.72) & hatch_cells[idx] & (np.roll(idx, -70, axis=0) != idx)
    rgb = ink_mask(rgb, stripes.astype(np.float32) * smooth(edge, 0.012, 0.03), 0.85)
    # tinta entre facetas, más gruesa con ruido (pincel)
    wn = 0.007 + 0.006 * vnoise(9, rng)
    rgb = ink_mask(rgb, 1.0 - smooth(edge, wn * 0.75, wn * 1.15))
    lay = Layer()
    # grietas finas dentro de las facetas
    for _ in range(26):
        p = np.array([pr.random() * S, pr.random() * S])
        ang = pr.uniform(-0.5, 0.5) + (math.pi if pr.random() < 0.5 else 0)
        pts2 = [tuple(p)]
        for _ in range(4):
            ang += pr.uniform(-0.5, 0.5)
            p = p + np.array([math.cos(ang), math.sin(ang)]) * pr.uniform(18, 36)
            pts2.append(tuple(p))
        lay.stroke(pts2, 4.0)
    rgb = lay.over(rgb)
    save("toon_rock", rgb, np.ones((S, S), np.float32), out_dir)


def make_flagstone(out_dir):
    rng = np.random.default_rng(47)
    wx, wy = warped(rng, 0.018, 6)
    pr = np.random.default_rng(13)
    pts = jittered(3, pr, 0.35)
    # distancia de Chebyshev → losas casi cuadradas
    n = S
    offs = [(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1)]
    f1 = np.full((n, n), 9.0, np.float32)
    f2 = np.full((n, n), 9.0, np.float32)
    idx = np.zeros((n, n), np.int32)
    for k, p in enumerate(pts):
        for o in offs:
            d = np.maximum(np.abs(wx - p[0] - o[0]), np.abs(wy - p[1] - o[1]))
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            idx = np.where(closer, k, idx)
            f1 = np.where(closer, d, f1)
    tone_of = pr.integers(0, 3, len(pts))
    rgb = tones(tone_of[idx], [(78, 78, 96), (96, 96, 114), (112, 112, 128)])
    edge = f2 - f1
    up = np.roll(idx, 16, axis=0)
    dn = np.roll(idx, -16, axis=0)
    rgb = np.where((up != idx)[..., None], np.clip(rgb * 1.2 + 0.02, 0, 1), rgb)
    rgb = np.where((dn != idx)[..., None], rgb * 0.74, rgb)
    wn = 0.012 + 0.006 * vnoise(8, rng)
    rgb = ink_mask(rgb, 1.0 - smooth(edge, wn * 0.75, wn * 1.15))
    lay = Layer()
    for _ in range(9):                                   # grietas
        p = np.array([pr.random() * S, pr.random() * S])
        ang = pr.uniform(0, math.tau)
        pts2 = [tuple(p)]
        for _ in range(int(pr.integers(4, 7))):
            ang += pr.uniform(-0.6, 0.6)
            p = p + np.array([math.cos(ang), math.sin(ang)]) * pr.uniform(24, 44)
            pts2.append(tuple(p))
        lay.stroke(pts2, 5.0)
    for _ in range(120):                                 # picado
        c = (pr.random() * S, pr.random() * S)
        r = pr.uniform(2.0, 4.0)
        lay.ellipse(c, r, r, fill=(52, 52, 68, 255))
    rgb = lay.over(rgb)
    # venas arcanas: crestas finas de un ruido periódico
    v = fbm(4, 3, rng)
    vein = (1.0 - np.abs(v * 2.0 - 1.0) * 2.2).clip(0, 1) ** 10
    veins = Image.fromarray((vein * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.2))
    save("toon_flagstone", rgb, np.asarray(veins, np.float32) / 255.0, out_dir)


def make_cave(out_dir):
    """Paredes y techo de las Cavernas (shader cave_rock, triplanar): roca tallada en facetas con tinta, en
    GRIS (la paleta del nivel la tiñe) y con el mismo brillo medio que la textura del escaneo a la que
    sustituye. Sale también su normal map: cada faceta inclinada a un lado, para que la luz de las antorchas
    las separe. Va a assets/textures/dungeon/cave_toon_{albedo,normal}.png (1024 px)."""
    rng = np.random.default_rng(71)
    wx, wy = warped(rng, 0.03, 5)
    pr = np.random.default_rng(17)
    pts = jittered(7, pr, 0.95)
    f1, f2, idx = voronoi(pts, wx, wy, (1.0, 1.45))
    tone_of = pr.integers(0, 4, len(pts))
    rgb = tones(tone_of[idx], [(98, 96, 100), (116, 114, 116), (134, 132, 132), (150, 148, 146)])
    edge = f2 - f1
    up = np.roll(idx, 12, axis=0)
    dn = np.roll(idx, -12, axis=0)
    rgb = np.where((up != idx)[..., None], np.clip(rgb * 1.2 + 0.02, 0, 1), rgb)
    rgb = np.where((dn != idx)[..., None], rgb * 0.7, rgb)
    hatch_cells = pr.random(len(pts)) < 0.35
    x, y = _grid()
    stripes = (np.sin((x + y * 0.9) * math.tau * 40) > 0.74) & hatch_cells[idx] & (np.roll(idx, -60, axis=0) != idx)
    rgb = ink_mask(rgb, stripes.astype(np.float32) * smooth(edge, 0.01, 0.025), 0.8)
    wn = 0.006 + 0.005 * vnoise(9, rng)
    groove = 1.0 - smooth(edge, wn * 0.75, wn * 1.15)
    rgb = ink_mask(rgb, groove)
    lay = Layer()
    for _ in range(34):                                  # grietas finas
        p = np.array([pr.random() * S, pr.random() * S])
        ang = pr.uniform(0, math.tau)
        pts2 = [tuple(p)]
        for _ in range(4):
            ang += pr.uniform(-0.5, 0.5)
            p = p + np.array([math.cos(ang), math.sin(ang)]) * pr.uniform(16, 30)
            pts2.append(tuple(p))
        lay.stroke(pts2, 3.5)
    for _ in range(160):                                 # picado
        c = (pr.random() * S, pr.random() * S)
        r = pr.uniform(1.5, 3.2)
        lay.ellipse(c, r, r, fill=(60, 58, 64, 255))
    rgb = lay.over(rgb)
    # mismo brillo medio (lineal) que el escaneo original: el shader compensa con tint_gain
    def lin(a):
        return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    ref = None
    for cand in (os.path.join(out_dir, "orig", "cave_scan_albedo.png"), os.path.join(out_dir, "cave_scan_albedo.png")):
        if os.path.exists(cand):
            ref = lin(np.asarray(Image.open(cand).convert("RGB"), np.float32) / 255.0).mean()
            break
    if ref is not None:
        g = ref / max(lin(np.clip(rgb, 0, 1)).mean(), 1e-5)
        l2 = lin(np.clip(rgb, 0, 1)) * g
        rgb = np.where(l2 <= 0.0031308, l2 * 12.92, 1.055 * np.clip(l2, 0, None) ** (1 / 2.4) - 0.055)
    save("cave_toon_albedo", rgb, np.ones((S, S), np.float32), out_dir, 1024)
    Image.open(os.path.join(out_dir, "cave_toon_albedo.png")).convert("RGB").save(os.path.join(out_dir, "cave_toon_albedo.png"))
    # normal map: cada faceta inclinada; la junta hundida no cambia la normal (la marca la tinta)
    tilt = (pr.random((len(pts), 2)).astype(np.float32) - 0.5) * 0.7
    nx, ny = tilt[idx, 0], tilt[idx, 1]
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / ln, ny / ln, nz / ln], axis=2) * 0.5 + 0.5
    Image.fromarray((nrm * 255.0 + 0.5).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(1.2)).save(
        os.path.join(out_dir, "cave_toon_normal.png"))
    print("guardado", os.path.join(out_dir, "cave_toon_normal.png"))


# ───────────────────────────── Cloacas (mapa de supervivencia "sewers") ─────────────────────────────
# Mismas ranuras que el bosque (ProceduralMap.GROUND_TEX_SEWERS): cobble = hierba, mud = tierra,
# brick = roca (paredes de los canales y acantilados), tile = losas (cuenca, con venas verdes en A).

def make_sewer_cobble(out_dir):
    """Adoquín mojado con verdín en las juntas. A = relieve."""
    rng = np.random.default_rng(61)
    wx, wy = warped(rng, 0.04, 6)
    pr = np.random.default_rng(17)
    pts = jittered(9, pr, 0.55)
    f1, f2, idx = voronoi(pts, wx, wy)
    tone_of = pr.integers(0, 4, len(pts))
    rgb = tones(tone_of[idx], [(70, 72, 66), (82, 84, 74), (94, 94, 82), (76, 70, 62)])
    edge = f2 - f1
    up = np.roll(idx, 10, axis=0)
    dn = np.roll(idx, -10, axis=0)
    rgb = np.where((up != idx)[..., None], np.clip(rgb * 1.2 + 0.02, 0, 1), rgb)
    rgb = np.where((dn != idx)[..., None], rgb * 0.75, rgb)
    # juntas: verdín (verde oscuro) y tinta en el borde de cada piedra
    moss = np.array([46, 66, 34], np.float32) / 255.0
    gap = 1.0 - smooth(edge, 0.018, 0.034)
    rgb = rgb * (1 - gap[..., None]) + moss * gap[..., None]
    wn = 0.008 + 0.004 * vnoise(8, rng)
    rgb = ink_mask(rgb, smooth(edge, wn * 0.4, wn * 0.7) * (1.0 - smooth(edge, wn * 1.1, wn * 1.6)))
    lay = Layer()
    for _ in range(160):                                 # manchas de humedad
        c = (pr.random() * S, pr.random() * S)
        r = pr.uniform(2.0, 4.5)
        lay.ellipse(c, r, r, fill=(40, 44, 36, 255))
    rgb = lay.over(rgb)
    save("toon_sewer_cobble", rgb, np.clip(smooth(edge, 0.01, 0.08) * 0.8 + fbm(4, 2, rng) * 0.3, 0, 1), out_dir)


def make_sewer_mud(out_dir):
    """Lodo de cloaca con charcos verdosos y restos. A = relieve."""
    rng = np.random.default_rng(71)
    wx, wy = warped(rng, 0.08)
    base = fbm(3, 3, rng, wx, wy)
    rgb = tones(posterize(base, 3), [(58, 52, 38), (68, 61, 44), (78, 70, 50)])
    lay = Layer()
    pr = np.random.default_rng(29)
    # charcos de agua sucia con brillo
    for p in jittered(5, pr, 0.9):
        if pr.random() < 0.45:
            continue
        c = (p[0] * S, p[1] * S)
        rx = pr.uniform(30, 70)
        ry = rx * pr.uniform(0.45, 0.8)
        lay.ellipse(c, rx, ry, fill=(52, 70, 46, 255), outline=INK + (255,), width=5)
        lay.stroke(curve((c[0] - rx * 0.5, c[1] - ry * 0.3), (c[0] + rx * 0.2, c[1] - ry * 0.5), -0.2, 5), 4.0,
                   fill=(130, 160, 104, 255))
    # restos: trozos de ladrillo y latas
    for _ in range(26):
        c = np.array([pr.random() * S, pr.random() * S])
        a = pr.uniform(0, math.tau)
        w, h = pr.uniform(10, 22), pr.uniform(6, 12)
        dx = np.array([math.cos(a), math.sin(a)])
        dy = np.array([-dx[1], dx[0]])
        quad = [tuple(c + dx * w + dy * h), tuple(c - dx * w + dy * h), tuple(c - dx * w - dy * h), tuple(c + dx * w - dy * h)]
        col = [(120, 66, 48, 255), (96, 98, 92, 255), (110, 96, 60, 255)][int(pr.integers(0, 3))]
        lay.poly([(q[0] + 3, q[1] + 5) for q in quad], INK + (255,))
        lay.poly(quad, col)
        lay.stroke(quad + [quad[0]], 3.5, taper=False)
    for _ in range(11):                                  # grietas
        p = np.array([pr.random() * S, pr.random() * S])
        ang = pr.uniform(0, math.tau)
        pts = [tuple(p)]
        for _ in range(int(pr.integers(4, 8))):
            ang += pr.uniform(-0.7, 0.7)
            p = p + np.array([math.cos(ang), math.sin(ang)]) * pr.uniform(24, 44)
            pts.append(tuple(p))
        lay.stroke(pts, 5.5)
    rgb = lay.over(rgb)
    a = np.asarray(lay.img, np.float32)[..., 3] / 255.0
    save("toon_sewer_mud", rgb, np.clip(base * 0.8 + a * 0.3, 0, 1), out_dir)


def make_sewer_brick(out_dir):
    """Ladrillo de cloaca en hiladas (paredes de los canales y acantilados)."""
    rng = np.random.default_rng(83)
    pr = np.random.default_rng(41)
    rows, cols = 8, 4
    x, y = _grid()
    wx, wy = warped(rng, 0.01, 6)
    ry = wy * rows
    row = np.floor(ry).astype(np.int32) % rows
    rx = (wx * cols + (row % 2) * 0.5) % cols
    col = np.floor(rx).astype(np.int32) % cols
    brick = row * cols + col
    tone_of = pr.integers(0, 4, rows * cols)
    rgb = tones(tone_of[brick], [(112, 58, 44), (128, 68, 50), (98, 54, 44), (120, 74, 56)])
    fy = ry - np.floor(ry)
    fx = rx - np.floor(rx)
    # luz arriba, sombra abajo de cada ladrillo
    rgb = np.where((fy < 0.16)[..., None], np.clip(rgb * 1.2 + 0.02, 0, 1), rgb)
    rgb = np.where((fy > 0.8)[..., None], rgb * 0.72, rgb)
    # verdín que sube desde abajo de la textura en manchas
    slime = smooth(fbm(4, 3, rng), 0.55, 0.7)
    rgb = rgb * (1 - slime[..., None] * 0.6) + np.array([52, 80, 38], np.float32) / 255.0 * slime[..., None] * 0.6
    mortar = np.minimum(np.minimum(fy, 1 - fy) * 2.0, np.minimum(fx, 1 - fx) * 2.0 * cols / rows * 2.0)
    rgb = ink_mask(rgb, 1.0 - smooth(mortar, 0.05, 0.11))
    lay = Layer()
    for _ in range(18):                                  # desconchones
        p = np.array([pr.random() * S, pr.random() * S])
        ang = pr.uniform(0, math.tau)
        pts = [tuple(p)]
        for _ in range(3):
            ang += pr.uniform(-0.6, 0.6)
            p = p + np.array([math.cos(ang), math.sin(ang)]) * pr.uniform(12, 26)
            pts.append(tuple(p))
        lay.stroke(pts, 3.5)
    rgb = lay.over(rgb)
    save("toon_sewer_brick", rgb, np.ones((S, S), np.float32), out_dir)


def make_sewer_tile(out_dir):
    """Losas del depósito con limo. A = venas verdes (emisión, como las venas arcanas de la cripta)."""
    rng = np.random.default_rng(97)
    pr = np.random.default_rng(53)
    n_side = 4
    x, y = _grid()
    wx, wy = warped(rng, 0.008, 6)
    gx = wx * n_side
    gy = wy * n_side
    tile = (np.floor(gy).astype(np.int32) % n_side) * n_side + (np.floor(gx).astype(np.int32) % n_side)
    tone_of = pr.integers(0, 3, n_side * n_side)
    rgb = tones(tone_of[tile], [(74, 82, 72), (86, 94, 80), (66, 76, 68)])
    fx = gx - np.floor(gx)
    fy = gy - np.floor(gy)
    rgb = np.where((fy < 0.08)[..., None], np.clip(rgb * 1.18, 0, 1), rgb)
    rgb = np.where((fy > 0.9)[..., None], rgb * 0.75, rgb)
    slime = smooth(fbm(3, 3, rng), 0.5, 0.62)
    rgb = rgb * (1 - slime[..., None] * 0.5) + np.array([58, 92, 40], np.float32) / 255.0 * slime[..., None] * 0.5
    edge = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy))
    rgb = ink_mask(rgb, 1.0 - smooth(edge, 0.03, 0.06))
    lay = Layer()
    for _ in range(8):
        p = np.array([pr.random() * S, pr.random() * S])
        ang = pr.uniform(0, math.tau)
        pts = [tuple(p)]
        for _ in range(int(pr.integers(4, 7))):
            ang += pr.uniform(-0.6, 0.6)
            p = p + np.array([math.cos(ang), math.sin(ang)]) * pr.uniform(22, 40)
            pts.append(tuple(p))
        lay.stroke(pts, 4.5)
    rgb = lay.over(rgb)
    v = fbm(4, 3, rng)
    vein = (1.0 - np.abs(v * 2.0 - 1.0) * 2.2).clip(0, 1) ** 10
    veins = Image.fromarray((vein * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.2))
    save("toon_sewer_tile", rgb, np.asarray(veins, np.float32) / 255.0, out_dir)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "assets", "textures", "toon")
    os.makedirs(out, exist_ok=True)
    which = sys.argv[2].split(",") if len(sys.argv) > 2 else ["grass", "dirt", "rock", "flagstone", "cave"]
    for w in which:
        # la roca de las Cavernas va con las demás texturas de mazmorra
        globals()["make_" + w](os.path.join(root, "assets", "textures", "dungeon") if w == "cave" else out)
