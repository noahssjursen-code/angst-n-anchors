#!/usr/bin/env python3
# Seamless tiling asphalt-ish albedo (~512²): periodic value-noise + grain.
# Dense sine Fourier sums read like rugs/weave; asphalt needs chaotic multi-scale grit.

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageFilter, ImageOps

W = H = 512
OUT = Path(__file__).resolve().parents[1] / "resources" / "textures" / "asphalt_albedo_512.png"


def _frac(x: float) -> float:
    return x - math.floor(x)


def _h01(ix: int, iy: int, salt: int) -> float:
    n = (ix * 374761393 + iy * 668265263 + salt * 224682251 + 974122127) & 0xFFFFFFFF
    n ^= n >> 13
    n ^= n >> 17
    n ^= n >> 5
    return (n % 1048577) / 1048576.0


def _val_noise(px: float, py: float, nx: int, ny: int, salt: int) -> float:
    ux = px / float(W) * nx
    uy = py / float(H) * ny
    x0 = int(math.floor(ux)) % nx
    x1 = (x0 + 1) % nx
    y0 = int(math.floor(uy)) % ny
    y1 = (y0 + 1) % ny
    fx = _frac(ux)
    fy = _frac(uy)
    sx = fx * fx * (3.0 - 2.0 * fx)
    sy = fy * fy * (3.0 - 2.0 * fy)

    v00 = _h01(x0, y0, salt)
    v10 = _h01(x1, y0, salt)
    v01 = _h01(x0, y1, salt)
    v11 = _h01(x1, y1, salt)

    a = v00 * (1.0 - sx) + v10 * sx
    b = v01 * (1.0 - sx) + v11 * sx
    return a * (1.0 - sy) + b * sy


def _fbm(px: float, py: float) -> float:
    tot = 0.0
    amp_sum = 0.0
    nx = 11
    ny = 13
    amp = 1.0
    for octave in range(7):
        tot += amp * _val_noise(px, py, max(3, nx), max(3, ny), 9001 + octave * 131)
        amp_sum += amp
        nx = min(192, nx * 2 + 3)
        ny = min(196, ny * 2 + 5)
        amp *= 0.48
        if amp < 1e-4:
            break
    return tot / max(amp_sum, 1e-9)


def main() -> None:
    vals: list[list[float]] = []
    infinity = float("inf")
    mi = infinity
    ma = -infinity
    for y in range(H):
        row: list[float] = []
        for x in range(W):
            v = _fbm(float(x) + 0.5, float(y) + 0.5)
            row.append(v)
            mi = min(mi, v)
            ma = max(ma, v)
        vals.append(row)
    span = max(ma - mi, 1e-9)

    # Narrow macro modulation (wet binder is broadly flat — micro chatter only).
    gr = Image.new("L", (W, H))
    gl = gr.load()
    for y in range(H):
        for x in range(W):
            v = ((vals[y][x] - mi) / span - 0.5) * 0.22 + 0.5  # centred, low swing
            gl[x, y] = int(min(255, max(0, v * 255.0)))

    # High-frequency blotches (broken aggregate chips, not yarns).
    speck = Image.effect_noise((W, H), 38.0).convert("L")
    grain = Image.effect_noise((W, H), 12.5).convert("L")
    gr = Image.blend(gr, grain, 0.12)
    gr = Image.blend(gr, speck, 0.065)
    gr = ImageOps.autocontrast(gr, cutoff=0.6)
    gr = gr.filter(ImageFilter.GaussianBlur(radius=0.52))

    colour = Image.new("RGB", (W, H))
    cpix = colour.load()
    lum = memoryview(gr.tobytes())
    idx = 0
    for y in range(H):
        for x in range(W):
            vpix = lum[idx] / 255.0
            # Compressed contrast: macro asphalt is matte and low-frequency.
            mid = math.pow(max(0.0, min(1.0, vpix)), 0.93)
            r = int(36 + mid * 32 + ((idx * 7919 % 73) / 73.0 - 0.5) * 4)
            g = int(33 + mid * 30 + ((idx * 4973 % 71) / 71.0 - 0.5) * 4)
            b = int(40 + mid * 29 + ((idx * 9341 % 67) / 67.0 - 0.5) * 5)
            r = max(24, min(112, r))
            g = max(22, min(108, g))
            b = max(28, min(118, b))
            cpix[x, y] = (r, g, b)
            idx += 1

    colour = Image.blend(colour, Image.new("RGB", (W, H), (48, 47, 52)), 0.048)
    colour = colour.filter(ImageFilter.GaussianBlur(radius=0.38))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    colour.save(OUT, format="PNG", compress_level=6)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
