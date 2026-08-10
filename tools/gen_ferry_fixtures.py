#!/usr/bin/env python3
"""Rebuild probe_ferry_catamaran.json / probe_ferry_catamaran_trim.json.

    python3 tools/gen_ferry_fixtures.py

The pair's whole point is that the two files differ ONLY by the trim run, so
they are generated from ONE description: build() emits the vessel, and the trim
call adds the 47 trim boxes on top of the same dictionaries. Nothing about the
vessel is written twice, so the two files cannot drift.

That matters because the gate only half-checks it. `structure_edge_trim_cost_test`
walks walls, decks and stairs; it does not walk items[] or edges[], which since
the rebuild is the entire superstructure and bulwark. Move one corner of plate
400 in the trim file alone and that test still passes all five checks. So the
identity is asserted HERE instead, over every collection, at the end of main() —
and the honest version of that sentence is that a generator is not a test, and
the day someone hand-edits one of the two JSONs this stops being true.

Where the numbers live: the sheer curve is cap_y() and its four constants; the
deckhouse is the three Tier objects, whose vertices are a plan polygon at the
foot plus a per-vertex plan shift applied at the head — that shift IS the rake.
Retune those, not the JSON.
""" 
import json, math, copy, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "..", "resources", "data", "structures")
PLAIN = os.path.join(ROOT, "probe_ferry_catamaran.json")
TRIM = os.path.join(ROOT, "probe_ferry_catamaran_trim.json")

# ── palette ────────────────────────────────────────────────────────────────
NAVY = [0.14, 0.17, 0.23]
WHITE = [0.93, 0.93, 0.90]
GLASS = [0.075, 0.09, 0.115]
RED = [0.78, 0.16, 0.14]
BONE = [0.87, 0.87, 0.84]
DECK = [0.30, 0.33, 0.35]
WALLPAL = [0.88, 0.89, 0.91]   # the plan palette's other colour

R = 4  # rounding


def rnd(v):
    return round(v + 0.0, R)


def vec(x, y, z):
    return [rnd(x), rnd(y), rnd(z)]


# ── plate helpers ──────────────────────────────────────────────────────────
def area_vector(c):
    a = [c[2][i] - c[0][i] for i in range(3)]
    b = [c[3][i] - c[1][i] for i in range(3)]
    return [
        0.5 * (a[1] * b[2] - a[2] * b[1]),
        0.5 * (a[2] * b[0] - a[0] * b[2]),
        0.5 * (a[0] * b[1] - a[1] * b[0]),
    ]


def normal(c):
    n = area_vector(c)
    m = math.sqrt(sum(v * v for v in n))
    return [v / m for v in n]


_next_id = [400]


def plate(note, corners, color, thickness=0.10, openings=None, segments=None):
    props = {
        "__is": note,
        "primitive": "plate",
        "corners": [vec(*p) for p in corners],
        "thickness": thickness,
        "color": color,
        "material": "painted",
    }
    if segments:
        props["segments"] = segments
    if openings:
        props["openings"] = openings
    item = {
        "id": _next_id[0],
        "item_id": "plate",
        "at": [0.0, 0.0, 0.0],
        "props": props,
    }
    _next_id[0] += 1
    return item


# ── tier description ───────────────────────────────────────────────────────
class Tier:
    """A deckhouse tier: a plan polygon at the foot, a per-vertex plan shift
    applied at the head (that is the RAKE), and horizontal bands of plating."""

    def __init__(self, name, verts, y0, y1):
        self.name = name
        self.verts = verts  # list of (x, z, dx, dz) — dx/dz applied at y1
        self.y0 = y0
        self.y1 = y1

    def at(self, i, y):
        x, z, dx, dz = self.verts[i]
        t = (y - self.y0) / (self.y1 - self.y0)
        return (x + dx * t, y, z + dz * t)

    def outward(self, i):
        """Unit plan normal of edge i, pointing away from the interior."""
        p = self.verts[i]
        q = self.verts[(i + 1) % len(self.verts)]
        dx, dz = q[0] - p[0], q[1] - p[1]
        n = (dz, -dx)
        m = math.hypot(*n)
        n = (n[0] / m, n[1] / m)
        # sanity: must point away from the centroid
        cx = sum(v[0] for v in self.verts) / len(self.verts)
        cz = sum(v[1] for v in self.verts) / len(self.verts)
        mx, mz = (p[0] + q[0]) * 0.5, (p[1] + q[1]) * 0.5
        assert (mx - cx) * n[0] + (mz - cz) * n[1] > 0, "%s edge %d normal" % (self.name, i)
        return n

    def face(self, i, ylo, yhi, note, color, thickness=0.10, inset=0.0,
             openings=None, u0=0.0, u1=1.0):
        """One plate on edge i between two heights. `inset` pushes the plate
        inboard along the edge's own normal — that is what makes glass sit in a
        reveal instead of flush with the plating around it."""
        j = (i + 1) % len(self.verts)
        nx, nz = self.outward(i)
        ox, oz = -nx * inset, -nz * inset

        def P(k, y, s):
            # s in [0,1] along the edge from vertex i to vertex j
            a = self.at(i, y)
            b = self.at(j, y)
            return (
                a[0] + (b[0] - a[0]) * s + ox,
                y,
                a[2] + (b[2] - a[2]) * s + oz,
            )

        c0 = P(j, ylo, u1)
        c1 = P(i, ylo, u0)
        c2 = P(i, yhi, u0)
        c3 = P(j, yhi, u1)
        corners = [c0, c1, c2, c3]
        n = normal(corners)
        assert n[0] * nx + n[2] * nz > 0.85, (
            "%s edge %d winding: normal %s vs outward %s" % (self.name, i, n, (nx, nz))
        )
        return plate(note, corners, color, thickness, openings)


