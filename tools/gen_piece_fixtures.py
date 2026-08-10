#!/usr/bin/env python3
"""Emit the piece placements for the two piece-built fixtures.

    python3 tools/gen_piece_fixtures.py      # run from the repo root

Writes resources/data/structures/probe_piece_trawler.json (the comparison: the
trawler with a piece-built deckhouse and everything else verbatim) and
probe_piece_house.json (the strict one: zero hand-authored plate corners).

Every entry is a PLACEMENT: a piece id, a whole-cell grid node, a facing off
{0,90,180,270} and parameters off each piece's declared set.  Nothing here is a
coordinate; the coordinates come out of piece_kit.gd.

── VERSION 2 OF THE KIT, AND WHY THIS FILE IS FULL OF ARITHMETIC ──────────────

Version 1 built this deckhouse dead flat and 0.24 m short, and said so.  The kit
now carries `head` (eighth-cells added to a wall's top), `fall` (eighth-cells the
top edge drops over the run) and `lift` (eighth-cells the whole piece stands off
its grid node), so the tier can be 2.75 m at the stem and 2.50 m at the transom
with a boat deck that falls between them.

The arithmetic below is not coordinate authoring: every number that reaches a
placement is a COUNT off a declared set.  What the arithmetic does is pick which
count, by measuring the hand-authored original — `TARGET` — and reporting the
residual.  Run this file and it prints the residual on every one of them.
"""
import json, collections
import plan_ids

CELL = 0.5
E = 0.125                      # one eighth-cell: the kit's trim step
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


# ── THE HAND-AUTHORED ORIGINAL, MEASURED ─────────────────────────────────────
# Read straight off probe_trawler_bulwark.json's plate corners.  Every one of
# these is a number the piece build is trying to hit, and the residual on each is
# printed at the end of this run rather than claimed in a comment.
TARGET = {
    # lower tier: top of the raked front / top of the aft bulkhead
    "tier_head_fwd": 2.74,
    "tier_head_aft": 2.50,
    # the boat deck plate, forward edge and after edge
    "deck_fwd_y": 2.7441, "deck_fwd_z": 16.91,
    "deck_aft_y": 2.4959, "deck_aft_z": 25.29,
    # side plating: how far the top edge tumbles home from its foot
    "tumblehome_fwd": 0.15, "tumblehome_aft": 0.13,
    # raked front: how far the top overhangs its foot
    "front_rake": 0.55,
    # wheelhouse windscreen rake, and the roof it carries
    "screen_rake": 0.85,
    "wh_top_fwd_y": 5.05, "wh_top_fwd_z": 18.15,
    "wh_top_aft_y": 4.75, "wh_top_aft_z": 23.70,
    "wh_foot_fwd": 2.6822, "wh_foot_aft": 2.5519,
    # funnel
    "funnel_foot": 2.4823, "funnel_top": 5.35,
    "funnel_fwd_rake": 0.40, "funnel_side_taper": 0.30, "funnel_aft_rake": 0.20,
}
RESID = []


def note_residual(what, target, built, unit="m"):
    RESID.append((what, target, built, built - target, unit))
    return built


def plan_y(cy, lift):
    """Plan-space height of a placement: whole cells plus eighth-cell lift."""
    return cy * CELL + lift * E


# ── LOWER TIER ───────────────────────────────────────────────────────────────
# footprint x 2.5..7.5 m (cells 5..15), z 17.5..25.0 (cells 35..50).
#
# THE TIER IS NO LONGER A BOX.  height 5 (2.50 m) is the whole-cell part; `head`
# adds eighth-cells on top, and the side runs carry a `fall` so the top edge
# walks DOWN from 2.75 m at the stem to 2.50 m at the transom in two steps of
# 0.125 m.  The boat deck laid over it falls the same 0.25 m as one plate, so the
# deck is a true plane and the wall tops are a chord of it.
#
#   z cell   35     36        39        47     49    50
#   top      2.75 ─ 2.75 ╲    2.625 ╲   2.50 ─ 2.50 ─ 2.50
#
# Front rakes 4 eighth-cells (0.50 m) forward; sides tumble home 1 (0.125 m,
# where version 1 had to say 0.25); the aft bulkhead rakes 2 (0.25 m).
HEAD_FWD = 2      # 2.75 m at the stem end of the tier
HEAD_MID = 1      # 2.625 m
HEAD_AFT = 0      # 2.50 m at the transom end
TUMBLE = -1       # 0.125 m of tumblehome, half version 1's smallest step
FRONT_RAKE = 4    # 0.50 m
AFT_RAKE = 2      # 0.25 m

