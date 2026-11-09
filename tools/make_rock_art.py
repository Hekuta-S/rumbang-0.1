"""Pinturas rupestres (calcos con transparencia) para las paredes de las Cavernas.

Uso: python tools/make_rock_art.py <atlas.png> [salida_dir]
  atlas.png: textura del escaneo de la Gruta do Janelão (Image_0 del glb; tools/blender_cave_relief.py la guarda
             con su tercer argumento).
  -> assets/textures/rock_art/rock_art_{a,b,c}.png (512x512 RGBA)

Las figuras del escaneo son demasiado pequeñas y borrosas: ampliadas parecían salpicaduras de sangre. Así que
cada calco DIBUJA pictogramas estilizados al estilo de ese panel (cazadores de palo con lanza, ciervos,
manos en positivo y en negativo, espirales y filas de puntos) en ocre rojo, con el borde erosionado por ruido
para que parezca pintura gastada sobre la roca, y añade debajo, muy tenue, el pigmento real del escaneo
(aislado por "rojez") como manchas de fondo. DungeonMap los proyecta con Decal en unas pocas paredes.
"""
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = 1024                      # se dibuja a 1024 y se reduce a 512 (bordes suaves)
OUT = 512
OCHRE = np.array([0.62, 0.28, 0.12])      # ocre terroso (un rojo puro parecía sangre)
STAIN_PANELS = {"a": (90, 60, 260, 230), "b": (95, 185, 265, 335), "c": (110, 335, 270, 505)}


def line(d, a, b, w):
    d.line([a, b], fill=255, width=w)
    for p in (a, b):
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=255)


def human(d, x, y, s, spear=True, lean=0.0):
    """Cazador de palo: cabeza, tronco, brazos (uno con lanza) y piernas abiertas."""
    w = max(6, int(9 * s))
    hip = (x + lean * 20 * s, y)
    neck = (x, y - 70 * s)
    d.ellipse([neck[0] - 13 * s, neck[1] - 30 * s, neck[0] + 13 * s, neck[1] - 4 * s], fill=255)
    line(d, neck, hip, w)
    line(d, hip, (hip[0] - 28 * s, hip[1] + 62 * s), w)
    line(d, hip, (hip[0] + 30 * s, hip[1] + 60 * s), w)
    sh = (neck[0], neck[1] + 12 * s)
    line(d, sh, (sh[0] - 34 * s, sh[1] + 30 * s), w)
    hand = (sh[0] + 30 * s, sh[1] - 26 * s)
    line(d, sh, hand, w)
    if spear:
        line(d, (hand[0] - 30 * s, hand[1] + 70 * s), (hand[0] + 24 * s, hand[1] - 90 * s), max(4, w - 3))


def deer(d, x, y, s, facing=1):
    """Ciervo: cuerpo, cuello, cabeza, cuatro patas y cornamenta."""
    w = max(6, int(10 * s))
    f = facing
    d.ellipse([x - 70 * s, y - 24 * s, x + 70 * s, y + 24 * s], fill=255)
    for dx in (-50, -30, 35, 55):
        line(d, (x + dx * s * f, y + 10 * s), (x + (dx + 6) * s * f, y + 80 * s), w)
    neck = (x + 62 * s * f, y - 10 * s)
    head = (x + 95 * s * f, y - 62 * s)
    line(d, neck, head, w + 4)
    d.ellipse([head[0] - 16 * s, head[1] - 10 * s, head[0] + 16 * s, head[1] + 12 * s], fill=255)
    for k in (-1, 1):
        base = (head[0] + k * 6 * s, head[1] - 8 * s)
        tip = (base[0] + k * 22 * s - 8 * s * f, base[1] - 52 * s)
        line(d, base, tip, max(4, w - 4))
        line(d, ((base[0] + tip[0]) / 2, (base[1] + tip[1]) / 2), ((base[0] + tip[0]) / 2 + k * 20 * s, (base[1] + tip[1]) / 2 - 12 * s), max(4, w - 4))
    line(d, (x - 66 * s * f, y - 8 * s), (x - 84 * s * f, y - 22 * s), w)