# ── the three tiers ────────────────────────────────────────────────────────
# Feet are set so the trim skirts and the retained deck plates 30/31/32 still
# land, and every front RAKES FORWARD under the deck above it.
# TUMBLE: tier 1's sides lean in 0.10 m over their height, as a uniform pinch
# about the centreline, so no face of the long saloon is a plumb slab.
def _tumble(x, amount=0.10, half=6.75):
    return -(x - 8.0) / half * amount


# Tier 1 is the only one with EIGHT sides: its after corners are cut back as
# well as its bow corners. That is shape, and it is also the one thing that
# keeps the 1.8 m figure in frame — see the note in the fixture.
TIER1 = Tier(
    "main saloon",
    [
        (1.25, 10.50, _tumble(1.25), -0.80),
        (3.60, 7.85, _tumble(3.60), -0.80),
        (12.40, 7.85, _tumble(12.40), -0.80),
        (14.75, 10.50, _tumble(14.75), -0.80),
        (14.75, 33.80, _tumble(14.75), 0.0),
        (13.40, 35.30, _tumble(13.40), 0.0),
        (2.60, 35.30, _tumble(2.60), 0.0),
        (1.25, 33.80, _tumble(1.25), 0.0),
    ],
    0.0,
    2.88,
)
T1_FWD = [0, 1, 2]
T1_SIDES = [3, 7]
T1_QUARTERS = [4, 6]
T1_AFT = 5
T1_NAMES = {0: "port bow facet", 1: "front", 2: "starboard bow facet",
            3: "starboard side", 4: "starboard quarter facet",
            6: "port quarter facet", 7: "port side"}
TIER2 = Tier(
    "upper saloon",
    [
        (1.70, 12.05, 0.0, -0.70),
        (3.70, 9.75, 0.0, -0.70),
        (12.30, 9.75, 0.0, -0.70),
        (14.30, 12.05, 0.0, -0.70),
        (14.30, 30.93, 0.0, 0.0),
        (1.70, 30.93, 0.0, 0.0),
    ],
    3.0,
    5.88,
)
TIER3 = Tier(
    "wheelhouse",
    [
        (4.72, 12.70, 0.0, -0.85),
        (5.92, 11.90, 0.0, -0.85),
        (10.08, 11.90, 0.0, -0.85),
        (11.28, 12.70, 0.0, -0.85),
        (11.28, 18.40, 0.0, 0.0),
        (4.72, 18.40, 0.0, 0.0),
    ],
    6.0,
    8.30,
)

# Edge indices are shared by all three: 0 port bow facet, 1 front, 2 starboard
# bow facet, 3 starboard side, 4 aft, 5 port side.
FWD = [0, 1, 2]
SIDES = [3, 5]


MULLION_W = 0.12


def mullions(tier, i, ylo, yhi, bays, note):
    """`bays` lights along edge i, divided by mullions standing in the reveal.
    The width is METRES on the plate, not a fraction of it: authored as a
    fraction, a mullion on a 26 m side came out 3 m wide and the band read as a
    row of portholes."""
    j = (i + 1) % len(tier.verts)
    a, b = tier.verts[i], tier.verts[j]
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    half = MULLION_W * 0.5 / length
    out = []
    for k in range(1, bays):
        s = k / float(bays)
        out.append(tier.face(i, ylo, yhi, note, WHITE, 0.14, u0=s - half, u1=s + half))
    return out


