"""Iconos DIBUJADOS de los objetos de supervivencia (ItemDB), mismo estilo cómic que los tomos
(tinta oscura + colores planos, ver tools/make_ui_icons.py).

    python tools/make_item_icons.py [hoja.png]

Sale assets/ui/icons/items/<id>.png (128 px, fondo transparente) y los amuletos de la mazmorra en
assets/ui/icons/amulets/<base>.png (EquipmentPanel, tarjetas de pieza). Los usan la bolsa (BagPanel), las
cartas de elección (item_choice_ui) y el hueco del objeto activo (ActiveItemSlot). Con una ruta de
argumento guarda además una hoja de contacto para revisarlos.
"""
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_ui_icons import INK, WHITE, ROOT, Pic, Axis, circle_pts, heart, lens, rgb, star  # noqa: E402

OUT = os.path.join(ROOT, "assets", "ui", "icons", "items")
GOLD = rgb(235, 185, 60)
GOLD_D = rgb(170, 120, 35)


def botas_caminante():
    p = Pic(128)
    p.poly([(0.32, 0.12), (0.6, 0.12), (0.62, 0.58), (0.9, 0.68), (0.92, 0.84), (0.24, 0.84), (0.28, 0.5)],
           rgb(150, 90, 48))
    p.rect(0.22, 0.82, 0.94, 0.9, rgb(70, 45, 30))
    p.rect(0.3, 0.12, 0.62, 0.2, rgb(110, 64, 34))
    for y in (0.3, 0.4, 0.5):
        p.detail([(0.36, y), (0.56, y + 0.04)], 0.018, rgb(240, 220, 170))
    p.detail([(0.66, 0.66), (0.86, 0.72)], 0.014, rgb(200, 140, 90))
    return p


def pluma_condor():
    p = Pic(128)
    p.poly(lens((0.2, 0.86), (0.84, 0.12), 0.17), rgb(55, 50, 60))
    p.poly(lens((0.56, 0.44), (0.84, 0.12), 0.08), WHITE)
    p.detail([(0.16, 0.92), (0.8, 0.17)], 0.02, rgb(200, 195, 190))
    for t in (0.3, 0.45, 0.6):
        x, y = 0.2 + 0.64 * t, 0.86 - 0.74 * t
        p.detail([(x, y), (x - 0.1, y - 0.04)], 0.012, rgb(120, 115, 125))
    return p


def alas_colibri():
    p = Pic(128)
    p.poly(lens((0.5, 0.52), (0.08, 0.16), 0.16), rgb(70, 200, 170))
    p.poly(lens((0.5, 0.52), (0.92, 0.16), 0.16), rgb(70, 200, 170))
    p.poly(lens((0.5, 0.56), (0.2, 0.3), 0.09), rgb(160, 240, 215))
    p.poly(lens((0.5, 0.56), (0.8, 0.3), 0.09), rgb(160, 240, 215))
    p.ell(0.5, 0.6, 0.08, 0.2, rgb(40, 140, 90))
    p.ell(0.5, 0.42, 0.07, 0.07, rgb(220, 60, 90))
    p.detail([(0.5, 0.36), (0.5, 0.18)], 0.016, INK)
    return p


def aguardiente_bendito():
    p = Pic(128)
    p.rect(0.42, 0.06, 0.58, 0.16, rgb(200, 60, 50))
    p.rect(0.44, 0.15, 0.56, 0.32, rgb(170, 220, 200))
    p.poly([(0.44, 0.3), (0.56, 0.3), (0.74, 0.44), (0.74, 0.92), (0.26, 0.92), (0.26, 0.44)], rgb(170, 220, 200))
    p.rect(0.3, 0.5, 0.7, 0.8, rgb(240, 225, 180))
    p.rect(0.47, 0.54, 0.53, 0.76, rgb(200, 60, 50), outline=False)
    p.rect(0.39, 0.6, 0.61, 0.65, rgb(200, 60, 50), outline=False)
    p.detail([(0.32, 0.46), (0.32, 0.86)], 0.02, WHITE)
    return p


def reloj_pendulo_roto():
    p = Pic(128)
    p.line([(0.5, 0.5), (0.36, 0.86)], 0.035, GOLD_D)
    p.ell(0.36, 0.86, 0.08, 0.08, GOLD)
    p.ell(0.5, 0.38, 0.32, 0.32, rgb(150, 95, 55))
    p.ell(0.5, 0.38, 0.24, 0.24, rgb(245, 238, 215))
    p.detail([(0.5, 0.38), (0.5, 0.22)], 0.026)
    p.detail([(0.5, 0.38), (0.62, 0.44)], 0.022)
    p.detail([(0.62, 0.18), (0.56, 0.28), (0.64, 0.34), (0.58, 0.46)], 0.012)
    return p


