#!/usr/bin/env python3
"""Generate detailed bridge JSON models for each ship class. Each bridge
contains the main deck house, a top deck, dark window strip, port + stbd
wings, exhaust funnel with cap, mast + crossbar + antenna, and railings
around the upper platform. The 5 ship classes share the same parts but
scale each piece to fit the hull.

JSON model format consumed by ModelAssembler: parts list, each with
mesh.vertices + mesh.indices + role + position + rotation + color +
roughness + collision (none here — superstructure is decorative).

Box winding matches Godot's CW-front-face convention so SurfaceTool
normal generation gives +normals pointing outward."""

import json
import os
from copy import deepcopy

OUT_DIR = "resources/data/models/superstructures"

# Standard CW-from-outside indices for a box with corners 0-7 ordered
#   0: (-x,-y,-z) 1: (x,-y,-z) 2: (x,-y,z) 3: (-x,-y,z)
#   4: (-x,y,-z)  5: (x,y,-z)  6: (x,y,z)  7: (-x,y,z)
BOX_INDICES = [
    0, 3, 2,  0, 2, 1,    # -Y bottom
    4, 5, 6,  4, 6, 7,    # +Y top
    0, 1, 5,  0, 5, 4,    # -Z back
    3, 7, 6,  3, 6, 2,    # +Z front
    0, 4, 7,  0, 7, 3,    # -X left
    1, 2, 6,  1, 6, 5,    # +X right
]


def box_verts(sx, sy, sz):
    """Box vertices flat list (24 floats) for size sx × sy × sz."""
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    return [
        -hx, -hy, -hz,   hx, -hy, -hz,   hx, -hy,  hz,  -hx, -hy,  hz,
        -hx,  hy, -hz,   hx,  hy, -hz,   hx,  hy,  hz,  -hx,  hy,  hz,
    ]


def box_part(name, size, position, color, roughness=0.7, metallic=0.05, rotation=None, role="visual"):
    p = {
        "name": name,
        "mesh": {"vertices": box_verts(*size), "indices": BOX_INDICES[:]},
        "role": role,
        "position": list(position),
        "scale": 1.0,
        "color": list(color),
        "roughness": roughness,
        "metallic": metallic,
        "collision": "none",
    }
    if rotation is not None:
        p["rotation_degrees"] = list(rotation)
    return p


# Per-ship-class size factors — multiply the coastal trader baseline by these.
# All numbers are in metres at scale 1.0; the hull JSON's `scale` field doesn't
# touch these since superstructure has its own scale param too.
SHIPS = {
    "bridge_coastal_trader": {
        "house":   (2.2, 2.3, 1.8),  # width × height × depth (Z is depth-along-ship)
        "house_pos": (0, 1.15, 0.9),
        "roof":    (2.5, 0.12, 1.9),
        "roof_pos": (0, 2.35, 0.95),
        "wing":    (0.4, 0.15, 1.5),
        "wing_y":   2.25,
        "wing_z":   0.9,
        "funnel":  (0.45, 0.85, 0.35),
        "funnel_pos": (0.5, 2.8, -0.25),  # above roof
        "mast_h":   1.5,
        "rail_h":   0.4,
        "interact_exit": (-1.2, -3.0),
        "scale_factor": 1.0,
    },
    "bridge_short_sea_coaster": {
        "house":   (3.4, 2.8, 2.4),
        "house_pos": (0, 1.4, 1.2),
        "roof":    (3.6, 0.15, 2.6),
        "roof_pos": (0, 2.85, 1.3),
        "wing":    (0.55, 0.18, 2.0),
        "wing_y":   2.7,
        "wing_z":   1.1,
        "funnel":  (0.55, 1.1, 0.42),
        "funnel_pos": (0.6, 3.45, -0.3),
        "mast_h":   2.0,
        "rail_h":   0.5,
        "interact_exit": (-2.0, -5.0),
        "scale_factor": 1.45,
    },
    "bridge_cargo_ship": {
        "house":   (3.4, 3.2, 3.8),
        "house_pos": (0, 1.6, 1.9),
        "roof":    (3.6, 0.15, 4.0),
        "roof_pos": (0, 3.25, 2.0),
        "wing":    (0.6, 0.18, 2.8),
        "wing_y":   2.95,
        "wing_z":   1.4,
        "funnel":  (0.55, 1.2, 0.45),
        "funnel_pos": (0.5, 3.9, -0.4),
        "mast_h":   2.2,
        "rail_h":   0.55,
        "interact_exit": (-1.8, -8.0),
        "scale_factor": 1.6,
    },
    "bridge_handysize_feeder": {
        "house":   (5.0, 3.5, 3.0),
        "house_pos": (0, 1.75, 1.5),
        "roof":    (5.4, 0.18, 3.2),
        "roof_pos": (0, 3.55, 1.6),
        "wing":    (0.7, 0.2, 2.5),
        "wing_y":   3.35,
        "wing_z":   1.5,
        "funnel":  (0.65, 1.4, 0.5),
        "funnel_pos": (0.8, 4.3, -0.4),
        "mast_h":   2.8,
        "rail_h":   0.65,
        "interact_exit": (-2.5, -9.0),
        "scale_factor": 2.0,
    },
    "bridge_deep_sea_freighter": {
        "house":   (7.0, 4.5, 4.0),
        "house_pos": (0, 2.25, 2.0),
        "roof":    (7.5, 0.22, 4.2),
        "roof_pos": (0, 4.6, 2.1),
        "wing":    (0.9, 0.25, 3.0),
        "wing_y":   4.35,
        "wing_z":   2.0,
        "funnel":  (0.8, 1.8, 0.6),
        "funnel_pos": (1.0, 5.55, -0.5),
        "mast_h":   3.5,
        "rail_h":   0.8,
        "interact_exit": (-4.0, -13.0),
        "scale_factor": 2.6,
    },
}

