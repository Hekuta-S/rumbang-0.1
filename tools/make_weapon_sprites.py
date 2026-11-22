"""Armas y ataques DIBUJADOS (cómic 2D horneado) para supervivencia: sustituyen a modelos 3D y bolas brillantes.

    python tools/make_weapon_sprites.py [hoja_de_revision.png]

Usa el mismo lienzo entintado que los iconos (tools/make_ui_icons.py: Pic, tinta gruesa debajo de cada pieza,
relleno plano con contorno fino y trazos de detalle). Sale en assets/textures/toon/fx/:

  guitarra.png   8 fotogramas en fila (giro de 45° en 45°) de la guitarra-hacha de Garri, mástil arriba.
                 Fotograma 0 = en la mano; la rueda entera = hacha girando en el aire.
  brazo.png      8 fotogramas en fila (giro) del brazo bumerán: mano arriba, hueso abajo.
  maza.png       2 fotogramas de la Maza Gigante, agarre abajo en el centro (x = 0,5, y = 0,94):
                 0 = quieta, 1 = con rayas de velocidad para la bajada.
  magia.png      2 columnas (fotogramas) x 3 filas: proyectil mágico arcano (magos), carmesí (jefe) y
                 verde (necromante). Bola con destello de estrella: se lee igual desde cualquier lado.
  grieta.png     grietas vistas desde arriba, para el suelo donde pega la maza.

Y el icono de la carta assets/ui/ingame_hub/armas/maza_gigante.png (sobre _marco.png, como los demás).
"""
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_ui_icons import INK, Pic, Axis, rgb, star, circle_pts, FRAME, WEAPONS_OUT  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "toon", "fx")
SPIN_FRAMES = 8


def _pic(size):
    # Contorno algo más grueso que en los iconos: en el juego se ven pequeños y lejos.
    return Pic(size, ss=4, outer=0.022, inner=0.009)


# ── guitarra-hacha de Garri ──────────────────────────────────────────────

def guitarra(size):
    p = _pic(size)
    a = Axis((0.5, 0.07), (0.5, 0.93))      # u = 0 punta del clavijero, u = 1 pincho de abajo
    wood, wood_dk = rgb(140, 86, 48), rgb(92, 56, 32)
    pink, pink_dk, pink_lt = rgb(240, 60, 150), rgb(178, 30, 104), rgb(255, 190, 225)
    steel, steel_dk = rgb(222, 226, 236), rgb(150, 155, 172)
    # clavijas (debajo del clavijero)
    for u in (0.035, 0.075, 0.115):
        for s in (1, -1):
            p.ell(*a(u, s * 0.062), 0.016, 0.012, steel)
    # clavijero
    p.poly(a.pts([(0.0, -0.035), (0.0, 0.035), (0.14, 0.03), (0.14, -0.03)]), pink)
    # mástil y diapasón
    p.line([a(0.13, 0.0), a(0.64, 0.0)], 0.05, wood)
    p.detail([a(0.15, 0.0), a(0.62, 0.0)], 0.026, wood_dk)
    for k in range(9):
        u = 0.17 + k * 0.05
        p.detail([a(u, -0.016), a(u, 0.016)], 0.005, rgb(225, 205, 150))
    # hojas de hacha = cuerpo de la guitarra (como el icono)
    for s in (1, -1):
        p.poly(a.pts([(0.62, 0.0), (0.6, s * 0.08), (0.555, s * 0.36), (0.76, s * 0.44),
                      (0.965, s * 0.36), (0.92, s * 0.08), (0.89, 0.0)]), pink)
        # sombra cel en la mitad baja de cada hoja
        p.poly(a.pts([(0.77, s * 0.05), (0.93, s * 0.1), (0.96, s * 0.34), (0.8, s * 0.3)]), pink_dk, outline=False)
        # filo de acero
        p.poly(a.pts([(0.555, s * 0.36), (0.76, s * 0.44), (0.965, s * 0.36), (0.93, s * 0.305),
                      (0.76, s * 0.375), (0.59, s * 0.305)]), steel)
        p.detail(a.pts([(0.62, s * 0.37), (0.76, s * 0.415), (0.9, s * 0.37)]), 0.006, rgb(255, 255, 255))
        p.detail(a.pts([(0.64, s * 0.12), (0.62, s * 0.27)]), 0.01, pink_lt)
    # centro: pastillas, puente y tornillo
    p.ell(*a(0.76, 0.0), 0.075, 0.075, rgb(80, 78, 98))
    for u in (0.69, 0.79):
        p.poly(a.rect(u - 0.025, u + 0.025, -0.06, 0.06), rgb(36, 32, 40))
        for v in (-0.035, 0.0, 0.035):
            p.detail([a(u, v)], 0.011, steel_dk)
    p.poly(a.rect(0.86, 0.885, -0.05, 0.05), steel)
    # cuerdas
    for v in (-0.009, 0.0, 0.009):
        p.detail([a(0.13, v), a(0.875, v)], 0.0035, rgb(240, 240, 245))
    # pincho de abajo
    p.poly(a.pts([(0.9, -0.03), (0.9, 0.03), (1.0, 0.0)]), steel)
    return p


