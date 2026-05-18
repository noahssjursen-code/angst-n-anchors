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


def prism_mesh(r_bottom: float, r_top: float, h: float, y_base: float = 0.0, sides: int = 12) -> dict:
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


def dump(filename: str, model: dict) -> None:
    path = OUT_DIR / filename
    with path.open("w") as f:
        json.dump(model, f, indent=1)
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
    """Wooden crate — main body + 4 corner posts + thin top/bottom rims."""
    w = 1.05
    h = 0.55
    pale = [0.66, 0.50, 0.30]
    dark = [0.38, 0.26, 0.15]
    half = w / 2.0
    post = 0.10
    parts = [
        # Main body
        part("body", box_mesh(w, h, w, 0), pale, (0, 0, 0)),
        # 4 vertical corner posts (slightly outside the body)
        part("post_fl", box_mesh(post, h + 0.02, post, -0.01), dark, (-half, 0, -half)),
        part("post_fr", box_mesh(post, h + 0.02, post, -0.01), dark, ( half, 0, -half)),
        part("post_bl", box_mesh(post, h + 0.02, post, -0.01), dark, (-half, 0,  half)),
        part("post_br", box_mesh(post, h + 0.02, post, -0.01), dark, ( half, 0,  half)),
        # Top + bottom rim band (thin horizontal slats)
        part("rim_bottom", box_mesh(w + 0.02, 0.04, w + 0.02, 0.02), dark, (0, 0, 0)),
        part("rim_top",    box_mesh(w + 0.02, 0.04, w + 0.02, h - 0.04), dark, (0, 0, 0)),
        # Lid hint — small raised square in the middle of the top
        part("lid", box_mesh(w * 0.6, 0.04, w * 0.6, h), [c * 0.85 for c in pale], (0, 0, 0)),
    ]
    dump("provisions_crate.json", {"name": "provisions_crate", "parts": parts})


def make_barrel() -> None:
    """Wooden barrel — bulging body (3 stacked frustums) + 2 metal hoops."""
    wood = [0.45, 0.27, 0.15]
    hoop = [0.20, 0.18, 0.16]
    # Bulging silhouette: narrow→wide→narrow.
    r_end = 0.35
    r_mid = 0.45
    h_low, h_mid, h_high = 0.22, 0.22, 0.22
    parts = [
        # Body: bottom frustum (narrows down → up to widest)
        part("body_low",  prism_mesh(r_end, r_mid, h_low,  0.00, sides=14), wood, (0, 0, 0)),
        # Middle: straight at widest
        part("body_mid",  prism_mesh(r_mid, r_mid, h_mid,  h_low, sides=14), wood, (0, 0, 0)),
        # Upper frustum (widest → narrows up)
        part("body_high", prism_mesh(r_mid, r_end, h_high, h_low + h_mid, sides=14), wood, (0, 0, 0)),
        # Two darker hoops at top + bottom of the middle bulge
        part("hoop_lo",   prism_mesh(r_mid * 1.02, r_mid * 1.02, 0.04, h_low - 0.02, sides=14),
             hoop, (0, 0, 0), roughness=0.45, metallic=0.6),
        part("hoop_hi",   prism_mesh(r_mid * 1.02, r_mid * 1.02, 0.04, h_low + h_mid - 0.02, sides=14),
             hoop, (0, 0, 0), roughness=0.45, metallic=0.6),
        # Top lid disc
        part("lid",       prism_mesh(r_end * 0.95, r_end * 0.95, 0.03,
                                     h_low + h_mid + h_high - 0.015, sides=14),
             [c * 0.85 for c in wood], (0, 0, 0)),
    ]
    dump("provisions_barrel.json", {"name": "provisions_barrel", "parts": parts})


def make_sack() -> None:
    """Canvas sack — bulbous body that narrows to a tied neck."""
    canvas = [0.82, 0.74, 0.58]
    rope   = [0.35, 0.25, 0.18]
    # Stacked frustums to build a teardrop: narrow base → wide belly → narrow neck → tiny tie.
    parts = [
        # Bottom (small footprint widening upward)
        part("base",   prism_mesh(0.30, 0.48, 0.18, 0.00, sides=12), canvas, (0, 0, 0)),
        # Belly (widest, slight outward bow)
        part("belly",  prism_mesh(0.48, 0.46, 0.18, 0.18, sides=12), canvas, (0, 0, 0)),
        # Shoulder (narrowing)
        part("shoulder", prism_mesh(0.46, 0.30, 0.15, 0.36, sides=12),
             [c * 0.94 for c in canvas], (0, 0, 0)),
        # Neck (small cinch)
        part("neck",   prism_mesh(0.18, 0.20, 0.08, 0.51, sides=12),
             [c * 0.88 for c in canvas], (0, 0, 0)),
        # Tie at the very top
        part("tie",    prism_mesh(0.22, 0.10, 0.05, 0.59, sides=12), rope, (0, 0, 0)),
    ]
    dump("provisions_sack.json", {"name": "provisions_sack", "parts": parts})


def make_amphora() -> None:
    """Cluster of 4 small clay amphorae (jars) in a 2×2 layout."""
    clay = [0.42, 0.26, 0.18]
    foot = 0.10
    belly = 0.18
    shoulder = 0.12
    neck = 0.06
    mouth = 0.09

    def one_jar(prefix: str, ox: float, oz: float) -> list[dict]:
        return [
            # Foot (narrow base)
            part(f"{prefix}_foot",
                 prism_mesh(foot, foot + 0.02, 0.06, 0.00, sides=10),
                 clay, (ox, 0, oz)),
            # Belly (round bulge)
            part(f"{prefix}_belly_lo",
                 prism_mesh(foot + 0.02, belly, 0.12, 0.06, sides=10),
                 clay, (ox, 0, oz)),
            part(f"{prefix}_belly_hi",
                 prism_mesh(belly, shoulder, 0.10, 0.18, sides=10),
                 clay, (ox, 0, oz)),
            # Neck (long narrow)
            part(f"{prefix}_neck",
                 prism_mesh(shoulder, neck, 0.16, 0.28, sides=10),
                 [c * 0.95 for c in clay], (ox, 0, oz)),
            # Mouth (slight flare)
            part(f"{prefix}_mouth",
                 prism_mesh(neck, mouth, 0.03, 0.44, sides=10),
                 [c * 0.85 for c in clay], (ox, 0, oz)),
        ]

    # 2×2 grid offsets — fit comfortably in one cell.
    o = 0.30
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