note_residual("lower tier head, forward", TARGET["tier_head_fwd"], 5 * CELL + HEAD_FWD * E)
note_residual("lower tier head, aft", TARGET["tier_head_aft"], 5 * CELL + HEAD_AFT * E)
note_residual("side tumblehome, forward", TARGET["tumblehome_fwd"], -TUMBLE * E)
note_residual("side tumblehome, aft", TARGET["tumblehome_aft"], -TUMBLE * E)
note_residual("raked front overhang", TARGET["front_rake"], FRONT_RAKE * E)

place("corner_45", (5, 0, 35), 0,
      {"span": 1, "height": 5, "head": HEAD_FWD, "rake_a": FRONT_RAKE, "rake_b": TUMBLE},
      WALL, "lower tier, forward port knuckle")
place("corner_45", (15, 0, 35), 270,
      {"span": 1, "height": 5, "head": HEAD_FWD, "rake_a": TUMBLE, "rake_b": FRONT_RAKE},
      WALL, "lower tier, forward starboard knuckle")
place("corner_45", (5, 0, 50), 90,
      {"span": 1, "height": 5, "head": HEAD_AFT, "rake_a": TUMBLE, "rake_b": AFT_RAKE},
      WALL, "lower tier, after port knuckle")
place("corner_45", (15, 0, 50), 180,
      {"span": 1, "height": 5, "head": HEAD_AFT, "rake_a": AFT_RAKE, "rake_b": TUMBLE},
      WALL, "lower tier, after starboard knuckle")

# Accommodation lights are a BAND, not a row of holes: a dark value is what
# reads as glass at capture distance, and the ferry proved the alternative reads
# as portholes.  sill 3 / band 1 puts the band low and thin, which is what an
# accommodation deck looks like against a wheelhouse's deep one.
LIGHTS = {"height": 5, "rake": TUMBLE, "sill": 3, "band": 1}

place("wall_panel", (6, 0, 35), 0, {"span": 1, "height": 5, "head": HEAD_FWD, "rake": FRONT_RAKE},
      WALL, "lower tier, raked front, port cheek")
place("wall_glazed", (7, 0, 35), 0,
      {"span": 6, "height": 5, "head": HEAD_FWD, "rake": FRONT_RAKE, "sill": 3, "band": 1, "lights": 3},
      WALL, "lower tier, raked front, mess lights")
place("wall_panel", (13, 0, 35), 0, {"span": 1, "height": 5, "head": HEAD_FWD, "rake": FRONT_RAKE},
      WALL, "lower tier, raked front, starboard cheek")

# Port side runs AFT-to-FORWARD (facing 90), so its falls are negative: the top
# edge climbs 0.125 m at each of the two joints as it walks toward the stem.
place("wall_panel", (5, 0, 49), 90,
      {"span": 2, "height": 5, "head": HEAD_AFT, "fall": 0, "rake": TUMBLE, "opening": "door"},
      WALL, "lower tier, port side, accommodation door")
place("wall_glazed", (5, 0, 47), 90, dict(LIGHTS, span=8, lights=4, head=HEAD_AFT, fall=-1),
      WALL, "lower tier, port side, mess lights — the top climbs a step forward")
place("wall_panel", (5, 0, 39), 90,
      {"span": 3, "height": 5, "head": HEAD_MID, "fall": -1, "rake": TUMBLE},
      WALL, "lower tier, port side, forward")