# ── brazo bumerán ────────────────────────────────────────────────────────

def brazo(size):
    p = _pic(size)
    skin, skin_dk, skin_lt = rgb(135, 175, 95), rgb(92, 128, 64), rgb(185, 215, 140)
    bone, bone_dk = rgb(236, 226, 196), rgb(186, 172, 138)
    # hueso que asoma por el codo
    p.line([(0.5, 0.9), (0.5, 0.74)], 0.055, bone)
    p.ell(0.465, 0.915, 0.04, 0.035, bone)
    p.ell(0.535, 0.915, 0.04, 0.035, bone)
    p.detail([(0.515, 0.76), (0.515, 0.88)], 0.008, bone_dk)
    # antebrazo con el borde roto
    p.poly([(0.41, 0.42), (0.59, 0.42), (0.615, 0.77), (0.585, 0.8), (0.56, 0.765), (0.52, 0.81),
            (0.485, 0.765), (0.45, 0.805), (0.425, 0.765), (0.39, 0.78)], skin)
    p.poly([(0.55, 0.44), (0.59, 0.44), (0.615, 0.765), (0.585, 0.79), (0.565, 0.76)], skin_dk, outline=False)
    # manga rota
    p.poly([(0.395, 0.66), (0.61, 0.66), (0.62, 0.75), (0.59, 0.72), (0.56, 0.76), (0.52, 0.715),
            (0.48, 0.76), (0.445, 0.72), (0.4, 0.75)], rgb(90, 70, 110))
    p.detail([(0.42, 0.68), (0.58, 0.68)], 0.006, rgb(130, 105, 150))
    # herida y puntos
    p.ell(0.465, 0.55, 0.032, 0.05, rgb(130, 30, 42))
    p.detail([(0.452, 0.53), (0.475, 0.565)], 0.006, rgb(200, 70, 80))
    p.detail([(0.52, 0.5), (0.56, 0.58)], 0.006)
    for t in (0.2, 0.5, 0.8):
        x, y = 0.52 + 0.04 * t, 0.5 + 0.08 * t
        p.detail([(x - 0.014, y + 0.008), (x + 0.014, y - 0.008)], 0.005)
    # palma, dedos (garras) y pulgar
    p.ell(0.5, 0.37, 0.105, 0.085, skin)
    for k, (x, top) in enumerate(((0.425, 0.17), (0.475, 0.12), (0.525, 0.13), (0.575, 0.18))):
        tip = (x + (k - 1.5) * 0.014, top)
        p.line([(x, 0.35), tip], 0.036, skin)
        p.detail([tip, (tip[0], tip[1] + 0.02)], 0.022, rgb(60, 48, 40))
        p.detail([(x - 0.008, 0.27), (x + 0.008, 0.27)], 0.005, skin_dk)
    p.line([(0.405, 0.4), (0.325, 0.3)], 0.036, skin)
    p.detail([(0.325, 0.3), (0.318, 0.28)], 0.02, rgb(60, 48, 40))
    p.detail([(0.43, 0.33), (0.47, 0.36)], 0.009, skin_lt)
    p.detail([(0.44, 0.47), (0.44, 0.62)], 0.009, skin_lt)
    return p


# ── Maza Gigante ─────────────────────────────────────────────────────────

GRIP = (0.5, 0.94)                         ## agarre: el pivote del golpe (Sprite3D.offset en el juego)


