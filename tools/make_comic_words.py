"""Onomatopeyas de cómic para los golpes: sprites con la tinta dibujada (sin shaders).

    python tools/make_comic_words.py [grupo]

Cada palabra es un PNG RGBA de 512×320 en assets/textures/toon/words/<grupo>_<n>.png: estallido de picos con
trama de puntos detrás, y la palabra en letras gruesas inclinadas con degradado, contorno de tinta, sombra
desplazada y brillo. Las muestra ComicWords (scripts/objects/comic_words.gd) como Sprite3D al golpear.
La lista WORDS debe coincidir con ComicWords.GROUPS (cuántas hay de cada tipo).
"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "toon", "words")
FONT = r"C:\Windows\Fonts\impact.ttf"
W, H = 512, 320
SS = 3                      # supermuestreo
INK = (18, 14, 22, 255)

# grupo -> [(texto, color arriba, color abajo, color del estallido, es remate)]
WORDS = {
    "sword": [
        ("¡ZAS!", (255, 240, 120), (255, 150, 30), (255, 255, 255), False),
        ("SLASH!", (255, 255, 255), (150, 220, 255), (60, 130, 230), False),
        ("¡CHAS!", (255, 230, 90), (240, 90, 40), (255, 250, 210), False),
        ("SHING!", (235, 250, 255), (120, 200, 255), (255, 255, 255), False),
        ("¡FIUU!", (255, 255, 200), (120, 230, 140), (255, 255, 255), False),
        ("¡TAJO!", (255, 220, 80), (230, 40, 40), (255, 240, 140), True),
        ("KRASH!", (255, 255, 255), (255, 70, 60), (255, 210, 60), True),
    ],
    # mazas: golpes contundentes, tonos de piedra, verde rúnico y naranja
    "mace": [
        ("¡PUM!", (255, 245, 150), (255, 130, 30), (255, 255, 255), False),
        ("CRACK!", (255, 255, 255), (170, 235, 190), (40, 150, 90), False),
        ("¡BONK!", (255, 235, 110), (235, 110, 40), (255, 245, 200), False),
        ("THUD!", (240, 240, 250), (150, 150, 185), (255, 255, 255), False),
        ("¡TOC!", (255, 255, 210), (120, 220, 150), (255, 255, 255), False),
        ("¡BOOM!", (255, 230, 90), (225, 45, 35), (255, 215, 70), True),
        ("CRUNCH!", (255, 255, 255), (60, 190, 110), (255, 240, 130), True),
    ],
    # puños: golpes secos y rápidos, rojos y amarillos de cómic clásico
    "fist": [
        ("¡PAF!", (255, 245, 140), (255, 120, 40), (255, 255, 255), False),
        ("POW!", (255, 255, 255), (255, 200, 60), (230, 50, 50), False),
        ("¡PLAF!", (255, 240, 200), (250, 130, 110), (255, 250, 220), False),
        ("BAM!", (255, 255, 255), (255, 90, 80), (255, 225, 80), False),
        ("¡ZOK!", (255, 250, 170), (170, 120, 255), (255, 255, 255), False),
        ("¡K.O.!", (255, 235, 90), (225, 40, 40), (255, 225, 90), True),
        ("WHAM!", (255, 255, 255), (255, 100, 40), (90, 60, 200), True),
    ],
}


def burst(rnd, spikes, r_in, r_out, cx, cy, squash=0.62):
    pts = []
    for i in range(spikes * 2):
        a = i * math.pi / spikes + rnd.uniform(-0.06, 0.06)
        r = (r_out * rnd.uniform(0.82, 1.08)) if i % 2 == 0 else (r_in * rnd.uniform(0.9, 1.1))
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * squash))
    return pts


def make(text, top, bottom, burst_col, kill, seed):
    rnd = random.Random(seed)
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2

    # ── estallido: sombra, relleno, trama de puntos y contorno
    spikes = 15 if kill else 12
    pts = burst(rnd, spikes, w * 0.31, w * 0.49, cx, cy)
    d.polygon([(x + 5 * SS, y + 7 * SS) for x, y in pts], fill=INK)
    d.polygon(pts, fill=burst_col + (255,))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    dots = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    step = 9 * SS
    shade = tuple(int(c * 0.72) for c in burst_col) + (255,)
    for j, y in enumerate(range(0, h, step)):
        for x in range((step // 2) * (j % 2), w, step):
            # los puntos crecen hacia abajo a la derecha (trama de imprenta)
            t = (x / w * 0.55 + y / h * 0.45)
            r = step * 0.46 * max(0.0, t - 0.25) / 0.75
            if r > 0.6:
                dd.ellipse([x - r, y - r, x + r, y + r], fill=shade)
    img.paste(dots, (0, 0), ImageChops.multiply(mask, dots.split()[3]))
    d.line(pts + [pts[0]], fill=INK, width=4 * SS, joint="curve")

    # ── palabra: se dibuja recta en su capa y luego se inclina y gira
    size = int(h * (0.5 if len(text) <= 5 else 0.43))
    font = ImageFont.truetype(FONT, size)
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    box = ld.textbbox((0, 0), text, font=font, stroke_width=7 * SS)
    tw, th = box[2] - box[0], box[3] - box[1]
    if tw > w * 0.8:                                   # que quepa dentro del estallido
        font = ImageFont.truetype(FONT, int(size * w * 0.8 / tw))
        box = ld.textbbox((0, 0), text, font=font, stroke_width=7 * SS)
        tw, th = box[2] - box[0], box[3] - box[1]
    ox, oy = cx - tw / 2 - box[0], cy - th / 2 - box[1]
    # sombra desplazada y contorno de tinta
    ld.text((ox + 6 * SS, oy + 7 * SS), text, font=font, fill=INK, stroke_width=7 * SS, stroke_fill=INK)
    ld.text((ox, oy), text, font=font, fill=INK, stroke_width=7 * SS, stroke_fill=INK)
    # relleno con degradado vertical, recortado a las letras
    glyph = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glyph).text((ox, oy), text, font=font, fill=255)
    grad = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(grad)
    y0, y1 = oy + box[1], oy + box[3]
    for y in range(h):
        t = min(max((y - y0) / max(y1 - y0, 1), 0.0), 1.0)
        t = 0.0 if t < 0.45 else (1.0 if t > 0.6 else (t - 0.45) / 0.15)      # corte casi duro (cel)
        gd.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    layer.paste(grad, (0, 0), glyph)
    # brillo: franja blanca fina arriba de cada letra
    hi = ImageChops.subtract(glyph, ImageChops.offset(glyph, 0, 5 * SS))
    hi = ImageChops.multiply(hi, ImageChops.offset(glyph, 0, -2 * SS))
    layer.paste(Image.new("RGBA", (w, h), (255, 255, 255, 235)), (0, 0), hi)
    # inclinación de cómic + giro
    shear = -0.22
    layer = layer.transform((w, h), Image.AFFINE, (1, shear, -shear * cy, 0, 1, 0), resample=Image.BICUBIC)
    layer = layer.rotate(rnd.uniform(5, 11), resample=Image.BICUBIC, center=(cx, cy))
    img.alpha_composite(layer)

    # ── rayas de velocidad saliendo del estallido
    for _ in range(7 if kill else 5):
        a = rnd.uniform(0, math.tau)
        r0, r1 = w * 0.47, w * rnd.uniform(0.5, 0.56)
        p0 = (cx + math.cos(a) * r0, cy + math.sin(a) * r0 * 0.62)
        p1 = (cx + math.cos(a) * r1, cy + math.sin(a) * r1 * 0.62)
        d = ImageDraw.Draw(img)
        d.line([p0, p1], fill=INK, width=3 * SS)

    out = img.resize((W, H), Image.LANCZOS)
    # el color de los píxeles transparentes del borde = tinta (sin halo claro al filtrar)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    for group, words in WORDS.items():
        if only and group != only:
            continue
        for i, (text, top, bottom, bcol, kill) in enumerate(words):
            path = os.path.join(OUT, "%s_%d.png" % (group, i))
            make(text, top, bottom, bcol, kill, 1000 + i * 37 + len(group)).save(path)
            print("guardado", os.path.relpath(path, ROOT), text, "(remate)" if kill else "")


if __name__ == "__main__":
    main()