def carcaj_encantado():
    p = Pic(128)
    a = Axis((0.36, 0.92), (0.66, 0.1))
    for v in (-0.08, 0.0, 0.08):
        p.line([a(0.5, v), a(1.0, v)], 0.022, rgb(160, 120, 80))
        p.poly([a(0.92, v - 0.05), a(1.02, v), a(0.92, v + 0.05), a(0.84, v)], rgb(190, 120, 255))
    p.poly(a.rect(0.0, 0.66, -0.15, 0.15), rgb(120, 70, 40))
    p.poly(a.rect(0.58, 0.66, -0.17, 0.17), rgb(90, 50, 30))
    p.poly(a.rect(0.12, 0.18, -0.15, 0.15), GOLD)
    p.detail([a(0.25, 0.0), a(0.5, 0.0)], 0.014, rgb(220, 170, 255))
    return p


def doble_filo():
    p = Pic(128)
    for (x0, y0), (x1, y1) in (((0.2, 0.86), (0.8, 0.14)), ((0.8, 0.86), (0.2, 0.14))):
        a = Axis((x0, y0), (x1, y1))
        p.poly(a.pts([(0.24, -0.06), (0.92, -0.04), (1.0, 0.0), (0.92, 0.04), (0.24, 0.06)]), rgb(215, 225, 245))
        p.poly(a.rect(0.2, 0.25, -0.12, 0.12), GOLD)
        p.poly(a.rect(0.0, 0.2, -0.035, 0.035), rgb(90, 55, 40))
    p.detail([(0.33, 0.7), (0.72, 0.24)], 0.012, WHITE)
    return p


def mango_hierro():
    p = Pic(128)
    a = Axis((0.24, 0.84), (0.78, 0.16))
    p.poly(a.rect(0.78, 1.0, -0.05, 0.05), rgb(200, 210, 230))
    p.poly(a.rect(0.66, 0.74, -0.2, 0.2), rgb(150, 155, 170))
    p.poly(a.rect(0.12, 0.7, -0.07, 0.07), rgb(110, 115, 130))
    p.ell(*a(0.06, 0.0), 0.08, 0.08, rgb(150, 155, 170))
    for u in (0.2, 0.32, 0.44, 0.56):
        p.detail([a(u, -0.07), a(u + 0.06, 0.07)], 0.016, rgb(60, 62, 75))
    return p


def polvora_gruesa():
    p = Pic(128)
    p.poly([(0.22, 0.3), (0.78, 0.3), (0.84, 0.6), (0.78, 0.9), (0.22, 0.9), (0.16, 0.6)], rgb(150, 95, 50))
    p.rect(0.18, 0.4, 0.82, 0.46, rgb(110, 110, 120))
    p.rect(0.18, 0.74, 0.82, 0.8, rgb(110, 110, 120))
    p.ell(0.5, 0.3, 0.28, 0.08, rgb(60, 50, 50))
    for x, y in ((0.4, 0.22), (0.52, 0.16), (0.62, 0.24), (0.46, 0.1)):
        p.ell(x, y, 0.04, 0.04, rgb(45, 40, 45))
    p.poly(star(0.74, 0.12, 0.1, 0.04, 5), rgb(255, 200, 70))
    return p


def mochila_cuero():
    p = Pic(128)
    p.line([(0.32, 0.3), (0.34, 0.1), (0.66, 0.1), (0.68, 0.3)], 0.05, rgb(100, 60, 32))
    p.poly([(0.2, 0.28), (0.8, 0.28), (0.86, 0.9), (0.14, 0.9)], rgb(150, 92, 50))
    p.poly([(0.2, 0.28), (0.8, 0.28), (0.8, 0.52), (0.5, 0.6), (0.2, 0.52)], rgb(115, 68, 36))
    p.rect(0.3, 0.66, 0.7, 0.84, rgb(130, 80, 42))
    p.rect(0.46, 0.5, 0.54, 0.62, GOLD)
    return p


