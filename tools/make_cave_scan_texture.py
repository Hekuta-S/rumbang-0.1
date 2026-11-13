"""Textura de pared de caverna estilizada a partir del atlas del escaneo de la Gruta do Janelão.

Uso: python tools/make_cave_scan_texture.py <atlas.png> [salida_dir]
  <atlas.png>  textura del .glb del escaneo (Image_0, 1024x1024), extraída con Blender.
  salida_dir   por defecto assets/textures/dungeon/

Genera cave_scan_albedo.png / cave_scan_normal.png (1024, tileables) para cave_rock.gdshader:
  1. recorta varias zonas limpias de roca del atlas (sin huecos borrosos del atlas),
  2. las vuelve casi grises (el shader tiñe con la paleta del nivel; las pinturas rojas desaparecen),
  3. estiliza: filtro de moda/mediana + posterizado suave + líneas oscuras en las grietas,
  4. las hace tileables (cruce de 4 copias desplazadas medio tile),
  5. iguala la media a rock_albedo.png (para que tint_gain del shader siga valiendo),
  6. normal map desde la luminancia (Sobel).
"""
import sys, os
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = 1024
# Zonas del atlas (x0, y0, x1, y1) con roca bien escaneada
PATCHES = [(425, 160, 685, 410), (80, 250, 330, 500), (610, 40, 860, 290)]
LEVELS = 7          # niveles de luminancia del posterizado
POSTER_MIX = 0.55   # 0 = foto, 1 = posterizado duro
CRACK_DARK = 0.35   # cuánto oscurecen las grietas
CONTRAST = 0.55     # contraste final de la luminancia (1 = estirado al 2-98%)


def lum(a):
    return a @ np.array([0.299, 0.587, 0.114])


def seamless(a, band=0.45):
    """Tileable por ejes: en cada eje mezcla la imagen con su copia desplazada medio tile, usando la
    copia solo cerca del borde (donde la original tiene la costura). La costura de la copia queda en el
    centro, donde manda la original. Primero en X y luego en Y."""
    for axis in (1, 0):
        n = a.shape[axis]
        t = np.abs(np.linspace(-1, 1, n))                       # 0 centro, 1 borde
        m = np.clip((1.0 - t) / band, 0, 1)
        m = m * m * (3 - 2 * m)                                 # smoothstep: 1 centro, 0 borde
        m = m[None, :, None] if axis == 1 else m[:, None, None]
        a = a * m + np.roll(a, n // 2, axis) * (1 - m)
    return a


def wrap_filter(a, fn):
    """Aplica un filtro PIL sobre la imagen repetida 3x3 y devuelve el centro: no rompe el tileado."""
    h, w = a.shape[:2]
    big = np.tile(a, (3, 3, 1) if a.ndim == 3 else (3, 3))
    im = fn(Image.fromarray((np.clip(big, 0, 1) * 255).astype(np.uint8)))
    return (np.asarray(im, dtype=np.float64) / 255.0)[h:2 * h, w:2 * w]


def patch_mosaic(atlas):
    """Compone una base de 512 con los parches (uno de fondo + los otros fundidos con máscaras suaves)."""
    tiles = []
    for p in PATCHES:
        t = atlas.crop(p).resize((512, 512), Image.BICUBIC)
        tiles.append(np.asarray(t, dtype=np.float64) / 255.0)
    base = tiles[0].copy()
    yy, xx = np.mgrid[0:512, 0:512] / 512.0
    rng = np.random.default_rng(7)
    for t in tiles[1:]:
        cx, cy = rng.uniform(0.25, 0.75, 2)
        m = np.clip(1.0 - np.hypot(xx - cx, yy - cy) / 0.35, 0, 1) ** 2
        base = base * (1 - m[..., None]) + t * m[..., None]
    return base


def main():
    src = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "assets", "textures", "dungeon")
    atlas = Image.open(src).convert("RGB")
    a = patch_mosaic(atlas)
    # Casi gris: conserva un 18% del color (variación cálida/fría sutil), las pinturas rojas se van
    l = lum(a)[..., None]
    a = l + (a - l) * 0.18
    a = seamless(a)
    # Estilizado: mediana (aplana el ruido fotográfico) + posterizado suave de la luminancia
    a = wrap_filter(a, lambda im: im.filter(ImageFilter.MedianFilter(7)).filter(ImageFilter.ModeFilter(5)))
    l = lum(a)
    lo, hi = np.percentile(l, 2), np.percentile(l, 98)
    ln = np.clip((l - lo) / (hi - lo), 0, 1)
    lp = np.round(ln * (LEVELS - 1)) / (LEVELS - 1)
    lmix = ln * (1 - POSTER_MIX) + lp * POSTER_MIX
    # Grietas: zonas bastante más oscuras que su entorno → líneas oscuras de "dibujo"
    blur = wrap_filter(ln, lambda im: im.filter(ImageFilter.GaussianBlur(6)))
    crack = np.clip((blur - ln - 0.08) * 6.0, 0, 1)
    lmix = lmix * (1 - crack * CRACK_DARK)
    lmix = lmix.mean() + (lmix - lmix.mean()) * CONTRAST
    a = a * ((lmix + 0.05) / (l + 0.05))[..., None]
    # Igualar la media de rock_albedo.png (en sRGB)
    ref_path = os.path.join(out_dir, "rock_albedo.png")
    ref = np.asarray(Image.open(ref_path).convert("RGB"), dtype=np.float64).mean((0, 1)) / 255.0 if os.path.exists(ref_path) else np.array([0.644, 0.62, 0.584])
    a = a * (ref / a.mean((0, 1)))
    a = np.clip(a, 0, 1)
    alb = Image.fromarray((a * 255).astype(np.uint8)).resize((OUT, OUT), Image.BICUBIC)
    alb.save(os.path.join(out_dir, "cave_scan_albedo.png"))
    # Normal map desde la altura (luminancia suavizada), tileable con np.roll
    hgt = np.asarray(alb.convert("L").filter(ImageFilter.GaussianBlur(2.5)), dtype=np.float64) / 255.0
    dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 0.5
    dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 0.5
    k = 9.0
    n = np.dstack([-dx * k, dy * k, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(out_dir, "cave_scan_normal.png"))
    print("ok", out_dir, "media", np.round(a.mean((0, 1)), 3))


if __name__ == "__main__":
    main()
