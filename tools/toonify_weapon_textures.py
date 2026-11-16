"""Texturas de las armas en estilo cartoon con la TINTA HORNEADA (una lectura por material).

    python tools/toonify_weapon_textures.py [filtro]

Recorre los .glb de assets/models/weapons y assets/models/katana, y de cada material toma el color base
(y, si existen, su normal map y su metal/rugosidad, que Godot extrae al lado del .glb como <glb>_<n>.png):
  - color en bandas planas (posterizado sin el grano de la foto);
  - relieve del normal map horneado como luz/sombra en bandas; en las zonas METÁLICAS, un brillo en banda
    (ya no hay especular en el material);
  - tinta en los saltos de relieve y en los bordes entre zonas de color.
Sale a assets/textures/toon/weapons/<nombre del color base>.png, como mucho a 1024 px. ToonWeapon.apply
(scripts/objects/toon_weapon.gd) cambia la textura al montar el arma y apaga normal map, metal y especular.
Los originales no se tocan.
"""
import glob
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")
OUT = os.path.join(ROOT, "assets", "textures", "toon", "weapons")
MAX_SIZE = 1024
INK = np.array([0.06, 0.05, 0.08], np.float32)


def read_gltf(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    return json.loads(b[20:20 + n])


def blur(a, sigma):
    """Desenfoque gaussiano por FFT (envuelve en los bordes; en un atlas de UV no importa)."""
    if a.ndim == 3:
        return np.stack([blur(a[..., c], sigma) for c in range(a.shape[2])], axis=2)
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    return np.fft.irfft2(np.fft.rfft2(a) * g, s=(h, w)).astype(np.float32)


def smooth(a, lo, hi):
    t = np.clip((a - lo) / max(hi - lo, 1e-6), 0, 1)
    return t * t * (3 - 2 * t)


def lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def load(path, size, mode="RGB"):
    return np.asarray(Image.open(path).convert(mode).resize(size, Image.LANCZOS), np.float32) / 255.0


def toonify(albedo, normal, orm, dst):
    src = Image.open(albedo)
    has_alpha = src.mode in ("RGBA", "LA", "P") and "A" in src.convert("RGBA").getbands()
    w, h = src.size
    sc = min(1.0, MAX_SIZE / max(w, h))
    size = (max(4, int(w * sc)), max(4, int(h * sc)))
    rgba = np.asarray(src.convert("RGBA").resize(size, Image.LANCZOS), np.float32) / 255.0
    a = rgba[..., :3]
    k = max(size) / 1024.0

    # Texturas ya estilizadas (paleta de colores planos, pixel art): se dejan como están. Posterizarlas les
    # cambia los colores y la tinta por gradiente las ensucia.
    flat = (np.abs(np.diff(a, axis=1)).sum(axis=2) < 0.004).mean()
    if flat > 0.8 or max(size) <= 256:
        return size, -1.0

    # color en bandas
    soft = blur(a, 1.6 * k)
    wide = blur(a, 3.5 * k)
    L = lum(soft)
    bands = 5
    qs = np.quantile(L, [(i + 1) / bands for i in range(bands - 1)])
    idx = np.digitize(L, qs)
    target = np.zeros_like(L)
    for b in range(bands):
        m = idx == b
        if m.any():
            target[m] = L[m].mean()
    target = blur(target, 0.7 * k)
    col = wide * (target / np.maximum(lum(wide), 1e-4))[..., None]

    # tinta entre zonas de color (bordes de la luminancia y del tono)
    gx = np.abs(np.roll(soft, -1, axis=1) - np.roll(soft, 1, axis=1)).sum(axis=2)
    gy = np.abs(np.roll(soft, -1, axis=0) - np.roll(soft, 1, axis=0)).sum(axis=2)
    grad = blur(np.hypot(gx, gy), 0.8 * k)
    ink = smooth(grad, np.quantile(grad, 0.93), np.quantile(grad, 0.985))

    metal = None
    if orm:
        metal = blur(load(orm, size)[..., 2], 1.5 * k)
    if metal is not None:
        # El color base de un metal es su reflejo (muy claro): sin especular se vería lavado. Se oscurece, y
        # el brillo lo ponen las bandas de luz de arriba.
        col = col * (1.0 - 0.45 * metal)[..., None]
    if normal:
        n = load(normal, size) * 2.0 - 1.0
        d = blur(-n[..., 0] * 0.6 + n[..., 1] * 0.8, 1.2 * k)
        hi_t = max(np.quantile(d, 0.88), 0.02)
        lo_t = min(np.quantile(d, 0.12), -0.02)
        light = smooth(d, hi_t * 0.8, hi_t)
        dark = smooth(-d, -lo_t * 0.8, -lo_t)
        gain = 0.16 if metal is None else 0.16 + 0.7 * metal        # brillo en banda sobre el metal
        col = col * (1.0 + gain * light - 0.22 * dark)[..., None]
        slope = blur(np.hypot(n[..., 0], n[..., 1]), 1.0 * k)
        if slope.max() > 0.05:
            ink = np.maximum(ink, smooth(slope, np.quantile(slope, 0.9), np.quantile(slope, 0.97)))
    ink = smooth(blur(ink, 1.6 * k), 0.34, 0.52)
    ink = blur(ink, 0.6 * k)[..., None] * 0.92
    out = np.clip(col * (1 - ink) + INK * ink, 0, 1)
    img = Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGB")
    if has_alpha and rgba[..., 3].min() < 0.99:
        img.putalpha(Image.fromarray((rgba[..., 3] * 255 + 0.5).astype(np.uint8), "L"))
    img.save(dst)
    return size, float(ink.mean() * 100)


def main():
    flt = sys.argv[1] if len(sys.argv) > 1 else ""
    os.makedirs(OUT, exist_ok=True)
    paths = sorted(glob.glob(os.path.join(MODELS, "weapons", "**", "*.glb"), recursive=True)
                   + glob.glob(os.path.join(MODELS, "katana", "*.glb")))
    done = set()
    for p in paths:
        if flt and flt not in p:
            continue
        g = read_gltf(p)
        base = os.path.splitext(p)[0]
        imgs, tex = g.get("images", []), g.get("textures", [])

        def find(ref):
            if ref is None:
                return None
            i = tex[ref["index"]].get("source")
            for ext in (".png", ".jpg", ".jpeg"):
                for key in (str(i), imgs[i].get("name", "?")):
                    c = "%s_%s%s" % (base, key, ext)
                    if os.path.exists(c):
                        return c
            return None

        for m in g.get("materials", []):
            pbr = m.get("pbrMetallicRoughness", {})
            sg = m.get("extensions", {}).get("KHR_materials_pbrSpecularGlossiness", {})
            alb = find(pbr.get("baseColorTexture")) or find(sg.get("diffuseTexture"))
            if alb is None or alb in done:
                continue
            done.add(alb)
            dst = os.path.join(OUT, os.path.splitext(os.path.basename(alb))[0] + ".png")
            size, pct = toonify(alb, find(m.get("normalTexture")), find(pbr.get("metallicRoughnessTexture")), dst)
            if pct < 0.0:
                for junk in (dst, dst + ".import"):
                    if os.path.exists(junk):
                        os.remove(junk)
                print("plana, sin cambios: %s" % os.path.basename(alb))
                continue
            print("toon %-44s %4dx%-4d tinta %.1f%%" % (os.path.basename(dst), size[0], size[1], pct))


if __name__ == "__main__":
    main()
