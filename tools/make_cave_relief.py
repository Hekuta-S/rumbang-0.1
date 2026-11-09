"""Mapa de relieve tileable (cave_scan_height.png) a partir de la profundidad del escaneo de la Gruta do Janelão.

Uso: python tools/make_cave_relief.py <scan_depth.npy> [salida.png]
  scan_depth.npy: rejilla (alto x ancho) con la coordenada Y del escaneo vista desde +Y (NaN = sin datos),
  sacada en Blender con raycasts (ver tools/blender_cave_relief.py).
DungeonMap lo usa para desplazar la carcasa de la cueva (paredes y techo): 0.5 = sin desplazamiento.
"""
import sys, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 256


def blur(a, sigma):
    """Desenfoque gaussiano periódico (FFT): sirve también para que el resultado tilee."""
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def seamless(a, band=0.45):
    for axis in (1, 0):
        n = a.shape[axis]
        t = np.abs(np.linspace(-1, 1, n))
        m = np.clip((1.0 - t) / band, 0, 1)
        m = m * m * (3 - 2 * m)
        m = m[None, :] if axis == 1 else m[:, None]
        a = a * m + np.roll(a, n // 2, axis) * (1 - m)
    return a


def main():
    d = np.load(sys.argv[1])
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "assets", "textures", "dungeon", "cave_scan_height.png")
    valid = ~np.isnan(d)
    d = np.where(valid, d, np.nanmean(d))
    # Rellenar huecos con la media local de los datos válidos
    for _ in range(6):
        num = blur(np.where(valid, d, 0.0), 6)
        den = blur(valid.astype(float), 6)
        d = np.where(valid, d, num / np.maximum(den, 1e-3))
    # Paso alto: fuera la curvatura grande de la pared, queda el relieve de 0.3-3 m
    hp = d - blur(d, 40)
    hp = blur(hp, 1.2)
    img = Image.fromarray(hp.astype(np.float32), mode="F").resize((SIZE, SIZE), Image.BICUBIC)
    hp = seamless(np.asarray(img, dtype=np.float64))
    lo, hi = np.percentile(hp, 1), np.percentile(hp, 99)
    m = max(abs(lo), abs(hi))
    v = np.clip(hp / m * 0.5 + 0.5, 0, 1)   # el escaneo mira a +Y: más Y = sobresale hacia la cueva
    Image.fromarray((v * 255).astype(np.uint8), mode="L").save(out)
    print("ok", out, "rango m", round(lo, 3), round(hi, 3))


if __name__ == "__main__":
    main()
