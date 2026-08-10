#!/usr/bin/env python3
"""Generates resources/data/structures/probe_container_feeder.json.

hull_150x32 — 150 x 32 m, the largest hull in the catalog. A gearded container
feeder: raised forecastle, five hatches, an aft accommodation block six tiers
high, a funnel, two deck cranes, and a cargo stow of LONG containers (4 cells
long x 1 wide = 16.0 x 4.0 x 4.0 m) both on the hatch covers and standing in
CELL GUIDES in an open-topped hold.

Provenance: the JSON is the interface, this file is where the numbers live.
"""

import json
import math
import os

OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "resources", "data", "structures", "probe_container_feeder.json",
)

# ── hull_150x32, as HullStations lofts it (measured, see _probe output) ──────
LOA = 150.0
BEAM = 32.0
CL = BEAM * 0.5          # centreline in plan x
HULL_ID = "hull_150x32"

# Deck-edge half beam at plan z. HullStations puts 16 stations 10 m apart and
# StructureEdge.deck_half_beam_at interpolates linearly between them, so the
# deck edge is piecewise linear with knuckles at z = 10 and z = 20. Restating
# THAT rather than a smooth curve is the point: every plate that lands on the
# deck edge has to land on the line the hull actually draws.
def hb(z):
    z = max(0.0, min(LOA, z))
    if z < 10.0:
        return 1.09375 * z
    if z < 20.0:
        return 10.9375 + 0.50625 * (z - 10.0)
    return 16.0


def edge_x(z, side):
    return CL + side * hb(z)


# ── The long container ──────────────────────────────────────────────────────
# The owner: "we would have 4x1 containers for larger ships". ContainerUnit's
# cubed unit is 4 m on a side, so four cells by one is 16.0 x 4.0 m in plan and
# one cell (4.0 m) tall. Drawn 15.80 x 3.94 x 3.80 with a 0.20 top cap, so the
# gaps between boxes are real gaps and every tier boundary draws its own dark
# line — a stack of same-height slabs with no seam reads as one block.
BOX_L = 15.80
BOX_W = 3.94
BOX_BODY_H = 3.80
BOX_CAP_H = 0.20
BOX_PITCH_Y = 4.00
ROW_PITCH = 4.16

# Six rows across, centred: 6 x 4.16 = 24.96 m inside a 32 m beam, which leaves
# a 3.2 m walkway outboard of the coaming on each side. Seven rows fits the
# boxes and leaves 1.1 m, which is not a walkway.
ROW_X = [CL + ROW_PITCH * (i - 2.5) for i in range(6)]
STOW_HALF = ROW_PITCH * 3.0                     # 12.48
COAM_X0 = CL - STOW_HALF - 0.55                 # 2.97
COAM_X1 = CL + STOW_HALF + 0.55                 # 29.03

# ── Longitudinal arrangement ────────────────────────────────────────────────
FC_BREAK_Z = 16.5        # break of the raised forecastle
# Bay pitch is NOT uniform, and the reason is the cranes. A pedestal carrying a
# 22.8 m column needs about 5 m of diameter at its foot; the gaps either side of
# the open bay are therefore 5.8 m and the other two are 2.6 m. Built uniform
# first, at 3.0 m, and the pedestal came out 2.7 m across and 22.8 m tall — an
# 8:1 stick that read as a flagpole with a shed on top.
BAY_Z0 = [20.4, 42.8, 62.0, 84.4, 103.6]
HATCH_L = 16.6
OPEN_BAY = 2             # bay 3 is open-topped: cell guides, no hatch cover
CRANE_A_Z = 39.9         # centre of the 5.8 m gap forward of the open bay
CRANE_B_Z = 81.5         # centre of the 5.8 m gap abaft it
HOUSE_Z0 = 122.5
HOUSE_Z1 = 143.5

COAM_TOP = 1.85          # coaming cap underside
COVER_Y = 1.95           # hatch cover underside
COVER_H = 0.26
DECK_STOW_Y = COVER_Y + COVER_H   # 2.21 — bottom of tier 0 on a hatch cover

# ── Colour. Free — the bake buckets on MATERIAL alone. Spent on VALUE. ───────
TOPSIDE = [0.135, 0.155, 0.180]   # matches HullLivery.DEFAULT_TOPSIDES
CAP = [0.88, 0.87, 0.82]
DECK_GREY = [0.30, 0.30, 0.29]
HOUSE = [0.90, 0.89, 0.85]
HOUSE_SHADE = [0.78, 0.77, 0.73]
GLASS = [0.085, 0.10, 0.115]
COAM_PLATE = [0.30, 0.30, 0.31]
COAM_CAP = [0.66, 0.63, 0.55]
COVER_COL = [0.235, 0.245, 0.25]
STEEL = [0.62, 0.63, 0.65]
DARK_STEEL = [0.20, 0.21, 0.23]
RUST = [0.36, 0.20, 0.13]
FUNNEL = [0.55, 0.13, 0.11]
FUNNEL_CAP = [0.075, 0.08, 0.085]
ORANGE = [0.82, 0.38, 0.06]
GUIDE_COL = [0.58, 0.60, 0.57]
PEDESTAL = [0.63, 0.63, 0.61]    # crane pedestals — grey, not the house cream
DECK_PAINT = [0.175, 0.235, 0.205]   # working alleyways; the hull deck mesh is tan   # cell guides — light against the hold shadow

# Ten liveries. A container stack is exactly where hue and value variation pay,
# because it is the one part of a ship that is genuinely many small objects.
LIVERY = [
    [0.075, 0.28, 0.52],   # deep blue
    [0.58, 0.19, 0.13],    # oxide red
    [0.78, 0.40, 0.08],    # orange
    [0.11, 0.34, 0.22],    # bottle green
    [0.44, 0.45, 0.47],    # grey
    [0.80, 0.79, 0.74],    # white
    [0.76, 0.60, 0.12],    # ochre
    [0.09, 0.33, 0.36],    # teal
    [0.34, 0.13, 0.19],    # maroon
    [0.47, 0.60, 0.68],    # pale blue
]


def darker(c, f=0.52):
    return [round(v * f, 4) for v in c]


def pick(bay, row, tier):
    return LIVERY[(bay * 7 + row * 3 + tier * 5 + (bay * row) % 3) % len(LIVERY)]


# ── Emitters ────────────────────────────────────────────────────────────────
items = []
walls = []
decks = []
edges = []
_next = [100]


def nid():
    _next[0] += 1
    return _next[0]


def plate(corners, thickness, color, note="", material="painted", openings=None, segments=None):
    props = {
        "__is": note,
        "primitive": "plate",
        "corners": [[round(v, 4) for v in c] for c in corners],
        "thickness": round(thickness, 4),
        "color": [round(v, 4) for v in color],
        "material": material,
    }
    if openings:
        props["openings"] = openings
    if segments:
        props["segments"] = segments
    items.append({"id": nid(), "item_id": "plate", "at": [0.0, 0.0, 0.0], "props": props})
    return items[-1]["id"]


def box_plate(x0, x1, y0, y1, z0, z1, color, note="", material="painted"):
    """A rectangular solid drawn as ONE plate: the quad is the horizontal
    mid-plane and the thickness is the height, so a slab costs 12 triangles and
    one collider box. This is what a container is."""
    ym = (y0 + y1) * 0.5
    return plate(
        [[x0, ym, z0], [x1, ym, z0], [x1, ym, z1], [x0, ym, z1]],
        y1 - y0, color, note, material,
    )