def maza(size, smear=False):
    p = _pic(size)
    iron, iron_dk, iron_lt = rgb(150, 156, 172), rgb(96, 100, 118), rgb(226, 230, 240)
    gold = rgb(212, 166, 62)
    hx, hy, hr = 0.5, 0.24, 0.165
    if smear:
        # rayas de velocidad detrás de la cabeza (baja girando a la derecha alrededor del agarre)
        gx, gy = GRIP
        for r, w in ((0.6, 0.016), (0.7, 0.022), (0.8, 0.016)):
            p.detail(circle_pts(gx, gy, r, 14, math.radians(-100), math.radians(-128)), w)
    # pinchos (debajo de la bola)
    for k in range(8):
        ang = k * math.tau / 8 + math.pi / 8
        ca, sa = math.cos(ang), math.sin(ang)
        base = 0.045
        p.poly([(hx + ca * hr * 0.85 - sa * base, hy + sa * hr * 0.85 + ca * base),
                (hx + ca * (hr + 0.085), hy + sa * (hr + 0.085)),
                (hx + ca * hr * 0.85 + sa * base, hy + sa * hr * 0.85 - ca * base)], iron_lt)
    # mango y empuñadura
    p.line([(0.5, 0.94), (0.5, 0.4)], 0.07, rgb(140, 90, 50))
    for k in range(5):
        y = 0.78 + k * 0.032
        p.detail([(0.465, y + 0.012), (0.535, y - 0.012)], 0.012, rgb(78, 48, 30))
    p.detail([(0.488, 0.45), (0.488, 0.74)], 0.01, rgb(180, 128, 80))
    p.ell(0.5, 0.945, 0.05, 0.035, iron)
    # collar dorado
    p.poly([(0.42, 0.38), (0.58, 0.38), (0.56, 0.44), (0.44, 0.44)], gold)
    # bola
    p.ell(hx, hy, hr, hr, iron)
    p.detail(circle_pts(hx, hy, hr * 0.78, 18, math.radians(-10), math.radians(110)), 0.05, iron_dk)
    p.detail(circle_pts(hx, hy, hr, 24, math.radians(160), math.radians(380)), 0.018, gold)
    p.detail(circle_pts(hx, hy, hr, 24, math.radians(160), math.radians(380)), 0.005)
    p.ell(hx - 0.06, hy - 0.07, 0.04, 0.026, rgb(250, 250, 255), outline=False)
    # runa
    p.detail([(hx - 0.02, hy + 0.05), (hx + 0.02, hy - 0.01), (hx + 0.045, hy + 0.05)], 0.012, rgb(255, 214, 110))
    return p


# ── proyectiles mágicos (enemigos) ───────────────────────────────────────

MAGIC = [
    # (destello, bola, centro)
    (rgb(150, 130, 255), rgb(84, 92, 232), rgb(226, 232, 255)),    # arcano (magos goblin)
    (rgb(255, 104, 122), rgb(206, 32, 62), rgb(255, 222, 222)),    # carmesí (jefe)
    (rgb(128, 255, 160), rgb(40, 172, 92), rgb(226, 255, 228)),    # verde (necromante)
]


def magia(size, row, frame):
    flare, ball, core = MAGIC[row]
    p = _pic(size)
    rot = 0.0 if frame == 0 else math.pi / 6
    p.poly(star(0.5, 0.5, 0.46, 0.22, 6, rot), flare)
    p.ell(0.5, 0.5, 0.25, 0.25, ball)
    p.ell(0.5, 0.5, 0.13, 0.13, core, outline=False)
    p.ell(0.43, 0.42, 0.05, 0.035, rgb(255, 255, 255), outline=False)
    for k in range(3):
        ang = rot + k * math.tau / 3 + 0.5
        x, y = 0.5 + math.cos(ang) * 0.36, 0.5 + math.sin(ang) * 0.36
        p.detail([(x - 0.03, y), (x + 0.03, y)], 0.01, rgb(255, 255, 255))
        p.detail([(x, y - 0.03), (x, y + 0.03)], 0.01, rgb(255, 255, 255))
    return p


# ── grietas del suelo ────────────────────────────────────────────────────

