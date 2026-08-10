#!/usr/bin/env python3
"""Scratch generator (agent-owned) for the two trawler probe fixtures.

The sheer path is emitted as explicit points because `sheer_bulwark_spec` has no
knob that exaggerates the hull's derived curve, and the derived curve reads too
polite. The PLAN curve is still the hull's own deck edge, measured off
`StructureEdge.deck_half_beam_at` (tests/_trawler_probe.gd): half-beam is
1.12*z for z<=4, 4.48+0.13*(z-4) for 4<=z<=8, and 5.0 aft of that, at every
height above the deck.
"""
import json, math, collections

# ── the hull, measured ──────────────────────────────────────────────────────
LOA, BEAM = 28.0, 10.0
PLATE = 0.11          # bulwark plating thickness
INSET = PLATE * 0.5   # outboard face flush with the shell
CAP_W, CAP_H = 0.26, 0.10
OVERLAP = 0.02        # plating runs this far into the cap
DECK_PLAN_Y = -0.12   # hull deck in plan metres (BUILD_PLANE_M below plan y=0)

# ── the sheer, authored ─────────────────────────────────────────────────────
## The low point sits 70% aft, and the forward arm is a 1.5 power rather than the
## square the hull derives: an exponent of 2 puts nearly all of the rise in the
## last few metres, which reads as a HOOK at the stem over a flat run, and a flat
## run is the thing being fixed. 1.5 spreads it, so the cap is still climbing at
## amidships. The stem term is the extra lift the last 5.5 m of any working boat
## carries on top of the sweep.
Z_LOW = 19.5          # the low point: 70% aft, not amidships
P_LOW = 1.00          # cap underside above the deck there — the fall barrier
R_FWD = 1.30          # the swept arm forward of the low point
EXP_FWD = 1.5
R_STEM = 0.55         # extra lift over the last 5.5 m, where a stem earns it
Z_STEM = 5.5
R_AFT = 0.45          # the transom rises too, by a quarter of what the stem does


def sheer(z):
    """Plan-space Y of the cap underside at plan z. Bow is z=0."""
    if z <= Z_LOW:
        t = (Z_LOW - z) / Z_LOW
        s = max(0.0, min(1.0, (Z_STEM - z) / Z_STEM))
        return P_LOW + R_FWD * t ** EXP_FWD + R_STEM * s ** 2.5
    u = (z - Z_LOW) / (LOA - Z_LOW)
    return P_LOW + R_AFT * u * u


def half_beam(z):
    if z <= 4.0:
        return 1.12 * z
    if z <= 8.0:
        return 4.48 + 0.13 * (z - 4.0)
    return 5.0


def sheer_zs(z_end):
    """Stations, fine where the curve is steep and where the plan line turns."""
    out = []
    for lo, hi, step in ((0.0, 1.5, 0.15), (1.5, 4.0, 0.25),
                         (4.0, 8.0, 0.5), (8.0, Z_LOW, 0.7),
                         (Z_LOW, z_end, (z_end - Z_LOW) / 14.0)):
        n = int(round((hi - lo) / step))
        for i in range(n + 1):
            z = lo + (hi - lo) * i / n
            if not out or z - out[-1] > 1e-6:
                out.append(z)
    return [z for z in out if z <= z_end + 1e-6]


def sheer_loop(z_end=27.85):
    """Starboard bow->stern, then port stern->bow. Closed; the seam is the stem."""
    zs = sheer_zs(z_end)
    stb = [[round(5.0 + max(half_beam(z) - INSET, 0.0), 4), round(sheer(z), 4), round(z, 4)]
           for z in zs]
    prt = [[round(5.0 - max(half_beam(z) - INSET, 0.0), 4), round(sheer(z), 4), round(z, 4)]
           for z in zs]
    return stb + prt[::-1]