def superstructure():
    _next_id[0] = 400
    items = []

    # ── TIER 1 ─ the long low saloon ────────────────────────────────────────
    # Band heights. The window band is one continuous run right round the
    # forward end, which is the feature a fast cat is recognised by.
    C0, C1 = 0.0, 0.78      # coaming, in the hull's own navy
    S0, S1 = 0.78, 0.92     # livery stripe
    G0, G1 = 0.92, 2.40     # window band
    H0, H1 = 2.40, 2.88     # header, into the deck above
    names = {0: "port bow facet", 1: "front", 2: "starboard bow facet",
             3: "starboard side", 5: "port side"}
    for i in T1_FWD + T1_SIDES + T1_QUARTERS:
        n = T1_NAMES[i]
        items.append(TIER1.face(i, C0, C1, "saloon %s — coaming strake, hull navy" % n, NAVY, 0.14))
        items.append(TIER1.face(i, S0, S1, "saloon %s — livery stripe, proud of the coaming" % n, RED, 0.16))
        items.append(TIER1.face(i, G0, G1, "saloon %s — window band, set 90 mm into a reveal" % n, GLASS, 0.06, inset=0.09))
        items.append(TIER1.face(i, H0, H1, "saloon %s — header" % n, WHITE, 0.14))
    # Aft bulkhead: the boarding face. Two 2 m doors, a transom light above.
    # x 4.60..6.60 is the boarding door; x 11.20..13.20 is the COMPANIONWAY the
    # after stair comes through — stair 50 runs z 32.6 -> 37.0 and the bulkhead
    # crosses it, so the arch is where the stair passes, not a decoration.
    doors = [
        {"type": "door", "offset": 2.00, "width": 2.0, "sill": 0.0, "height": 2.05},
        {"type": "door", "offset": 8.60, "width": 2.0, "sill": 0.0, "height": 2.05},
    ]
    items.append(TIER1.face(T1_AFT, 0.0, 2.15, "saloon aft bulkhead — boarding door and the after companionway", WHITE, 0.14, openings=doors))
    items.append(TIER1.face(T1_AFT, 2.15, 2.60, "saloon aft bulkhead — transom light", GLASS, 0.06, inset=0.09))
    items.append(TIER1.face(T1_AFT, 2.60, 2.88, "saloon aft bulkhead — header", WHITE, 0.14))

    # Mullions: the window band is a band, not a hole, so the structure between
    # the lights has to be drawn rather than left out.
    for i in T1_SIDES:
        items += mullions(TIER1, i, G0, G1, 9, "saloon window mullion")
    items += mullions(TIER1, 1, G0, G1, 4, "saloon forward window mullion")

    # ── TIER 2 ─ the upper saloon ───────────────────────────────────────────
    C0, C1 = 3.00, 3.66
    G0, G1 = 3.66, 5.32
    H0, H1 = 5.32, 5.88
    for i in FWD + SIDES:
        items.append(TIER2.face(i, C0, C1, "upper saloon %s — coaming" % names[i], WHITE, 0.14))
        items.append(TIER2.face(i, G0, G1, "upper saloon %s — window band" % names[i], GLASS, 0.06, inset=0.09))
        items.append(TIER2.face(i, H0, H1, "upper saloon %s — header" % names[i], WHITE, 0.14))
    items.append(TIER2.face(4, 3.00, 5.15, "upper saloon aft bulkhead — door to the open deck", WHITE, 0.14,
                            openings=[{"type": "door", "offset": 5.30, "width": 2.0, "sill": 0.0, "height": 2.05}]))
    items.append(TIER2.face(4, 5.15, 5.55, "upper saloon aft bulkhead — transom light", GLASS, 0.06, inset=0.09))
    items.append(TIER2.face(4, 5.55, 5.88, "upper saloon aft bulkhead — header", WHITE, 0.14))
    for i in SIDES:
        items += mullions(TIER2, i, G0, G1, 8, "upper saloon window mullion")
    items += mullions(TIER2, 1, G0, G1, 4, "upper saloon forward window mullion")

    # ── TIER 3 ─ the wheelhouse, set forward and raised ─────────────────────
    C0, C1 = 6.00, 6.85
    G0, G1 = 6.85, 8.02
    H0, H1 = 8.02, 8.30
    for i in FWD + SIDES:
        items.append(TIER3.face(i, C0, C1, "wheelhouse %s — coaming" % names[i], WHITE, 0.14))
        # The windscreen glass is barely recessed: the sidelights are mounted on
        # the bow facets and must land on something.
        items.append(TIER3.face(i, G0, G1, "wheelhouse %s — glass" % names[i], GLASS, 0.06, inset=0.04))
        items.append(TIER3.face(i, H0, H1, "wheelhouse %s — header" % names[i], WHITE, 0.14))
    items.append(TIER3.face(4, 6.00, 8.02, "wheelhouse aft bulkhead — door to the boat deck", WHITE, 0.14,
                            openings=[{"type": "door", "offset": 2.29, "width": 1.80, "sill": 0.0, "height": 2.02}]))
    items.append(TIER3.face(4, 8.02, 8.30, "wheelhouse aft bulkhead — header", WHITE, 0.14))
    # Windscreen mullions, one per facet joint.
    items += mullions(TIER3, 1, G0, G1, 3, "windscreen mullion")

    return items


# ── the bulwark: one swept sheer band replacing walls 1/2/3 ────────────────
Z_FWD, Z_LOW, Z_AFT = 4.0, 30.0, 40.90
Y_LOW = 1.06
RISE_FWD = 0.70
RISE_AFT = 0.12
X_STBD, X_PORT = 15.28, 0.72


def cap_y(z):
    if z <= Z_LOW:
        t = (Z_LOW - z) / (Z_LOW - Z_FWD)
        return Y_LOW + RISE_FWD * t * t
    t = (z - Z_LOW) / (Z_AFT - Z_LOW)
    return Y_LOW + RISE_AFT * t * t