def spar(at, points, radius, color, note="", taper=None, sides=8, material="steel"):
    props = {
        "__is": note,
        "points": [[round(v, 4) for v in p] for p in points],
        "radius": round(radius, 4),
        "sides": sides,
        "material": material,
        "color": [round(v, 4) for v in color],
    }
    if taper is not None:
        props["taper"] = taper
    items.append({
        "id": nid(), "item_id": "spar",
        "at": [round(v, 4) for v in at], "props": props,
    })
    return items[-1]["id"]


def wire(at, points, radius, color, note="", sag=0.05, steps=6):
    items.append({
        "id": nid(), "item_id": "wire",
        "at": [round(v, 4) for v in at],
        "props": {
            "__is": note,
            "points": [[round(v, 4) for v in p] for p in points],
            "radius": radius, "sag": sag, "span_steps": steps, "sides": 4,
            "material": "steel", "color": [round(v, 4) for v in color],
        },
    })
    return items[-1]["id"]


# ══ 1. THE BULWARK — the hull's own sheer, lofted, not restated ═════════════
#
# full_bodied gives bow_keel_rise 0.18 / stern 0.05 over 7.0 m of freeboard, so
# the cap runs 2.44 m above the build plane at the stem, 1.18 amidships and
# 1.53 at the transom. That is a shallow, bow-dominant sheer, which is what a
# box freighter has and is exactly why this edge is `from_hull`: the trawler
# had to author its curve because the derived one was too polite for a working
# boat, and this hull is the case the derivation was written for.
edges.append({
    "id": 1,
    "primitive": "sheer_band",
    "from_hull": HULL_ID,
    "_is": "main-deck bulwark, the whole loop, lofted off hull_150x32's own sheer",
    "height": 1.30,
    "plate_m": 0.14,
    "cap_w": 0.36,
    "cap_h": 0.09,
    "plate_color": TOPSIDE,
    "cap_color": CAP,
    "material": "painted",
    "solid": True,
})

# ══ 2. RAISED FORECASTLE ════════════════════════════════════════════════════
#
# A separate deck, not a taller bulwark. Its own sheer on top of the hull's:
# 3.20 m above the build plane at the break, lifting to 3.92 at the stem.
FC_TOP = 1.15            # bulwark above the forecastle deck
FC_PROUD = 0.24          # side plating stands this far outboard of the deck edge
FC_T = 0.14


def fc_y(z):
    u = max(0.0, (FC_BREAK_Z - z) / FC_BREAK_Z)
    return 3.20 + 0.72 * u * u


FC_Z = [FC_BREAK_Z, 10.0, 5.0, 1.4]

for side in (-1.0, 1.0):
    for a, b in zip(FC_Z[:-1], FC_Z[1:]):
        xa = edge_x(a, side) + side * FC_PROUD
        xb = edge_x(b, side) + side * FC_PROUD
        # Side plating AND the forecastle bulwark are one sheet of steel, which
        # is what they are on a ship — the bulwark is the shell carried up past
        # the deck. Drawing them as two plates would put a seam where a ship has
        # a continuous plate, and would need a second inset to avoid z-fighting
        # the bulwark loop underneath.
        plate(
            [[xa, -0.16, a], [xb, -0.16, b],
             [xb, fc_y(b) + FC_TOP, b], [xa, fc_y(a) + FC_TOP, a]],
            FC_T, TOPSIDE, "forecastle side plating carried up as the bulwark",
        )
        # The deck itself, inboard of the plating's inner face.
        if side < 0:
            xa2 = edge_x(a, 1.0) + FC_PROUD - FC_T * 0.5
            xb2 = edge_x(b, 1.0) + FC_PROUD - FC_T * 0.5
            plate(
                [[xa + FC_T * 0.5, fc_y(a), a], [xa2, fc_y(a), a],
                 [xb2, fc_y(b), b], [xb + FC_T * 0.5, fc_y(b), b]],
                0.16, DECK_GREY, "forecastle deck, swept with its own sheer",
            )

# Stem plate closing the head of the forecastle bulwark.
xs = edge_x(FC_Z[-1], -1.0) + -1.0 * FC_PROUD
xp = edge_x(FC_Z[-1], 1.0) + FC_PROUD
plate(
    [[xs, -0.16, FC_Z[-1]], [xp, -0.16, FC_Z[-1]],
     [xp, fc_y(FC_Z[-1]) + FC_TOP, FC_Z[-1] - 0.30],
     [xs, fc_y(FC_Z[-1]) + FC_TOP, FC_Z[-1] - 0.30]],
    FC_T, TOPSIDE, "stem plate — rakes forward 0.30 m over its height",
)

# Cap rail round the forecastle bulwark. A constant section on a curve: the one
# thing `edges[]` exists for, and the lightest line on a dark ship.
cap_path = []
for z in [FC_BREAK_Z, 13.0, 10.0, 7.0, 5.0, 3.0, 1.4]:
    cap_path.append([round(edge_x(z, -1.0) - FC_PROUD, 4), round(fc_y(z) + FC_TOP, 4), z])
cap_path.append([CL, round(fc_y(1.4) + FC_TOP, 4), 1.15])
for z in [1.4, 3.0, 5.0, 7.0, 10.0, 13.0, FC_BREAK_Z]:
    cap_path.append([round(edge_x(z, 1.0) + FC_PROUD, 4), round(fc_y(z) + FC_TOP, 4), z])
edges.append({
    "id": 2,
    "primitive": "sheer_band",
    "_is": "forecastle cap rail — constant section swept along the raised deck edge",
    "path": cap_path,
    "closed": False,
    "material": "painted",
    "solid": False,
    "profile": [
        {"u": 0.0, "v": 0.055, "w": 0.42, "h": 0.11, "color": CAP},
    ],
})

# Break of the forecastle: one transverse bulkhead the full beam, with a door.
xb0 = edge_x(FC_BREAK_Z, -1.0) - FC_PROUD - FC_T * 0.5
xb1 = edge_x(FC_BREAK_Z, 1.0) + FC_PROUD + FC_T * 0.5
plate(
    [[xb0, -0.16, FC_BREAK_Z], [xb1, -0.16, FC_BREAK_Z],
     [xb1, fc_y(FC_BREAK_Z) + 0.16, FC_BREAK_Z], [xb0, fc_y(FC_BREAK_Z) + 0.16, FC_BREAK_Z]],
    0.18, HOUSE_SHADE, "break of the forecastle — the aft face of the fo'c'sle",
    openings=[
        {"type": "door", "offset": 12.9, "width": 1.1, "sill": 0.16, "height": 2.05},
        {"type": "door", "offset": 14.6, "width": 1.1, "sill": 0.16, "height": 2.05},
    ],
)

# ── Breakwater. A V across the open deck aft of the fo'c'sle: it throws a
# boarding sea outboard before it reaches bay 1. Raked aft 0.9 m over 1.95 m of
# height, which is 25 degrees, and it is the reason this deck does not read flat
# between the forecastle and the first stack.
BW_Z = 17.4
for side in (-1.0, 1.0):
    x_out = CL + side * 13.4
    plate(
        [[CL, 0.0, BW_Z], [x_out, 0.0, BW_Z + 2.3],
         [x_out, 2.10, BW_Z + 3.2], [CL, 2.10, BW_Z + 0.9]],
        0.16, HOUSE_SHADE, "breakwater — raked 25 degrees aft",
    )
    # Stiffeners on the aft face, because a 1.95 m plate on its own reads as
    # cardboard at this distance.
    for t in (0.28, 0.55, 0.82):
        px = CL + (x_out - CL) * t
        pz = BW_Z + 2.3 * t
        spar([px, 0.0, pz + 0.16], [[0, 0, 0], [0, 2.05, 0.86]], 0.10, DARK_STEEL,
             "breakwater stiffener", sides=4)