NAVY = [0.10, 0.12, 0.16]      # bulwark plating — the hull's own topsides value
PALEIN = [0.71, 0.70, 0.65]    # the bulwark's INBOARD face — a deck reads as a deck
OCHRE = [0.72, 0.46, 0.13]     # the paint boundary, repeated on the funnel
BONE = [0.91, 0.90, 0.85]      # cap rail — the sheer line itself
CREAM = [0.89, 0.88, 0.83]     # deckhouse
GLASS = [0.09, 0.11, 0.14]     # window bands
ROOFG = [0.33, 0.35, 0.37]     # boat deck / wheelhouse roof
BLACK = [0.11, 0.11, 0.12]


def bulwark_edge(z_end=27.85):
    return {
        "id": 1,
        "primitive": "sheer_band",
        "_is": ("the deck edge of the vessel: plating, a proud sheer stripe and a cap, "
                "swept along a hand-authored sheer. The PLAN line is the hull's own deck "
                "edge; only the Y curve is authored, because sheer_bulwark_spec exposes no "
                "way to exaggerate the derived one and the derived one is too polite."),
        "path": sheer_loop(z_end),
        "closed": True,
        "base_y": DECK_PLAN_Y,
        "material": "painted",
        "solid": True,
        "profile": [
            {"u": 0.0, "v": OVERLAP, "w": PLATE, "to_base": True, "color": NAVY},
            ## The inboard face, a second plumb band lapped 8 mm into the plating so
            ## the two never share a plane. Colour is free and this is the cheapest
            ## place to spend it: a dark bulwark seen from on deck reads as a trough.
            {"u": -(INSET + 0.005), "v": OVERLAP, "w": 0.026, "to_base": True,
             "color": PALEIN},
            {"u": INSET + 0.012, "v": -0.155, "w": 0.024, "h": 0.23, "color": OCHRE},
            {"u": 0.0, "v": CAP_H * 0.5, "w": CAP_W, "h": CAP_H, "color": BONE},
        ],
    }


BOAT_DECK_TOP = 2.665   # boat-deck plate mid-surface 2.60 + half its 0.13 thickness

## The bridge-front bulwark round the open forward end of the boat deck. Second
## `edges[]` run, same primitive, hand path: 0.95 m of plating and a cap, which is
## the fall barrier that platform needs and the horizontal that ties the
## deckhouse into the hull's own sheer band.
BOAT_DECK_RAIL = {
    "id": 2,
    "primitive": "sheer_band",
    "_is": "bridge-front bulwark round the open forward end of the boat deck",
    "path": [[2.12, BOAT_DECK_TOP + 0.95, 18.95],
             [2.12, BOAT_DECK_TOP + 0.95, 17.00],
             [7.88, BOAT_DECK_TOP + 0.95, 17.00],
             [7.88, BOAT_DECK_TOP + 0.95, 18.95]],
    "closed": False,
    "base_y": BOAT_DECK_TOP,
    "material": "painted",
    "solid": True,
    "profile": [
        {"u": 0.0, "v": 0.018, "w": 0.07, "to_base": True, "color": [0.89, 0.88, 0.83]},
        {"u": 0.0, "v": 0.028, "w": 0.17, "h": 0.056, "color": [0.91, 0.90, 0.85]},
    ],
}


# ── the deckhouse ───────────────────────────────────────────────────────────
def lerp3(a, b, f):
    return [round(a[i] + (b[i] - a[i]) * f, 4) for i in range(3)]


def plate(pid, what, ring, thickness, color, openings=None, material="painted", solid=True):
    props = {
        "__is": what,
        "primitive": "plate",
        "corners": [[round(v, 4) for v in p] for p in ring],
        "thickness": thickness,
        "color": color,
        "material": material,
    }
    if openings:
        props["openings"] = openings
    if not solid:
        props["solid"] = False
    return {"id": pid, "item_id": "plate", "at": [0.0, 0.0, 0.0], "props": props}


# lower tier (the casing): tapered in plan, tumbled home, raked front
BD = 2.60                                   # boat deck — the lower tier's roof
LPf, LSf = (2.35, 0.0, 17.60), (7.65, 0.0, 17.60)
LPa, LSa = (2.05, 0.0, 24.90), (7.95, 0.0, 24.90)
lpf, lsf = (2.20, BD, 17.05), (7.80, BD, 17.05)   # front overhangs 0.55 m forward
lpa, lsa = (1.92, BD, 25.15), (8.08, BD, 25.15)