# Starboard runs FORWARD-to-AFT (facing 270): same wall, falls the other sign.
place("wall_panel", (15, 0, 36), 270,
      {"span": 3, "height": 5, "head": HEAD_FWD, "fall": 1, "rake": TUMBLE},
      WALL, "lower tier, starboard side, forward")
place("wall_glazed", (15, 0, 39), 270, dict(LIGHTS, span=8, lights=4, head=HEAD_MID, fall=1),
      WALL, "lower tier, starboard side, mess lights — the top falls a step aft")
place("wall_panel", (15, 0, 47), 270,
      {"span": 2, "height": 5, "head": HEAD_AFT, "fall": 0, "rake": TUMBLE, "opening": "door"},
      WALL, "lower tier, starboard side, accommodation door")

run("wall_panel", (14, 0, 50), 180,
    [(3, {}), (2, {"opening": "door"}), (3, {})],
    {"height": 5, "head": HEAD_AFT, "rake": AFT_RAKE}, WALL, "lower tier, aft bulkhead")

# ── BOAT DECK ────────────────────────────────────────────────────────────────
# ONE tile, 12 x 16 cells, and it FALLS.  Version 1 laid this dead flat because
# the kit had nothing to say; `fall` 2 drops the after edge 0.25 m over 8.00 m,
# which is 1.79 degrees where the hand-authored plate is 1.70.  `lift` 2 stands
# the forward edge at 2.75 m so the tier's head lands inside the plate.
DECK_LIFT, DECK_FALL = 2, 2
deck_fwd = plan_y(5, DECK_LIFT)
deck_aft = deck_fwd - DECK_FALL * E
note_residual("boat deck, forward edge y", TARGET["deck_fwd_y"], deck_fwd)
note_residual("boat deck, after edge y", TARGET["deck_aft_y"], deck_aft)
note_residual("boat deck FALL over its length",
              TARGET["deck_fwd_y"] - TARGET["deck_aft_y"], DECK_FALL * E)

place("deck_tile", (4, 5, 34), 0,
      {"span": 12, "depth": 16, "gauge": "deck", "fall": DECK_FALL, "lift": DECK_LIFT},
      DECKGREY, "boat deck — falls 0.25 m aft over 8.00 m")
place("deck_tile", (4, 5, 50), 0,
      {"span": 12, "depth": 1, "gauge": "deck", "fall": 0, "lift": DECK_LIFT - DECK_FALL},
      DECKGREY, "boat deck, after strip — carries the fall's end level")

# Coaming lip round the open side edges of the boat deck, in four segments that
# step down with the deck.  A trim run has no fall (it has no height to fall),
# so it follows in `lift`, and the step is 0.125 m where the deck itself has
# dropped 0.0625 — the worst departure is 0.031 m on a 0.25 m lip.
COAM_AFT_TO_FWD = [(1, 0), (4, 0), (4, 1), (4, 1), (4, 2)]
run("trim_band", (4, 5, 51), 90,
    [(cells, {"lift": lift}) for cells, lift in COAM_AFT_TO_FWD],
    {"profile": "coaming"}, WALL, "boat deck coaming, port")
run("trim_band", (16, 5, 34), 270,
    [(cells, {"lift": lift}) for cells, lift in reversed(COAM_AFT_TO_FWD)],
    {"profile": "coaming"}, WALL, "boat deck coaming, starboard")

# ── WHEELHOUSE ───────────────────────────────────────────────────────────────
# x 3.0..7.0 (cells 6..14), z 19.0..23.0 (cells 38..46), standing on the FALLING
# boat deck.  A wall's foot is level — that is a stated boundary of the kit — so
# the house sits on the MEAN of the deck under it (lift 1 = 2.625 m, and the deck
# runs 2.6875 down to 2.5625, so the foot never leaves the 0.13 m deck plate).
# Its top does fall: 5.00 m forward to 4.75 m aft, in one 0.25 m step carried by
# the two side panels.  The windscreen rakes 7 eighth-cells — 0.875 m against the
# original's 0.85, where version 1's coarsest-but-one step had to say 1.00.
WH_LIFT = 1
WH_HEAD_FWD, WH_HEAD_AFT = 3, 1
SCREEN_RAKE = 7
wh_foot = plan_y(5, WH_LIFT)
wh_top_fwd = wh_foot + 4 * CELL + WH_HEAD_FWD * E
wh_top_aft = wh_foot + 4 * CELL + WH_HEAD_AFT * E
note_residual("wheelhouse foot (mean of the deck under it)",
              (TARGET["wh_foot_fwd"] + TARGET["wh_foot_aft"]) * 0.5, wh_foot)
