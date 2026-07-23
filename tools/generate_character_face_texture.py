"""Generate the optional palette-driven face surface atlas.

The character's eyes, mouth, and nose remain JSON geometry. This atlas only
adds restrained skin grain and broad low-poly shading, so it can support age,
freckles, scars, or weathering later without changing the approved base body.
"""

from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFilter


WIDTH = 384
HEIGHT = 256
CELL = 128
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "resources" / "textures" / "characters" / "face_surface_base.png"
MASK_OUTPUT = ROOT / "resources" / "textures" / "characters" / "face_surface_mask.png"


def main() -> None:
    random.seed(1987)
    image = Image.new("RGB", (WIDTH, HEIGHT), (186, 186, 186))
    draw = ImageDraw.Draw(image)

    # Give every atlas face a slightly different broad value while keeping the
    # source neutral. The palette shader supplies the actual skin colour.
    values = [198, 184, 176, 184, 205, 169]
    for index, value in enumerate(values):
        x0 = (index % 3) * CELL
        y0 = (index // 3) * CELL
        draw.rectangle((x0, y0, x0 + CELL - 1, y0 + CELL - 1), fill=(value, value, value))
        for _ in range(460):
            x = random.randrange(x0 + 2, x0 + CELL - 2)
            y = random.randrange(y0 + 2, y0 + CELL - 2)
            delta = random.choice((-9, -6, -3, 3, 5, 8))
            shade = max(0, min(255, value + delta))
            draw.point((x, y), fill=(shade, shade, shade))

    # Front tile: quiet cheek/chin modelling only. Facial features remain the
    # authored JSON blocks and therefore stay crisp at gameplay distance.
    front = Image.new("L", (CELL, CELL), 0)
    front_draw = ImageDraw.Draw(front)
    front_draw.ellipse((14, 44, 57, 99), fill=18)
    front_draw.ellipse((71, 44, 114, 99), fill=18)
    front_draw.ellipse((38, 84, 90, 122), fill=12)
    front = front.filter(ImageFilter.GaussianBlur(13))
    front_pixels = front.load()
    pixels = image.load()
    for y in range(CELL):
        for x in range(CELL):
            shade = 198 - front_pixels[x, y]
            grain = pixels[x, y][0] - 198
            value = max(0, min(255, shade + grain))
            pixels[x, y] = (value, value, value)

    # Red means primary skin colour. Green is deliberately unused by this base
    # profile but remains available to variants (lips, scars, paint, tattoos).
    mask = Image.new("RGB", (WIDTH, HEIGHT), (255, 0, 0))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT, optimize=True)
    mask.save(MASK_OUTPUT, optimize=True)
    print(OUTPUT)
    print(MASK_OUTPUT)


if __name__ == "__main__":
    main()