def hand(d, x, y, s, rot=0.0):
    """Mano: palma y cinco dedos."""
    pts = []
    for k in range(24):
        a = 2 * math.pi * k / 24
        pts.append((x + math.cos(a) * 34 * s, y + math.sin(a) * 40 * s))
    d.polygon(pts, fill=255)
    fingers = [(-30, 52, -0.55), (-14, 70, -0.18), (2, 76, 0.0), (18, 70, 0.18), (40, 18, 1.05)]
    for fx, length, ang in fingers:
        a = ang + rot
        base = (x + fx * s, y - 22 * s if fx < 35 else y + 4 * s)
        tip = (base[0] + math.sin(a) * length * s, base[1] - math.cos(a) * length * s)
        line(d, base, tip, max(8, int(17 * s)))


def spiral(d, x, y, s):
    pts = []
    for k in range(200):
        t = k / 200 * 3.2 * 2 * math.pi
        r = 6 * s + t * 9 * s
        pts.append((x + math.cos(t) * r, y + math.sin(t) * r))
    d.line(pts, fill=255, width=max(5, int(9 * s)))


def dots(d, x, y, s, n=7):
    for k in range(n):
        cx = x + k * 30 * s
        d.ellipse([cx - 9 * s, y - 9 * s, cx + 9 * s, y + 9 * s], fill=255)


def panel(name):
    img = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(img)
    if name == "a":            # escena de caza
        human(d, 250, 470, 1.6, True, 0.3)
        human(d, 400, 500, 1.4, True, -0.2)
        human(d, 170, 640, 1.1, False)
        deer(d, 680, 450, 1.6, -1)
        deer(d, 760, 700, 1.1, -1)
        dots(d, 300, 860, 1.4, 8)
    elif name == "b":          # manos
        hand(d, 300, 380, 1.7, -0.2)
        hand(d, 560, 330, 1.5, 0.1)
        hand(d, 760, 470, 1.6, 0.35)
        hand(d, 430, 620, 1.3, -0.05)
        dots(d, 260, 840, 1.6, 9)
    else:                      # espiral, fila de figuras y un animal
        spiral(d, 290, 330, 1.35)
        for k in range(4):
            human(d, 640 + k * 90, 360, 0.95, k % 2 == 0)
        deer(d, 520, 760, 1.3, 1)
        dots(d, 180, 720, 1.3, 4)
    return np.asarray(img, dtype=np.float64) / 255.0


def erode(a, seed):
    """Pintura gastada: ruido de dos escalas quita trozos del trazo."""
    rng = np.random.default_rng(seed)
    n1 = np.asarray(Image.fromarray((rng.random((64, 64)) * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC), dtype=np.float64) / 255
    n2 = np.asarray(Image.fromarray((rng.random((256, 256)) * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC), dtype=np.float64) / 255
    wear = 0.6 * n1 + 0.4 * n2
    return a * np.clip((wear - 0.28) / 0.2, 0, 1)


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "assets", "textures", "rock_art")
    os.makedirs(out, exist_ok=True)
    atlas = np.asarray(Image.open(src).convert("RGB"), dtype=np.float64) / 255.0
    red = atlas[..., 0] - (atlas[..., 1] + atlas[..., 2]) / 2.0
    yy, xx = np.mgrid[0:W, 0:W] / (W - 1)
    edge = np.clip(np.minimum.reduce([xx, yy, 1 - xx, 1 - yy]) / 0.06, 0, 1)
    for i, name in enumerate(sorted(STAIN_PANELS)):
        x0, y0, x1, y1 = STAIN_PANELS[name]
        stain = np.clip((red[y0:y1, x0:x1] - 0.07) / 0.1, 0, 1)
        stain = np.asarray(Image.fromarray((stain * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC)
                           .filter(ImageFilter.GaussianBlur(6)), dtype=np.float64) / 255.0
        fig = np.asarray(Image.fromarray((panel(name) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5)), dtype=np.float64) / 255.0
        a = np.maximum(erode(fig, 11 + i) * 0.78, stain * 0.22) * edge
        tone = 0.85 + 0.3 * np.asarray(Image.fromarray((np.random.default_rng(i).random((32, 32)) * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC), dtype=np.float64)[..., None] / 255
        rgb = np.clip(OCHRE * tone, 0, 1)
        img = Image.fromarray((np.dstack([rgb, a]) * 255).astype(np.uint8), "RGBA").resize((OUT, OUT), Image.LANCZOS)
        img.save(os.path.join(out, "rock_art_%s.png" % name))
        print(name, "cobertura %.3f" % a.mean())


if __name__ == "__main__":
    main()