note_residual("windscreen rake", TARGET["screen_rake"], SCREEN_RAKE * E)
note_residual("wheelhouse ROOF fall over the house",
              TARGET["wh_top_fwd_y"] - TARGET["wh_top_aft_y"],
              (WH_HEAD_FWD - WH_HEAD_AFT) * E)

place("corner_45", (6, 5, 38), 0,
      {"span": 1, "height": 4, "head": WH_HEAD_FWD, "lift": WH_LIFT,
       "rake_a": SCREEN_RAKE, "rake_b": TUMBLE},
      WALL, "wheelhouse, forward port knuckle")
place("corner_45", (14, 5, 38), 270,
      {"span": 1, "height": 4, "head": WH_HEAD_FWD, "lift": WH_LIFT,
       "rake_a": TUMBLE, "rake_b": SCREEN_RAKE},
      WALL, "wheelhouse, forward starboard knuckle")
place("corner_45", (6, 5, 46), 90,
      {"span": 1, "height": 4, "head": WH_HEAD_AFT, "lift": WH_LIFT,
       "rake_a": TUMBLE, "rake_b": AFT_RAKE},
      WALL, "wheelhouse, after port knuckle")
place("corner_45", (14, 5, 46), 180,
      {"span": 1, "height": 4, "head": WH_HEAD_AFT, "lift": WH_LIFT,
       "rake_a": AFT_RAKE, "rake_b": TUMBLE},
      WALL, "wheelhouse, after starboard knuckle")

WH = {"height": 4, "lift": WH_LIFT, "sill": 1, "band": 2}
place("wall_glazed", (7, 5, 38), 0,
      dict(WH, span=6, head=WH_HEAD_FWD, rake=SCREEN_RAKE, lights=4),
      WALL, "wheelhouse, raked windscreen")
place("wall_glazed", (6, 5, 45), 90,
      dict(WH, span=6, head=WH_HEAD_AFT, fall=-2, rake=TUMBLE, lights=4),
      WALL, "wheelhouse, port side lights — the roofline climbs forward")
place("wall_glazed", (14, 5, 39), 270,
      dict(WH, span=6, head=WH_HEAD_FWD, fall=2, rake=TUMBLE, lights=4),
      WALL, "wheelhouse, starboard side lights — the roofline falls aft")
place("wall_glazed", (13, 5, 46), 180,
      dict(WH, span=6, head=WH_HEAD_AFT, rake=AFT_RAKE, lights=3),
      WALL, "wheelhouse, aft bulkhead")

# Wheelhouse roof: x 2.5..7.5, z 18.5..23.5, half a metre of eave all round, and
# it falls with the house.  Four tiles rather than one custom 10x10 slab: 10 is
# not a size the kit sells, and the forward pair carry the fall while the after
# pair carry its end level, which is how a falling deck chains.
ROOF_LIFT = 0
ROOF_FALL = 2
roof_fwd = plan_y(10, ROOF_LIFT)
note_residual("wheelhouse roof, forward edge y", TARGET["wh_top_fwd_y"], roof_fwd)
place("deck_tile", (5, 10, 37), 0,
      {"span": 8, "depth": 8, "gauge": "deck", "fall": ROOF_FALL, "lift": ROOF_LIFT},
      ROOFGREY, "wheelhouse roof — falls 0.25 m aft")
place("deck_tile", (13, 10, 37), 0,
      {"span": 2, "depth": 8, "gauge": "deck", "fall": ROOF_FALL, "lift": ROOF_LIFT},
      ROOFGREY, "wheelhouse roof, starboard strip")