# ══ 3. HATCH COAMINGS, COVERS AND THE CARGO STOW ════════════════════════════
for b, z0 in enumerate(BAY_Z0):
    z1 = z0 + HATCH_L
    # Coaming: a closed sweep with a to_base plate and a cap. Four segments,
    # eight boxes, and it collides exactly what it draws.
    edges.append({
        "id": 10 + b,
        "primitive": "sheer_band",
        "_is": "hatch coaming, bay %d" % (b + 1),
        "path": [
            [COAM_X0, COAM_TOP, z0], [COAM_X1, COAM_TOP, z0],
            [COAM_X1, COAM_TOP, z1], [COAM_X0, COAM_TOP, z1],
        ],
        "closed": True,
        "base_y": 0.0,
        "material": "painted",
        "solid": True,
        "profile": [
            {"u": 0.0, "v": 0.03, "w": 0.18, "to_base": True, "color": COAM_PLATE},
            {"u": 0.0, "v": 0.045, "w": 0.40, "h": 0.09, "color": COAM_CAP},
        ],
    })
    if b == OPEN_BAY:
        continue
    # Hatch cover — pontoon covers, drawn as one slab with a raised centre seam.
    box_plate(COAM_X0 + 0.12, COAM_X1 - 0.12, COVER_Y, COVER_Y + COVER_H, z0 + 0.1, z1 - 0.1,
              COVER_COL, "hatch cover, bay %d" % (b + 1))
    for f in (0.34, 0.66):
        zc = z0 + HATCH_L * f
        box_plate(COAM_X0 + 0.12, COAM_X1 - 0.12, COVER_Y + COVER_H, COVER_Y + COVER_H + 0.10,
                  zc - 0.16, zc + 0.16, darker(COVER_COL, 0.7), "hatch cover panel seam")

# Deck stow. Tier counts per row, per bay. The zero and the twos are the point:
# a stow with the same height everywhere is a brick, and a container ship at sea
# is never uniformly loaded.
STOW = {
    0: [4, 5, 5, 5, 5, 4],
    1: [5, 5, 5, 5, 5, 4],
    3: [4, 4, 4, 3, 4, 4],
    4: [3, 4, 4, 3, 2, 0],
}
for b, tiers in STOW.items():
    z0 = BAY_Z0[b]
    zc = z0 + HATCH_L * 0.5
    for r, n in enumerate(tiers):
        x = ROW_X[r]
        for t in range(n):
            y0 = DECK_STOW_Y + t * BOX_PITCH_Y
            col = pick(b, r, t)
            box_plate(x - BOX_W * 0.5, x + BOX_W * 0.5, y0, y0 + BOX_BODY_H,
                      zc - BOX_L * 0.5, zc + BOX_L * 0.5, col,
                      "container %d-%d-%d" % (b, r, t))
            box_plate(x - BOX_W * 0.5 - 0.03, x + BOX_W * 0.5 + 0.03,
                      y0 + BOX_BODY_H, y0 + BOX_BODY_H + BOX_CAP_H,
                      zc - BOX_L * 0.5 - 0.03, zc + BOX_L * 0.5 + 0.03,
                      darker(col), "container top rail")

# ══ 4. THE RACK — cell guides in the open-topped bay ════════════════════════
#
# The owner asked for large containers on racks. A rack on a container ship is
# a CELL GUIDE: paired vertical angles at every cell corner that a box is
# lowered into, so it needs no lashing at all. On a normal bay they are under
# the hatch cover and invisible, so bay 3 is OPEN-TOPPED and its guides are
# carried right up past the deck — a real ship type, and the only arrangement
# in which the rack is a thing you can look at.
oz0 = BAY_Z0[OPEN_BAY]
oz1 = oz0 + HATCH_L
GUIDE_TOP = 18.6
GUIDE_BOT = -9.4
GUIDE_R = 0.24
guide_x = [CL + ROW_PITCH * (i - 3.0) for i in range(7)]
GUIDE_Z = [oz0 + 0.55, oz1 - 0.55]

for gz in GUIDE_Z:
    for gx in guide_x:
        # A cell guide is a PAIR of angles, one each side of the cell corner,
        # 0.34 m apart. Drawing one post per corner reads as scaffolding; the
        # pair reads as a slot with a box in it, which is what it is.
        for dx in (-0.17, 0.17):
            spar([gx + dx, GUIDE_BOT, gz], [[0, 0, 0], [0, GUIDE_TOP - GUIDE_BOT, 0]],
                 GUIDE_R, GUIDE_COL, "cell guide angle", sides=4)

# The guides are a FRAME, not fourteen free-standing poles: ties athwartships
# and fore-and-aft at the head and at mid height, and portal knees in all four
# top corners. Tied at four evenly spaced levels it photographed as a BOOKCASE
# — the eye reads evenly spaced horizontals as shelves before it reads the
# verticals as guides, which is the opposite of what this structure is.
TIE_Y = (2.6, 11.0, GUIDE_TOP - 0.3)
for gz in GUIDE_Z:
    for y in TIE_Y:
        spar([guide_x[0] - 0.17, y, gz], [[0, 0, 0], [guide_x[-1] - guide_x[0] + 0.34, 0, 0]],
             0.15, GUIDE_COL, "cell-guide tie, athwartships", sides=4)
for gx in (guide_x[0] - 0.17, guide_x[-1] + 0.17):
    for y in TIE_Y:
        spar([gx, y, GUIDE_Z[0]], [[0, 0, 0], [0, 0, GUIDE_Z[1] - GUIDE_Z[0]]],
             0.15, GUIDE_COL, "cell-guide tie, fore and aft", sides=4)
# Portal knees at the head of each end frame — the corner brackets that stop a
# 25 m guide frame racking when a 30 t box lands in it off a moving crane.
for gz, zdir in ((GUIDE_Z[0], 1.0), (GUIDE_Z[1], -1.0)):
    for gx, xdir in ((guide_x[0] - 0.17, 1.0), (guide_x[-1] + 0.17, -1.0)):
        spar([gx, GUIDE_TOP - 0.3, gz],
             [[0, 0, 0], [xdir * 2.4, -2.4, 0]], 0.13, GUIDE_COL,
             "cell-guide portal knee", sides=4)
        spar([gx, GUIDE_TOP - 0.3, gz],
             [[0, 0, 0], [0, -2.4, zdir * 2.4]], 0.13, GUIDE_COL,
             "cell-guide portal knee", sides=4)

# Boxes standing IN the guides: three tiers below the coaming and up to three
# above. Row 0 is left at two tiers — both of them below deck — so the PORT
# profile, which is the canonical one, looks straight into an empty rack with
# the loaded cells behind it. A rack you cannot see is not evidence of a rack.
IN_GUIDE = [2, 5, 6, 6, 4, 5]
oc = (oz0 + oz1) * 0.5
for r, n in enumerate(IN_GUIDE):
    x = ROW_X[r]
    for t in range(n):
        y0 = -8.6 + t * BOX_PITCH_Y
        col = pick(OPEN_BAY, r, t)
        box_plate(x - BOX_W * 0.5, x + BOX_W * 0.5, y0, y0 + BOX_BODY_H,
                  oc - BOX_L * 0.5, oc + BOX_L * 0.5, col,
                  "container in cell guides %d-%d" % (r, t))
        box_plate(x - BOX_W * 0.5 - 0.03, x + BOX_W * 0.5 + 0.03,
                  y0 + BOX_BODY_H, y0 + BOX_BODY_H + BOX_CAP_H,
                  oc - BOX_L * 0.5 - 0.03, oc + BOX_L * 0.5 + 0.03,
                  darker(col), "container top rail")