def colmillo_jaguar():
    p = Pic(128)
    p.line([(0.1, 0.2), (0.3, 0.36), (0.5, 0.4), (0.7, 0.36), (0.9, 0.2)], 0.022, rgb(140, 90, 50))
    p.poly([(0.38, 0.38), (0.62, 0.38), (0.6, 0.56), (0.5, 0.92), (0.46, 0.66)], rgb(250, 240, 215))
    for x, y in ((0.2, 0.28), (0.8, 0.28)):
        p.ell(x, y, 0.06, 0.06, rgb(240, 175, 50))
        p.ell(x, y, 0.022, 0.022, INK, outline=False)
    p.detail([(0.42, 0.44), (0.48, 0.66)], 0.014, rgb(210, 195, 165))
    return p


def poncho_reforzado():
    p = Pic(128)
    p.poly([(0.36, 0.16), (0.64, 0.16), (0.94, 0.78), (0.5, 0.9), (0.06, 0.78)], rgb(190, 60, 50))
    for k, col in enumerate((rgb(240, 200, 80), rgb(40, 35, 45), rgb(240, 200, 80))):
        y = 0.5 + k * 0.07
        xl = lambda yy: 0.36 - 0.30 * (yy - 0.16) / 0.62 + 0.02   # borde izquierdo del poncho
        p.poly([(xl(y), y), (1.0 - xl(y), y), (1.0 - xl(y + 0.04), y + 0.04), (xl(y + 0.04), y + 0.04)],
               col, outline=False)
    p.ell(0.5, 0.17, 0.1, 0.05, rgb(70, 40, 30))
    p.rect(0.32, 0.26, 0.68, 0.32, rgb(140, 145, 160))
    return p


def corazon_ceiba():
    p = Pic(128)
    p.poly(heart(0.5, 0.56, 0.4), rgb(120, 190, 90))
    p.poly(heart(0.5, 0.56, 0.26), rgb(170, 225, 120), outline=False)
    p.poly(lens((0.5, 0.26), (0.72, 0.06), 0.07), rgb(60, 150, 70))
    p.detail([(0.5, 0.36), (0.5, 0.8)], 0.02, rgb(90, 60, 35))
    p.detail([(0.5, 0.55), (0.36, 0.44)], 0.014, rgb(90, 60, 35))
    p.detail([(0.5, 0.65), (0.64, 0.54)], 0.014, rgb(90, 60, 35))
    return p


def vela_anima():
    p = Pic(128)
    p.ell(0.5, 0.88, 0.3, 0.07, GOLD_D)
    p.rect(0.36, 0.38, 0.64, 0.86, rgb(245, 235, 210))
    p.ell(0.5, 0.38, 0.14, 0.04, rgb(225, 215, 190))
    p.poly([(0.5, 0.04), (0.6, 0.2), (0.58, 0.32), (0.42, 0.32), (0.4, 0.2)], rgb(120, 200, 255))
    p.ell(0.5, 0.26, 0.04, 0.05, WHITE, outline=False)
    p.detail([(0.42, 0.44), (0.42, 0.6)], 0.018, rgb(255, 255, 250))
    return p


def ojo_mohan_comun():
    p = Pic(128)
    p.poly(lens((0.06, 0.5), (0.94, 0.5), 0.26), WHITE)
    p.ell(0.5, 0.5, 0.18, 0.18, rgb(60, 170, 90))
    p.ell(0.5, 0.5, 0.08, 0.08, INK, outline=False)
    p.ell(0.44, 0.44, 0.035, 0.035, WHITE, outline=False)
    for x in (0.3, 0.5, 0.7):
        p.detail([(x, 0.26), (x + (x - 0.5) * 0.3, 0.12)], 0.02)
    return p


def duende_travieso():
    p = Pic(128)
    p.ell(0.66, 0.78, 0.18, 0.18, GOLD)
    p.ell(0.66, 0.78, 0.11, 0.11, rgb(250, 215, 100), outline=False)
    p.poly([(0.42, 0.04), (0.66, 0.6), (0.1, 0.6)], rgb(70, 170, 70))
    p.poly([(0.06, 0.58), (0.72, 0.58), (0.7, 0.68), (0.08, 0.68)], rgb(50, 120, 50))
    p.rect(0.28, 0.5, 0.5, 0.6, rgb(120, 80, 40))
    p.ell(0.42, 0.04, 0.05, 0.05, rgb(240, 200, 80))
    return p


