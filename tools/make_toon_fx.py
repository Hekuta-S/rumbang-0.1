"""Nubes de polvo y humo DIBUJADAS (estilo cómic) para las partículas, en vez de manchas difuminadas.

    python tools/make_toon_fx.py

Sale assets/textures/toon/fx/impact.png (4 estrellas de impacto entintadas, para HitFeedback._flash) y
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


def main():
    os.makedirs(OUT, exist_ok=True)
    stars = Image.new("RGBA", (CELL * 2, CELL * 2), INK + (0,))
    for i in range(4):
        stars.paste(impact_star(90 + i * 7), ((i % 2) * CELL, (i // 2) * CELL))
    stars.save(os.path.join(OUT, "impact.png"))
    print("guardado", os.path.relpath(os.path.join(OUT, "impact.png"), ROOT))
    sheet = Image.new("RGBA", (CELL * 2, CELL * 2), INK + (0,))
    for i in range(4):
        sheet.paste(puff(40 + i * 13), ((i % 2) * CELL, (i // 2) * CELL))
    path = os.path.join(OUT, "puff.png")
    sheet.save(path)
    print("guardado", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
