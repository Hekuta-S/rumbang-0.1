"""Texturas de los hongos de las Cavernas a partir del atlas de hongo_fab.glb (CC-BY 4.0, Diego Duarte).

Uso: python tools/make_mushroom_textures.py <atlas_basecolor.png> [salida_dir]
  -> mushroom_albedo.png (atlas sin el logo "H": el sombrero pequeño recibe una copia reducida del
     sombrero grande, con sus manchas) y mushroom_glow.png (máscara de las manchas que brillan).
Las coordenadas son las del atlas original de 1024x1024.
"""
import sys, os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIG_CAP = ((822, 841), 192)      # (centro, radio) del sombrero grande (con manchas)
SMALL_CAP = ((550, 628), 146)    # sombrero pequeño (con el logo "H")
CAPS = [BIG_CAP, SMALL_CAP]


def disc_mask(shape, center, r, feather=3.0):
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    d = np.hypot(xx - center[0], yy - center[1])
    return np.clip((r - d) / feather, 0, 1)


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "assets", "textures", "mushrooms")
    os.makedirs(out, exist_ok=True)
    img = Image.open(src).convert("RGB")
    a = np.asarray(img, dtype=np.float64) / 255.0
    # Copia del sombrero grande, girada 70° y reducida al radio del pequeño, encima del logo
    (bc, br), (sc, sr) = BIG_CAP, SMALL_CAP
    big = img.crop((bc[0] - br, bc[1] - br, bc[0] + br, bc[1] + br)).rotate(70, resample=Image.BICUBIC)
    big = big.resize((2 * sr, 2 * sr), Image.LANCZOS)
    patch = np.zeros_like(a)
    patch[sc[1] - sr:sc[1] + sr, sc[0] - sr:sc[0] + sr] = np.asarray(big, dtype=np.float64) / 255.0
    m = disc_mask(a.shape[:2], sc, sr + 1, 3.0)[..., None]
    a = a * (1 - m) + patch * m
    Image.fromarray((a * 255).astype(np.uint8)).save(os.path.join(out, "mushroom_albedo.png"))
    # Máscara de brillo: manchas claras y poco saturadas dentro de los sombreros
    lum = a.mean(axis=2)
    sat = a.max(axis=2) - a.min(axis=2)
    spots = np.clip((lum - 0.74) / 0.08, 0, 1) * np.clip((0.16 - sat) / 0.06, 0, 1)
    inside = np.zeros(lum.shape)
    for c, r in CAPS:
        inside = np.maximum(inside, disc_mask(lum.shape, c, r - 6, 3.0))
    glow = spots * inside
    g = Image.fromarray((glow * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))
    g.save(os.path.join(out, "mushroom_glow.png"))
    print("ok", out, "cobertura brillo %.3f" % (np.asarray(g).mean() / 255.0))


if __name__ == "__main__":
    main()