def mascara_tryhard():
    p = Pic(128)
    p.poly([(0.12, 0.2), (0.5, 0.1), (0.88, 0.2), (0.82, 0.66), (0.5, 0.92), (0.18, 0.66)], rgb(220, 50, 50))
    p.poly([(0.22, 0.38), (0.44, 0.46), (0.4, 0.54), (0.24, 0.48)], INK)
    p.poly([(0.78, 0.38), (0.56, 0.46), (0.6, 0.54), (0.76, 0.48)], INK)
    p.poly([(0.36, 0.7), (0.64, 0.7), (0.58, 0.78), (0.42, 0.78)], INK)
    p.poly([(0.46, 0.14), (0.54, 0.14), (0.52, 0.34), (0.48, 0.34)], rgb(255, 200, 70))
    p.detail([(0.2, 0.24), (0.16, 0.52)], 0.016, rgb(255, 140, 130))
    return p


def amuleto_tumbaga():
    p = Pic(128)
    p.line([(0.2, 0.06), (0.5, 0.32), (0.8, 0.06)], 0.02, rgb(140, 90, 50))
    p.ell(0.5, 0.6, 0.3, 0.3, GOLD)
    p.ell(0.5, 0.6, 0.2, 0.2, rgb(220, 150, 60))
    pts = [(0.5 + math.cos(t * 0.35) * t * 0.012, 0.6 + math.sin(t * 0.35) * t * 0.012) for t in range(1, 15)]
    p.detail(pts, 0.018, GOLD_D)
    return p


# ── pasivas únicas ──

def totuma_chicha():
    p = Pic(128)
    p.poly(circle_pts(0.5, 0.42, 0.4, 32, 0.0, math.pi), rgb(140, 85, 45))
    p.poly([(0.12, 0.42), (0.88, 0.42), (0.84, 0.5), (0.16, 0.5)], rgb(250, 205, 90))
    p.ell(0.5, 0.42, 0.38, 0.07, rgb(250, 205, 90))
    for x, y, r in ((0.34, 0.3, 0.05), (0.5, 0.2, 0.06), (0.64, 0.3, 0.045)):
        p.ell(x, y, r, r, rgb(255, 240, 190))
    p.detail([(0.26, 0.6), (0.36, 0.72)], 0.014, rgb(90, 50, 25))
    p.detail([(0.62, 0.74), (0.72, 0.62)], 0.014, rgb(90, 50, 25))
    return p


def sangre_mohan():
    p = Pic(128)
    p.poly([(0.5, 0.04)] + circle_pts(0.5, 0.6, 0.3, 30, -0.35, math.pi + 0.35), rgb(200, 30, 45))
    p.ell(0.4, 0.58, 0.07, 0.12, rgb(255, 120, 120), outline=False)
    p.poly([(0.6, 0.62), (0.7, 0.62), (0.66, 0.84)], WHITE)
    p.ell(0.5, 0.94, 0.26, 0.04, rgb(140, 20, 30), outline=False)
    return p


def ruana_llorona():
    p = Pic(128)
    p.poly([(0.3, 0.14), (0.7, 0.14), (0.92, 0.6), (0.78, 0.9), (0.5, 0.78), (0.22, 0.9), (0.08, 0.6)],
           rgb(190, 215, 240))
    p.poly([(0.42, 0.14), (0.58, 0.14), (0.5, 0.46)], rgb(60, 70, 100))
    p.detail([(0.22, 0.5), (0.3, 0.84)], 0.014, rgb(130, 160, 200))
    p.detail([(0.78, 0.5), (0.7, 0.84)], 0.014, rgb(130, 160, 200))
    p.poly([(0.5, 0.48)] + circle_pts(0.5, 0.62, 0.08, 16, -0.4, math.pi + 0.4), rgb(110, 200, 255))
    return p


def mecha_tejo():
    p = Pic(128)
    p.ell(0.44, 0.66, 0.34, 0.2, rgb(150, 155, 170))
    p.ell(0.44, 0.62, 0.26, 0.13, rgb(190, 195, 210), outline=False)
    p.poly([(0.56, 0.18), (0.86, 0.3), (0.62, 0.52)], WHITE)
    p.poly([(0.6, 0.26), (0.78, 0.32), (0.64, 0.44)], rgb(220, 40, 40), outline=False)
    p.poly(star(0.74, 0.16, 0.16, 0.06, 6), rgb(255, 180, 50))
    p.poly(star(0.74, 0.16, 0.08, 0.03, 6), rgb(255, 245, 170), outline=False)
    return p


