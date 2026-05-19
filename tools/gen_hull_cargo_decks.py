#!/usr/bin/env python3
"""Add a `cargo_decks` array to each hull JSON. Dimensions are derived
from the hull's bounding box: deck takes ~80% of beam, ~75-90% of
length minus the superstructure footprint. Multi-deck hulls (those that
already had cargo_main + cargo_aft slots) get the same split positions
the legacy slot-only system used."""

import json
import os

HULLS_DIR = "resources/data/models/hulls"

def hull_dims(d):
    for p in d.get("parts", []):
        if p.get("name") == "hull_upper":
            v = p["mesh"]["vertices"]
            xs = [v[i] for i in range(0, len(v), 3)]
            ys = [v[i] for i in range(1, len(v), 3)]
            zs = [v[i] for i in range(2, len(v), 3)]
            return {
                "length": max(xs) - min(xs),
                "beam":   max(zs) - min(zs),
                "height": max(ys) - min(ys),
                "deck_y": max(ys),
            }
    return None

def cargo_decks_for_hull(name, dims, existing_slots):
    """Return cargo_decks array. Use existing slots as the source of truth
    for which decks the hull supports, with derived sizes."""
    L = dims["length"]
    B = dims["beam"]
    deck_y = dims["deck_y"]
    # Bridge is at slot["bridge"] z (negative = aft). Reserve room for it.
    bridge_z = 0.0
    if "bridge" in existing_slots:
        bridge_z = float(existing_slots["bridge"][2])
    out = []
    deck_top_y = round(deck_y + 0.05, 2)  # pallets sit just above deck plate
    deck_w = round(B * 0.78, 2)
    # Choose a cell size sensible for this hull class — bigger ships handle bigger pallets.
    if L < 16:
        cell = 1.0
    elif L < 28:
        cell = 1.25
    elif L < 45:
        cell = 1.5
    else:
        cell = 1.5
    # If hull has both cargo_main + cargo_aft, split fore/aft of bridge.
    has_main = "cargo_main" in existing_slots
    has_aft  = "cargo_aft"  in existing_slots
    has_fwd  = "cargo_fwd"  in existing_slots
    if has_main and has_aft:
        # Big ships: cargo_main forward of bridge, cargo_aft astern.
        # Bridge is typically aft on real cargo ships; use it as the boundary.
        # Forward deck: from bow (L/2 - margin) down to bridge_z + 1m.
        bow_z = L / 2 - 1.0
        main_len = round((bow_z - (bridge_z + 1.0)), 2)
        main_z = round((bow_z + (bridge_z + 1.0)) / 2, 2)
        out.append({
            "name":        "main",
            "position":    [0.0, deck_top_y, main_z],
            "deck_width":  deck_w,
            "deck_length": main_len,
            "cell_size":   cell,
        })
        # Aft deck: from bridge_z - 2m down to stern.
        stern_z = -L / 2 + 1.0
        aft_len = round(((bridge_z - 2.0) - stern_z), 2)
        aft_z = round((stern_z + (bridge_z - 2.0)) / 2, 2)
        if aft_len >= 2.0:
            out.append({
                "name":        "aft",
                "position":    [0.0, deck_top_y, aft_z],
                "deck_width":  deck_w,
                "deck_length": aft_len,
                "cell_size":   cell,
            })
    elif has_main and has_fwd:
        # hull_cargo_ship layout: two side-by-side decks fore.
        bow_z = L / 2 - 1.0
        midbridge = bridge_z + 1.0 if bridge_z < 0 else -L * 0.2
        avail_len = bow_z - midbridge
        # Split in half along Z.
        seg = round(avail_len / 2.0, 2)
        out.append({
            "name":        "main",
            "position":    [0.0, deck_top_y, round(midbridge + seg / 2, 2)],
            "deck_width":  deck_w,
            "deck_length": seg,
            "cell_size":   cell,
        })
        out.append({
            "name":        "fwd",
            "position":    [0.0, deck_top_y, round(midbridge + seg + seg / 2, 2)],
            "deck_width":  deck_w,
            "deck_length": seg,
            "cell_size":   cell,
        })
    elif has_main:
        # Single deck filling from bow down to just forward of the bridge.
        bow_z = L / 2 - 1.0
        # Avoid overlap with bridge — keep 1.5 m buffer.
        rear_z = (bridge_z + 1.5) if bridge_z < 0 else -L * 0.3
        deck_len = round(bow_z - rear_z, 2)
        center_z = round((bow_z + rear_z) / 2, 2)
        out.append({
            "name":        "main",
            "position":    [0.0, deck_top_y, center_z],
            "deck_width":  deck_w,
            "deck_length": deck_len,
            "cell_size":   cell,
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
        if "cargo_decks" in data:
            print(f"SKIP {fname}: already has cargo_decks")
            continue
        slots = data.get("slots", {})
        decks = cargo_decks_for_hull(fname, dims, slots)
        data["cargo_decks"] = decks
        text = json.dumps(data, indent=2)
        with open(path, "w") as f:
            f.write(text + "\n")
        print(f"OK {fname}: added {len(decks)} cargo decks")

if __name__ == "__main__":
    main()
