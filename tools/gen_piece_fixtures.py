#!/usr/bin/env python3
"""Emit the piece placements for the two piece-built fixtures.

    python3 tools/gen_piece_fixtures.py      # run from the repo root

Writes resources/data/structures/probe_piece_trawler.json (the comparison: the
trawler with a piece-built deckhouse and everything else verbatim) and
probe_piece_house.json (the strict one: zero hand-authored plate corners).

Every entry is a PLACEMENT: a piece id, a whole-cell grid node, a facing off
{0,90,180,270} and parameters off each piece's declared set.  Nothing here is a
coordinate; the coordinates come out of piece_kit.gd.
"""
import json, collections

CELL = 0.5
WALL = "#e3e0d4"
DECKGREY = "#4d5257"
ROOFGREY = "#858a8f"
OCHRE = "#9e5c1c"
BLACK = "#1c1c1f"

P = []
_n = [200]


def place(piece, cell, facing, params=None, color=None, note=""):
    e = {"id": _n[0], "piece": piece, "cell": list(cell), "facing": facing}
    if params:
        e["params"] = params
    if color:
        e["color"] = color
    if note:
        e["_is"] = note
    _n[0] += 1
    P.append(e)
    return e


def run(piece, start_cell, facing, spans, base_params, color=None, note=""):
    """A RUN of panels along one wall line.  `spans` is [(cells, extra), ...];
    consecutive panels advance along the run direction, which is what makes a
    wall a sequence of placements instead of one tailored plate."""
    cx, cy, cz = start_cell
    # run direction in CELLS for each facing: local +X after yaw
    step = {0: (1, 0), 90: (0, -1), 180: (-1, 0), 270: (0, 1)}[facing]
    for cells, extra in spans:
        params = dict(base_params)
        params["span"] = cells
        params.update(extra)
        place(piece, (cx, cy, cz), facing, params, color, note)
        cx += step[0] * cells
        cz += step[1] * cells
    return (cx, cy, cz)


# ── LOWER TIER ───────────────────────────────────────────────────────────────
# footprint x 2.5..7.5 m (cells 5..15), z 17.5..25.0 (cells 35..50), 5 cells tall.
# front rakes 2 quarter-cells (0.50 m) forward; sides tumble home 1 (0.25 m);
# the aft bulkhead rakes 1 aft.  All four corners are corner_45 knuckles, and
# each one is handed the rakes of the two walls it joins.
LT = {"height": 5}
place("corner_45", (5, 0, 35), 0, {"span": 1, "height": 5, "rake_a": 2, "rake_b": -1},
      WALL, "lower tier, forward port knuckle")
place("corner_45", (15, 0, 35), 270, {"span": 1, "height": 5, "rake_a": -1, "rake_b": 2},
      WALL, "lower tier, forward starboard knuckle")
place("corner_45", (5, 0, 50), 90, {"span": 1, "height": 5, "rake_a": -1, "rake_b": 1},
      WALL, "lower tier, after port knuckle")
place("corner_45", (15, 0, 50), 180, {"span": 1, "height": 5, "rake_a": 1, "rake_b": -1},
      WALL, "lower tier, after starboard knuckle")

# Accommodation lights are a BAND, not a row of holes: a dark value is what
# reads as glass at capture distance, and the ferry proved the alternative reads
# as portholes.  sill 3 / band 1 puts the band low and thin, which is what an
# accommodation deck looks like against a wheelhouse's deep one.
LIGHTS = {"height": 5, "rake": -1, "sill": 3, "band": 1}

place("wall_panel", (6, 0, 35), 0, {"span": 1, "height": 5, "rake": 2}, WALL,
      "lower tier, raked front, port cheek")
place("wall_glazed", (7, 0, 35), 0,
      {"span": 6, "height": 5, "rake": 2, "sill": 3, "band": 1, "lights": 3}, WALL,
      "lower tier, raked front, mess lights")
place("wall_panel", (13, 0, 35), 0, {"span": 1, "height": 5, "rake": 2}, WALL,
      "lower tier, raked front, starboard cheek")

place("wall_panel", (5, 0, 49), 90, {"span": 2, "height": 5, "rake": -1, "opening": "door"},
      WALL, "lower tier, port side, accommodation door")
place("wall_glazed", (5, 0, 47), 90, dict(LIGHTS, span=8, lights=4), WALL,
      "lower tier, port side, mess lights")
place("wall_panel", (5, 0, 39), 90, {"span": 3, "height": 5, "rake": -1}, WALL,
      "lower tier, port side, forward")

