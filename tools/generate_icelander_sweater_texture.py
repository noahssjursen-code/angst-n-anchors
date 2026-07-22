"""Generate the deterministic knit texture used by the sweater rendering proof.

The image is deliberately graphic rather than photoreal: it adds fibre-scale
variation and a readable Nordic yoke while preserving the game's low-poly
visual language. It is source-controlled so the same pixels ship everywhere.
"""

from pathlib import Path

from PIL import Image, ImageDraw


WIDTH = 512
HEIGHT = 512
OUTPUT = Path(__file__).resolve().parents[1] / "resources" / "textures" / "characters" / "icelander_sweater.png"
MASK_OUTPUT = Path(__file__).resolve().parents[1] / "resources" / "textures" / "characters" / "icelander_sweater_mask.png"

NAVY = (24, 54, 78, 255)
NAVY_DARK = (14, 35, 53, 255)
NAVY_LIGHT = (35, 70, 96, 255)
CREAM = (224, 220, 199, 255)
CREAM_SHADOW = (190, 190, 177, 255)


def wrapped_polygon(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], fill: tuple[int, int, int, int]) -> None:
    for offset in (-WIDTH, 0, WIDTH):
        draw.polygon([(x + offset, y) for x, y in points], fill=fill)


def main() -> None:
    image = Image.new("RGBA", (WIDTH, HEIGHT), NAVY)
    draw = ImageDraw.Draw(image)

    # Fine two-colour knit grain. It remains visible up close and naturally
    # averages into the base colour through mipmaps at gameplay distance.
    for y in range(HEIGHT):
        grain = NAVY_LIGHT if y % 4 == 0 else NAVY_DARK
        for x in range((y // 2) % 4, WIDTH, 8):
            draw.point((x, y), fill=grain)
    for x in range(0, WIDTH, 4):
        draw.line((x, 0, x, HEIGHT), fill=(28, 62, 86, 150), width=1)

    # Ribbed neck band.
    draw.rectangle((0, 0, WIDTH, 30), fill=NAVY_DARK)
    for x in range(0, WIDTH, 8):
        draw.rectangle((x, 0, x + 2, 30), fill=NAVY_LIGHT)

    # Icelandic-inspired yoke: horizontal separators and repeating diamonds.
    draw.rectangle((0, 42, WIDTH, 56), fill=CREAM)
    draw.rectangle((0, 164, WIDTH, 178), fill=CREAM)
    draw.rectangle((0, 68, WIDTH, 78), fill=CREAM_SHADOW)
    draw.rectangle((0, 142, WIDTH, 152), fill=CREAM_SHADOW)
    repeat = 64
    for x in range(-repeat, WIDTH + repeat, repeat):
        wrapped_polygon(draw, [(x + 32, 82), (x + 55, 110), (x + 32, 138), (x + 9, 110)], CREAM)
        wrapped_polygon(draw, [(x + 32, 92), (x + 46, 110), (x + 32, 128), (x + 18, 110)], NAVY_DARK)
        wrapped_polygon(draw, [(x + 0, 91), (x + 13, 110), (x + 0, 129), (x - 13, 110)], CREAM_SHADOW)

    # Restrained sailor-like stripes below the yoke keep the garment readable
    # from a ship deck without turning it into a high-frequency checkerboard.
    draw.rectangle((0, 266, WIDTH, 278), fill=CREAM)
    draw.rectangle((0, 302, WIDTH, 312), fill=CREAM_SHADOW)

    # Ribbed hem/cuffs occupy the bottom of the shared vertical mapping.
    draw.rectangle((0, 454, WIDTH, HEIGHT), fill=NAVY_DARK)
    for x in range(0, WIDTH, 8):
        draw.rectangle((x, 454, x + 2, HEIGHT), fill=NAVY_LIGHT)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT, optimize=True)
    # Red selects the dark yarn, green selects the light pattern. The shader
    # replaces only those broad colours and keeps the source knit luminance.
    mask = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
    source = image.load()
    mask_pixels = mask.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            red, green, blue, _alpha = source[x, y]
            mask_pixels[x, y] = (255, 0, 0) if blue < 145 else (0, 255, 0)
    mask.save(MASK_OUTPUT, optimize=True)
    print(OUTPUT)
    print(MASK_OUTPUT)


if __name__ == "__main__":
    main()