def sombrero_vueltiao():
    p = Pic(128)
    p.ell(0.5, 0.66, 0.44, 0.17, rgb(245, 235, 200))
    p.poly([(0.3, 0.64), (0.34, 0.3), (0.5, 0.22), (0.66, 0.3), (0.7, 0.64)], rgb(245, 235, 200))
    for y in (0.36, 0.46, 0.56):
        p.detail([(0.33, y), (0.67, y)], 0.03, INK)
    p.detail([(0.16, 0.7), (0.5, 0.76), (0.84, 0.7)], 0.02, INK)
    p.detail([(0.42, 0.41), (0.5, 0.36), (0.58, 0.41)], 0.012, rgb(245, 235, 200))
    return p


def collar_madremonte():
    p = Pic(128)
    p.line(circle_pts(0.5, 0.36, 0.34, 24, 0.25, math.pi - 0.25), 0.03, rgb(110, 80, 45))
    for k, t in enumerate((0.35, 0.8, 1.25, 1.7, 2.15, 2.6)):
        x, y = 0.5 + math.cos(t) * 0.34, 0.36 + math.sin(t) * 0.34
        p.poly(lens((x, y), (x + math.cos(t + 1.2) * 0.14, y + math.sin(t + 1.2) * 0.14), 0.05),
               rgb(80, 170, 70) if k % 2 else rgb(120, 200, 90))
    p.poly(lens((0.5, 0.66), (0.5, 0.96), 0.12), rgb(60, 150, 70))
    p.detail([(0.5, 0.68), (0.5, 0.92)], 0.014, rgb(30, 90, 40))
    p.ell(0.5, 0.7, 0.06, 0.06, rgb(230, 80, 120))
    return p


def ojo_candileja():
    p = Pic(128)
    p.poly([(0.5, 0.02), (0.68, 0.2), (0.86, 0.16), (0.84, 0.4), (0.96, 0.6), (0.82, 0.86), (0.5, 0.96),
            (0.18, 0.86), (0.04, 0.6), (0.16, 0.4), (0.14, 0.16), (0.32, 0.2)], rgb(255, 128, 40))
    p.poly(lens((0.18, 0.58), (0.82, 0.58), 0.2), rgb(255, 230, 120))
    p.ell(0.5, 0.58, 0.13, 0.13, rgb(220, 40, 20))
    p.poly([(0.5, 0.46), (0.53, 0.58), (0.5, 0.7), (0.47, 0.58)], INK)
    return p


def hamaca_abuelo():
    p = Pic(128)
    p.line([(0.06, 0.2), (0.06, 0.9)], 0.04, rgb(120, 80, 45))
    p.line([(0.94, 0.2), (0.94, 0.9)], 0.04, rgb(120, 80, 45))
    p.poly([(0.08, 0.3), (0.3, 0.36), (0.5, 0.38), (0.7, 0.36), (0.92, 0.3), (0.8, 0.5), (0.5, 0.66),
            (0.2, 0.5)], rgb(220, 70, 60))
    for k, col in enumerate((rgb(250, 200, 70), rgb(60, 140, 200))):
        y = 0.44 + 0.08 * k
        p.detail([(0.18 + 0.04 * k, y), (0.5, y + 0.1), (0.82 - 0.04 * k, y)], 0.026, col)
    return p


def pacto_patasola():
    p = Pic(128)
    p.poly([(0.16, 0.1), (0.84, 0.1), (0.84, 0.9), (0.16, 0.9)], rgb(235, 220, 180))
    p.ell(0.5, 0.1, 0.36, 0.05, rgb(200, 180, 140))
    p.ell(0.5, 0.9, 0.36, 0.05, rgb(200, 180, 140))
    for y in (0.24, 0.32, 0.4):
        p.detail([(0.26, y), (0.74, y)], 0.012, rgb(150, 130, 100))
    p.poly([(0.44, 0.48), (0.56, 0.48), (0.56, 0.66), (0.66, 0.74), (0.62, 0.8), (0.44, 0.74)], rgb(60, 120, 60))
    p.ell(0.68, 0.62, 0.07, 0.07, rgb(200, 30, 40))
    return p


