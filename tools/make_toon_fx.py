"""Nubes de polvo y humo DIBUJADAS (estilo cómic) para las partículas, en vez de manchas difuminadas.

    python tools/make_toon_fx.py

Sale assets/textures/toon/fx/flame.png (4 lenguas de fuego entintadas, para fuego en partículas),
ring.png (anillo de onda entintado), chispa.png (4 destellos entintados: 2 estrellas de 4 puntas, 1 de 8 y
un grano, para los polvos alquímicos y destellos), impact.png (4 estrellas de impacto entintadas, para HitFeedback._flash) y
assets/textures/toon/fx/puff.png: 256×256 RGBA con 4 nubes distintas (rejilla 2×2). Cada una es un
racimo de bolas en blanco con una banda de sombra abajo, contorno de tinta y un par de trazos interiores.
Va en blanco para que cada efecto la tiña con su color (el contorno sale como ese color en oscuro).
ToonFX (scripts/objects/toon_fx.gd) la pone en los materiales de partículas y elige una nube al azar.
"""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "toon", "fx")
CELL = 128
SS = 4
INK = (26, 22, 30)


def puff(seed):
    rnd = random.Random(seed)
    n = CELL * SS
    c = n / 2
    mask = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask)
    balls = [(c, c + n * 0.04, n * 0.21)]
    count = rnd.randint(6, 8)
    for i in range(count):
        a = i * math.tau / count + rnd.uniform(-0.25, 0.25)
        dist = n * rnd.uniform(0.14, 0.2)
        r = n * rnd.uniform(0.11, 0.165)
        balls.append((c + math.cos(a) * dist, c + n * 0.03 + math.sin(a) * dist * 0.8, r))
    for x, y, r in balls:
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    # contorno: la silueta engordada menos la silueta
    width = int(n * 0.03)
    grown = mask.filter(ImageFilter.MaxFilter(width * 2 + 1))
    # sombra cel: la parte de la nube que no cubre la misma silueta subida
    shade = ImageChops.subtract(mask, ImageChops.offset(mask, -int(n * 0.03), -int(n * 0.07)))
    img = Image.new("RGBA", (n, n), INK + (0,))
    img.paste(Image.new("RGBA", (n, n), INK + (255,)), (0, 0), grown)
    img.paste(Image.new("RGBA", (n, n), (255, 255, 255, 255)), (0, 0), mask)
    img.paste(Image.new("RGBA", (n, n), (196, 198, 214, 255)), (0, 0), shade)
    # trazos interiores: arcos cortos que siguen el borde de alguna bola
    dd = ImageDraw.Draw(img)
    for x, y, r in rnd.sample(balls[1:], 3):
        a0 = rnd.uniform(200, 250)
        rr = r * 0.72
        box = [x - rr, y - rr, x + rr, y + rr]
        inside = Image.new("L", (n, n), 0)
        ImageDraw.Draw(inside).arc(box, a0, a0 + rnd.uniform(60, 95), fill=255, width=int(n * 0.016))
        inside = ImageChops.multiply(inside, mask.filter(ImageFilter.MinFilter(width * 2 + 1)))
        img.paste(Image.new("RGBA", (n, n), INK + (255,)), (0, 0), inside)
    del dd
    return img.resize((CELL, CELL), Image.LANCZOS)


