"""Dibuja el atlas de la fauna ambiental (assets/textures/critters/critters_atlas.png).

Siluetas entintadas, al estilo cómic del juego: relleno oscuro, contorno negro grueso y un acento de color.
Atlas de 4 x 4 celdas de 96 px (las usa AmbientCritters con critter_sprite.gdshader):
   0 cuervo posado   1 cuervo alas arriba   2 cuervo alas abajo   3 murciélago colgado
   4 murciélago alas arriba   5 murciélago alas abajo   6 rata corriendo A   7 rata corriendo B
   8 punto de luz (luciérnagas, bichos de los hongos)   9 mosca A   10 mosca B
Todas miran a la derecha; el shader las voltea según hacia dónde van.

Uso: python tools/make_critter_sprites.py   (Godot reimporta el .png al abrir el proyecto)
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

CELL = 96
GRID = 4
SS = 4                                 # supermuestreo: se dibuja a 4x y se reduce
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures", "critters")

INK = (12, 10, 14, 255)
CROW = (38, 36, 52, 255)
CROW_LIGHT = (72, 70, 96, 255)
BEAK = (214, 150, 60, 255)
BAT = (58, 40, 66, 255)
BAT_WING = (84, 56, 92, 255)
RAT = (96, 80, 70, 255)
RAT_BELLY = (132, 112, 98, 255)
TAIL = (190, 128, 128, 255)
EYE = (255, 236, 170, 255)


def cell_image():
    return Image.new("RGBA", (CELL * SS, CELL * SS), (0, 0, 0, 0))


def P(points):
    """Puntos en coordenadas de celda (0..96) -> píxeles supermuestreados."""
    return [(x * SS, y * SS) for x, y in points]


def inked(img, draw_fill, outline=3.2):
    """Dibuja con `draw_fill(draw)` y le pone contorno de tinta: la silueta dilatada en negro va debajo."""
    layer = cell_image()
    draw_fill(ImageDraw.Draw(layer))
    alpha = layer.getchannel("A")
    grown = alpha.filter(ImageFilter.MaxFilter(int(outline * SS) * 2 + 1))
    ink = Image.new("RGBA", layer.size, INK)
    ink.putalpha(grown)
    img.alpha_composite(ink)
    img.alpha_composite(layer)


def ellipse(d, cx, cy, rx, ry, fill):
    d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=fill)


# ───────────────────────────── cuervo ─────────────────────────────

def crow_perched():
    img = cell_image()

    def fill(d):
        d.polygon(P([(24, 62), (10, 70), (26, 68)]), fill=CROW)                 # cola
        ellipse(d, 44, 56, 22, 15, CROW)                                        # cuerpo
        d.polygon(P([(30, 50), (58, 46), (62, 62), (34, 68)]), fill=CROW_LIGHT)  # ala plegada
        ellipse(d, 64, 40, 12, 11, CROW)                                        # cabeza
        d.polygon(P([(73, 37), (90, 42), (74, 46)]), fill=BEAK)                 # pico
        d.line(P([(42, 70), (40, 82)]), fill=INK, width=2 * SS)                 # patas
        d.line(P([(50, 70), (52, 82)]), fill=INK, width=2 * SS)
        ellipse(d, 67, 38, 2.2, 2.2, EYE)
    inked(img, fill)
    return img


def crow_flying(wing_up):
    img = cell_image()

    def fill(d):
        d.polygon(P([(26, 50), (8, 56), (26, 56)]), fill=CROW)                  # cola
        ellipse(d, 46, 52, 22, 10, CROW)                                        # cuerpo
        ellipse(d, 68, 48, 10, 9, CROW)                                         # cabeza
        d.polygon(P([(76, 45), (92, 50), (76, 53)]), fill=BEAK)
        if wing_up:
            d.polygon(P([(34, 48), (30, 14), (46, 22), (62, 46)]), fill=CROW_LIGHT)
            d.polygon(P([(30, 14), (22, 22), (34, 30)]), fill=CROW)             # plumas de la punta
        else:
            d.polygon(P([(34, 54), (26, 84), (44, 78), (62, 56)]), fill=CROW_LIGHT)
            d.polygon(P([(26, 84), (18, 76), (32, 70)]), fill=CROW)
        ellipse(d, 71, 46, 2.0, 2.0, EYE)
    inked(img, fill)
    return img


# ───────────────────────────── murciélago ─────────────────────────────

def bat_hanging():
    img = cell_image()

    def fill(d):
        d.line(P([(44, 8), (44, 20)]), fill=INK, width=2 * SS)                  # patas agarradas al techo
        d.line(P([(52, 8), (52, 20)]), fill=INK, width=2 * SS)
        d.polygon(P([(34, 20), (62, 20), (66, 58), (48, 74), (30, 58)]), fill=BAT_WING)   # alas envueltas
        d.polygon(P([(48, 26), (48, 70)]), fill=BAT)
        ellipse(d, 48, 72, 10, 9, BAT)                                          # cabeza abajo
        d.polygon(P([(40, 78), (36, 90), (46, 80)]), fill=BAT)                  # orejas (hacia abajo)
        d.polygon(P([(56, 78), (60, 90), (50, 80)]), fill=BAT)
        ellipse(d, 44, 71, 1.8, 1.8, EYE)
        ellipse(d, 52, 71, 1.8, 1.8, EYE)
    inked(img, fill)
    return img


def bat_flying(wing_up):
    img = cell_image()
    tip = 22 if wing_up else 70
    mid = 34 if wing_up else 60

    def fill(d):
        for s in (-1, 1):                                                       # ala a cada lado
            x = lambda v: 48 + s * v
            d.polygon(P([(x(6), 46), (x(22), mid - 8), (x(42), tip), (x(36), mid + 6), (x(26), mid + 2),
                         (x(20), mid + 12), (x(12), 54), (x(6), 56)]), fill=BAT_WING)
        ellipse(d, 48, 50, 9, 12, BAT)                                          # cuerpo
        ellipse(d, 48, 38, 8, 7, BAT)                                           # cabeza
        d.polygon(P([(42, 34), (39, 22), (47, 32)]), fill=BAT)                  # orejas
        d.polygon(P([(54, 34), (57, 22), (49, 32)]), fill=BAT)
        ellipse(d, 45, 38, 1.7, 1.7, EYE)
        ellipse(d, 51, 38, 1.7, 1.7, EYE)
    inked(img, fill)
    return img


# ───────────────────────────── rata ─────────────────────────────

def rat(stride):
    img = cell_image()
    lift = 3 if stride else 0

    def fill(d):
        pts = [(22 - 19 * t, 60 - lift - 10 * t + 5 * math.sin(t * 5.0 + (1.6 if stride else 0.0))) for t in
               [i / 8.0 for i in range(9)]]
        d.line(P(pts), fill=TAIL, width=int(2.4 * SS), joint="curve")           # cola
        ellipse(d, 42, 60 - lift, 24, 13, RAT)                                  # cuerpo
        ellipse(d, 44, 66 - lift, 16, 6, RAT_BELLY)
        d.polygon(P([(58, 50 - lift), (86, 62 - lift), (60, 70 - lift)]), fill=RAT)   # cabeza en cuña
        ellipse(d, 62, 48 - lift, 6, 6, RAT_BELLY)                              # oreja
        ellipse(d, 85, 62 - lift, 2.4, 2.4, TAIL)                               # hocico
        ellipse(d, 72, 57 - lift, 1.9, 1.9, INK)
        legs = [(30, 12), (52, -10)] if stride else [(34, -10), (50, 12)]
        for lx, sweep in legs:
            d.line(P([(lx, 70 - lift), (lx + sweep, 80)]), fill=RAT, width=int(3.0 * SS))
    inked(img, fill)
    return img


# ───────────────────────────── luces y moscas ─────────────────────────────

def glow_dot():
    """Punto suave con núcleo brillante: sin tinta, se tiñe y brilla en el shader."""
    size = CELL * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = size / 2.0
    for y in range(size):
        for x in range(size):
            r = math.hypot(x - c, y - c) / (size * 0.42)
            a = max(0.0, 1.0 - r) ** 2.2 * 0.85 + (1.0 if r < 0.16 else 0.0) * 0.15
            if a > 0.0:
                px[x, y] = (255, 255, 255, int(min(a, 1.0) * 255))
    return img


def fly(wing_up):
    img = cell_image()

    def fill(d):
        wy = 34 if wing_up else 44
        ellipse(d, 38, wy, 10, 6, (210, 220, 230, 200))                         # alas translúcidas
        ellipse(d, 58, wy, 10, 6, (210, 220, 230, 200))
        ellipse(d, 48, 50, 9, 7, INK)                                           # cuerpo
        ellipse(d, 56, 48, 5, 5, (60, 20, 20, 255))                             # cabeza rojiza
    inked(img, fill, outline=1.6)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    frames = [crow_perched(), crow_flying(True), crow_flying(False), bat_hanging(),
              bat_flying(True), bat_flying(False), rat(False), rat(True),
              glow_dot(), fly(True), fly(False)]
    atlas = Image.new("RGBA", (CELL * GRID, CELL * GRID), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        small = frame.resize((CELL, CELL), Image.LANCZOS)
        atlas.alpha_composite(small, ((i % GRID) * CELL, (i // GRID) * CELL))
    path = os.path.join(OUT, "critters_atlas.png")
    atlas.save(path)
    print("%s  %d frames, %dx%d" % (path, len(frames), atlas.width, atlas.height))


if __name__ == "__main__":
    main()