def moneda_duende():
    p = Pic(128)
    p.ell(0.38, 0.58, 0.3, 0.3, GOLD)
    p.ell(0.38, 0.58, 0.2, 0.2, rgb(250, 215, 100), outline=False)
    p.poly([(0.38, 0.4), (0.48, 0.58), (0.38, 0.76), (0.28, 0.58)], GOLD_D)
    p.ell(0.72, 0.36, 0.22, 0.22, GOLD)
    p.ell(0.72, 0.36, 0.14, 0.14, rgb(250, 215, 100), outline=False)
    p.poly(star(0.8, 0.12, 0.09, 0.035, 4), WHITE)
    return p


# ── activas ──

def totumo_polvora():
    p = Pic(128)
    p.ell(0.46, 0.6, 0.34, 0.32, rgb(110, 140, 60))
    p.ell(0.36, 0.5, 0.08, 0.1, rgb(160, 190, 90), outline=False)
    p.rect(0.48, 0.24, 0.6, 0.32, rgb(110, 75, 45))
    p.line([(0.54, 0.24), (0.62, 0.14), (0.72, 0.12)], 0.022, rgb(220, 200, 150))
    p.poly(star(0.78, 0.1, 0.12, 0.05, 6), rgb(255, 170, 50))
    p.detail([(0.3, 0.72), (0.5, 0.8), (0.66, 0.72)], 0.016, rgb(70, 95, 40))
    return p


def silbido_mohan():
    p = Pic(128)
    p.poly([(0.08, 0.5), (0.5, 0.42), (0.5, 0.62), (0.08, 0.58)], rgb(150, 100, 60))
    p.ell(0.56, 0.58, 0.16, 0.16, rgb(170, 115, 65))
    p.ell(0.56, 0.58, 0.06, 0.06, INK, outline=False)
    for r in (0.18, 0.28):
        p.detail(circle_pts(0.62, 0.44, r, 10, -1.3, -0.1), 0.022, rgb(120, 220, 255))
    p.ell(0.86, 0.82, 0.05, 0.05, rgb(80, 200, 255))
    p.ell(0.74, 0.9, 0.035, 0.035, rgb(80, 200, 255))
    return p


def tamal_emergencia():
    p = Pic(128)
    p.poly([(0.12, 0.5), (0.3, 0.2), (0.7, 0.2), (0.88, 0.5), (0.7, 0.82), (0.3, 0.82)], rgb(60, 140, 60))
    p.poly([(0.3, 0.32), (0.7, 0.32), (0.76, 0.5), (0.7, 0.7), (0.3, 0.7), (0.24, 0.5)], rgb(250, 205, 90))
    p.poly([(0.12, 0.5), (0.3, 0.2), (0.4, 0.5), (0.3, 0.82)], rgb(80, 170, 75))
    p.poly([(0.88, 0.5), (0.7, 0.2), (0.6, 0.5), (0.7, 0.82)], rgb(80, 170, 75))
    p.detail([(0.5, 0.18), (0.5, 0.84)], 0.022, rgb(230, 215, 170))
    p.detail([(0.4, 0.5), (0.6, 0.5)], 0.022, rgb(230, 215, 170))
    p.rect(0.44, 0.08, 0.56, 0.16, rgb(230, 60, 60))
    p.rect(0.47, 0.05, 0.53, 0.19, rgb(230, 60, 60), outline=False)
    return p


def trompo_guerra():
    p = Pic(128)
    p.poly([(0.16, 0.36), (0.84, 0.36), (0.54, 0.9), (0.46, 0.9)], rgb(210, 55, 45))
    p.ell(0.5, 0.36, 0.34, 0.1, rgb(240, 90, 70))
    p.poly([(0.22, 0.46), (0.78, 0.46), (0.73, 0.54), (0.27, 0.54)], rgb(250, 205, 70), outline=False)
    p.rect(0.45, 0.1, 0.55, 0.32, rgb(110, 70, 40))
    p.line([(0.46, 0.9), (0.5, 0.98)], 0.02, rgb(150, 155, 170))
    for r in (0.42, 0.48):
        p.detail(circle_pts(0.5, 0.62, r, 8, math.radians(200), math.radians(250)), 0.016, rgb(250, 240, 210))
    return p


def machete_relampago():
    p = Pic(128)
    a = Axis((0.16, 0.86), (0.88, 0.12))
    p.poly(a.pts([(0.3, -0.04), (0.9, -0.1), (1.0, 0.0), (0.92, 0.07), (0.3, 0.06)]), rgb(215, 225, 245))
    p.poly(a.rect(0.0, 0.3, -0.06, 0.06), rgb(60, 45, 35))
    p.poly([(0.66, 0.5), (0.8, 0.5), (0.72, 0.62), (0.86, 0.62), (0.6, 0.92), (0.68, 0.72), (0.56, 0.72)],
           rgb(255, 225, 60))
    p.detail([a(0.35, 0.0), a(0.85, -0.05)], 0.012, WHITE)
    return p