place("wall_panel", (15, 0, 36), 270, {"span": 3, "height": 5, "rake": -1}, WALL,
      "lower tier, starboard side, forward")
place("wall_glazed", (15, 0, 39), 270, dict(LIGHTS, span=8, lights=4), WALL,
      "lower tier, starboard side, mess lights")
place("wall_panel", (15, 0, 47), 270, {"span": 2, "height": 5, "rake": -1, "opening": "door"},
      WALL, "lower tier, starboard side, accommodation door")

run("wall_panel", (14, 0, 50), 180,
    [(3, {}), (2, {"opening": "door"}), (3, {})],
    {"height": 5, "rake": 1}, WALL, "lower tier, aft bulkhead")

# ── BOAT DECK ────────────────────────────────────────────────────────────────
# Laid on the grid at its own level and NOT derived from the walls beneath it.
# x 2.0..8.0, z 17.0..25.5 — the overhang that results IS the eave.
place("deck_tile", (4, 5, 34), 0, {"span": 12, "depth": 16, "gauge": "deck"},
      DECKGREY, "boat deck")
place("deck_tile", (4, 5, 50), 0, {"span": 12, "depth": 1, "gauge": "deck"},
      DECKGREY, "boat deck, after strip")

# Coaming lip round the open side edges of the boat deck.
run("trim_band", (4, 5, 51), 90, [(16, {}), (1, {})],
    {"profile": "coaming"}, WALL, "boat deck coaming, port")
run("trim_band", (16, 5, 34), 270, [(16, {}), (1, {})],
    {"profile": "coaming"}, WALL, "boat deck coaming, starboard")

# ── WHEELHOUSE ───────────────────────────────────────────────────────────────
# x 3.0..7.0 (cells 6..14), z 19.0..23.0 (cells 38..46), on the boat deck at
# cy 5, 5 cells tall.  The windscreen rakes the full 4 quarter-cells (1.00 m
# over 2.50 m = 21.8 deg); the sides tumble home 1; the aft bulkhead rakes 1 aft.
place("corner_45", (6, 5, 38), 0, {"span": 1, "height": 5, "rake_a": 4, "rake_b": -1},
      WALL, "wheelhouse, forward port knuckle")
place("corner_45", (14, 5, 38), 270, {"span": 1, "height": 5, "rake_a": -1, "rake_b": 4},
      WALL, "wheelhouse, forward starboard knuckle")
place("corner_45", (6, 5, 46), 90, {"span": 1, "height": 5, "rake_a": -1, "rake_b": 1},
      WALL, "wheelhouse, after port knuckle")
place("corner_45", (14, 5, 46), 180, {"span": 1, "height": 5, "rake_a": 1, "rake_b": -1},
      WALL, "wheelhouse, after starboard knuckle")

place("wall_glazed", (7, 5, 38), 0,
      {"span": 6, "height": 5, "rake": 4, "sill": 2, "band": 2, "lights": 4},
      WALL, "wheelhouse, raked windscreen")
place("wall_glazed", (6, 5, 45), 90,
      {"span": 6, "height": 5, "rake": -1, "sill": 2, "band": 2, "lights": 4},
      WALL, "wheelhouse, port side lights")
place("wall_glazed", (14, 5, 39), 270,
      {"span": 6, "height": 5, "rake": -1, "sill": 2, "band": 2, "lights": 4},
      WALL, "wheelhouse, starboard side lights")
place("wall_glazed", (13, 5, 46), 180,
      {"span": 6, "height": 5, "rake": 1, "sill": 2, "band": 2, "lights": 3},
      WALL, "wheelhouse, aft bulkhead")

# Wheelhouse roof: x 2.5..7.5, z 18.5..23.5, half a metre of eave all round.
# Four tiles rather than one custom 10x10 slab: 10 is not a size the kit sells,
# and tiling is what a player does anyway.
place("deck_tile", (5, 10, 37), 0, {"span": 8, "depth": 8, "gauge": "deck"},
      ROOFGREY, "wheelhouse roof")
place("deck_tile", (13, 10, 37), 0, {"span": 2, "depth": 8, "gauge": "deck"},
      ROOFGREY, "wheelhouse roof, starboard strip")
place("deck_tile", (5, 10, 45), 0, {"span": 8, "depth": 2, "gauge": "deck"},
      ROOFGREY, "wheelhouse roof, after strip")
place("deck_tile", (13, 10, 45), 0, {"span": 2, "depth": 2, "gauge": "deck"},
      ROOFGREY, "wheelhouse roof, after quarter")

