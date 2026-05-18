#!/usr/bin/env python3
"""
One-shot generator for cargo model JSON files. Outputs ModelAssembler-format
composition JSONs into resources/data/models/cargo/, with inline mesh data
(vertices + indices) for each primitive part.

Run:   python tools/gen_cargo_models.py
"""

from __future__ import annotations
import json
import math
import os
from pathlib import Path

OUT_DIR = Path("resources/data/models/cargo")
OUT_DIR.mkdir(parents=True, exist_ok=True)


# ── Primitive mesh builders ────────────────────────────────────────────────────

def box_mesh(w: float, h: float, d: float, y_base: float = 0.0) -> dict:
    """Axis-aligned box centred on XZ, sitting on y_base."""
    hw, hd = w / 2.0, d / 2.0
    y0, y1 = y_base, y_base + h
    v = [
        -hw, y0, -hd,
         hw, y0, -hd,
         hw, y1, -hd,
        -hw, y1, -hd,
        -hw, y0,  hd,
         hw, y0,  hd,
         hw, y1,  hd,
        -hw, y1,  hd,
    ]
    i = [
        0, 1, 5,  0, 5, 4,
        3, 7, 6,  3, 6, 2,
        0, 3, 2,  0, 2, 1,
        4, 5, 6,  4, 6, 7,
        0, 4, 7,  0, 7, 3,
        1, 2, 6,  1, 6, 5,
    ]
    return {"vertices": v, "indices": i}


def prism_mesh(r_bottom: float, r_top: float, h: float, y_base: float = 0.0, sides: int = 6) -> dict:
    """Truncated regular prism (cone-like) with `sides` sides."""
    v: list[float] = []
    for k in range(sides):
        a = 2.0 * math.pi * k / sides
        v.extend([r_bottom * math.cos(a), y_base, r_bottom * math.sin(a)])
    for k in range(sides):
        a = 2.0 * math.pi * k / sides
        v.extend([r_top * math.cos(a), y_base + h, r_top * math.sin(a)])

    i: list[int] = []
    # Side quads (two tris each).
    for k in range(sides):
        a = k
        b = (k + 1) % sides
        c = b + sides
        d = a + sides
        i.extend([a, b, c, a, c, d])
    # Top cap (fan from vertex 0 of top ring).
    for k in range(1, sides - 1):
        i.extend([sides, sides + k + 1, sides + k])
    # Bottom cap (reverse winding so it faces down).
    for k in range(1, sides - 1):
        i.extend([0, k, k + 1])
    return {"vertices": v, "indices": i}


# ── Shared part builders ──────────────────────────────────────────────────────

def part(name: str, mesh: dict, color: list[float], pos=(0, 0, 0), roughness: float = 0.85, metallic: float = 0.0) -> dict:
    return {
        "name": name,
        "mesh": mesh,
        "role": "visual",
        "position": list(pos),
        "color": color,
        "roughness": roughness,
        "metallic": metallic,
        "collision": "none",
    }


def _render(obj, indent: int = 0) -> str:
    """JSON-ish formatter: dicts indented, numeric arrays kept inline so
    vertex/index lists don't blow up to thousands of lines."""
    pad = "  " * indent
    inner_pad = "  " * (indent + 1)
    if isinstance(obj, dict):
        if not obj:
            return "{}"
        items = []
        for k, v in obj.items():
            items.append(f'{inner_pad}"{k}": {_render(v, indent + 1)}')
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(obj, list):
        if obj and all(isinstance(x, (int, float, bool)) for x in obj):
            return "[" + ", ".join(json.dumps(x) for x in obj) + "]"
        if not obj:
            return "[]"
        items = [f"{inner_pad}{_render(x, indent + 1)}" for x in obj]
        return "[\n" + ",\n".join(items) + "\n" + pad + "]"
    return json.dumps(obj)


def dump(filename: str, model: dict) -> None:
    path = OUT_DIR / filename
    with path.open("w") as f:
        f.write(_render(model))
        f.write("\n")
    print(f"  wrote {path}")


# ── Models ────────────────────────────────────────────────────────────────────