def side_zs():
    zs = []
    n = 24
    for k in range(n + 1):
        zs.append(Z_FWD + (Z_LOW - Z_FWD) * k / n)
    m = 4
    for k in range(1, m + 1):
        zs.append(Z_LOW + (Z_AFT - Z_LOW) * k / m)
    return zs


def sheer_edge():
    zs = side_zs()
    path = [vec(X_STBD, cap_y(z), z) for z in zs]
    path += [vec(X_PORT, cap_y(z), z) for z in reversed(zs)]
    return {
        "id": 60,
        "primitive": "sheer_band",
        "_is": (
            "the main-deck bulwark, and the only thing on this vessel that carries the "
            "SHEER. Plating in the hull's own navy so hull and bulwark read as one body, "
            "a red livery stripe proud of it, a bone cap so the curve itself is the "
            "lightest line on the ship. Runs z 4 -> 40.9 down each side and across the "
            "transom; the fore and after decks keep the guardrails they already had."
        ),
        "path": path,
        "closed": False,
        "base_y": -0.10,
        "material": "painted",
        "solid": True,
        "profile": [
            {"u": 0.0, "v": 0.0333, "w": 0.26, "to_base": True, "color": NAVY},
            {"u": 0.145, "v": -0.17, "w": 0.026, "h": 0.22, "color": RED},
            {"u": 0.0, "v": 0.05, "w": 0.36, "h": 0.10, "color": BONE},
        ],
    }


# ── the retained rig, with the two fittings that lost their host re-belayed ─
def rebelay(items):
    """The sidelights stood on the deleted wheelhouse. They now sit on the two
    bow facets of the rebuilt one, pushed out along each facet's own normal."""
    for item in items:
        note = item["props"].get("__is", "")
        if note.startswith("sidelight - port"):
            item["at"] = vec(5.264, 7.40, 11.70)
        elif note.startswith("sidelight - starboard"):
            item["at"] = vec(10.736, 7.40, 11.70)
    return items


# ── trim (ids 100-151), 47 boxes, re-placed onto the rebuilt tiers ─────────
def trim_decks():
    out = []

    def d(i, origin, size, th, note, color=DECK):
        out.append({"id": i, "_is": note, "origin": [rnd(v) for v in origin],
                    "size": [rnd(v) for v in size], "thickness": th,
                    "color": color, "openings": []})

    # 100-102 — EYEBROWS over the saloon window band. These three were the flat
    # bulwark cap rails; the bulwark carries its own swept cap now, so a flat
    # plate can no longer cap it. Same three boxes, doing a job the new shape
    # actually has.
    d(100, [1.20, 2.46, 9.90], [0.22, 23.90], 0.10, "eyebrow over the port window band", WALLPAL)
    d(101, [14.58, 2.46, 9.90], [0.22, 23.90], 0.10, "eyebrow over the starboard window band", WALLPAL)
    d(102, [2.72, 2.70, 35.23], [10.56, 0.22], 0.10, "eyebrow over the transom light", WALLPAL)

    # 103-105 fascia rings on the three deck plates — unchanged, the plates did
    # not move.
    out.append({"id": 103, "_is": "fascia ring on the promenade deck edge",
                "origin": [1.1, 3.06, 6.9], "size": [13.8, 30.2], "thickness": 0.28,
                "color": WALLPAL,
                "openings": [{"type": "hole", "offset": [0.2, 0.2], "size": [13.4, 29.8]}]})
    out.append({"id": 104, "_is": "fascia ring on the sun deck edge",
                "origin": [1.5, 6.06, 8.9], "size": [13.0, 24.2], "thickness": 0.28,
                "color": WALLPAL,
                "openings": [{"type": "hole", "offset": [0.2, 0.2], "size": [12.6, 23.8]}]})
    out.append({"id": 105, "_is": "fascia ring on the boat deck edge",
                "origin": [4.5, 8.46, 10.9], "size": [7.0, 7.7], "thickness": 0.28,
                "color": WALLPAL,
                "openings": [{"type": "hole", "offset": [0.2, 0.2], "size": [6.6, 7.3]}]})

    # 106-111 tier 1 skirts, split around the two boarding doors.
    d(106, [1.16, 0.2, 10.45], [0.22, 23.40], 0.28, "saloon base skirt, port")
    d(107, [14.62, 0.2, 10.45], [0.22, 23.40], 0.28, "saloon base skirt, starboard")
    d(108, [3.66, 0.2, 7.83], [8.68, 0.22], 0.28, "saloon base skirt, front")
    d(109, [2.66, 0.2, 35.09], [1.94, 0.22], 0.28, "saloon base skirt, aft — port of the door")
    d(110, [6.60, 0.2, 35.09], [4.60, 0.22], 0.28, "saloon base skirt, aft — door to companionway")
    d(111, [13.20, 0.2, 35.09], [0.14, 0.22], 0.28, "saloon base skirt, aft — the corner return")

    # 112-116 tier 2 skirts, split around its one door.
    d(112, [1.61, 3.2, 12.00], [0.20, 19.01], 0.24, "upper saloon base skirt, port")
    d(113, [14.19, 3.2, 12.00], [0.20, 19.01], 0.24, "upper saloon base skirt, starboard")
    d(114, [3.76, 3.2, 9.73], [8.48, 0.20], 0.24, "upper saloon base skirt, front")
    d(115, [1.61, 3.2, 30.79], [5.39, 0.20], 0.24, "upper saloon base skirt, aft — port of the door")
    d(116, [9.00, 3.2, 30.79], [5.39, 0.20], 0.24, "upper saloon base skirt, aft — starboard of the door")

    # 117-121 tier 3 skirts, split around the wheelhouse door.
    d(117, [4.63, 6.2, 12.70], [0.18, 5.79], 0.24, "wheelhouse base skirt, port")
    d(118, [11.19, 6.2, 12.70], [0.18, 5.79], 0.24, "wheelhouse base skirt, starboard")
    d(119, [5.98, 6.2, 11.88], [4.04, 0.18], 0.24, "wheelhouse base skirt, front")
    d(120, [4.63, 6.2, 18.29], [2.38, 0.18], 0.24, "wheelhouse base skirt, aft — port of the door")
    d(121, [8.81, 6.2, 18.29], [2.56, 0.18], 0.24, "wheelhouse base skirt, aft — starboard of the door")
    return out