# Colours — consistent across the fleet so a freighter bridge reads the same
# style as a coastal trader's, just bigger.
COL_HOUSE       = [0.82, 0.80, 0.74]   # off-white hull paint
COL_HOUSE_ALT   = [0.88, 0.86, 0.80]   # slightly lighter (top deck)
COL_WINDOWS     = [0.08, 0.18, 0.28]   # dark glass
COL_FUNNEL      = [0.07, 0.06, 0.05]   # near-black exhaust stack
COL_FUNNEL_CAP  = [0.62, 0.20, 0.16]   # red cap stripe
COL_STEEL       = [0.55, 0.55, 0.58]   # railings, mast, ladders
COL_DOOR        = [0.45, 0.38, 0.32]   # weathered wood door

# Roughness defaults
R_PAINT  = 0.55
R_METAL  = 0.45
R_GLASS  = 0.10
R_STEEL  = 0.40


def build_bridge_parts(cfg):
    """Return a list of part dicts for one bridge."""
    parts = []
    hx, hy, hz = cfg["house"]
    house_x, house_y, house_z = cfg["house_pos"]
    rx, ry, rz = cfg["roof"]
    roof_x, roof_y, roof_z = cfg["roof_pos"]
    wx, wy, wz = cfg["wing"]
    wing_y = cfg["wing_y"]
    wing_z = cfg["wing_z"]
    fx, fy, fz = cfg["funnel"]
    fpos = cfg["funnel_pos"]
    mast_h = cfg["mast_h"]
    rail_h = cfg["rail_h"]

    # Main deck house — primary wheelhouse box.
    parts.append(box_part("deck_house", (hx, hy, hz), (house_x, house_y, house_z),
                          COL_HOUSE, R_PAINT, 0.05))

    # Dark window strip across the front of the deck house. Inset z so it sits
    # just outside the front face. Y is mid-height, slightly above the floor.
    win_h = hy * 0.42
    win_w = hx * 0.86
    win_y = house_y + hy * 0.18
    win_z = house_z + hz * 0.5 + 0.005
    parts.append(box_part("bridge_windows", (win_w, win_h, 0.03),
                          (house_x, win_y, win_z),
                          COL_WINDOWS, R_GLASS, 0.0))

    # Door on the side of the deck house (front-port corner).
    door_h = hy * 0.55
    parts.append(box_part("door", (0.04, door_h, hz * 0.35),
                          (house_x - hx * 0.5 - 0.02, house_y - hy * 0.5 + door_h * 0.5, house_z + hz * 0.15),
                          COL_DOOR, R_PAINT, 0.0))

    # Roof / top deck — slightly wider than the house, gives the wheelhouse a brim.
    parts.append(box_part("roof", (rx, ry, rz), (roof_x, roof_y, roof_z),
                          COL_HOUSE_ALT, R_PAINT, 0.05))

    # Bridge wings — port + starboard outrigger walkways at the roof level.
    parts.append(box_part("wing_port", (wx, wy, wz),
                          (-hx * 0.5 - wx * 0.5, wing_y, wing_z),
                          COL_HOUSE_ALT, R_PAINT, 0.05))
    parts.append(box_part("wing_starboard", (wx, wy, wz),
                          ( hx * 0.5 + wx * 0.5, wing_y, wing_z),
                          COL_HOUSE_ALT, R_PAINT, 0.05))

    # Funnel — main stack + red cap band.
    parts.append(box_part("funnel", (fx, fy, fz),
                          tuple(fpos),
                          COL_FUNNEL, 0.75, 0.4))
    cap_h = 0.10 * (fy / 0.85)  # scaled cap height
    cap_w = fx * 1.18
    cap_d = fz * 1.18
    parts.append(box_part("funnel_cap", (cap_w, cap_h, cap_d),
                          (fpos[0], fpos[1] + fy * 0.5 + cap_h * 0.5, fpos[2]),
                          COL_FUNNEL_CAP, 0.55, 0.1))

    # Mast — vertical pole rising from roof centre. Aft of the deck house slightly.
    mast_d = max(0.06, hx * 0.025)
    mast_y = roof_y + ry * 0.5 + mast_h * 0.5
    parts.append(box_part("mast", (mast_d, mast_h, mast_d),
                          (0.0, mast_y, roof_z + rz * 0.1),
                          COL_STEEL, R_STEEL, 0.6))

    # Mast crossbar (yard) — horizontal beam at upper mast.
    yard_w = hx * 0.35
    yard_y = mast_y + mast_h * 0.25
    parts.append(box_part("mast_yard", (yard_w, mast_d * 0.9, mast_d * 0.9),
                          (0.0, yard_y, roof_z + rz * 0.1),
                          COL_STEEL, R_STEEL, 0.6))

    # Antenna — thin extra mast on top of the yard.
    ant_h = mast_h * 0.35
    parts.append(box_part("antenna", (mast_d * 0.5, ant_h, mast_d * 0.5),
                          (0.0, yard_y + ant_h * 0.6, roof_z + rz * 0.1),
                          COL_STEEL, R_STEEL, 0.7))

    # Railings around the upper deck (roof). 4 sides, each a thin strip.
    # We use long thin boxes rather than discrete posts — keeps polycount low.
    rail_t = 0.04  # rail thickness
    rail_y_center = roof_y + ry * 0.5 + rail_h * 0.5
    # Forward rail (front of roof)
    parts.append(box_part("rail_fwd",
                          (rx * 0.96, rail_h * 0.18, rail_t),
                          (roof_x, rail_y_center + rail_h * 0.4, roof_z + rz * 0.5 - rail_t * 0.5),
                          COL_STEEL, R_STEEL, 0.5))
    # Aft rail
    parts.append(box_part("rail_aft",
                          (rx * 0.96, rail_h * 0.18, rail_t),
                          (roof_x, rail_y_center + rail_h * 0.4, roof_z - rz * 0.5 + rail_t * 0.5),
                          COL_STEEL, R_STEEL, 0.5))
    # Port rail
    parts.append(box_part("rail_port",
                          (rail_t, rail_h * 0.18, rz * 0.96),
                          (roof_x - rx * 0.5 + rail_t * 0.5, rail_y_center + rail_h * 0.4, roof_z),
                          COL_STEEL, R_STEEL, 0.5))
    # Starboard rail
    parts.append(box_part("rail_starboard",
                          (rail_t, rail_h * 0.18, rz * 0.96),
                          (roof_x + rx * 0.5 - rail_t * 0.5, rail_y_center + rail_h * 0.4, roof_z),
                          COL_STEEL, R_STEEL, 0.5))

    # External ladder from main deck up the aft side of the deck house.
    # Rendered as a single slanted strip — cheap but reads as a ladder.
    ladder_h = hy
    ladder_z = house_z - hz * 0.5 - 0.06
    parts.append(box_part("ladder_aft",
                          (0.32, ladder_h, 0.04),
                          (house_x + hx * 0.3, house_y - 0.05, ladder_z),
                          COL_STEEL, R_STEEL, 0.5,
                          rotation=(-12, 0, 0)))  # slight lean for "ladder" feel

    return parts