# ── FUNNEL ───────────────────────────────────────────────────────────────────
# The kit was not designed for funnels and gets one for free: four faces at
# rake -1 (a 0.25 m taper over 3.00 m) with a knuckle at each corner, capped by
# a heavy deck tile.  Nothing here is a funnel piece.
FUN = {"height": 6, "rake": -1}
place("corner_45", (8, 5, 47), 0, {"span": 1, "height": 6, "rake_a": -1, "rake_b": -1},
      OCHRE, "funnel, forward port knuckle")
place("corner_45", (12, 5, 47), 270, {"span": 1, "height": 6, "rake_a": -1, "rake_b": -1},
      OCHRE, "funnel, forward starboard knuckle")
place("corner_45", (8, 5, 50), 90, {"span": 1, "height": 6, "rake_a": -1, "rake_b": -1},
      OCHRE, "funnel, after port knuckle")
place("corner_45", (12, 5, 50), 180, {"span": 1, "height": 6, "rake_a": -1, "rake_b": -1},
      OCHRE, "funnel, after starboard knuckle")
place("wall_panel", (9, 5, 47), 0, dict(FUN, span=2), OCHRE, "funnel, forward face")
place("wall_panel", (11, 5, 50), 180, dict(FUN, span=2), OCHRE, "funnel, aft face")
place("wall_panel", (8, 5, 49), 90, dict(FUN, span=1), OCHRE, "funnel, port face")
place("wall_panel", (12, 5, 48), 270, dict(FUN, span=1), OCHRE, "funnel, starboard face")
place("deck_tile", (8, 11, 47), 0, {"span": 4, "depth": 3, "gauge": "heavy"},
      BLACK, "funnel cap")


NOTE = """PIECE-BUILT. The deckhouse on this vessel contains ZERO hand-authored plate corners: it is
{n} placements of standard pieces on the 0.5 m deck grid, resolved by scripts/construction/piece_kit.gd
into exactly the `plate` primitives StructureBaker already bakes. Everything else in this file - the
sheer-band bulwark, the bow bulwark plating, the gallows steelwork and the spar and wire rig - is
probe_trawler_bulwark.json verbatim, so a side-by-side capture isolates the deckhouse and nothing else.

WHAT REPLACED WHAT. {removed} of that fixture's plate items were the deckhouse: the lower tier, its glass
and mullions, the boat deck, a three-band wheelhouse with every mullion and corner pillar positioned
individually, and a tapered funnel. Every one of them was a quad an agent solved by hand. All {removed}
are gone. In their place: {walls} wall panels, {glazed} glazed panels, {corners} corner facets,
{decks} deck tiles and {trims} trim runs, not one of which knows this vessel exists.

The {kept} authored plates that REMAIN are bow bulwark plating and gallows steelwork, and they remain on
purpose. A bulwark follows the sheer, which is a swept curve; quantising it to 0.5 m would step the one
curve the whole fleet was rebuilt to draw. That is a boundary of the kit, stated rather than papered over.

THE CORNERS ARE THE WHOLE ARGUMENT. In the hand-authored version the raked front's 0.55 m overhang was
smeared into the side plates as a twist running their whole 7.3 m length - a bespoke move, and the reason
those side plates could not have been standard pieces. Here the front rakes 2 quarter-cells, the sides
tumble home 1, and a `corner_45` knuckle at each of the four corners carries the difference. Its plate is
bilinear, so a twisted quad is exactly what it is for. The by-product is that every corner on this
deckhouse is chamfered, which is the one shape a stack of square panels cannot make.

WHAT THIS FIXTURE CANNOT SAY, and it is not hidden: the hand-authored version's boat deck fell 0.24 m
over 8.4 m and its sides tapered 0.30 m in plan over 7.3 m. Both are under a quarter-cell and neither
survives the grid. The house is 2.50 m to the boat deck where the original was 2.74.
"""