def impact_star(seed):
    """Estrella de impacto de cómic: picos irregulares en gris claro, núcleo blanco con su propia línea de
    tinta y contorno grueso de tinta. El color lo pone el `modulate` del sprite (el del arma)."""
    rnd = random.Random(seed)
    n = CELL * SS
    c = n / 2

    def star(r_out, r_in, spikes, jitter):
        pts = []
        off = rnd.uniform(0, math.tau)
        for i in range(spikes * 2):
            a = off + i * math.pi / spikes + rnd.uniform(-jitter, jitter)
            r = r_out * rnd.uniform(0.72, 1.0) if i % 2 == 0 else r_in * rnd.uniform(0.85, 1.1)
            pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
        return pts

    outer = star(n * 0.44, n * 0.2, rnd.randint(9, 12), 0.12)
    core = star(n * 0.22, n * 0.11, rnd.randint(6, 8), 0.1)
    img = Image.new("RGBA", (n, n), INK + (0,))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).polygon(outer, fill=255)
    width = int(n * 0.028)
    img.paste(Image.new("RGBA", (n, n), INK + (255,)), (0, 0), mask.filter(ImageFilter.MaxFilter(width * 2 + 1)))
    img.paste(Image.new("RGBA", (n, n), (205, 205, 215, 255)), (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.polygon(core, fill=(255, 255, 255, 255))
    d.line(core + [core[0]], fill=INK + (255,), width=int(n * 0.014), joint="curve")
    return img.resize((CELL, CELL), Image.LANCZOS)


def flame(seed):
    """Lengua de fuego de cómic: lágrima con el borde ondulado y una o dos puntas laterales, cuerpo en gris
    claro, núcleo blanco (otra lágrima más pequeña y baja) y contorno de tinta. En blanco/gris para que la
    partícula la tiña (amarillo -> naranja -> rojo a lo largo de su vida)."""
    rnd = random.Random(seed)
    n = CELL * SS
    cx = n / 2

    def tongue(base_y, height, half_w, waves, lean, side_tips):
        pts_l, pts_r = [], []
        steps = 48
        for i in range(steps + 1):
            t = i / steps                                   # 0 = base, 1 = punta
            w = half_w * math.sin(math.pi * min(1.0, 0.15 + t * 0.95)) ** 0.8 * (1.0 - t) ** 0.6
            wob = math.sin(t * math.pi * waves + seed) * half_w * 0.12 * t
            x0 = cx + lean * t * t * half_w + wob
            y = base_y - t * height
            pts_l.append((x0 - w, y))
            pts_r.append((x0 + w, y))
        for side, at, size in side_tips:
            k = int(at * steps)
            pts = pts_l if side < 0 else pts_r
            x, y = pts[k]
            pts.insert(k + 1, (x + side * half_w * size * 0.6, y - height * size * 0.55))
        return pts_l + pts_r[::-1]

    half_w = n * rnd.uniform(0.25, 0.3)
    lean = rnd.uniform(-0.5, 0.5)
    tips = [(rnd.choice((-1, 1)), rnd.uniform(0.35, 0.55), rnd.uniform(0.35, 0.5))]
    if rnd.random() < 0.6:
        tips.append((-tips[0][0], rnd.uniform(0.25, 0.45), rnd.uniform(0.25, 0.4)))
    body = tongue(n * 0.9, n * rnd.uniform(0.72, 0.8), half_w, rnd.uniform(2.5, 4.0), lean, tips)
    core = tongue(n * 0.86, n * rnd.uniform(0.4, 0.48), half_w * 0.5, 2.0, lean * 0.6, [])
    def bulb(draw, base_y, r, fill):                         # base redonda de la lágrima
        draw.ellipse([cx - r, base_y - 2 * r, cx + r, base_y], fill=fill)

    mask = Image.new("L", (n, n), 0)
    md = ImageDraw.Draw(mask)
    md.polygon(body, fill=255)
    bulb(md, n * 0.93, half_w * 0.86, 255)
    width = int(n * 0.03)
    img = Image.new("RGBA", (n, n), INK + (0,))
    img.paste(Image.new("RGBA", (n, n), INK + (255,)), (0, 0), mask.filter(ImageFilter.MaxFilter(width * 2 + 1)))
    img.paste(Image.new("RGBA", (n, n), (190, 190, 200, 255)), (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.polygon(core, fill=(255, 255, 255, 255))
    bulb(d, n * 0.88, half_w * 0.44, (255, 255, 255, 255))
    return img.resize((CELL, CELL), Image.LANCZOS)


def sparkle(kind, seed):
    """Destello de cómic: estrella de 4 puntas cóncava (0, 1), de 8 puntas (2) o grano redondo (3).
    Cuerpo gris claro con núcleo blanco y contorno de tinta; en blanco/gris para que la partícula la tiña."""
    rnd = random.Random(seed)
    n = CELL * SS
    c = n / 2

    def star(r_out, r_in, spikes, rot):
        pts = []
        for i in range(spikes * 2):
            a = rot + i * math.pi / spikes
            r = r_out if i % 2 == 0 else r_in
            pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
        return pts

    mask = Image.new("L", (n, n), 0)
    md = ImageDraw.Draw(mask)
    if kind == 3:
        r = n * 0.26
        md.ellipse([c - r, c - r, c + r, c + r], fill=255)
        core = None
    elif kind == 2:
        long_ = star(n * 0.42, n * 0.1, 4, -math.pi / 2)
        short = star(n * 0.24, n * 0.08, 4, -math.pi / 2 + math.pi / 4)
        md.polygon(long_, fill=255)
        md.polygon(short, fill=255)
        core = star(n * 0.17, n * 0.06, 4, -math.pi / 2)
    else:
        thin = 0.085 if kind == 0 else 0.12
        md.polygon(star(n * 0.43, n * thin, 4, -math.pi / 2 + rnd.uniform(-0.08, 0.08)), fill=255)
        core = star(n * 0.2, n * thin * 0.55, 4, -math.pi / 2)
    width = int(n * 0.03)
    img = Image.new("RGBA", (n, n), INK + (0,))
    img.paste(Image.new("RGBA", (n, n), INK + (255,)), (0, 0), mask.filter(ImageFilter.MaxFilter(width * 2 + 1)))
    img.paste(Image.new("RGBA", (n, n), (200, 200, 212, 255)), (0, 0), mask)
    d = ImageDraw.Draw(img)
    if core is None:
        r = n * 0.13
        d.ellipse([c - r - n * 0.04, c - r - n * 0.05, c + r - n * 0.04, c + r - n * 0.05], fill=(255, 255, 255, 255))
    else:
        d.polygon(core, fill=(255, 255, 255, 255))
    return img.resize((CELL, CELL), Image.LANCZOS)


def ring():
    """Anillo de onda entintado (polvo al aterrizar, onda de fuego): banda blanca con tinta a ambos lados.
    Sale a 512 px (no 128): se estira a varios metros en el suelo y la tinta fina se emborronaba."""
    size = 512
    n = size * SS
    img = Image.new("RGBA", (n, n), INK + (0,))
    d = ImageDraw.Draw(img)
    c = n / 2
    for r, col in ((0.47, INK + (255,)), (0.455, (255, 255, 255, 255)), (0.415, INK + (255,)), (0.4, INK + (0,))):
        rr = n * r
        d.ellipse([c - rr, c - rr, c + rr, c + rr], fill=col)
    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    flames = Image.new("RGBA", (CELL * 2, CELL * 2), INK + (0,))
    for i in range(4):
        flames.paste(flame(7 + i * 11), ((i % 2) * CELL, (i // 2) * CELL))
    flames.save(os.path.join(OUT, "flame.png"))
    print("guardado", os.path.relpath(os.path.join(OUT, "flame.png"), ROOT))
    ring().save(os.path.join(OUT, "ring.png"))
    print("guardado", os.path.relpath(os.path.join(OUT, "ring.png"), ROOT))
    stars = Image.new("RGBA", (CELL * 2, CELL * 2), INK + (0,))
    for i in range(4):
        stars.paste(impact_star(90 + i * 7), ((i % 2) * CELL, (i // 2) * CELL))
    stars.save(os.path.join(OUT, "impact.png"))
    print("guardado", os.path.relpath(os.path.join(OUT, "impact.png"), ROOT))
    sparks = Image.new("RGBA", (CELL * 2, CELL * 2), INK + (0,))
    for i in range(4):
        sparks.paste(sparkle(i, 60 + i * 5), ((i % 2) * CELL, (i // 2) * CELL))
    sparks.save(os.path.join(OUT, "chispa.png"))
    print("guardado", os.path.relpath(os.path.join(OUT, "chispa.png"), ROOT))
    sheet = Image.new("RGBA", (CELL * 2, CELL * 2), INK + (0,))
    for i in range(4):
        sheet.paste(puff(40 + i * 13), ((i % 2) * CELL, (i // 2) * CELL))
    path = os.path.join(OUT, "puff.png")
    sheet.save(path)
    print("guardado", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