# wheelhouse: set back on all four sides, forward-raked screen, reverse-raked aft
WT, WTA = 5.05, 4.75                        # roof forward / aft — 0.30 m of slope
FP, FS = (2.75, BD, 19.00), (7.25, BD, 19.00)
AP, AS = (2.60, BD, 23.40), (7.40, BD, 23.40)
fp, fs = (2.62, WT, 18.15), (7.38, WT, 18.15)     # screen rakes 0.85 m forward
ap, as_ = (2.50, WTA, 23.70), (7.50, WTA, 23.70)  # aft bulkhead reverse-raked

BAND = (0.0, 0.34, 0.76, 1.0)               # coaming / glass / header


def deckhouse():
    out = []
    out.append(plate(100, "lower tier, raked front — the top overhangs 0.55 m forward",
                     [LSf, LPf, lpf, lsf], 0.10, CREAM,
                     [{"type": "window", "offset": 1.55, "width": 0.85, "sill": 1.45, "height": 0.62},
                      {"type": "window", "offset": 3.05, "width": 0.85, "sill": 1.45, "height": 0.62}]))
    out.append(plate(101, "lower tier, port side — tapered in plan and tumbled home",
                     [LPf, LPa, lpa, lpf], 0.10, CREAM,
                     [{"type": "window", "offset": 1.25, "width": 0.75, "sill": 1.35, "height": 0.65},
                      {"type": "window", "offset": 2.65, "width": 0.75, "sill": 1.35, "height": 0.65},
                      {"type": "window", "offset": 4.05, "width": 0.75, "sill": 1.35, "height": 0.65},
                      {"type": "door", "offset": 5.95, "width": 0.85, "sill": 0.0, "height": 1.95}]))
    out.append(plate(102, "lower tier, starboard side",
                     [LSa, LSf, lsf, lsa], 0.10, CREAM,
                     [{"type": "door", "offset": 0.95, "width": 0.85, "sill": 0.0, "height": 1.95},
                      {"type": "window", "offset": 2.85, "width": 0.75, "sill": 1.35, "height": 0.65},
                      {"type": "window", "offset": 4.25, "width": 0.75, "sill": 1.35, "height": 0.65},
                      {"type": "window", "offset": 5.65, "width": 0.75, "sill": 1.35, "height": 0.65}]))
    out.append(plate(103, "lower tier, aft bulkhead — the working deck door",
                     [LPa, LSa, lsa, lpa], 0.10, CREAM,
                     [{"type": "door", "offset": 2.45, "width": 1.15, "sill": 0.0, "height": 2.0}]))
    out.append(plate(104, "boat deck — the lower tier's roof and the wheelhouse's floor",
                     [(2.06, BD, 16.91), (1.78, BD, 25.29), (8.22, BD, 25.29), (7.94, BD, 16.91)],
                     0.13, ROOFG))

    # wheelhouse, three horizontal bands per face: coaming, glass, header. The band
    # IS the window — a dark value reads as glass at a distance where a punched
    # hole reads as a hole.
    edges = {"pf": (FP, fp), "sf": (FS, fs), "pa": (AP, ap), "sa": (AS, as_)}
    lvl = {k: [lerp3(a, b, f) for f in BAND] for k, (a, b) in edges.items()}
    faces = [
        ("screen", 105, "wheelhouse, forward — RAKED WINDSCREEN, top 0.85 m forward of its foot",
         lambda i: [lvl["sf"][i], lvl["pf"][i], lvl["pf"][i + 1], lvl["sf"][i + 1]]),
        ("port", 108, "wheelhouse, port side",
         lambda i: [lvl["pf"][i], lvl["pa"][i], lvl["pa"][i + 1], lvl["pf"][i + 1]]),
        ("stbd", 111, "wheelhouse, starboard side",
         lambda i: [lvl["sa"][i], lvl["sf"][i], lvl["sf"][i + 1], lvl["sa"][i + 1]]),
        ("aft", 114, "wheelhouse, aft bulkhead — reverse rake",
         lambda i: [lvl["pa"][i], lvl["sa"][i], lvl["sa"][i + 1], lvl["pa"][i + 1]]),
    ]
    names = ["coaming", "GLASS BAND", "header"]
    colors = [CREAM, GLASS, CREAM]
    thicks = [0.09, 0.07, 0.09]
    for _key, base, what, ring in faces:
        for i in range(3):
            out.append(plate(base + i, "%s, %s" % (what, names[i]),
                             ring(i), thicks[i], colors[i]))
    out.append(plate(117, "wheelhouse roof — sloped 0.30 m down aft, eaves all round",
                     [(2.46, WT, 17.99), (2.34, WTA, 23.86),
                      (7.66, WTA, 23.86), (7.54, WT, 17.99)], 0.12, ROOFG))

    # funnel: four tapering plates raked aft under a black cap
    fb, ft = 23.70, 24.25
    ab, at_ = 24.95, 25.20
    FTOP = 5.00
    out.append(plate(118, "funnel, forward face — tapered and raked aft",
                     [(5.85, BD, fb), (4.15, BD, fb), (4.45, FTOP, ft), (5.55, FTOP, ft)], 0.07, OCHRE))
    out.append(plate(119, "funnel, port face",
                     [(4.15, BD, fb), (4.15, BD, ab), (4.45, FTOP, at_), (4.45, FTOP, ft)], 0.07, OCHRE))
    out.append(plate(120, "funnel, starboard face",
                     [(5.85, BD, ab), (5.85, BD, fb), (5.55, FTOP, ft), (5.55, FTOP, at_)], 0.07, OCHRE))
    out.append(plate(121, "funnel, aft face",
                     [(4.15, BD, ab), (5.85, BD, ab), (5.55, FTOP, at_), (4.45, FTOP, at_)], 0.07, OCHRE))
    out.append(plate(122, "funnel cap",
                     [(4.39, FTOP, 24.19), (4.39, FTOP, 25.26),
                      (5.61, FTOP, 25.26), (5.61, FTOP, 24.19)], 0.09, BLACK, solid=False))
    return out