def garrafon_aguardiente():
    p = Pic(128)
    p.line([(0.62, 0.2), (0.84, 0.24), (0.86, 0.46), (0.7, 0.5)], 0.035, rgb(130, 90, 50))
    p.rect(0.38, 0.06, 0.54, 0.18, rgb(200, 60, 50))
    p.poly([(0.38, 0.18), (0.54, 0.18), (0.8, 0.4), (0.84, 0.86), (0.72, 0.94), (0.2, 0.94), (0.08, 0.86),
            (0.12, 0.4)], rgb(170, 220, 200))
    p.rect(0.22, 0.5, 0.7, 0.8, rgb(240, 225, 180))
    p.poly(star(0.46, 0.65, 0.12, 0.05, 5), rgb(220, 60, 50))
    p.detail([(0.16, 0.44), (0.14, 0.84)], 0.02, WHITE)
    return p


def campana_iglesia():
    p = Pic(128)
    p.poly([(0.36, 0.18), (0.64, 0.18), (0.7, 0.5), (0.86, 0.76), (0.14, 0.76), (0.3, 0.5)], GOLD)
    p.rect(0.12, 0.74, 0.88, 0.82, GOLD_D)
    p.ell(0.5, 0.88, 0.08, 0.07, rgb(120, 90, 40))
    p.line([(0.44, 0.18), (0.5, 0.06), (0.56, 0.18)], 0.03, rgb(110, 80, 40))
    p.detail([(0.36, 0.3), (0.3, 0.66)], 0.018, rgb(255, 235, 150))
    for s in (-1, 1):
        p.detail([(0.5 + s * 0.4, 0.3), (0.5 + s * 0.46, 0.4)], 0.02, rgb(120, 220, 255))
        p.detail([(0.5 + s * 0.38, 0.5), (0.5 + s * 0.48, 0.54)], 0.02, rgb(120, 220, 255))
    return p


# ── amuletos de la mazmorra (EquipmentDB "amuleto", activa de la E): todos cuelgan de un cordón ──

CORD = rgb(140, 90, 50)


def _cord(p, x0=0.22, x1=0.78, bottom=0.3):
    p.line([(x0, 0.04), (0.5, bottom), (x1, 0.04)], 0.02, CORD)


def pata_conejo():
    p = Pic(128)
    _cord(p, bottom=0.22)
    p.rect(0.4, 0.2, 0.6, 0.32, GOLD)
    p.detail([(0.42, 0.26), (0.58, 0.26)], 0.012, GOLD_D)
    p.poly(lens((0.5, 0.3), (0.5, 0.94), 0.2), rgb(225, 200, 165))
    for dx in (-0.12, 0.0, 0.12):
        p.ell(0.5 + dx, 0.86, 0.075, 0.08, rgb(245, 235, 220))
    p.detail([(0.38, 0.44), (0.36, 0.7)], 0.016, WHITE)
    for y in (0.48, 0.6):
        p.detail([(0.56, y), (0.62, y + 0.05)], 0.012, rgb(170, 140, 110))
    return p


def botella_aguardiente():
    p = Pic(128)
    _cord(p, 0.3, 0.7, bottom=0.3)
    p.rect(0.43, 0.12, 0.57, 0.22, rgb(200, 60, 50))
    p.rect(0.44, 0.21, 0.56, 0.36, rgb(150, 205, 120))
    p.ell(0.5, 0.64, 0.27, 0.29, rgb(150, 205, 120))
    p.ell(0.5, 0.68, 0.17, 0.13, rgb(240, 225, 180))
    p.poly(star(0.5, 0.68, 0.09, 0.04, 5), rgb(220, 60, 50))
    p.detail([(0.3, 0.52), (0.29, 0.72)], 0.02, WHITE)
    p.detail([(0.43, 0.3), (0.57, 0.3)], 0.014, CORD)
    return p


