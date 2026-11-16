"""Fuente de cómic para los números de daño: letras ya ENTINTADAS (contorno grueso y sombra dura) en un
atlas BMFont que Godot importa como fuente.

    python tools/make_comic_font.py

Sale assets/fonts/comic_dmg.png + comic_dmg.fnt. Cada letra va inclinada, con relleno BLANCO, una franja
inferior gris clara (sombreado cel), contorno de tinta y sombra dura desplazada: el Label3D la tiñe con su
`modulate` (cada tipo de golpe conserva su color) y la tinta sigue negra. La usa FloatingDamage.
Misma letra que las onomatopeyas (tools/make_comic_words.py).
"""
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "fonts")
FONT = r"C:\Windows\Fonts\impact.ttf"
SIZE = 64                   # tamaño base de la fuente (px)
INK = (14, 10, 20, 255)
OUTLINE = 6                 # px de contorno
SHADOW = (4, 5)
SHEAR = 0.16                # inclinación hacia delante
CHARS = "0123456789.,:+-x%/!¡?¿ABCDEFGHIJKLMNOPQRSTUVWXYZÁÉÍÓÚÑÜ "
PAD = OUTLINE + 6


def glyph(font, ch):
    """Imagen RGBA de una letra entintada y su avance horizontal."""
    adv = font.getlength(ch)
    asc, desc = font.getmetrics()
    w = int(adv + SIZE * SHEAR + PAD * 2 + SHADOW[0]) + 2
    h = asc + desc + PAD * 2 + SHADOW[1]
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((PAD + SIZE * SHEAR * 0.5, PAD), ch, font=font, fill=255)
    # inclinación de cómic (el pie se queda, la cabeza avanza)
    base_y = PAD + asc
    mask = mask.transform((w, h), Image.AFFINE, (1, SHEAR, -SHEAR * base_y, 0, 1, 0), resample=Image.BICUBIC)
    grown = mask.filter(ImageFilter.MaxFilter(OUTLINE * 2 + 1)).filter(ImageFilter.GaussianBlur(0.6))
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    img.paste(Image.new("RGBA", (w, h), INK), SHADOW, grown)       # sombra dura
    img.paste(Image.new("RGBA", (w, h), INK), (0, 0), grown)       # contorno
    # relleno: blanco arriba, gris claro en el tercio de abajo (cel), y un brillo fino arriba
    fill = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    d = ImageDraw.Draw(fill)
    d.rectangle([0, PAD + int(asc * 0.62), w, h], fill=(196, 196, 206, 255))
    img.paste(fill, (0, 0), mask)
    hi = ImageChops.subtract(mask, ImageChops.offset(mask, 0, 4))
    img.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), (0, 0), hi)
    return img, adv


def main():
    os.makedirs(OUT, exist_ok=True)
    font = ImageFont.truetype(FONT, SIZE)
    asc, desc = font.getmetrics()
    glyphs = [(ch, *glyph(font, ch)) for ch in CHARS]
    # empaquetado en filas
    atlas_w = 2048                  # dos filas: 2048x256
    x = y = row_h = 0
    places = []
    for ch, img, adv in glyphs:
        if x + img.width > atlas_w:
            x = 0
            y += row_h + 2
            row_h = 0
        places.append((ch, img, adv, x, y))
        x += img.width + 2
        row_h = max(row_h, img.height)
    atlas_h = 1
    while atlas_h < y + row_h:
        atlas_h *= 2
    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))
    lines = []
    for ch, img, adv, gx, gy in places:
        atlas.paste(img, (gx, gy))
        # las letras se solapan un poco (contorno común), como en un rótulo de cómic
        xadv = int(round(adv + OUTLINE * 0.6))
        lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15"
                     % (ord(ch), gx, gy, img.width, img.height, -PAD, -PAD, xadv))
    atlas.save(os.path.join(OUT, "comic_dmg.png"))
    fnt = ['info face="ComicDmg" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 '
           'padding=0,0,0,0 spacing=0,0 outline=0' % SIZE,
           'common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 '
           'blueChnl=0' % (asc + desc, asc, atlas_w, atlas_h),
           'page id=0 file="comic_dmg.png"',
           'chars count=%d' % len(lines)] + lines
    open(os.path.join(OUT, "comic_dmg.fnt"), "w", encoding="utf-8").write("\n".join(fnt) + "\n")
    print("guardado assets/fonts/comic_dmg.fnt (%d letras, atlas %dx%d)" % (len(lines), atlas_w, atlas_h))


if __name__ == "__main__":
    main()