# ══ 5. DECK CRANES ══════════════════════════════════════════════════════════
#
# Two pedestal cranes on the centreline, standing in the 3.0 m cross-deck gaps
# the bay pitch leaves. The first pass built them 10 m tall and they vanished:
# the stacks either side are 22.2 m, so a crane whose machinery house is below
# the stack line is a stick poking out of the cargo. A real deck crane slews its
# jib OVER the stow, so the house has to clear it — 22.8 m to the slewing ring,
# measured against the tallest stack rather than picked, and the bay pitch was
# opened to 5.8 m at both crane stations to give the pedestal a foot to stand on.
def lattice(heel, tip, radius, color, note, chord_r=0.16, bays=7, width=1.15):
    """A jib drawn as three chords and their lacing. One tapered tube reads as
    a drainpipe at this framing; three chords with bars between them read as
    the open steelwork a crane jib actually is, for about 40 extra boxes."""
    ax = [tip[i] - heel[i] for i in range(3)]
    ln = math.sqrt(sum(v * v for v in ax))
    ax = [v / ln for v in ax]
    # Frame: side vector horizontal-perpendicular, up vector completes it.
    side = [ax[2], 0.0, -ax[0]]
    sl = math.sqrt(side[0] ** 2 + side[2] ** 2) or 1.0
    side = [side[0] / sl, 0.0, side[2] / sl]
    up = [ax[1] * side[2] - ax[2] * side[1],
          ax[2] * side[0] - ax[0] * side[2],
          ax[0] * side[1] - ax[1] * side[0]]
    offs = [[-width, -width * 0.55], [width, -width * 0.55], [0.0, width * 0.75]]
    nodes = []
    for su, uu in offs:
        a = [heel[i] + side[i] * su + up[i] * uu for i in range(3)]
        b = [tip[i] + side[i] * su * 0.35 + up[i] * uu * 0.35 for i in range(3)]
        spar(a, [[0, 0, 0], [b[i] - a[i] for i in range(3)]], chord_r, color,
             note + " chord", sides=4)
        nodes.append((a, b))
    for k in range(bays + 1):
        t = k / float(bays)
        pts = [[a[i] + (b[i] - a[i]) * t for i in range(3)] for a, b in nodes]
        for j in range(3):
            q = pts[(j + 1) % 3]
            spar(pts[j], [[0, 0, 0], [q[i] - pts[j][i] for i in range(3)]],
                 chord_r * 0.55, color, note + " lacing", sides=4)
        if k < bays:
            t2 = (k + 0.5) / float(bays)
            mid = [[a[i] + (b[i] - a[i]) * t2 for i in range(3)] for a, b in nodes]
            for j in range(3):
                spar(pts[j], [[0, 0, 0], [mid[j][i] - pts[j][i] for i in range(3)]],
                     chord_r * 0.5, color, note + " diagonal", sides=4)


def crane(zc, tip, working, cid):
    PED_TOP = 22.8
    HOUSE_TOP = PED_TOP + 4.3
    spar([CL, 0.0, zc], [[0, 0, 0], [0, PED_TOP, 0]], 2.45, PEDESTAL,
         "crane %d pedestal" % cid, taper=0.55, sides=12)
    spar([CL, 0.0, zc], [[0, 0, 0], [0, 1.9, 0]], 2.52, DARK_STEEL,
         "crane %d pedestal skirt" % cid, sides=12)
    # Ring beam where the pedestal meets the slewing ring.
    spar([CL, PED_TOP - 0.7, zc], [[0, 0, 0], [0, 0.7, 0]], 2.35, DARK_STEEL,
         "crane %d slewing ring" % cid, sides=12)
    box_plate(CL - 3.6, CL + 3.6, PED_TOP, HOUSE_TOP, zc - 2.4, zc + 7.4,
              ORANGE, "crane %d machinery house" % cid)
    box_plate(CL - 3.75, CL + 3.75, HOUSE_TOP, HOUSE_TOP + 0.24, zc - 2.55, zc + 7.55,
              darker(ORANGE, 0.6), "crane %d house roof" % cid)
    head = [CL, HOUSE_TOP + 8.4, zc + 0.6]
    for s_ in (-1.0, 1.0):
        spar([CL + s_ * 2.8, HOUSE_TOP + 0.24, zc + 5.9],
             [[0, 0, 0], [-s_ * 2.8, head[1] - HOUSE_TOP - 0.24, head[2] - zc - 5.9]],
             0.34, ORANGE, "crane %d A-frame leg" % cid, sides=6)
    heel = [CL, PED_TOP + 2.6, zc + 1.6]
    lattice(heel, tip, 0.5, ORANGE, "crane %d jib" % cid)
    # Luffing pendants, head sheave to jib tip. Taut: they are holding the jib.
    for s_ in (-0.55, 0.55):
        wire([head[0] + s_, head[1], head[2]],
             [[0, 0, 0], [tip[0] - head[0] - s_, tip[1] - head[1], tip[2] - head[2]]],
             0.055, DARK_STEEL, "crane %d luffing pendant" % cid, sag=0.015, steps=4)
    if not working:
        return
    # Hoist falls, hook block, spreader and a box in it — hung high and outboard
    # of the stack line so the whole lift is against sky rather than against
    # cargo. A crane with nothing hanging off it is a mast.
    sp_y = 25.2
    box_plate(tip[0] - 1.15, tip[0] + 1.15, sp_y + 1.15, sp_y + 2.6,
              tip[2] - 1.15, tip[2] + 1.15, DARK_STEEL, "hook block")
    for s_ in (-1.0, 1.0):
        wire([tip[0] + s_ * 0.45, tip[1] - 0.4, tip[2]],
             [[0, 0, 0], [-s_ * 0.45, sp_y + 2.0 - tip[1] + 0.4, 0.0]],
             0.085, DARK_STEEL, "hoist fall", sag=0.0, steps=3)
    for s_ in (-1.0, 1.0):
        wire([tip[0] + s_ * 0.5, sp_y + 1.2, tip[2]],
             [[0, 0, 0], [s_ * 1.6, -0.55, s_ * 5.9]],
             0.04, DARK_STEEL, "spreader pendant", sag=0.0, steps=2)
        wire([tip[0] + s_ * 0.5, sp_y + 1.2, tip[2]],
             [[0, 0, 0], [s_ * 1.6, -0.55, -s_ * 5.9]],
             0.04, DARK_STEEL, "spreader pendant", sag=0.0, steps=2)
    box_plate(tip[0] - 1.15, tip[0] + 1.15, sp_y + 0.2, sp_y + 0.85,
              tip[2] - BOX_L * 0.5 + 0.5, tip[2] + BOX_L * 0.5 - 0.5,
              [0.88, 0.66, 0.06], "container spreader")
    box_plate(tip[0] - BOX_W * 0.5, tip[0] + BOX_W * 0.5, sp_y - 3.6, sp_y + 0.2,
              tip[2] - BOX_L * 0.5, tip[2] + BOX_L * 0.5,
              LIVERY[2], "container on the spreader")
    box_plate(tip[0] - BOX_W * 0.5 - 0.03, tip[0] + BOX_W * 0.5 + 0.03,
              sp_y + 0.2, sp_y + 0.4,
              tip[2] - BOX_L * 0.5 - 0.03, tip[2] + BOX_L * 0.5 + 0.03,
              darker(LIVERY[2]), "container top rail")
    # Corner posts. A box in a STACK reads as a box because of its neighbours;
    # this one is alone against the sky and photographed as a plain plank, so it
    # gets the four corner castings that say container at 2 px wide.
    for dz in (-1.0, 1.0):
        box_plate(tip[0] - BOX_W * 0.5 - 0.05, tip[0] + BOX_W * 0.5 + 0.05,
                  sp_y - 3.6, sp_y + 0.2,
                  tip[2] + dz * (BOX_L * 0.5 - 0.42), tip[2] + dz * BOX_L * 0.5,
                  darker(LIVERY[2], 0.62), "corner post, hanging box")