def build_bridge_slots(cfg):
    """Return a slots dict for one bridge."""
    hx, hy, hz = cfg["house"]
    house_x, house_y, house_z = cfg["house_pos"]
    rx, ry, rz = cfg["roof"]
    roof_x, roof_y, roof_z = cfg["roof_pos"]
    mast_h = cfg["mast_h"]
    # Bridge interactable position — front centre of the deck house.
    bridge_interact = [house_x, house_y, house_z]
    return {
        # Light positions in the bridge's local space — ShipBuilder reads
        # these and spawns ShipLight nodes at the right place. Slot names
        # use the format `light_<type>` where <type> matches the enum
        # spelling consumed by ShipBuilder._light_type_from_string.
        "light_window":        [house_x, house_y, house_z + hz * 0.5 - 0.1],
        "light_nav_masthead":  [0.0, roof_y + ry * 0.5 + mast_h * 0.85, roof_z + rz * 0.1],
        "light_nav_port":      [-hx * 0.5 - 0.05, house_y - hy * 0.18, house_z + hz * 0.45],
        "light_nav_starboard": [ hx * 0.5 + 0.05, house_y - hy * 0.18, house_z + hz * 0.45],
        # Bridge interactable position (player boards here).
        "bridge_interactable":  bridge_interact,
    }


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, cfg in SHIPS.items():
        path = os.path.join(OUT_DIR, f"{name}.json")
        data = {
            "name": name,
            "parts": build_bridge_parts(cfg),
            "slots": build_bridge_slots(cfg),
            "interactable": {
                "exit_deck_offset": list(cfg["interact_exit"]),
            },
        }
        with open(path, "w") as f:
            f.write(json.dumps(data, indent=2) + "\n")
        print(f"OK {path}: {len(data['parts'])} parts")


if __name__ == "__main__":
    main()