def grieta(size):
    import random
    rnd = random.Random(7)
    p = _pic(size)
    p.ell(0.5, 0.5, 0.15, 0.13, rgb(70, 54, 40))
    p.ell(0.5, 0.5, 0.09, 0.075, rgb(42, 32, 26), outline=False)
    for k in range(9):
        ang = k * math.tau / 9 + rnd.uniform(-0.2, 0.2)
        pts = [(0.5 + math.cos(ang) * 0.12, 0.5 + math.sin(ang) * 0.11)]
        r, a_ = 0.12, ang
        while r < 0.47:
            r += rnd.uniform(0.06, 0.1)
            a_ += rnd.uniform(-0.28, 0.28)
            pts.append((0.5 + math.cos(a_) * min(r, 0.47), 0.5 + math.sin(a_) * min(r, 0.47)))
        p.detail(pts, 0.022 * (1.0 - 0.1 * (k % 3)))
        if k % 2 == 0:   # rama
            j = len(pts) // 2
            bx, by = pts[j]
            b_ang = a_ + rnd.choice((-0.9, 0.9))
            p.detail([(bx, by), (bx + math.cos(b_ang) * 0.1, by + math.sin(b_ang) * 0.1)], 0.012)
    for k in range(7):
        ang = rnd.uniform(0, math.tau)
        rr = rnd.uniform(0.2, 0.4)
        x, y = 0.5 + math.cos(ang) * rr, 0.5 + math.sin(ang) * rr
        s = rnd.uniform(0.018, 0.03)
        p.poly([(x - s, y), (x, y - s * 0.8), (x + s, y - s * 0.2), (x + s * 0.6, y + s * 0.7)], rgb(150, 116, 80))
    return p


# ── salida ───────────────────────────────────────────────────────────────

def _spin_strip(fn, cell):
    # Se dibuja a 2x y se gira en grande (la tinta no se emborrona), luego se reduce a la celda.
    big = fn(cell * 2).render()
    strip = Image.new("RGBA", (cell * SPIN_FRAMES, cell), INK[:3] + (0,))
    for f in range(SPIN_FRAMES):
        rot = big.rotate(-f * 360.0 / SPIN_FRAMES, resample=Image.BICUBIC)
        strip.paste(rot.resize((cell, cell), Image.LANCZOS), (f * cell, 0))
    return strip


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []

    def save(img, name):
        path = os.path.join(OUT, name)
        img.save(path)
        made.append(path)

    save(_spin_strip(guitarra, 192), "guitarra.png")
    save(_spin_strip(brazo, 160), "brazo.png")
    cell = 256
    sheet = Image.new("RGBA", (cell * 2, cell), INK[:3] + (0,))
    sheet.paste(maza(cell).render(), (0, 0))
    sheet.paste(maza(cell, smear=True).render(), (cell, 0))
    save(sheet, "maza.png")
    cell = 128
    sheet = Image.new("RGBA", (cell * 2, cell * len(MAGIC)), INK[:3] + (0,))
    for row in range(len(MAGIC)):
        for frame in range(2):
            sheet.paste(magia(cell, row, frame).render(), (frame * cell, row * cell))
    save(sheet, "magia.png")
    save(grieta(256).render(), "grieta.png")

    # Icono de la carta: la maza en diagonal sobre el marco
    frame_img = Image.open(FRAME).convert("RGBA")
    obj = maza(frame_img.size[0]).render().rotate(-35, resample=Image.BICUBIC)
    obj = obj.resize((int(frame_img.size[0] * 0.86),) * 2, Image.LANCZOS)
    icon = frame_img.copy()
    off = (frame_img.size[0] - obj.size[0]) // 2
    icon.alpha_composite(obj, (off, off))
    path = os.path.join(WEAPONS_OUT, "maza_gigante.png")
    icon.save(path)
    made.append(path)

    for path in made:
        print("guardado", os.path.relpath(path, ROOT))
    if len(sys.argv) > 1:
        tiles = [Image.open(p_).convert("RGBA") for p_ in made]
        w = max(t.size[0] for t in tiles)
        h = sum(t.size[1] for t in tiles) + 8 * len(tiles)
        review = Image.new("RGBA", (w, h), (110, 104, 92, 255))
        y = 0
        for t in tiles:
            review.alpha_composite(t, (0, y))
            y += t.size[1] + 8
        review.save(sys.argv[1])
        print("hoja", sys.argv[1])


if __name__ == "__main__":
    main()