# Forward crane luffed up and parked; after crane working the open bay, with the
# jib slewed 24 degrees to port so the lift hangs clear of the guide frame.
crane(CRANE_A_Z, [CL, 45.0, CRANE_A_Z - 19.5], False, 1)
# Slewed so the hook is over ROW 0 of the open bay — the one cell whose guides
# are standing empty. A box hanging over a full stack is a box going nowhere.
crane(CRANE_B_Z, [ROW_X[0], 40.0, 68.0], True, 2)

# ══ 6. THE AFT ACCOMMODATION BLOCK ══════════════════════════════════════════
#
# Six tiers, every one of them set back from the one below on three sides, every
# one of them carrying a window band. On a 150 m hull the house is the second
# silhouette event after the stacks, and a house that is one extruded rectangle
# is what the room primitive used to build.
TIER_H = 3.55
TIER = []
for t in range(5):
    inset = 0.0 if t == 0 else 0.55 * t
    front = HOUSE_Z0 + (0.0 if t == 0 else 1.1 + 0.9 * (t - 1))
    TIER.append({
        "y0": t * TIER_H, "y1": (t + 1) * TIER_H,
        "x0": CL - 12.0 + inset, "x1": CL + 12.0 - inset,
        "z0": front, "z1": HOUSE_Z1,
    })
HT = 0.18


def house_tier(t, front_rake=0.0, band=True, wall=HOUSE):
    y0, y1 = t["y0"], t["y1"]
    x0, x1, z0, z1 = t["x0"], t["x1"], t["z0"], t["z1"]
    zt = z0 - front_rake
    # front
    plate([[x0, y0, z0], [x1, y0, z0], [x1, y1, zt], [x0, y1, zt]], HT, wall,
          "house front")
    # sides
    for x in (x0, x1):
        plate([[x, y0, z0], [x, y0, z1], [x, y1, z1], [x, y1, zt]], HT, wall,
              "house side")
    # aft
    plate([[x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]], HT, wall,
          "house aft bulkhead")
    if band:
        by0, by1 = y0 + 1.45, y0 + 2.40
        # A window BAND, not punched holes: at 10 px per metre a dark value
        # reads as glass and a punched hole reads as damage. Proud of the skin
        # by 0.09 so it casts its own line.
        fz = z0 - front_rake * (by0 - y0) / max(y1 - y0, 0.01) - 0.09
        fz2 = z0 - front_rake * (by1 - y0) / max(y1 - y0, 0.01) - 0.09
        plate([[x0 + 1.0, by0, fz], [x1 - 1.0, by0, fz],
               [x1 - 1.0, by1, fz2], [x0 + 1.0, by1, fz2]], 0.10, GLASS,
              "window band, front")
        for s, x in ((-1.0, x0), (1.0, x1)):
            xx = x + s * 0.09
            plate([[xx, by0, z0 + 0.9], [xx, by0, z1 - 0.9],
                   [xx, by1, z1 - 0.9], [xx, by1, z0 + 0.9]], 0.10, GLASS,
                  "window band, side")
    return


for i, t in enumerate(TIER):
    house_tier(t, front_rake=0.0 if i == 0 else 0.22)
    # Each set-back leaves an open deck in front of the tier above: rail it.
    if i < len(TIER) - 1:
        nxt = TIER[i + 1]
        edges.append({
            "id": 20 + i,
            "primitive": "railing",
            "_is": "tier %d forward walkway rail" % (i + 1),
            "path": [
                [round(t["x0"] + 0.2, 3), round(t["y1"], 3), round(nxt["z0"] - 0.25, 3)],
                [round(t["x1"] - 0.2, 3), round(t["y1"], 3), round(nxt["z0"] - 0.25, 3)],
            ],
            "closed": False,
            "height": 1.05,
            "material": "steel",
            "color": CAP,
            "solid": True,
        })
    # Tier deck / roof.
    box_plate(t["x0"] - 0.1, t["x1"] + 0.1, t["y1"] - 0.16, t["y1"] + 0.06,
              t["z0"] - 0.32, t["z1"] + 0.1, DECK_GREY, "tier deck")

# ── Bridge deck: the sixth tier, WIDER than the block under it (the wings hang
# out over the ship's side so the master can see the quay) and with a windscreen
# raked 1.15 m forward over its height.
BR_Y0 = 5 * TIER_H
BR_Y1 = BR_Y0 + 4.0
BR_Z0 = HOUSE_Z0 + 5.0
BR_Z1 = BR_Z0 + 8.8
BR_X0, BR_X1 = CL - 15.0, CL + 15.0
bridge = {"y0": BR_Y0, "y1": BR_Y1, "x0": BR_X0, "x1": BR_X1, "z0": BR_Z0, "z1": BR_Z1}
house_tier(bridge, front_rake=1.15, band=False)

# Wheelhouse glazing: one band right round the front and both sides, tall,
# because a bridge is mostly window.
gy0, gy1 = BR_Y0 + 1.25, BR_Y0 + 3.05
fz0 = BR_Z0 - 1.15 * (gy0 - BR_Y0) / 4.0 - 0.10
fz1 = BR_Z0 - 1.15 * (gy1 - BR_Y0) / 4.0 - 0.10
plate([[BR_X0 + 0.5, gy0, fz0], [BR_X1 - 0.5, gy0, fz0],
       [BR_X1 - 0.5, gy1, fz1], [BR_X0 + 0.5, gy1, fz1]], 0.12, GLASS,
      "wheelhouse windscreen — raked forward 1.15 m over 4.0 m")
for s, x in ((-1.0, BR_X0), (1.0, BR_X1)):
    xx = x + s * 0.10
    plate([[xx, gy0, BR_Z0 + 0.4], [xx, gy0, BR_Z0 + 6.2],
           [xx, gy1, BR_Z0 + 6.2], [xx, gy1, BR_Z0 + 0.4]], 0.12, GLASS,
          "bridge wing glazing")

# Monkey island, its rail, and the radar mast.
box_plate(BR_X0 - 0.15, BR_X1 + 0.15, BR_Y1 - 0.18, BR_Y1 + 0.08,
          BR_Z0 - 1.4, BR_Z1 + 0.15, DECK_GREY, "monkey island deck")
edges.append({
    "id": 30,
    "primitive": "railing",
    "_is": "monkey island rail",
    "path": [
        [round(BR_X0 + 0.3, 3), round(BR_Y1 + 0.08, 3), round(BR_Z0 - 1.1, 3)],
        [round(BR_X1 - 0.3, 3), round(BR_Y1 + 0.08, 3), round(BR_Z0 - 1.1, 3)],
        [round(BR_X1 - 0.3, 3), round(BR_Y1 + 0.08, 3), round(BR_Z1 - 0.2, 3)],
        [round(BR_X0 + 0.3, 3), round(BR_Y1 + 0.08, 3), round(BR_Z1 - 0.2, 3)],
    ],
    "closed": True,
    "height": 1.05,
    "material": "steel",
    "color": CAP,
    "solid": True,
})
mast_foot = [CL, BR_Y1 + 0.08, BR_Z0 + 3.2]
spar(mast_foot, [[0, 0, 0], [0, 7.2, 0.55]], 0.24, HOUSE,
     "radar mast, raked 4 degrees aft", taper=0.55, sides=8)
