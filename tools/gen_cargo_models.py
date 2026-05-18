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

def make_pallet_section() -> None:
    """Single 1×1 cell pallet section — used N×M times to tile a multi-cell pallet base."""
    cell = 1.5
    pad = 0.1
    w = cell - pad
    plank_h = 0.14
    wood = [0.55, 0.38, 0.22]
    parts = [
        # Top deck slab
        part("deck", box_mesh(w, plank_h, w), wood, (0, 0, 0)),
        # Two darker stringers underneath for visible pallet construction
        part("stringer_l", box_mesh(w * 0.95, 0.04, 0.12),
             [c * 0.65 for c in wood], (0, -0.04, -w * 0.35)),
        part("stringer_r", box_mesh(w * 0.95, 0.04, 0.12),
             [c * 0.65 for c in wood], (0, -0.04, w * 0.35)),
    ]
    dump("pallet_section.json", {"name": "pallet_section", "parts": parts})


def make_crate() -> None:
    """Wooden crate — just body + dark rim caps. Reference: gantry crane parts."""
    w = 1.05
    h = 0.55
    pale = [0.66, 0.50, 0.30]
    dark = [0.38, 0.26, 0.15]
    parts = [
        part("body", box_mesh(w, h, w, 0), pale, (0, 0, 0)),
        # Thin dark rim band wrapping top + bottom (two slim boxes).
        part("rim_bottom", box_mesh(w + 0.04, 0.05, w + 0.04, 0.0), dark, (0, 0, 0)),
        part("rim_top",    box_mesh(w + 0.04, 0.05, w + 0.04, h - 0.05), dark, (0, 0, 0)),
    ]
    dump("provisions_crate.json", {"name": "provisions_crate", "parts": parts})


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


def make_sack() -> None:
    """Canvas sack — two stacked hex frustums + tiny tie. 6 sides."""
    canvas = [0.82, 0.74, 0.58]
    rope   = [0.35, 0.25, 0.18]
    parts = [
        # Body: base → belly (one frustum) → shoulder narrows up.
        part("belly",    prism_mesh(0.34, 0.48, 0.35, 0.0,  sides=6), canvas, (0, 0, 0)),
        part("shoulder", prism_mesh(0.48, 0.20, 0.20, 0.35, sides=6),
             [c * 0.92 for c in canvas], (0, 0, 0)),
        # Tiny tie/knob on top.
        part("tie",      prism_mesh(0.16, 0.10, 0.06, 0.55, sides=6), rope, (0, 0, 0)),
    ]
    dump("provisions_sack.json", {"name": "provisions_sack", "parts": parts})


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
    make_pallet_section()
    make_crate()
    make_barrel()
    make_sack()
    make_amphora()
    print("Done.")