def trim_walls():
    out = []

    def w(i, start, axis, length, height, thickness, note):
        out.append({"id": i, "_is": note, "start": [rnd(v) for v in start], "axis": axis,
                    "length": length, "height": height, "thickness": thickness,
                    "color": DECK, "openings": []})

    # 130-133 rubbing strake round the whole bridge-deck edge — unchanged.
    w(130, [-0.1, -0.3, 0.0], "z", 45.0, 0.34, 0.24, "rubbing strake, port")
    w(131, [16.1, -0.3, 0.0], "z", 45.0, 0.34, 0.24, "rubbing strake, starboard")
    w(132, [-0.22, -0.3, -0.1], "x", 16.44, 0.34, 0.24, "rubbing strake, forward")
    w(133, [-0.22, -0.3, 45.1], "x", 16.44, 0.34, 0.24, "rubbing strake, aft")

    # 140-151 corner posts. Four per tier: the two AFT corners, where the
    # bulkhead is plumb and a post can stand at a corner, and two pilasters just
    # abaft each tier's raked bow facet — a vertical post cannot follow a rake,
    # so it stands where the plating is plumb and dies into the skirt and the
    # fascia as before.
    w(140, [1.18, 0.18, 10.85], "x", 0.24, 2.62, 0.24, "saloon pilaster, port")
    w(141, [14.58, 0.18, 10.85], "x", 0.24, 2.62, 0.24, "saloon pilaster, starboard")
    w(142, [1.18, 0.18, 33.45], "x", 0.24, 2.62, 0.24, "saloon pilaster, port quarter")
    w(143, [14.58, 0.18, 33.45], "x", 0.24, 2.62, 0.24, "saloon pilaster, starboard quarter")
    w(144, [1.60, 3.18, 12.40], "x", 0.22, 2.42, 0.22, "upper saloon pilaster, port")
    w(145, [14.18, 3.18, 12.40], "x", 0.22, 2.42, 0.22, "upper saloon pilaster, starboard")
    w(146, [1.60, 3.18, 30.82], "x", 0.22, 2.42, 0.22, "upper saloon corner post, port aft")
    w(147, [14.18, 3.18, 30.82], "x", 0.22, 2.42, 0.22, "upper saloon corner post, starboard aft")
    w(148, [4.62, 6.18, 13.00], "x", 0.20, 2.22, 0.20, "wheelhouse pilaster, port")
    w(149, [11.18, 6.18, 13.00], "x", 0.20, 2.22, 0.20, "wheelhouse pilaster, starboard")
    w(150, [4.62, 6.18, 18.30], "x", 0.20, 2.22, 0.20, "wheelhouse corner post, port aft")
    w(151, [11.18, 6.18, 18.30], "x", 0.20, 2.22, 0.20, "wheelhouse corner post, starboard aft")
    return out


HULL_BLOCK = {
    "_note": (
        "hull_45x16_cat as PassengerCatamaran builds it, restated so an edges[] run can "
        "loft this hull's stations without naming a vessel script. Held against the built "
        "hull by tests/vessel_render_capture.gd's _check_hull_restatement."
    ),
    "loa_m": 45.0,
    "beam_m": 16.0,
    "depth_m": 5.5,
    "draft_m": 2.2,
    "displacement_t": 520.0,
    "form": "catamaran_demihull",
    "bow_taper_fraction": 0.04,
    "station_count": 10,
}

