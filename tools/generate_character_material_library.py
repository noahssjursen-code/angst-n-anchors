"""Build the reusable character/workwear texture library.

These are deliberately small, deterministic material maps rather than painted
costume pictures. JSON meshes provide the silhouette; the maps provide knit,
twill, oilskin, rubber, leather, and weathered-skin surface character. Palette
masks keep every material recolourable for company uniforms.
"""

from __future__ import annotations

from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "resources" / "textures" / "materials"
SIZE = 512


def _save(relative: str, image: Image.Image, mask: Image.Image) -> None:
    path = OUT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    mask.save(path.with_name(path.stem + "_mask.png"), optimize=True)
    print(path)


def _noise(seed: int, base: int, spread: int = 12) -> Image.Image:
    rng = random.Random(seed)
    image = Image.new("RGB", (SIZE, SIZE), (base, base, base))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            value = max(0, min(255, base + rng.randint(-spread, spread)))
            pixels[x, y] = (value, value, value)
    return image


def fine_nordic_knit() -> None:
    image = _noise(1905, 207, 9)
    mask = Image.new("RGB", (SIZE, SIZE), (255, 0, 0))
    draw = ImageDraw.Draw(image)
    mask_draw = ImageDraw.Draw(mask)

    # Dense black-and-white lice pattern from the supplied reference. The
    # repeated one-stitch marks remain readable without becoming a large yoke.
    for y in range(44, 456, 9):
        offset = 4 if (y // 9) % 2 else 0
        for x in range(-8, SIZE + 8, 10):
            px = x + offset
            draw.rectangle((px, y, px + 2, y + 3), fill=(76, 76, 76))
            mask_draw.rectangle((px, y, px + 2, y + 3), fill=(0, 255, 0))
            draw.point((px + 3, y + 1), fill=(120, 120, 120))
            mask_draw.point((px + 3, y + 1), fill=(0, 255, 0))

    # The fitted collar uses the top strip; cuffs and hem use the bottom. This
    # produces the exact striped ribbing of the reference without extra meshes.
    for y0, y1 in ((0, 43), (457, 511)):
        draw.rectangle((0, y0, SIZE - 1, y1), fill=(218, 218, 218))
        mask_draw.rectangle((0, y0, SIZE - 1, y1), fill=(255, 0, 0))
        stripe = 6
        for y in range(y0 + 3, y1, 13):
            draw.rectangle((0, y, SIZE - 1, min(y + stripe, y1)), fill=(64, 64, 64))
            mask_draw.rectangle((0, y, SIZE - 1, min(y + stripe, y1)), fill=(0, 255, 0))
    _save("knit/fine_nordic_knit.png", image, mask)


def plain_wool() -> None:
    image = _noise(1989, 178, 18)
    draw = ImageDraw.Draw(image)
    for y in range(0, SIZE, 5):
        shade = 152 if (y // 5) % 2 else 199
        draw.line((0, y, SIZE, y), fill=(shade, shade, shade), width=1)
    mask = Image.new("RGB", (SIZE, SIZE), (255, 0, 0))
    _save("knit/plain_wool.png", image, mask)


def work_twill() -> None:
    image = _noise(1997, 180, 8)
    draw = ImageDraw.Draw(image)
    for offset in range(-SIZE, SIZE * 2, 12):
        draw.line((offset, 0, offset - SIZE, SIZE), fill=(151, 151, 151), width=2)
        draw.line((offset + 4, 0, offset + 4 - SIZE, SIZE), fill=(202, 202, 202), width=1)
    mask = Image.new("RGB", (SIZE, SIZE), (255, 0, 0))
    _save("fabric/work_twill.png", image, mask)


def denim() -> None:
    image = _noise(2001, 166, 15)
    draw = ImageDraw.Draw(image)
    for offset in range(-SIZE, SIZE * 2, 8):
        draw.line((offset, 0, offset - SIZE, SIZE), fill=(205, 205, 205), width=1)
        draw.line((offset + 3, 0, offset + 3 - SIZE, SIZE), fill=(125, 125, 125), width=1)
    mask = Image.new("RGB", (SIZE, SIZE), (255, 0, 0))
    _save("fabric/denim.png", image, mask)


def oilskin() -> None:
    image = _noise(1991, 193, 7)
    crease = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(crease)
    for points in [
        ((38, 80), (240, 132), (454, 94)),
        ((70, 352), (258, 318), (470, 382)),
        ((150, 16), (180, 222), (132, 500)),
    ]:
        draw.line(points, fill=42, width=4)
    crease = crease.filter(ImageFilter.GaussianBlur(7))
    pixels = image.load()
    shade = crease.load()
    for y in range(SIZE):
        for x in range(SIZE):
            value = max(0, pixels[x, y][0] - shade[x, y])
            pixels[x, y] = (value, value, value)
    mask = Image.new("RGB", (SIZE, SIZE), (255, 0, 0))
    _save("weatherproof/oilskin.png", image, mask)


def rubber() -> None:
    image = _noise(1986, 150, 5)
    draw = ImageDraw.Draw(image)
    for y in range(14, SIZE, 32):
        draw.line((0, y, SIZE, y), fill=(164, 164, 164), width=2)
    mask = Image.new("RGB", (SIZE, SIZE), (255, 0, 0))
    _save("weatherproof/rubber.png", image, mask)


def leather() -> None:
    image = _noise(1984, 173, 20).filter(ImageFilter.GaussianBlur(0.7))
    draw = ImageDraw.Draw(image)
    rng = random.Random(81)
    for _ in range(120):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        length = rng.randrange(4, 22)
        draw.arc((x - length, y - 3, x + length, y + 3), 8, 172, fill=(130, 130, 130))
    mask = Image.new("RGB", (SIZE, SIZE), (255, 0, 0))
    _save("leather/work_leather.png", image, mask)


def face_surface(name: str, seed: int, freckles: int, weathering: float) -> None:
    width, height, cell = 384, 256, 128
    rng = random.Random(seed)
    image = Image.new("RGB", (width, height), (190, 190, 190))
    mask = Image.new("RGB", (width, height), (255, 0, 0))
    draw = ImageDraw.Draw(image)
    mask_draw = ImageDraw.Draw(mask)
    values = [201, 185, 176, 186, 207, 169]
    for index, base in enumerate(values):
        x0 = (index % 3) * cell
        y0 = (index // 3) * cell
        draw.rectangle((x0, y0, x0 + cell - 1, y0 + cell - 1), fill=(base, base, base))
        for _ in range(370):
            x, y = rng.randrange(x0 + 2, x0 + cell - 2), rng.randrange(y0 + 2, y0 + cell - 2)
            value = max(0, min(255, base + rng.randint(-8, 8)))
            draw.point((x, y), fill=(value, value, value))

    # Front face occupies atlas tile zero. Keep details subdued so the JSON
    # eyes/nose/mouth remain the character's graphic readable features.
    for _ in range(freckles):
        x = rng.randrange(24, 105)
        y = rng.randrange(48, 91)
        r = rng.choice((1, 1, 2))
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(104, 104, 104))
        mask_draw.ellipse((x - r, y - r, x + r, y + r), fill=(0, 255, 0))
    if weathering > 0:
        overlay = Image.new("L", (cell, cell), 0)
        od = ImageDraw.Draw(overlay)
        od.ellipse((12, 46, 58, 104), fill=int(30 * weathering))
        od.ellipse((70, 46, 116, 104), fill=int(30 * weathering))
        od.line((28, 35, 101, 35), fill=int(20 * weathering), width=2)
        overlay = overlay.filter(ImageFilter.GaussianBlur(9))
        src, dst = overlay.load(), image.load()
        for y in range(cell):
            for x in range(cell):
                value = max(0, dst[x, y][0] - src[x, y])
                dst[x, y] = (value, value, value)
    _save(f"skin/{name}.png", image, mask)


def main() -> None:
    fine_nordic_knit()
    plain_wool()
    work_twill()
    denim()
    oilskin()
    rubber()
    leather()
    face_surface("clean", 1969, 0, 0.15)
    face_surface("freckled", 1976, 48, 0.25)
    face_surface("weathered", 1952, 12, 1.0)


if __name__ == "__main__":
    main()