def make_pallet(fp_x: int, fp_z: int) -> None:
    """Wooden pallet at fp_x × fp_z cells (cell = 1.5 m). Structure:
      * 3 stringers running along Z (the long axis when fp_z >= fp_x)
      * N top deck planks running along X, spaced across Z with visible gaps
      * 2 bottom planks (front + back) for when the crane lifts it
    Total vertical height: stringer (0.10) + plank (0.04) = 0.14 m."""
    cell = 1.5
    pad = 0.10
    w = cell * fp_x - pad
    d = cell * fp_z - pad

    wood = [0.55, 0.38, 0.22]
    dark = [c * 0.70 for c in wood]

    stringer_h = 0.10
    stringer_w = 0.12
    plank_h    = 0.04
    plank_w    = 0.18
    plank_gap  = 0.07
    pitch      = plank_w + plank_gap

    top_y      = stringer_h          # planks sit on top of stringers
    bottom_y   = -plank_h            # bottom planks below stringers

    parts: list[dict] = []

    # Three stringers spaced across X (positions: -0.4w, 0, +0.4w)
    for i in range(3):
        sx = (i - 1) * (w * 0.40)
        parts.append(part(
            f"stringer_{i}",
            box_mesh(stringer_w, stringer_h, d),
            dark, (sx, 0, 0),
        ))

    # Top deck planks — count scales with depth so pitch stays ~0.25 m.
    num_top = maxi_py(5, int(round(d / pitch)))
    actual_pitch = d / num_top
    for i in range(num_top):
        pz = -d / 2.0 + actual_pitch * (i + 0.5)
        parts.append(part(
            f"top_{i}",
            box_mesh(w, plank_h, plank_w),
            wood, (0, top_y, pz),
        ))

    # Two bottom planks at front + back (visible when lifted).
    for i, ratio in enumerate([-0.42, 0.42]):
        parts.append(part(
            f"bottom_{i}",
            box_mesh(w, plank_h, plank_w),
            wood, (0, bottom_y, ratio * d),
        ))

    name = f"pallet_{fp_x}x{fp_z}"
    dump(f"{name}.json", {"name": name, "parts": parts})


def maxi_py(a: int, b: int) -> int:
    return a if a > b else b


def make_produce_pile() -> None:
    """Open wooden crate filled with round produce (cabbages / melons).
    Slatted wood frame around six green hex-sphere heads."""
    wood   = [0.55, 0.38, 0.22]
    dark   = [c * 0.70 for c in wood]
    skin   = [0.50, 0.66, 0.30]
    leaves = [0.36, 0.50, 0.20]

    crate_w = 1.05
    crate_d = 1.05
    crate_h = 0.45
    post_t  = 0.07
    rail_t  = 0.06
    hw, hd = crate_w / 2.0, crate_d / 2.0

    parts: list[dict] = []

    # 4 corner posts (vertical)
    for i, (ox, oz) in enumerate([(-hw, -hd), (hw, -hd), (-hw, hd), (hw, hd)]):
        parts.append(part(
            f"post_{i}",
            box_mesh(post_t, crate_h, post_t),
            wood, (ox, 0.0, oz),
        ))

    # Top + bottom + mid horizontal rails around the perimeter (X and Z axes)
    side_t = post_t * 0.9
    rail_lengths = [(crate_w, rail_t, side_t), (side_t, rail_t, crate_d)]
    for y_label, ry in [("bot", 0.0), ("mid", crate_h * 0.5 - rail_t * 0.5), ("top", crate_h - rail_t)]:
        parts.append(part(f"rail_{y_label}_front",
                          box_mesh(*rail_lengths[0]), dark, (0, ry, -hd)))
        parts.append(part(f"rail_{y_label}_back",
                          box_mesh(*rail_lengths[0]), dark, (0, ry,  hd)))
        parts.append(part(f"rail_{y_label}_left",
                          box_mesh(*rail_lengths[1]), dark, (-hw, ry, 0)))
        parts.append(part(f"rail_{y_label}_right",
                          box_mesh(*rail_lengths[1]), dark, ( hw, ry, 0)))

    # Bottom deck so produce isn't floating between rails.
    parts.append(part("floor",
                      box_mesh(crate_w - 0.04, rail_t, crate_d - 0.04),
                      wood, (0, 0.03, 0)))

    # Cabbages — sit on the floor; bottom row of 4, top row of 2.
    r = 0.20
    h = 0.22
    base_y = rail_t + 0.04
    bottoms = [(-0.25, -0.25), ( 0.25, -0.25), (-0.25,  0.25), ( 0.25,  0.25)]
    tops    = [(-0.12, 0.0),   ( 0.12, 0.0)]
    for i, (ox, oz) in enumerate(bottoms):
        parts.append(part(f"head_b{i}",
                          prism_mesh(r, r * 0.55, h, base_y, sides=6),
                          skin, (ox, 0, oz)))
        parts.append(part(f"stem_b{i}",
                          prism_mesh(r * 0.45, r * 0.20, 0.05, base_y + h - 0.02, sides=6),
                          leaves, (ox, 0, oz)))
    for i, (ox, oz) in enumerate(tops):
        y = base_y + h + 0.02
        parts.append(part(f"head_t{i}",
                          prism_mesh(r, r * 0.55, h, y, sides=6),
                          skin, (ox, 0, oz)))
        parts.append(part(f"stem_t{i}",
                          prism_mesh(r * 0.45, r * 0.20, 0.05, y + h - 0.02, sides=6),
                          leaves, (ox, 0, oz)))

    dump("provisions_produce_pile.json",
         {"name": "provisions_produce_pile", "parts": parts})