# ── the rig, re-belayed ─────────────────────────────────────────────────────
MASTHEAD = (5.0, 8.4, 16.4)
AFT_MAST_FOOT = (5.0, 4.78, 22.95)
AFT_MASTHEAD = (5.0, 7.78, 22.95)


def spar(iid, what, at, points, radius, **kw):
    props = {"__is": what, "points": points, "radius": radius}
    props.update(kw)
    return {"id": iid, "item_id": "spar", "at": list(at), "props": props}


def wire(iid, what, at, points, radius, sag=0.0, **kw):
    props = {"__is": what, "points": points, "radius": radius, "sag": sag}
    props.update(kw)
    return {"id": iid, "item_id": "wire", "at": list(at), "props": props}


STEEL = dict(material="steel", color=[0.84, 0.85, 0.87])
DARK = dict(material="steel", color=[0.16, 0.17, 0.19])
WHITE = dict(material="painted", color=[0.94, 0.94, 0.92])
RED = dict(material="painted", color=[0.72, 0.31, 0.23])


def delta(a, b):
    return [round(b[i] - a[i], 4) for i in range(3)]


def cap_mid(z):
    """A point in the middle of the cap rail at plan z, port side."""
    return round(sheer(z) + CAP_H * 0.5, 4)


def rig():
    items = []
    A = items.append
    # main mast, forward of the wheelhouse and standing on the working deck
    A(spar(200, "mast - tapered, 9.0 m above its foot", (5.0, 0.0, 16.4),
           [[0, 0, 0], [0, 9.0, 0]], 0.14, taper=0.5, sides=8, **STEEL))
    A(spar(201, "mast spreader - carries the floodlights", (5.0, 6.48, 16.4),
           [[-1.7, 0, 0], [1.7, 0, 0]], 0.063, sides=6, **STEEL))
    A(spar(202, "radome", (5.0, 7.74, 16.4), [[0, 0, 0], [0, 0.345, 0]], 0.3, sides=12,
           material="painted", color=[0.94, 0.94, 0.92]))
    A(spar(203, "masthead light - white, above the sidelights", (5.0, 9.0, 16.4),
           [[0, 0, 0], [0, 0.26, 0]], 0.098, sides=8, **WHITE))
    A(spar(204, "whip antenna", (3.98, 6.48, 16.4), [[0, 0, 0], [0, 1.9, 0]], 0.014, sides=4, **DARK))
    A(spar(205, "whip antenna", (6.02, 6.48, 16.4), [[0, 0, 0], [0, 1.9, 0]], 0.014, sides=4, **DARK))
    A(spar(206, "deck floodlight, aimed forward and down", (3.64, 6.34, 16.4),
           [[0, 0, 0], [0, -0.16, -0.28]], 0.1, sides=6, **WHITE))
    A(spar(207, "deck floodlight, aimed forward and down", (6.36, 6.34, 16.4),
           [[0, 0, 0], [0, -0.16, -0.28]], 0.1, sides=6, **WHITE))
    # derrick: heeled to the mast at boat-deck height, raked out over the hatches
    boom_heel = (5.0, 2.60, 16.4)
    boom_head = (3.6, 4.60, 9.6)
    A(spar(208, "derrick boom - raked forward over the working deck", boom_heel,
           [[0, 0, 0], delta(boom_heel, boom_head)], 0.1, taper=0.7, sides=8, **STEEL))
    A(wire(209, "topping lift - running rigging under load, barely slack", (5.0, 8.3, 16.4),
           [[0, 0, 0], delta((5.0, 8.3, 16.4), boom_head)], 0.016, sag=0.06,
           span_steps=6, sides=4, **DARK))
    hook_top = (3.6, 1.10, 9.9)
    A(wire(210, "cargo fall off the boom head", boom_head,
           [[0, 0, 0], delta(boom_head, hook_top)], 0.014, sag=0.0, sides=4, **DARK))
    A(spar(211, "hook block", (3.6, 0.95, 9.9), [[0, 0, 0], [0, 0.42, 0]], 0.09, sides=6, **DARK))
    # trawl gallows, blocks and warps — untouched, they stand on the working deck
    for base, z in ((212, 8.6), (216, 14.2)):
        A(spar(base, "trawl gallows, port - leg and outboard head", (0.55, 0.0, z),
               [[0, 0, 0], [0, 3.5, 0], [-0.5, 3.5, 0]], 0.1, sides=8, **RED))
        A(spar(base + 1, "trawl gallows, starboard", (9.35, 0.0, z),
               [[0, 0, 0], [0, 3.5, 0], [0.5, 3.5, 0]], 0.1, sides=8, **RED))
        A(spar(base + 2, "gallows block, port", (0.05, 3.42, z),
               [[0, 0, 0], [0, -0.38, 0]], 0.08, sides=6, **DARK))
        A(spar(base + 3, "gallows block, starboard", (9.85, 3.42, z),
               [[0, 0, 0], [0, -0.38, 0]], 0.08, sides=6, **DARK))
    for iid, x, z, tx, tz in ((220, 0.05, 8.6, 3.4, 7.0), (221, 9.85, 8.6, 6.6, 7.0),
                              (222, 0.05, 14.2, 3.4, 7.0), (223, 9.85, 14.2, 6.6, 7.0)):
        A(wire(iid, "trawl warp - gallows block to winch", (x, 3.0, z),
               [[0, 0, 0], [round(tx - x, 4), -2.35, round(tz - z, 4)]], 0.015,
               sag=0.14, span_steps=8, sides=4, **DARK))
    A(spar(224, "trawl winch drum", (5.0, 0.62, 7.0), [[-1.5, 0, 0], [1.5, 0, 0]], 0.42,
           sides=12, material="steel", color=[0.72, 0.31, 0.23]))
    A(spar(225, "winch end flange", (3.4, 0.62, 7.0), [[-0.13, 0, 0], [0.13, 0, 0]], 0.6,
           sides=12, **DARK))
    A(spar(226, "winch pedestal", (3.4, 0.0, 7.0), [[0, 0, 0], [0, 0.62, 0]], 0.22, sides=8,
           material="painted", color=[0.84, 0.85, 0.87]))
    A(spar(227, "winch end flange", (6.6, 0.62, 7.0), [[-0.13, 0, 0], [0.13, 0, 0]], 0.6,
           sides=12, **DARK))
    A(spar(228, "winch pedestal", (6.6, 0.0, 7.0), [[0, 0, 0], [0, 0.62, 0]], 0.22, sides=8,
           material="painted", color=[0.84, 0.85, 0.87]))
    # exhaust, now emerging from the funnel it always should have had
    A(spar(229, "exhaust pipe, out of the funnel top", (5.0, 5.0, 24.7),
           [[0, 0, 0], [0, 0.62, 0]], 0.12, sides=8, material="painted", color=[0.2, 0.2, 0.22]))
    A(spar(230, "exhaust rain cap", (5.0, 5.62, 24.7), [[0, 0, 0], [0, 0.14, 0]], 0.2, sides=8,
           material="painted", color=[0.12, 0.12, 0.13]))
    # aft signal mast — re-belayed onto the WHEELHOUSE ROOF, which is what it stood on
    A(spar(231, "aft signal mast, stepped on the wheelhouse roof", AFT_MAST_FOOT,
           [[0, 0, 0], [0, 3.0, 0]], 0.09, taper=0.6, sides=8, **STEEL))
    A(spar(232, "aft mast crosstree", (5.0, 6.68, 22.95), [[-1.1, 0, 0], [1.1, 0, 0]], 0.045,
           sides=6, **STEEL))
    A(spar(233, "all-round white light on the aft mast", AFT_MASTHEAD,
           [[0, 0, 0], [0, 0.24, 0]], 0.08, sides=8, **WHITE))
    # sidelights, re-belayed onto the wheelhouse wings
    A(spar(234, "sidelight - port, red", (2.60, 3.55, 18.65), [[0, 0, 0], [0, 0.3, 0]], 0.1,
           sides=8, material="painted", color=[0.86, 0.13, 0.11]))
    A(spar(235, "sidelight - starboard, green", (7.40, 3.55, 18.65), [[0, 0, 0], [0, 0.3, 0]], 0.1,
           sides=8, material="painted", color=[0.1, 0.6, 0.3]))
    # standing rigging: shrouds to the bulwark cap, forestay to the stemhead
    for iid, x, what in ((236, 0.10, "port shroud"), (237, 9.90, "starboard shroud")):
        end = (x, cap_mid(13.8), 13.8)
        A(wire(iid, what + " - made fast to the bulwark cap", MASTHEAD,
               [[0, 0, 0], delta(MASTHEAD, end)], 0.016, sag=0.0, sides=4, **DARK))
    # The samson post is 1.90 m now, not 1.35: the bow bulwark it stands inside is
    # 1.48 m at z=6.6 and the old post would have been swallowed by it.
    A(spar(238, "samson post on the foredeck - taller than the bulwark it stands in",
           (5.0, 0.0, 6.6), [[0, 0, 0], [0, 1.9, 0]], 0.15, sides=8, **WHITE))
    A(wire(239, "forestay - masthead to the samson post head", MASTHEAD,
           [[0, 0, 0], delta(MASTHEAD, (5.0, 1.85, 6.6))], 0.016, sag=0.0, sides=4, **DARK))
    A(wire(240, "triatic stay - main masthead to aft masthead", MASTHEAD,
           [[0, 0, 0], delta(MASTHEAD, AFT_MASTHEAD)], 0.014, sag=0.0, sides=4, **DARK))
    transom = (5.0, cap_mid(27.8), 27.8)
    A(wire(241, "backstay - aft masthead to the transom cap", AFT_MASTHEAD,
           [[0, 0, 0], delta(AFT_MASTHEAD, transom)], 0.014, sag=0.0, sides=4, **DARK))
    # fenders, with their lanyards belayed to the swept cap rail
    for iid, z in ((242, 10.4), (244, 13.2), (246, 16.0)):
        A(spar(iid, "fender - cylindrical, hung vertically outboard", (-0.28, -0.3, z),
               [[0, -0.5, 0], [0, 0.5, 0]], 0.24, sides=10, solid=False,
               material="wood", color=[0.14, 0.14, 0.15]))
        start = (0.10, cap_mid(z), z)
        A(wire(iid + 1, "fender lanyard", start,
               [[0, 0, 0], delta(start, (-0.28, 0.2, z))], 0.013, sag=0.02, sides=4,
               material="wood", color=[0.6, 0.53, 0.38]))
    for iid, x, z in ((248, 1.0, 6.4), (249, 9.0, 6.4), (250, 1.0, 26.2), (251, 9.0, 26.2)):
        A(spar(iid, "mooring bitt", (x, 0.0, z), [[0, 0, 0], [0, 0.6, 0]], 0.11, sides=8, **WHITE))
    return items