def build():
    src = json.load(open("resources/data/structures/probe_trawler_bulwark.json"))
    # The deckhouse as probe_trawler_bulwark authors it: the lower tier, the boat
    # deck, the wheelhouse and the funnel (100-122), plus the glass, mullions and
    # corner pillars a later pass added (400-438).  Everything else on that
    # vessel is bow bulwark, gallows steelwork and rigging and is kept verbatim.
    deckhouse = set(range(100, 123)) | set(range(400, 439))
    kept = [i for i in src["items"] if i["id"] not in deckhouse]
    left = sum(1 for i in kept if i.get("props", {}).get("primitive") == "plate")
    assert left == 39, "expected 39 non-deckhouse plates, got %d" % left
    counts = collections.Counter(p["piece"] for p in P)
    out = collections.OrderedDict()
    out["format"] = src["format"]
    out["context"] = src["context"]
    out["hull_id"] = src["hull_id"]
    removed = sum(1 for i in src["items"]
                  if i["id"] in deckhouse and i.get("props", {}).get("primitive") == "plate")
    out["_note"] = NOTE.format(
        n=len(P), removed=removed, kept=left,
        walls=counts["wall_panel"], glazed=counts["wall_glazed"],
        corners=counts["corner_45"], decks=counts["deck_tile"], trims=counts["trim_band"])
    out["palette"] = src["palette"]
    out["hull"] = src["hull"]
    out["walls"] = src["walls"]
    out["decks"] = src["decks"]
    out["stairs"] = src["stairs"]
    out["pieces"] = P
    out["items"] = kept
    out["edges"] = src["edges"]
    with open("resources/data/structures/probe_piece_trawler.json", "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print("probe_piece_trawler.json: %d placements, %d kept items (%d of them plates)"
          % (len(P), len(kept),
             sum(1 for i in kept if i.get("props", {}).get("primitive") == "plate")))

    # The strict fixture: the same deckhouse and NOTHING hand-authored anywhere.
    house = collections.OrderedDict()
    house["format"] = src["format"]
    house["context"] = src["context"]
    house["hull_id"] = src["hull_id"]
    house["_note"] = (
        "THE STRICT ONE. Zero hand-authored plate corners in this file, full stop, and zero `items[]` of "
        "any kind: the whole superstructure is {n} piece placements, and the only other entity is the "
        "hull's own sheer-band bulwark, which is a SWEPT CURVE and is deliberately not a grid piece - "
        "quantising a sheer to 0.5 m would step the one curve the fleet was rebuilt to draw.\n\n"
        "It carries the trawler's deckhouse unchanged plus the parts of the kit that vessel never asks "
        "for, so nothing in the kit ships unproven: a `roof_slope` foredeck breakwater rising two cells "
        "over two, its after face and its eave, and the `cap` and `strake` profiles of `trim_band` - the "
        "strakes set out one quarter-cell with `offset`, because a trim run has no height and cannot "
        "carry a rake, so on a raked wall it has to be pushed out to meet it."
    ).format(n=len(P) + 6)
    house["palette"] = src["palette"]
    house["hull"] = src["hull"]
    house["walls"] = []
    house["decks"] = []
    house["stairs"] = []
    strict = [dict(p) for p in P]
    nid = [max(p["id"] for p in P) + 1]

    def add(piece, cell, facing, params=None, color=None, note=""):
        e = {"id": nid[0], "piece": piece, "cell": list(cell), "facing": facing}
        if params:
            e["params"] = params
        if color:
            e["color"] = color
        if note:
            e["_is"] = note
        nid[0] += 1
        strict.append(e)

    # A breakwater on the foredeck - a spray deflector sloping up as it runs aft.
    # This is `roof_slope` doing the job it exists for, and the trawler itself
    # never asks for it, so it ships here rather than shipping unproven.
    add("roof_slope", (6, 0, 20), 0, {"span": 6, "depth": 2, "rise": 2, "gauge": "light"},
        ROOFGREY, "foredeck breakwater - two cells of rise over two of run")
    add("wall_panel", (12, 0, 22), 180, {"span": 6, "height": 2, "rake": 0}, WALL,
        "breakwater, after face")
    add("trim_band", (12, 2, 22), 180, {"span": 6, "profile": "eave"}, WALL,
        "eave along the breakwater's after edge")
    # The three trim profiles the trawler does not ask for, each on a wall whose
    # rake it has to be set out to meet: `offset` is what makes that possible.
    add("trim_band", (4, 5, 34), 0, {"span": 12, "profile": "cap"}, OCHRE,
        "cap rail across the forward edge of the boat deck")
    add("trim_band", (6, 2, 35), 0, {"span": 8, "profile": "strake", "offset": 1}, OCHRE,
        "rubbing strake across the raked deckhouse front, set out one quarter-cell to meet it")
    add("trim_band", (14, 1, 50), 180, {"span": 8, "profile": "strake", "offset": 1}, OCHRE,
        "rubbing strake across the raked aft bulkhead")

    house["pieces"] = strict
    house["items"] = []
    house["edges"] = src["edges"]
    with open("resources/data/structures/probe_piece_house.json", "w") as f:
        json.dump(house, f, indent=1)
        f.write("\n")
    print("probe_piece_house.json: %d placements, 0 items" % len(strict))
    print(collections.Counter(p["piece"] for p in strict))


build()