place("deck_tile", (5, 10, 45), 0,
      {"span": 8, "depth": 2, "gauge": "deck", "fall": 0, "lift": ROOF_LIFT - ROOF_FALL},
      ROOFGREY, "wheelhouse roof, after strip")
place("deck_tile", (13, 10, 45), 0,
      {"span": 2, "depth": 2, "gauge": "deck", "fall": 0, "lift": ROOF_LIFT - ROOF_FALL},
      ROOFGREY, "wheelhouse roof, after quarter")

# ── FUNNEL ───────────────────────────────────────────────────────────────────
# The kit was not designed for funnels and gets one for free: four faces with a
# knuckle at each corner, capped by a heavy deck tile.  Nothing here is a funnel
# piece.  At the eighth-cell step the four faces can finally carry DIFFERENT
# rakes — the original tapers 0.30 m on the sides, 0.40 forward and leans 0.20
# aft, and version 1 had to say 0.25 for all three.
FUN_HEAD = 3
FUN_FWD, FUN_SIDE, FUN_AFT = -3, -2, 2
note_residual("funnel top", TARGET["funnel_top"], plan_y(5, 0) + 5 * CELL + FUN_HEAD * E)
note_residual("funnel forward face rake", TARGET["funnel_fwd_rake"], -FUN_FWD * E)
note_residual("funnel side taper", TARGET["funnel_side_taper"], -FUN_SIDE * E)
note_residual("funnel aft face rake", TARGET["funnel_aft_rake"], FUN_AFT * E)

FUN = {"height": 5, "head": FUN_HEAD}
place("corner_45", (8, 5, 47), 0,
      {"span": 1, "height": 5, "head": FUN_HEAD, "rake_a": FUN_FWD, "rake_b": FUN_SIDE},
      OCHRE, "funnel, forward port knuckle")
place("corner_45", (12, 5, 47), 270,
      {"span": 1, "height": 5, "head": FUN_HEAD, "rake_a": FUN_SIDE, "rake_b": FUN_FWD},
      OCHRE, "funnel, forward starboard knuckle")
place("corner_45", (8, 5, 50), 90,
      {"span": 1, "height": 5, "head": FUN_HEAD, "rake_a": FUN_SIDE, "rake_b": FUN_AFT},
      OCHRE, "funnel, after port knuckle")
place("corner_45", (12, 5, 50), 180,
      {"span": 1, "height": 5, "head": FUN_HEAD, "rake_a": FUN_AFT, "rake_b": FUN_SIDE},
      OCHRE, "funnel, after starboard knuckle")
place("wall_panel", (9, 5, 47), 0, dict(FUN, span=2, rake=FUN_FWD), OCHRE, "funnel, forward face")
place("wall_panel", (11, 5, 50), 180, dict(FUN, span=2, rake=FUN_AFT), OCHRE, "funnel, aft face")
place("wall_panel", (8, 5, 49), 90, dict(FUN, span=1, rake=FUN_SIDE), OCHRE, "funnel, port face")
place("wall_panel", (12, 5, 48), 270, dict(FUN, span=1, rake=FUN_SIDE), OCHRE, "funnel, starboard face")
place("deck_tile", (8, 11, 47), 0, {"span": 4, "depth": 3, "gauge": "heavy", "lift": -1},
      BLACK, "funnel cap")