for s in (-1.0, 1.0):
    spar([mast_foot[0], mast_foot[1] + 4.1, mast_foot[2] + 0.31],
         [[0, 0, 0], [s * 3.1, 0.55, 0.0]], 0.09, HOUSE, "yardarm", sides=4)
    spar([mast_foot[0] + s * 3.1, mast_foot[1] + 4.65, mast_foot[2] + 0.31],
         [[0, 0, 0], [0, 0.42, 0]], 0.11,
         [0.15, 0.55, 0.20] if s > 0 else [0.62, 0.10, 0.12], "sidelight", sides=6)
spar([mast_foot[0], mast_foot[1] + 5.6, mast_foot[2] + 0.43],
     [[0, 0, 0], [0, 0.9, 0]], 0.44, DARK_STEEL, "radar scanner", sides=4)

# ── Funnel, on the tier-5 roof aft of the bridge. Raked aft, tapering, black
# top: the only warm-coloured mass on the ship and the thing that says "this end
# is the stern" from three miles off.
FN_Y0 = 5 * TIER_H
FN_Y1 = FN_Y0 + 11.4
fn = {"x0": CL - 4.6, "x1": CL + 4.6, "z0": HOUSE_Z0 + 14.5, "z1": HOUSE_Z1 - 0.8}
fn_top = {"x0": CL - 3.7, "x1": CL + 3.7, "z0": fn["z0"] + 1.9, "z1": fn["z1"] - 0.2}
plate([[fn["x0"], FN_Y0, fn["z0"]], [fn["x1"], FN_Y0, fn["z0"]],
       [fn_top["x1"], FN_Y1, fn_top["z0"]], [fn_top["x0"], FN_Y1, fn_top["z0"]]],
      0.16, FUNNEL, "funnel front — rakes 1.9 m aft over 11.4 m")
plate([[fn["x0"], FN_Y0, fn["z1"]], [fn["x1"], FN_Y0, fn["z1"]],
       [fn_top["x1"], FN_Y1, fn_top["z1"]], [fn_top["x0"], FN_Y1, fn_top["z1"]]],
      0.16, FUNNEL, "funnel back")
for a, b in ((fn["x0"], fn_top["x0"]), (fn["x1"], fn_top["x1"])):
    plate([[a, FN_Y0, fn["z0"]], [a, FN_Y0, fn["z1"]],
           [b, FN_Y1, fn_top["z1"]], [b, FN_Y1, fn_top["z0"]]],
          0.16, FUNNEL, "funnel side")
box_plate(fn_top["x0"] - 0.28, fn_top["x1"] + 0.28, FN_Y1, FN_Y1 + 0.55,
          fn_top["z0"] - 0.28, fn_top["z1"] + 0.28, FUNNEL_CAP, "funnel cap")
for s in (-1.0, 0.0, 1.0):
    spar([CL + s * 1.7, FN_Y1 + 0.55, (fn_top["z0"] + fn_top["z1"]) * 0.5],
         [[0, 0, 0], [0, 1.5 - abs(s) * 0.45, 0]], 0.32, DARK_STEEL,
         "exhaust uptake", sides=8)

# ── Free-fall lifeboat on a stern ramp. One of the two things (with the funnel)
# that instantly dates a ship as modern, and it breaks the transom's flat.
lb_top = [[CL - 2.5, 7.1, HOUSE_Z1 - 0.6], [CL + 2.5, 7.1, HOUSE_Z1 - 0.6],
          [CL + 2.5, 3.5, HOUSE_Z1 + 5.6], [CL - 2.5, 3.5, HOUSE_Z1 + 5.6]]
plate(lb_top, 2.2, ORANGE, "free-fall lifeboat")
for s in (-1.0, 1.0):
    spar([CL + s * 2.85, 5.7, HOUSE_Z1 - 0.4],
         [[0, 0, 0], [0, -3.3, 6.7]], 0.20, DARK_STEEL, "lifeboat launch rail", sides=4)
    spar([CL + s * 2.85, 2.4, HOUSE_Z1 + 6.3],
         [[0, 0, 0], [0, 1.4, -1.4]], 0.16, DARK_STEEL, "launch-rail stool", sides=4)

# ══ 7. DECK FITTINGS — the things that give a 150 m deck a sense of size ═════
# Mooring bitts along both walkways, vent posts, and the fo'c'sle gear.
for z in (24.0, 48.0, 68.0, 92.0, 112.0, 146.0, 149.0):
    for side in (-1.0, 1.0):
        x = CL + side * (STOW_HALF + 2.35)
        if z > 140.0:
            x = CL + side * 11.0
        spar([x, 0.0, z], [[0, 0, 0], [0, 0.95, 0]], 0.24, DARK_STEEL,
             "mooring bitt", sides=6)
        spar([x, 0.85, z], [[0, 0, 0], [0, 0.22, 0]], 0.34, DARK_STEEL,
             "bitt head", sides=6)
for z in (30.0, 54.0, 74.0, 96.0, 116.0):
    for side in (-1.0, 1.0):
        x = CL + side * (STOW_HALF + 2.0)
        spar([x, 0.0, z], [[0, 0, 0], [0, 2.3, 0]], 0.2, HOUSE_SHADE,
             "hold vent trunk", sides=6)
        spar([x, 2.3, z], [[0, 0, 0], [0, 0.0, -0.85]], 0.28, HOUSE_SHADE,
             "vent cowl", sides=6)

# Forecastle: windlasses, the foremast, and a jackstaff.
for side in (-1.0, 1.0):
    x = CL + side * 4.6
    spar([x, fc_y(8.5), 8.5], [[0, 0, 0], [0, 1.35, 0]], 0.85, DARK_STEEL,
         "anchor windlass barrel", sides=8)
    spar([x - 1.3, fc_y(8.5) + 0.9, 8.5], [[0, 0, 0], [2.6, 0, 0]], 0.34, STEEL,
         "windlass warping end", sides=8)
    spar([x, fc_y(12.0), 12.0], [[0, 0, 0], [0, 0.95, 0]], 0.24, DARK_STEEL,
         "fo'c'sle bitt", sides=6)
fm = [CL, fc_y(13.6), 13.6]
spar(fm, [[0, 0, 0], [0, 8.4, 0.62]], 0.24, HOUSE, "foremast, raked aft",
     taper=0.55, sides=8)
spar([fm[0], fm[1] + 5.6, fm[2] + 0.41], [[0, 0, 0], [0, 0.85, 0]], 0.16,
     [0.92, 0.88, 0.55], "masthead light", sides=6)
for s in (-1.0, 1.0):
    # Backstays off the foremast head to the fo'c'sle bulwark, so the mast is
    # stayed to something that exists rather than drawn as a free pole.
    tz = 16.2
    tx = edge_x(tz, s) + s * (FC_PROUD - 0.05)
    wire([fm[0], fm[1] + 8.4, fm[2] + 0.62],
         [[0, 0, 0], [tx - fm[0], fc_y(tz) + FC_TOP - 0.15 - (fm[1] + 8.4), tz - fm[2] - 0.62]],
         0.035, DARK_STEEL, "foremast backstay", sag=0.03, steps=4)