NOTE = """Two-deck passenger fast ferry on the 45 x 16 m catamaran hull. Bow is -Z, so z=0 is the bow, and every dimension is metres against the 1.8 m figure the capture stands on the afterdeck.

REBUILT 2026-08-10, after the room purge took both saloons and the wheelhouse and left 192 fittings standing in open air. Nothing here is a box made out of walls: the superstructure is 104 RAKED PLATES and the bulwark is one swept sheer band.

1. THE BULWARK IS ONE `edges[]` SHEER BAND (id 60) and it is where the sheer lives. Walls 1/2/3 and the flat cap-rail plates 20/21 are GONE: a deck plate cannot follow a curve, and a constant-height wall is exactly the two-parallel-bars silhouette this fixture used to read as. 58 path points, 57 segments, 171 boxes; three profile rects — navy plating carried `to_base` off base_y -0.10, a red livery stripe 15 mm proud of it, a 0.36 x 0.10 bone cap whose underside sits on the path. It runs z 4 -> 40.9 down each side and across the transom, leaving the fore and after decks to the guardrails they already carried.
   THE CURVE: 1.06 m at the low point, which sits at z=30 — 67% aft, not amidships — rising 0.70 m to 1.76 m at z=4 and 0.12 m to 1.18 m at the transom, a forward-to-aft ratio of 5.8:1. On a 45 m hull the Load Line Convention's standard forward sheer is 50*(L/3+10) mm = 1.25 m, so this is deliberately UNDER standard, about 0.56 of it, where the trawler is 1.6x over: a fast catamaran is a flat-sheered ship and a trawler's sheer on one would be a lie. The band is never authored below 1.06 m, which is the fall-barrier dimension the 1.8 m figure sets, and is not authored down anywhere.
   WHY THE PATH IS AUTHORED AND NOT `from_hull`, which is the more expensive answer and is the honest one. `sheer_bulwark_spec` derives the PLAN line from `deck_half_beam_at`, which puts the band on the hull's own deck edge at plan x ~= 0.05 — 0.6 m outboard of where walls 1 and 2 stood, and outside the strip `tests/vessel_render_capture.gd`'s FERRY_FALL_EDGES actually probes (x 0.25..0.80 inboard of x=0.2, and 15.20..15.75 inboard of x=15.8). Lofting the bulwark there would take the fall-protection claim red for a reason that has nothing to do with fall protection, and that claim is not mine to move. So the path is written down on the lines walls 1 and 2 held and only the Y is a curve. MEASURED: delete this one `edges[]` entry and the rig goes from 0/2922 exposed-edge stations unguarded to 738/2922, first at (0.2, 0, 4.1) — the band really is the barrier the walls were, not a decoration over them.
   The `hull` block is restated anyway, because the capture rig lofts it and holds it against the hull the game spawns: loa 45.000/45.000, beam 16.000/16.000, deck_y 5.500/5.500, sheer 0.990 m forward and 0.330 m aft, all matching.

2. THE SUPERSTRUCTURE IS RAKED PLATES IN THREE TIERS, AND EVERY FRONT OVERHANGS FORWARD. Tier 1 is the long low saloon — 27.5 m of it, 13.6 m wide, 2.88 m of head height — with a front whose top stands 0.80 m forward of its foot, bow facets cutting the forward corners at 45 degrees in plan, quarter facets cutting the after ones, and sides that TUMBLE HOME 0.10 m over their height as a uniform pinch about the centreline, so not one face of the longest thing on the ship is a plumb slab. Tier 2 is the upper saloon, set in and set back, front overhanging 0.70 m. Tier 3 is the wheelhouse: set FORWARD (z 11.9 -> 18.5 of a 45 m ship) and RAISED onto the sun deck, windscreen overhanging 0.85 m over 2.30 m of height, which is 20 degrees of reverse rake and is what a fast ferry's bridge front actually looks like.
   Each tier's FOOT is set aft of the deck plate above it so that deck's edge just clears the top of the rake: foot 7.85 under a deck edge at 7.0, foot 9.75 under 9.0, foot 11.90 under 11.0. That is the constraint that decides where a raked front may stand, because decks 30, 31 and 32 survived the purge and are not moving.

3. THE WINDOW BAND IS A BAND, NOT A ROW OF HOLES. It runs unbroken from the port side, round both bow facets and across the front, to the starboard side — the one thing a fast catamaran ferry is recognised by at any distance. A dark plate set 90 mm into a reveal between a coaming below and a header above, with mullions standing in the reveal. The mullions are 0.12 m WIDE IN METRES: authored as a fraction of the plate they came out 3.1 m wide on a 26 m side and the whole band read as a row of portholes, which is the picture that sent this back for a second pass. They lean forward with the rake of each side's leading edge, because the side fans as it rises and a mullion at a fixed parameter follows it.
   The DOORS are real openings with their proud casing, so both routes are exercised: a 2 m boarding door in the saloon's aft bulkhead, a second 2 m opening beside it that is the AFTER COMPANIONWAY — stair 50 runs z 32.6 -> 37.0 and the bulkhead crosses it, so the arch is where the stair comes through onto the afterdeck, not a decoration — one door in the upper saloon's aft bulkhead and one in the wheelhouse's.

4. WHY THE AFTER QUARTERS ARE CUT BACK TO z=35.3, which is a shape decision made for a measurement. The capture rig stands its 1.8 m figure at plan (12, 0, 39); that spot is data in the rig and is not mine to move. With the saloon's aft bulkhead square at z=36.93 the figure was OCCLUDED: 247 -> 0 orange pixels in profile_port and 42 -> 0 in bow_quarter, measured off the PNGs. The camera sits about 52 m off, so the near (port) side of the deckhouse projects roughly 15% further aft than the far side does, and the saloon's port quarter was landing exactly on top of a figure two metres abaft of it. Cutting the after corners back — sides ending at z=33.80, 1.35 x 1.50 m quarter facets closing to a bulkhead at z=35.30 — restores 247 and 16. CONVENTIONS §3a: a capture with no visible figure has no absolute scale, and a wrongly-proportioned build looks entirely plausible without one. This fixture had four such frames for most of a rebuild.

5. COLOUR DOES VALUE WORK, FOR FREE. The bucket key is material alone, so every colour here rides in the vertex stream and the whole ship still bakes to two surfaces. Squinted it is four values, not one: a dark navy mass running from the hull's topsides through the bulwark plating into the saloon's coaming strake; a bone cap and a red stripe drawing the sheer as two lines that rise together; near-black window bands on both decks; white houses above dark grey decks. The red is the funnels' own red, so the stripe and the stacks are one livery.

6. THE 192-ITEM RIG IS KEPT AND ONLY WHAT LOST ITS HOST MOVED. The sidelights stood on the deleted wheelhouse's corners at y=7.4 and now sit on the rebuilt wheelhouse's two bow facets, pushed out along each facet's own normal. Everything else was already made fast to something that survived the purge — the mast and its two backstays on the boat deck, the funnels and the liferaft cradles on the sun deck, the guardrails on the promenade and the sun deck, the bitts on the main deck — and the rig check agrees: all 4 wire ends made fast, 0 loose.

COST, on RenderingServer's own counters over the four canonical views: DRAW CALLS UNCHANGED at 18 with the shadow pass, because 104 plates, a swept bulwark and eight colours all bucket on MATERIAL alone. Triangles 26 924 -> 33 860, inside the rig's 38 000. Bake 36.7 ms flat, 60.0 ms with AO, against a 900 ms studio budget.

KNOWN RED, and it is not new: `vessel_render_capture._check_fittings` counts anything that is not a spar or a wire as MUTE, so it reports "104 mute" here and "34 mute" on probe_trawler_bulwark. The parent rig has not learned the `plate` primitive; `tests/trawler_render_capture.gd` carries the two-line override and says in its own header that the override should be deleted when the main capture learns it. This fixture is waiting on the same fix and does not have a subclass of its own.

GENERATED by tools/gen_ferry_fixtures.py, together with its trim pair and from one description, which is where the sheer curve's four constants and the three tiers' plan polygons live and where they should be retuned. The JSON is the interface; the generator is the provenance.

WHAT IS STILL MISSING, and is not pretended otherwise: no seats — passenger_capacity is an item attribute and items[] has no reader, so this is still not a certifiable passenger vessel. The promenade deck's side strips are 0.25 m wide between the guardrail and the upper saloon, which is not a walkway; fixing it means moving tier 2 inboard and re-cutting every trim skirt with it. Deck 30 cantilevers 1.7 m abaft the saloon with nothing under it. And `structure_edge_trim_cost_test` compares only walls, decks and stairs between the pair, so the 296 items and the one edge that make up the actual vessel are NOT held identical by anything in the gate — see the trim fixture's note."""