NOTE = """PIECE-BUILT, KIT VERSION 2. The deckhouse on this vessel contains ZERO hand-authored plate corners:
it is {n} placements of standard pieces on the 0.5 m deck grid, resolved by scripts/construction/piece_kit.gd
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
those side plates could not have been standard pieces. Here the front rakes 4 eighth-cells, the sides
tumble home 1, and a `corner_45` knuckle at each of the four corners carries the difference. Its plate is
bilinear, so a twisted quad is exactly what it is for. The by-product is that every corner on this
deckhouse is chamfered, which is the one shape a stack of square panels cannot make.

WHAT VERSION 2 SAYS THAT VERSION 1 COULD NOT. The three numbers version 1 wrote down as beyond it:

  the 2.74 m tier   ->  height 5 + head 2 = 2.75 m       residual 0.010 m (was 0.240)
  the 0.15 m tumblehome -> rake -1 = 0.125 m             residual 0.025 m (was 0.100)
  the 0.248 m boat-deck fall -> fall 2 = 0.250 m         residual 0.002 m (was 0.248)

and, not on that list but the same defect, the windscreen's 0.85 m rake is now 0.875 (residual 0.025,
was 0.150) and the funnel's three different tapers are three different numbers instead of one.

WHAT THIS FIXTURE STILL CANNOT SAY. A wall's foot is LEVEL, so the wheelhouse standing on the falling
boat deck sits on the mean of the deck under it and its foot wanders 0.0625 m inside the deck plate's own
0.13 m. And a continuous fall shared between several panels is dealt out in whole 0.125 m lumps, so the
tier's side wall is a two-step chord of the deck plane rather than the plane itself; its worst departure
is 0.047 m, against 0.240 m when the whole thing was flat.
"""