def make_barrel() -> None:
    """Wooden barrel — single hex body with two thin hoops. 6-sided prisms."""
    wood = [0.45, 0.27, 0.15]
    hoop = [0.20, 0.18, 0.16]
    r = 0.42
    h = 0.66
    parts = [
        part("body",    prism_mesh(r, r, h, 0.0, sides=6), wood, (0, 0, 0)),
        part("hoop_lo", prism_mesh(r * 1.04, r * 1.04, 0.05, h * 0.2, sides=6),
             hoop, (0, 0, 0), roughness=0.45, metallic=0.6),
        part("hoop_hi", prism_mesh(r * 1.04, r * 1.04, 0.05, h * 0.7, sides=6),
             hoop, (0, 0, 0), roughness=0.45, metallic=0.6),
    ]
    dump("provisions_barrel.json", {"name": "provisions_barrel", "parts": parts})


def make_chest() -> None:
    """Wooden trading chest with iron straps + lock — low, wide, distinctive
    silhouette unlike barrel / crate / amphora."""
    wood = [0.55, 0.38, 0.22]
    iron = [0.20, 0.17, 0.14]
    w, h, d = 0.85, 0.32, 0.55
    parts = [
        # Lower body
        part("body", box_mesh(w, h, d), wood, (0, 0, 0)),
        # Slightly raised lid (flat slab on top, overhangs the body a touch)
        part("lid",  box_mesh(w + 0.03, 0.08, d + 0.03),
             [c * 0.9 for c in wood], (0, h, 0)),
        # Three iron straps wrapping front-to-back across the body + lid
        part("strap_l", box_mesh(0.05, h + 0.12, d + 0.04), iron,
             (-w * 0.35, h * 0.5, 0), roughness=0.45, metallic=0.6),
        part("strap_r", box_mesh(0.05, h + 0.12, d + 0.04), iron,
             ( w * 0.35, h * 0.5, 0), roughness=0.45, metallic=0.6),
        part("strap_c", box_mesh(0.05, h + 0.12, d + 0.04), iron,
             ( 0.0,      h * 0.5, 0), roughness=0.45, metallic=0.6),
        # Lock plate centred on the front face
        part("lock", box_mesh(0.12, 0.11, 0.03), iron,
             (0, h * 0.65, d * 0.5), roughness=0.45, metallic=0.6),
    ]
    dump("provisions_chest.json", {"name": "provisions_chest", "parts": parts})


def make_amphora() -> None:
    """Cluster of 4 small clay jars — each jar is 2 hex frustums + a neck."""
    clay = [0.42, 0.26, 0.18]

    def one_jar(prefix: str, ox: float, oz: float) -> list[dict]:
        return [
            part(f"{prefix}_belly",
                 prism_mesh(0.10, 0.20, 0.22, 0.00, sides=6),
                 clay, (ox, 0, oz)),
            part(f"{prefix}_shoulder",
                 prism_mesh(0.20, 0.08, 0.18, 0.22, sides=6),
                 [c * 0.92 for c in clay], (ox, 0, oz)),
        ]

    o = 0.28
    parts: list[dict] = []
    parts.extend(one_jar("fl", -o, -o))
    parts.extend(one_jar("fr",  o, -o))
    parts.extend(one_jar("bl", -o,  o))
    parts.extend(one_jar("br",  o,  o))
    dump("provisions_amphora.json", {"name": "provisions_amphora", "parts": parts})


# ── Entry ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print(f"Writing cargo model JSONs into {OUT_DIR}/")
    # Pallets: one per canonical footprint. Other orientations (2×1, 3×2)
    # are these rotated 90° at instantiation time.
    for fp in [(1, 1), (1, 2), (2, 2), (2, 3)]:
        make_pallet(*fp)
    make_produce_pile()
    make_barrel()
    make_chest()
    make_amphora()
    print("Done.")