spar([CL, fc_y(2.4), 2.4], [[0, 0, 0], [0, 2.6, 0]], 0.09, CAP, "jackstaff", sides=4)
# Chain stoppers, warping drums and panama fairleads. The fo'c'sle photographed
# as a bare grey pan with two black stumps on it; this is the gear that is
# actually up there and it is what gives the bow something to cast shadows with.
for side in (-1.0, 1.0):
    x = CL + side * 4.6
    for z in (5.4, 6.8):
        spar([x, fc_y(z), z], [[0, 0, 0], [0, 0.72, 0]], 0.30, DARK_STEEL,
             "chain stopper", sides=6)
    spar([x, fc_y(10.6), 10.6], [[0, 0, 0], [0, 1.55, 0]], 0.46, STEEL,
         "warping drum", sides=8)
    xf = CL + side * 8.4
    spar([xf, fc_y(12.6), 12.6], [[0, 0, 0], [0, 1.05, 0]], 0.20, DARK_STEEL,
         "fairlead post", sides=6)
    spar([xf, fc_y(12.6) + 1.05, 12.6], [[0, 0, 0], [side * 0.8, 0, 0]], 0.26,
         DARK_STEEL, "fairlead roller head", sides=6)
# Working paint on the forecastle, same green as the alleyways.
box_plate(CL - 6.6, CL + 6.6, fc_y(11.0), fc_y(11.0) + 0.05, 4.4, 13.6,
          DECK_PAINT, "forecastle working paint")

# Ensign staff aft.
spar([CL, 0.0, 149.4], [[0, 0, 0], [0, 3.1, 0.35]], 0.09, CAP, "ensign staff", sides=4)

# ══ 8. HULL SIDE RELIEF AND DECK PAINT ══════════════════════════════════════
#
# The first bake photographed as a 150 m slab of one value between the boot top
# and the bulwark cap — the exact complaint STATE.md still carries against the
# trawler ("flat hull sides with no plating relief"). Two runs fix it and they
# are the two things a real ship has there.
#
# THE RUBBING STRAKE's plan line is the SHELL AT THE STRAKE'S OWN HEIGHT, not
# the deck edge. The topsides tumble home 0.10 m over the parallel body and
# FLARE 0.92 m at z = 8, so a band hung on the deck's half-beam would stand a
# metre off the plating at the bow. Measured off HullStations at y = -1.05 and
# restated at the hull's own station breaks, so it is exact rather than fitted:
#   z    0    10       20       130      140      150
#   hb   0    9.9453   15.8986  15.8988  15.8801  15.6460
STRAKE_Y = -1.05
STRAKE_KNOTS = [(0.0, 0.0), (10.0, 9.9453), (20.0, 15.8986),
                (130.0, 15.8988), (140.0, 15.8801), (150.0, 15.6460)]


def strake_hb(z):
    for (za, ha), (zb, hbb) in zip(STRAKE_KNOTS[:-1], STRAKE_KNOTS[1:]):
        if za <= z <= zb:
            return ha + (hbb - ha) * (z - za) / (zb - za)
    return STRAKE_KNOTS[-1][1]


for eid, side in ((40, -1.0), (41, 1.0)):
    zs = [3.0, 6.0, 10.0, 14.0, 20.0, 40.0, 70.0, 100.0, 130.0, 140.0, 146.0, 149.4]
    if side < 0:
        zs = list(reversed(zs))
    edges.append({
        "id": eid,
        "primitive": "sheer_band",
        "_is": "rubbing strake, %s — a swept section on the shell's own line at "
               "y = -1.05, measured rather than taken from the deck edge"
               % ("port" if side < 0 else "starboard"),
        "path": [[round(CL + side * strake_hb(z), 4), STRAKE_Y, z] for z in zs],
        "closed": False,
        "material": "painted",
        "solid": False,
        "profile": [
            {"u": 0.0575, "v": 0.0, "w": 0.115, "h": 0.30, "color": [0.30, 0.32, 0.35]},
            {"u": 0.048, "v": 0.175, "w": 0.096, "h": 0.05, "color": [0.60, 0.61, 0.62]},
        ],
    })

# DECK PAINT. The hull's own deck mesh is a pale tan and the plan view was a
# tan plank with coloured stripes on it. Working alleyways are painted, and the
# paint is what tells you where you may walk on a 150 m deck.
for side in (-1.0, 1.0):
    xa = CL + side * 15.6
    xb = CL + side * (STOW_HALF + 0.63)
    box_plate(min(xa, xb), max(xa, xb), 0.0, 0.05, 19.9, HOUSE_Z0 - 0.6,
              DECK_PAINT, "alleyway paint")
for b in range(len(BAY_Z0) - 1):
    z0 = BAY_Z0[b] + HATCH_L + 0.15
    z1 = BAY_Z0[b + 1] - 0.15
    box_plate(COAM_X0 + 0.2, COAM_X1 - 0.2, 0.0, 0.05, z0, z1,
              DECK_PAINT, "cross-deck paint")
box_plate(1.2, 30.8, 0.0, 0.05, HOUSE_Z1 + 0.3, 149.3, DECK_PAINT, "poop deck paint")
box_plate(COAM_X0 + 0.2, COAM_X1 - 0.2, 0.0, 0.05, 19.9, BAY_Z0[0] - 0.15,
          DECK_PAINT, "fore-deck paint")

# ── Bosun's store on the forecastle. In profile the fo'c'sle was a dark wedge
# with nothing on it; a 4.6 x 3.2 x 2.5 m house at the break gives the bow an
# outline of its own and is where the mooring gear actually lives.
st_y = fc_y(15.0)
box_plate(CL - 2.3, CL + 2.3, st_y, st_y + 2.5, 14.4, 16.3, HOUSE_SHADE,
          "bosun's store")
box_plate(CL - 2.45, CL + 2.45, st_y + 2.5, st_y + 2.66, 14.25, 16.45,
          DECK_GREY, "bosun's store roof")
plate([[CL - 1.9, st_y + 0.5, 14.33], [CL + 1.9, st_y + 0.5, 14.33],
       [CL + 1.9, st_y + 1.55, 14.33], [CL - 1.9, st_y + 1.55, 14.33]],
      0.09, GLASS, "store window band")

# ── Funnel mark: one cream band. A funnel with a mark on it belongs to somebody.
box_plate(CL - 4.35, CL + 4.35, FN_Y0 + 6.6, FN_Y0 + 8.5,
          fn["z0"] + 1.15, fn["z1"] - 0.1, CAP, "funnel band")