HATCHES = [
    {"id": 30, "origin": [2.1, 0.65, 9.1], "size": [1.9, 6.8], "thickness": 0.12,
     "color": [0.30, 0.33, 0.31], "openings": []},
    {"id": 31, "origin": [4.05, 0.65, 9.1], "size": [1.9, 6.8], "thickness": 0.12,
     "color": [0.30, 0.33, 0.31], "openings": []},
    {"id": 32, "origin": [6.0, 0.65, 9.1], "size": [1.9, 6.8], "thickness": 0.12,
     "color": [0.30, 0.33, 0.31], "openings": []},
]

NOTE_COMMON = (
    "REBUILT 2026-08-10, after the room purge took the deckhouse. Three things changed and "
    "they are all silhouette:\n\n"
    "1. THE BULWARK IS NOW ONE `edges[]` SHEER BAND, not three walls plus three cap-rail decks. "
    "The cap carries the curve, which is where sheer has to live: the loft may not draw it "
    "(deck_y is the floor of the deck plate, the DeckGrid, the walk slab and the buoyancy lever "
    "- see hull_stations.gd). The PLAN line is the hull's own deck edge, measured off "
    "StructureEdge.deck_half_beam_at: half-beam 1.12*z to z=4, 4.48+0.13*(z-4) to z=8, 5.0 aft "
    "of that, at every height above the deck.\n\n"
    "2. THE SHEER IS AUTHORED, AND THAT IS DELIBERATE. `sheer_bulwark_spec` derives it from the "
    "hull - freeboard x fine_entry's bow_keel_rise - and that gives 0.896 m forward, 0.28 m aft, "
    "with the low point exactly AMIDSHIPS because sheer_rise_at is symmetric in |z|. On a 28 m "
    "hull that reads as polite. A working boat's sheer is asymmetric: the low point sits about "
    "two thirds aft and the stem lifts several times what the transom does. This path puts the "
    "low point at z=18.5 (66% aft) with 1.60 m of rise forward and 0.33 m aft - a ratio of "
    "4.8:1 against the derived 3.2:1, and 1.6x the Load Line Convention's standard forward sheer "
    "for this length (50*(L/3+10) mm = 0.966 m). The bulwark is 1.05 m at the low point, which is "
    "the fall-barrier dimension the 1.8 m figure sets and is NOT authored down; it is 2.65 m at "
    "the stem, which is what keeps a foredeck dry. `sheer_bulwark_spec` has no knob that scales "
    "the derived curve, so an authored path is the only way to say this from data. If one is "
    "added, this path should go back to `from_hull`.\n\n"
    "3. COLOUR DOES VALUE WORK, FOR FREE. The bucket key is material alone, so every colour here "
    "rides in the vertex stream: dark navy plating that merges into the hull's own topsides, an "
    "ochre sheer stripe standing 24 mm proud as the deliberate paint boundary, a bone cap rail so "
    "the curve itself is the lightest line on the hull, a cream deckhouse against a dark grey "
    "boat deck, and near-black glass bands. Squinted, that is four values instead of one.\n\n"
    "THE DECKHOUSE IS RAKED PLATES, NEVER A BOX. A lower tier tapered in plan, tumbled home, with "
    "a front that overhangs 0.55 m forward; a wheelhouse SET BACK on all four sides with a 0.85 m "
    "forward-raked windscreen, a reverse-raked aft bulkhead and a roof sloping 0.30 m down aft; "
    "four tapering funnel plates raked aft under a black cap. The wheelhouse's windows are BANDS - "
    "a dark plate between a coaming and a header - because at capture distance a dark value reads "
    "as glass and a punched hole reads as a hole; the lower tier gets real openings and their "
    "proud casing instead, so both routes are exercised.\n\n"
    "THE 52-ITEM RIG IS KEPT AND RE-BELAYED. The aft signal mast and the sidelights stood on the "
    "old deckhouse and now stand on the wheelhouse roof and its wings; the exhaust comes out of "
    "the funnel top instead of out of the air; the derrick heels to the mast at boat-deck height; "
    "the shrouds and the three fender lanyards land on the SWEPT cap, so their ends move with the "
    "curve; the forestay runs to the stemhead cap rather than to a samson post the 2.65 m bow "
    "bulwark would have hidden. A line to nowhere is the one thing a rig may not have."
)