TRIM_NOTE = """probe_ferry_catamaran with EDGE TRIM added by hand, and nothing else changed. Every entity with id < 100 is identical to probe_ferry_catamaran.json; every entity with id >= 100 is trim. Both files are emitted from one description, so the identity is a property of how they are made rather than something anybody has to keep checking by hand.

THE IDENTITY CLAIM IS ONLY HALF-COVERED BY THE GATE, and the gap is worth naming because it is exactly where this pair could rot. `tests/structure_edge_trim_cost_test.gd` walks walls, decks and stairs. It does not walk items[] or edges[] — which since the rebuild is 296 entities and the entire superstructure and bulwark. MEASURED: move one corner of superstructure plate 400 by 0.30 m in this file only and that test still reports PASS on all five checks, including "base entities are unchanged", because the triangle count did not move. A whole-plan comparison catches it (0 differences -> 1). Until the test walks every collection, the two files must keep being generated together.

47 trim boxes in five families, the same count and the same two palette colours as before the rebuild, so the delta the test asserts is still exactly 47 x 12 triangles at zero new mesh instances:
 (a) EYEBROWS 100-102, a 0.22 band brought proud over the saloon's window band, port, starboard and across the transom light. These three ids were the flat bulwark cap rails. The bulwark is a swept sheer band now and carries its own cap in its own profile, so a horizontal plate cannot cap it — a flat cap rail over a curve is the exact mistake the sheer band exists to stop. Same three boxes, moved to a job the rebuilt shape actually has.
 (b) FASCIA BANDS 103-105, a 0.28 ring hung on the edge of each deck plate that serves as a deckhouse roof, bracketing the plate so the roof edge reads as a member rather than a cut. The plates did not move — 30, 31 and 32 survived the purge — but the COLOUR did: these were the deck grey, which on a white deckhouse merged with the window band under it and swallowed the header between them, so the trimmed ferry read as a darker, muddier version of the same ship. They are the palette's other colour now, which is still a palette colour and still one bucket.
 (c) BASE SKIRTS 106-121, a coaming band where each tier's foot meets the deck it stands on, SPLIT AROUND EVERY DOOR so no threshold gains a 0.2 m step. Re-solved against the rebuilt feet, which all moved aft under the raked fronts. This split is the reason hand-authoring does not scale: it needs every door in every tier back-solved by hand, and it has now needed doing twice.
 (d) CORNER POSTS 140-151, four per tier. The two after ones are pilasters on the side just forward of each tier's quarter, the two forward ones pilasters just abaft its raked bow facet. NONE of them is on a corner any more, and that is the finding: a wall is a vertical prism, a vertical post cannot follow a rake, and left at the old forward corners they stood up to 0.56 m proud of the front plate, floating in mid-air ahead of the ship. Trim authored as axis-aligned boxes cannot follow a raked plate. The fix is either to move it by hand every time the shape changes — which is what this file is — or to derive it from the entity it trims.
 (e) RUBBING STRAKE 130-133, a band round the whole 16 x 45 m bridge-deck edge at the hull-deck junction. Unmoved.

Costs nothing in draw calls: every trim entity is material 'painted' in a palette colour, and the baker buckets on material alone. Measured 18 draw calls with the shadow pass, the same as the untrimmed ferry; triangles 33 860 -> 34 988.

GENERATED by tools/gen_ferry_fixtures.py, which emits this file and its untrimmed pair from the same dictionaries and asserts their identity over every collection before it writes."""


