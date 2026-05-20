#!/usr/bin/env python3
"""Add a `lights` array to each hull JSON. Positions are derived from the
hull's length/beam so the lights sit at sensible places without manual
tuning. Bridge-mounted lights (masthead, window, plus the bridge-wing
nav_port/nav_starboard already in the .tscn bridges) stay on the
superstructure scene; we only add stern + work lights here so we don't
duplicate what the bridge already has."""

import json
import sys
import os

HULLS_DIR = "resources/data/models/hulls"

# Hull dimensions derived from the hull_upper part vertices. Y is up,
# Z is the length axis post-rotation (so +Z is bow).
def hull_dims(d):
    for p in d.get("parts", []):
        if p.get("name") == "hull_upper":
            v = p["mesh"]["vertices"]
            xs = [v[i] for i in range(0, len(v), 3)]
            ys = [v[i] for i in range(1, len(v), 3)]
            zs = [v[i] for i in range(2, len(v), 3)]
            # Raw mesh: X is length (bow-stern), Z is beam (port-stbd). After
            # the part's rotation_degrees [0,-90,0], world X becomes Z and
            # world Z becomes X. So in the FINAL coordinate system used by
            # slots, length axis is Z and beam axis is X.
            return {
                "length": max(xs) - min(xs),
                "beam":   max(zs) - min(zs),
                "height": max(ys) - min(ys),
                "deck_y": max(ys),  # top of hull_upper = deck level
                "stern_z": -((max(xs) - min(xs)) * 0.5),  # in final-space, length is Z
                "bow_z":   (max(xs) - min(xs)) * 0.5,
            }
    return None

def lights_for_hull(dims):
    """Return the `lights` array for a hull of these dimensions."""
    L = dims["length"]
    deck = dims["deck_y"]
    stern_z = dims["stern_z"] + 0.5   # slightly inboard of the transom
    out = []
    # Stern nav light — white, low aft, centerline
    out.append({
        "type": "nav_stern",
        "position": [0.0, round(deck + 0.2, 2), round(stern_z, 2)],
    })
    # Deck work lights — count scales with hull length
    if L < 16:
        work_positions_z = [0.0]
    elif L < 28:
        work_positions_z = [L * 0.18, -L * 0.18]
    elif L < 45:
        work_positions_z = [L * 0.25, 0.0, -L * 0.25]
    else:
        work_positions_z = [L * 0.3, L * 0.1, -L * 0.1, -L * 0.3]
    # Mount work lights ~1 m above deck so the spot can flood down
    for wz in work_positions_z:
        out.append({
            "type": "work",
            "position": [0.0, round(deck + 1.0, 2), round(wz, 2)],
        })
    return out

def main():
    files = sorted(os.listdir(HULLS_DIR))
    for fname in files:
        if not fname.endswith(".json"):
            continue
        path = os.path.join(HULLS_DIR, fname)
        with open(path) as f:
            data = json.load(f)
        dims = hull_dims(data)
        if dims is None:
            print(f"SKIP {fname}: no hull_upper part")
            continue
        # Skip if already has lights (idempotent)
        if "lights" in data:
            print(f"SKIP {fname}: already has lights")
            continue
        data["lights"] = lights_for_hull(dims)
        # Pretty-print with 2-space indent, matching existing style
        text = json.dumps(data, indent=2)
        with open(path, "w") as f:
            f.write(text + "\n")
        print(f"OK {fname}: added {len(data['lights'])} lights")

if __name__ == "__main__":
    main()