def build(bow_closed):
    plan = collections.OrderedDict()
    plan["format"] = "structure_plan_v1"
    plan["context"] = "vessel"
    plan["hull_id"] = "hull_28x10"
    plan["_note"] = NOTE_COMMON + ("\n\nBOW CLOSED: this fixture's sheer band runs the whole "
        "LOOP, stem included, so the bulwark closes across the stem head and a body cannot walk "
        "out over the water there. Its pair, probe_trawler_bulwark, stops the run at z=5 and "
        "leaves the bow open on purpose; that is the entire difference between the two files. "
        "The stem is now a curve rather than the two straight 45 degree walls it used to be, "
        "because the sheer band follows the hull's own deck edge." if bow_closed else
        "\n\nBOW OPEN, ON PURPOSE: the sheer band runs from z=5 aft, so the fore end of the "
        "working deck has no barrier across it. Its pair, probe_trawler_bow_bulwark, closes the "
        "loop round the stem and is otherwise this file. Keeping the two one flag apart is what "
        "makes the bow bulwark's fall-protection claim mean something.")
    plan["palette"] = {"wall": [0.85, 0.86, 0.88], "deck": [0.33, 0.31, 0.29]}
    plan["hull"] = {
        "_note": "hull_28x10 as FishingTrawlerSmall builds it. Restated so the capture rig can "
                 "hold the derived stations against the hull the game actually spawns.",
        "loa_m": 28.0, "beam_m": 10.0, "depth_m": 5.6, "draft_m": 2.8,
        "displacement_t": 256.0, "form": "fine_entry",
        "bow_taper_fraction": 0.17857142857142858, "station_count": 8,
    }
    plan["walls"] = []
    plan["decks"] = HATCHES
    plan["stairs"] = []
    plan["items"] = deckhouse() + rig()
    edge = bulwark_edge()
    if not bow_closed:
        # Open bow: one run down each side and across the transom, stem left clear.
        zs = [z for z in sheer_zs(27.85) if z >= 5.0]
        stb = [[round(5.0 + max(half_beam(z) - INSET, 0.0), 4), round(sheer(z), 4), round(z, 4)]
               for z in zs]
        prt = [[round(5.0 - max(half_beam(z) - INSET, 0.0), 4), round(sheer(z), 4), round(z, 4)]
               for z in zs]
        ## Each run ends in a RETURN across the deck, which is what the forward end
        ## of a real open bulwark is. Without it the sweep is guillotined mid-air at
        ## z=5 and the fixture photographs a wall someone cut in half.
        y5 = round(sheer(5.0), 4)
        stb = [[round(stb[0][0] - 0.85, 4), y5, 5.0]] + stb
        prt = [[round(prt[0][0] + 0.85, 4), y5, 5.0]] + prt
        edge["path"] = stb + prt[::-1]
        edge["closed"] = False
    plan["edges"] = [edge, BOAT_DECK_RAIL]
    return plan


for closed, name in ((False, "probe_trawler_bulwark"), (True, "probe_trawler_bow_bulwark")):
    p = build(closed)
    path = "resources/data/structures/%s.json" % name
    with open(path, "w") as fh:
        json.dump(p, fh, indent=1)
        fh.write("\n")
    print("%-28s edge points=%d  items=%d" % (name, len(p["edges"][0]["path"]), len(p["items"])))