def espejo_mohan():
    p = Pic(128)
    _cord(p, bottom=0.18)
    p.ell(0.5, 0.18, 0.06, 0.05, GOLD)
    p.ell(0.5, 0.56, 0.36, 0.36, rgb(60, 140, 100))
    for k in range(8):
        a = k * math.tau / 8
        p.ell(0.5 + math.cos(a) * 0.36, 0.56 + math.sin(a) * 0.36, 0.045, 0.045, GOLD)
    p.ell(0.5, 0.56, 0.26, 0.26, rgb(170, 225, 240))
    p.poly(lens((0.36, 0.56), (0.64, 0.56), 0.08), WHITE)
    p.ell(0.5, 0.56, 0.06, 0.06, rgb(60, 140, 100))
    p.detail([(0.33, 0.44), (0.42, 0.36)], 0.022, WHITE)
    p.detail([(0.62, 0.74), (0.68, 0.66)], 0.016, WHITE)
    return p


def pluma_gallinazo():
    p = Pic(128)
    _cord(p, 0.12, 0.62, bottom=0.2)
    p.poly(lens((0.36, 0.22), (0.72, 0.94), 0.17), rgb(45, 40, 50))
    p.poly(lens((0.48, 0.46), (0.72, 0.94), 0.07), rgb(95, 90, 105))
    p.detail([(0.36, 0.22), (0.72, 0.93)], 0.018, rgb(150, 145, 155))
    for t in (0.35, 0.5, 0.65, 0.8):
        x, y = 0.36 + 0.36 * t, 0.22 + 0.72 * t
        p.detail([(x, y), (x + 0.1, y - 0.03)], 0.012, rgb(110, 105, 120))
    p.ell(0.37, 0.24, 0.06, 0.06, rgb(200, 60, 50))
    p.detail([(0.35, 0.22), (0.38, 0.21)], 0.012, WHITE)
    return p


AMULETS = {
    "pata_conejo": pata_conejo, "botella_aguardiente": botella_aguardiente,
    "espejo_mohan": espejo_mohan, "pluma_gallinazo": pluma_gallinazo,
}
OUT_AMULETS = os.path.join(ROOT, "assets", "ui", "icons", "amulets")


ITEMS = {
    "botas_caminante": botas_caminante, "pluma_condor": pluma_condor, "alas_colibri": alas_colibri,
    "aguardiente_bendito": aguardiente_bendito, "reloj_pendulo_roto": reloj_pendulo_roto,
    "carcaj_encantado": carcaj_encantado, "doble_filo": doble_filo, "mango_hierro": mango_hierro,
    "polvora_gruesa": polvora_gruesa, "mochila_cuero": mochila_cuero, "colmillo_jaguar": colmillo_jaguar,
    "poncho_reforzado": poncho_reforzado, "corazon_ceiba": corazon_ceiba, "vela_anima": vela_anima,
    "ojo_mohan_comun": ojo_mohan_comun, "duende_travieso": duende_travieso, "mascara_tryhard": mascara_tryhard,
    "amuleto_tumbaga": amuleto_tumbaga,
    "totuma_chicha": totuma_chicha, "sangre_mohan": sangre_mohan, "ruana_llorona": ruana_llorona,
    "mecha_tejo": mecha_tejo, "sombrero_vueltiao": sombrero_vueltiao, "collar_madremonte": collar_madremonte,
    "ojo_candileja": ojo_candileja, "hamaca_abuelo": hamaca_abuelo, "pacto_patasola": pacto_patasola,
    "moneda_duende": moneda_duende,
    "totumo_polvora": totumo_polvora, "silbido_mohan": silbido_mohan, "tamal_emergencia": tamal_emergencia,
    "trompo_guerra": trompo_guerra, "machete_relampago": machete_relampago,
    "garrafon_aguardiente": garrafon_aguardiente, "campana_iglesia": campana_iglesia,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    os.makedirs(OUT_AMULETS, exist_ok=True)
    jobs = [(OUT, n, f) for n, f in ITEMS.items()] + [(OUT_AMULETS, n, f) for n, f in AMULETS.items()]
    for out_dir, name, fn in jobs:
        path = os.path.join(out_dir, name + ".png")
        fn().render().save(path)
        made.append(path)
        print("guardado", os.path.relpath(path, ROOT))
    if len(sys.argv) > 1:
        cols = 7
        rows = (len(made) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * 136, rows * 136), (110, 104, 92, 255))
        for k, path in enumerate(made):
            sheet.alpha_composite(Image.open(path).convert("RGBA"), ((k % cols) * 136 + 4, (k // cols) * 136 + 4))
        sheet.save(sys.argv[1])
        print("hoja", sys.argv[1])


if __name__ == "__main__":
    main()