# ══ Document ════════════════════════════════════════════════════════════════
NOTE = """A GEARED CONTAINER FEEDER ON hull_150x32 — 150 x 32 m, the largest hull in the
catalog and the first thing built at this size. Assembled from the trawler's kit and nothing
else: one `from_hull` sheer band, thirteen authored `edges[]` runs, raked plates for every piece
of superstructure and every container, spars and wires for the gear.

1. THE BULWARK IS `from_hull`, AND ON THIS HULL THAT IS THE RIGHT CALL. The trawler had to author
   its sheer because `sheer_bulwark_spec`'s derived curve was too polite for a working boat.
   full_bodied is the form that derivation was written FOR: bow_keel_rise 0.18 over 7.0 m of
   freeboard puts the cap 2.44 m above the build plane at the stem, 1.18 amidships and 1.53 at
   the transom — a shallow, bow-dominant sheer, which is what a box freighter has. Nothing here
   restates a curve the hull already owns.

2. SCALE IS THE EXERCISE, AND A BIG SHIP IS NOT A SMALL SHIP ENLARGED. The trawler's deckhouse is
   2.74 m to its boat deck; this house is 21.7 m to the monkey island, 34.2 m to the funnel cap
   and 45 m to a crane head. The BULWARK IS THE SAME 1.30 m on both, because it is a fall barrier
   set by the 1.8 m figure and not by the ship — that one constant against a 45 m crane is the
   whole point of the fixture. The figure therefore stands on the FORECASTLE: at 150 m LOA a
   figure on the aft deck is four pixels with a stack behind it.

3. THE LONG CONTAINER. The owner: "4x1 containers for larger ships". ContainerUnit's cubed unit
   is 4 m on a side, so four cells by one is 16.0 x 4.0 x 4.0 m. Drawn 15.80 x 3.94 x 3.80 with a
   0.20 top rail in a darker tone: a column of same-height slabs with no seam reads as ONE block,
   and the rail is what draws the tier line. Six rows at 4.16 m pitch leaves a 3.2 m alleyway
   outboard of the coaming on both sides — seven rows fits the boxes and leaves 1.1 m, which is
   not an alleyway.

   EACH CONTAINER IS ONE PLATE: the quad is the horizontal mid-plane and the thickness is the
   height, so a box costs 12 triangles and exactly one collider box. That is the only reason this
   ship can be FULL — 253 of them — instead of carrying the three that make a hull read as a barge.

4. THE RACK IS AN OPEN-TOP BAY. Cell guides are what "racks" means on a container ship: paired
   vertical angles at every cell corner that a box is lowered into, so it needs no lashing at all.
   On a normal bay they live under the hatch cover and are invisible, so BAY 3 IS OPEN-TOPPED and
   its guides run from 9.4 m below the build plane to 18.6 m above it — 28 angles in 14 pairs,
   tied athwartships and fore-and-aft at the head and at mid height, with portal knees in all four
   top corners. Boxes stand in them three tiers below deck and up to three above, and ROW 0 IS
   LEFT EMPTY so the port profile — the canonical one — looks straight into a bare cell with the
   loaded ones behind it. A rack you cannot see is not evidence of a rack.

   Tied at four evenly spaced levels it photographed as a BOOKCASE: the eye reads evenly spaced
   horizontals as shelves before it reads verticals as guides. Two tie levels and the knees.

5. THE STOW IS NOT UNIFORM. Tier counts run 2 to 5 by row and by bay and one row is empty. A stow
   at a constant height is a brick, and the top line of the stacks is most of the silhouette of a
   container ship.

6. TWO CRANES, AND THE BAY PITCH IS BUILT ROUND THEM. Pedestal, slewing ring, machinery house,
   A-frame, a THREE-CHORD LATTICE jib with lacing and diagonals, luffing pendants, and on the
   after crane hoist falls to a hook block, a spreader and a box hanging over the one cell whose
   guides are standing empty. Two things were measured rather than picked: the slewing ring is at
   22.8 m because the tallest stack is 22.2 m and a crane whose house is below the cargo is a
   stick poking out of it; and the gaps either side of the open bay are 5.8 m rather than the
   2.6 m used elsewhere, because at a uniform pitch the pedestal came out 2.7 m across and 22.8 m
   tall — an 8:1 stick that read as a flagpole with a shed on it.

7. SIX TIERS, EVERY ONE WITH A WINDOW BAND. Tiers 2 to 5 set back 0.55 m each side and 0.9 m
   forward of the one below, and each set-back leaves a walkway carrying a `railing` run. The
   bridge deck is WIDER than the block under it — the wings hang out over the ship's side — and
   its windscreen rakes 1.15 m forward over 4.0 m. Bands, not punched holes: at this framing a
   dark value reads as glass and a punched hole reads as damage.

8. THE FORECASTLE IS SEPARATE AND RAISED, with its own sheer on top of the hull's: 3.20 m above
   the build plane at the break, 3.92 at the stem. Its side plating and its bulwark are ONE sheet
   of steel, which is what they are on a ship, and the `from_hull` bulwark runs on behind them. A
   breakwater rakes 25 degrees aft across the deck between the break and hatch 1.

9. HULL RELIEF AND DECK PAINT, because the first bake photographed as a 150 m slab of one value
   between the boot top and the cap. The RUBBING STRAKE's plan line is the shell AT THE STRAKE'S
   OWN HEIGHT, not the deck edge: the topsides tumble home 0.10 m over the parallel body and FLARE
   0.92 m at z = 8, so a band hung on the deck's half-beam would stand a metre off the plating at
   the bow. Measured off HullStations at y = -1.05 and restated at the hull's own station breaks.
   The alleyways, the cross-decks and the poop are PAINTED, because the hull's own deck mesh is a
   pale tan and the plan view was a tan plank with coloured stripes on it.

COLOUR DOES VALUE WORK, FOR FREE — the bucket key is material alone. Dark topsides the bulwark
plating merges into, a bone cap so the sheer is the lightest line on the hull, cream house against
green deck paint, near-black glass, an oxide-red funnel with a black top and a cream band, grey
crane pedestals (cream ones read as grain silos), orange crane houses and lifeboat, and ten
container liveries. Squinted, that is seven values, and the stacks are where the hue lives.

WHAT THIS FIXTURE CAUGHT, since it is the reason the railing collides correctly today. On the day
it was built, `vessel_render_capture`'s "every drawn edge corner is inside a collider" failed here
with 92 loose corners, all of them the TOP RAIL of the five `railing` runs: `railing_profile` puts
the top course's CENTRE at `height`, so it draws to `height + rail_width/2`, while
`railing_collider_boxes` bounded the run at `height`. No fixture in the rig had used the railing
primitive before, so nothing had ever held it to the claim. It was left RED with that diagnosis
rather than silenced — turning the runs `solid: false` would have removed five real fall barriers
from collision to make a check stop complaining.

Fixing the 20 mm exposed a second, larger leak the spec could never have shown: 148 corners at the
MITRES, where a joint deliberately overshoots its path vertex to fill the corner wedge. So the
analytic derivation is gone. `railing_collider_boxes` now groups the boxes the run actually DRAWS
by their `segment` tag and bounds each group, the same mechanism `sweep_collider_boxes` uses.
All nine fixtures are at 0 loose corners.

GENERATED by tools/gen_container_feeder.py, which is where the arrangement, the stow pattern, the
crane geometry and the measured strake line live and where they should be retuned. The JSON is the
interface; the generator is the provenance."""

plan = {
    "format": "structure_plan_v1",
    "context": "vessel",
    "hull_id": HULL_ID,
    "_note": NOTE,
    "palette": {"wall": HOUSE, "deck": DECK_GREY},
    "hull": {
        "_note": "hull_150x32 restated from resources/data/vessels/hulls/catalog.json so the "
                 "capture rig can hold the derived stations against the hull the game spawns.",
        "loa_m": 150.0,
        "beam_m": 32.0,
        "depth_m": 15.0,
        "draft_m": 8.0,
        "form": "full_bodied",
        "bow_taper_m": 16.0,
    },
    "walls": walls,
    "decks": decks,
    "stairs": [],
    "items": items,
    "edges": edges,
}

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    json.dump(plan, f, indent=1)
    f.write("\n")

plates = sum(1 for i in items if i["item_id"] == "plate")
spars = sum(1 for i in items if i["item_id"] == "spar")
wires = sum(1 for i in items if i["item_id"] == "wire")
boxes = sum(1 for i in items if i["props"].get("__is", "").startswith("container "))
print("%s: %d items (%d plate, %d spar, %d wire), %d edges, %d containers"
      % (os.path.basename(OUT), len(items), plates, spars, wires, len(edges), boxes))
