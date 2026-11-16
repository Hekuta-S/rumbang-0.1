"""Texturas cartoon del personaje con la TINTA HORNEADA (una lectura por material).

    python tools/make_riva_toon_textures.py

Combina los horneados de tools/blender_riva_toon_bake.py con las texturas del personaje
(assets/textures/entities/riva/humano/):
  piel_toon.png   RGB = detalle de la piel (piel.png) × sombra cel, con tinta en pliegues y contorno de
                  labios y areolas; A = máscara de cejas (antes piel_mask.png). Sustituye a 4 texturas.
  ojos_toon.png   ojos con el aro del iris entintado (A = máscara del iris, como antes).
"""
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "assets", "textures", "entities", "riva", "humano")


def load(name, size, mode="RGB"):
    return np.asarray(Image.open(os.path.join(D, name)).convert(mode).resize((size, size), Image.LANCZOS), np.float32) / 255.0


def gblur(a, r):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), np.float32) / 255.0


def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def crease_ink(mask):
    """Tinta solo en pliegues finos. Las manchas grandes (muslos que se tocan en la pose de reposo, costados
    bajo el brazo) no son un trazo: ahí se quita la tinta y se devuelve una sombra suave en su lugar."""
    solid = smooth(gblur(mask, 12.0), 0.45, 0.6)
    near = smooth(gblur(solid, 10.0), 0.02, 0.15)
    line = smooth(gblur(mask, 1.3), 0.3, 0.55) * (1.0 - near)
    return line, near


def skin():
    n = 1024
    bake = load("_piel_bake.png", n)
    detail = load("piel.png", n)
    brows = load("piel_mask.png", n)[..., 0]
    covered = bake.max(axis=2) > 0.02
    shade = gblur(np.where(covered, bake[..., 0], 1.0), 1.2)     # fuera de las islas: sin sombra (no ensucia el borde)
    ink, blob = crease_ink(bake[..., 1])
    shade = shade * (1.0 - 0.2 * blob)
    # contorno de labios, areolas y mejillas marcadas: bordes de las zonas con color en piel.png
    base = np.median(detail.reshape(-1, 3), axis=0)
    feat = smooth(np.abs(detail - base).sum(axis=2), 0.1, 0.18)
    edge = np.clip(gblur(feat, 2.2) * 2.0, 0, 1)
    feat_ink = smooth(edge * (1.0 - edge) * 4.0, 0.55, 0.9) * 0.8
    ink = np.clip(np.maximum(ink, feat_ink), 0, 1)[..., None]
    # sombra algo más cálida que un gris (rojo baja menos)
    sh = np.stack([shade ** 0.85, shade ** 1.1, shade ** 1.25], axis=2)
    rgb = detail * sh
    rgb = rgb * (1 - ink) + detail * np.array([0.3, 0.16, 0.15], np.float32) * ink
    out = np.concatenate([rgb, brows[..., None]], axis=2)
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(D, "piel_toon.png"))
    print("piel_toon.png  tinta %.2f%%" % (ink.mean() * 100))


def eyes():
    im = Image.open(os.path.join(D, "ojos.png")).convert("RGBA")
    a = np.asarray(im, np.float32) / 255.0
    m = a[..., 3]
    soft = gblur(m, 3.0)
    ring = smooth(soft * (1.0 - soft) * 4.0, 0.5, 0.9)[..., None]
    rgb = a[..., :3] * (1 - ring * 0.85)
    out = np.concatenate([rgb, m[..., None]], axis=2)
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(D, "ojos_toon.png"))
    print("ojos_toon.png")


if __name__ == "__main__":
    skin()
    eyes()