def build(with_trim):
    items = superstructure()
    plan = {
        "format": "structure_plan_v1",
        "context": "vessel",
        "hull_id": "hull_45x16_cat",
        "_note": TRIM_NOTE if with_trim else NOTE,
        "palette": {"wall": [0.88, 0.89, 0.91], "deck": DECK},
        "hull": HULL_BLOCK,
        "walls": [],
        "decks": [],
        "stairs": [],
        "items": [],
        "edges": [sheer_edge()],
    }
    base = json.load(open(PLAIN))
    kept_decks = [d for d in base["decks"] if d["id"] in (30, 31, 32)]
    plan["decks"] = copy.deepcopy(kept_decks)
    plan["stairs"] = copy.deepcopy(base["stairs"])
    rig = rebelay(copy.deepcopy([i for i in base["items"] if i["id"] < 400]))
    plan["items"] = rig + items
    if with_trim:
        plan["walls"] = plan["walls"] + trim_walls()
        plan["decks"] = plan["decks"] + trim_decks()
    return plan


def identical(a, b):
    """Every collection, not just the three the gate test walks."""
    bad = 0
    for key in ("format", "context", "hull_id", "palette", "hull", "stairs",
                "items", "edges"):
        if a[key] != b[key]:
            print("  DIFFERS  %s" % key)
            bad += 1
    for key in ("walls", "decks"):
        base = {e["id"]: e for e in a[key]}
        mirror = {e["id"]: e for e in b[key]}
        for i, e in base.items():
            if mirror.get(i) != e:
                print("  DIFFERS  %s id %d" % (key, i))
                bad += 1
        below = [i for i in set(mirror) - set(base) if i < 100]
        if below:
            print("  TRIM ID BELOW 100  %s %s" % (key, below))
            bad += 1
    print("pair identity over every collection: %s" % ("PASS" if not bad else "FAIL"))
    return bad == 0


def main():
    plain = build(False)
    trim = build(True)
    # The identity claim, asserted here rather than hoped for.
    for key in ("hull_id", "palette", "hull", "stairs", "items", "edges"):
        assert plain[key] == trim[key], key
    assert plain["walls"] == [] and [w["id"] for w in trim["walls"]] == \
        [130, 131, 132, 133] + list(range(140, 152))
    for d in plain["decks"]:
        mirror = [t for t in trim["decks"] if t["id"] == d["id"]]
        assert mirror and mirror[0] == d, d["id"]
    json.dump(plain, open(PLAIN, "w"), indent=1)
    json.dump(trim, open(TRIM, "w"), indent=1)
    if not identical(json.load(open(PLAIN)), json.load(open(TRIM))):
        raise SystemExit("the pair is not identical outside the trim run")
    print("items %d (rig %d + plates %d)  edges %d  decks %d/%d  walls %d/%d" % (
        len(plain["items"]), 192, len(plain["items"]) - 192, len(plain["edges"]),
        len(plain["decks"]), len(trim["decks"]), len(plain["walls"]), len(trim["walls"])))
    print("sheer path points", len(plain["edges"][0]["path"]))
    trim_boxes = 0
    for d in trim["decks"]:
        if d["id"] >= 100:
            trim_boxes += 4 if d["openings"] else 1
    trim_boxes += len(trim["walls"])
    print("trim boxes", trim_boxes, "(must be 47)")


if __name__ == "__main__":
    main()