def build():
    src = json.load(open("resources/data/structures/probe_trawler_bulwark.json"))
    # The deckhouse as probe_trawler_bulwark authors it: the lower tier, the boat
    # deck, the wheelhouse, the funnel, and the glass, mullions and corner
    # pillars a later pass added.  Everything else on that vessel is bow bulwark,
    # gallows steelwork and rigging, and is kept verbatim.
    #
    # Selected by what each item SAYS IT IS, not by an id range.  It was two id
    # ranges (100-122 and 400-438) until the source fixture was renumbered to
    # give its entities unique ids, at which point this silently selected the
    # wrong 50 items and the plate count caught it.  An id is an address, not a
    # description, and it is allowed to move.
    DECKHOUSE_PREFIXES = (
        "lower tier", "boat deck", "wheelhouse", "wheelhouse roof",
        "wheelhouse corner pillar", "window mullion", "funnel", "funnel cap",
    )

    def is_deckhouse(item):
        return str(item.get("props", {}).get("__is", "")).startswith(DECKHOUSE_PREFIXES)

    deckhouse_items = [i for i in src["items"] if is_deckhouse(i)]
    assert len(deckhouse_items) == 50, (
        "expected 50 deckhouse items, got %d — the source fixture's descriptions moved"
        % len(deckhouse_items))
    kept = [i for i in src["items"] if not is_deckhouse(i)]
    left = sum(1 for i in kept if i.get("props", {}).get("primitive") == "plate")
    assert left == 39, "expected 39 non-deckhouse plates, got %d" % left
    counts = collections.Counter(p["piece"] for p in P)
    out = collections.OrderedDict()
    out["format"] = src["format"]
    out["context"] = src["context"]
    out["hull_id"] = src["hull_id"]
    removed = sum(1 for i in deckhouse_items
                  if i.get("props", {}).get("primitive") == "plate")
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
    ## The piece placements were numbered from 200 and the source fixture's
    ## items already used 200+, so all 43 placements collided and none of them
    ## was addressable by id. Renumbered across every collection.
    plan_ids.renumber(out)
    assert not plan_ids.duplicate_ids(out), plan_ids.duplicate_ids(out)
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
        "for, so nothing in the kit ships unproven: a `roof_slope` VISOR over the windscreen and its eave, "
        "the `cap` and `strake` profiles of `trim_band` - the strakes set out two eighth-cells with "
        "`offset`, because a trim run has no height and cannot carry a rake, so on a raked wall it has "
        "to be pushed out to meet it - and a DIAGONAL WALL RUN: three 4-cell `corner_45` facets in "
        "`chain: run`, raked one step and chained nose to tail across the foredeck, which is the piece "
        "doing the job version 1 said the kit had no piece for.\n\n"
        "TWO THINGS A CRITIC BROKE HERE AND THIS FILE NOW CARRIES THE FIX FOR. The diagonal run shipped "
        "in the default `chain: corner`, which opened both its joints by 0.1768 m at the head - "
        "daylight, in the fixture that was the evidence for the feature. And the `roof_slope` shipped "
        "as a breakwater PRISM whose two triangular ends nothing in the kit can close; it is a "
        "cantilevered visor now, which has no ends."
    ).format(n=len(P) + 8)
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

    # `roof_slope` as a VISOR over the wheelhouse windscreen, which is one of the
    # four jobs its own description names.  It was a breakwater PRISM - a slope
    # plus an after face - until a critic measured the two open triangular ends:
    # 0.5 x 1.0 m of daylight each, because the kit has no gusset and a prism
    # cannot be closed with the six pieces that exist.  A visor is a cantilevered
    # plate; it has no ends to close, and it is the honest use of the piece.
    add("roof_slope", (7, 9, 36), 0, {"span": 6, "depth": 2, "rise": 1, "gauge": "light",
                                      "lift": -3},
        ROOFGREY, "wheelhouse visor over the windscreen - one cell of rise over two of run")
    add("trim_band", (7, 9, 36), 0, {"span": 6, "profile": "eave", "lift": -3}, WALL,
        "eave along the visor's forward edge")
    # The three trim profiles the trawler does not ask for, each on a wall whose
    # rake it has to be set out to meet: `offset` is what makes that possible.
    # The cap rail sits on the boat deck's forward edge, which is 0.25 m off the
    # whole-cell lattice, so it carries the same `lift` the deck does.
    add("trim_band", (4, 5, 34), 0, {"span": 12, "profile": "cap", "lift": DECK_LIFT}, OCHRE,
        "cap rail across the forward edge of the boat deck")
    add("trim_band", (6, 2, 35), 0, {"span": 8, "profile": "strake", "offset": 2}, OCHRE,
        "rubbing strake across the raked deckhouse front, set out two eighth-cells to meet it")
    add("trim_band", (14, 1, 50), 180, {"span": 8, "profile": "strake", "offset": 2}, OCHRE,
        "rubbing strake across the raked aft bulkhead")

    # A DIAGONAL WALL RUN, which version 1 declared impossible.  Three facets at
    # span 4 chained nose to tail: each one's OUT edge is the next one's IN edge,
    # so they make one straight 45-degree wall 8.49 m long across the foredeck.
    # Nothing is placed at 45 degrees - every facing here is 0 - and no seventh
    # piece was added.
    #
    # `chain: "run"` IS LOAD-BEARING AND THIS FIXTURE SHIPPED WITHOUT IT.  In the
    # default `corner` mode each top corner moves along an AXIS wall's normal, so
    # a RAKED chain opens at the head by 0.125*sqrt(rake_a^2 + rake_b^2) - the
    # 0.1768 m of daylight a critic measured in exactly these three placements.
    # In `run` mode both corners move along the FACET's normal and the joints
    # close to the bit at any rake.
    for step in range(3):
        add("corner_45", (12 - 4 * step, 0, 24 + 4 * step), 0,
            {"span": 4, "height": 3, "chain": "run", "rake_a": -1, "rake_b": -1}, WALL,
            "diagonal wall run, facet %d of 3 — a 5.66 m chord, raked and chained" % (step + 1))

    house["pieces"] = strict
    house["items"] = []
    house["edges"] = src["edges"]
    plan_ids.renumber(house)
    assert not plan_ids.duplicate_ids(house), plan_ids.duplicate_ids(house)
    with open("resources/data/structures/probe_piece_house.json", "w") as f:
        json.dump(house, f, indent=1)
        f.write("\n")
    print("probe_piece_house.json: %d placements, 0 items" % len(strict))
    print(collections.Counter(p["piece"] for p in strict))

    print("\nRESIDUAL AGAINST THE HAND-AUTHORED ORIGINAL (metres)")
    print("  %-46s %9s %9s %9s" % ("", "target", "built", "residual"))
    for what, target, built, delta, unit in RESID:
        print("  %-46s %9.4f %9.4f %+9.4f" % (what, target, built, delta))


build()
