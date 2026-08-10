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
R_AFT = 0.52          # the transom rises too, by a quarter of what the stem does


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


## Every station costs FOUR boxes (four profile rects x one segment), so the
## sampling is solved rather than picked, and the solution is the same one
## `StructureEdge.sheer_samples_for` uses: a `to_base` band takes its height at
## the segment's HIGHER end, so it over-runs the true curve at the low end by
## exactly the segment's RISE. Keep that rise under the cap's headroom
## (CAP_H - OVERLAP = 0.08 m) and the step is buried inside the cap; let it past
## and a slot of sea opens between the plating and the cap.
##
## `check_sheer_sampling()` measures the worst segment on the emitted path and
## refuses to write a fixture that breaks it, so these five steps are checked,
## not asserted in a comment. Coarsening 8..Z_LOW from 0.7 m to 1.05 m and the
## aft arm from 14 spans to 13 is where the triangles for the rubbing strake and
## the raked stem came from: 10 stations off the open path, 16 off the loop.
SHEER_STEPS = ((0.0, 1.5, 0.2), (1.5, 4.0, 0.3), (4.0, 8.0, 0.7),
               (8.0, Z_LOW, 1.05), (Z_LOW, None, None))
AFT_SPANS = 13
CAP_HEADROOM = CAP_H - OVERLAP


def sheer_zs(z_end):
    """Stations, fine where the curve is steep and where the plan line turns."""
    out = []
    for lo, hi, step in SHEER_STEPS:
        if hi is None:
            hi, n = z_end, AFT_SPANS
        else:
            n = int(round((hi - lo) / step))
        for i in range(n + 1):
            z = lo + (hi - lo) * i / n
            if not out or z - out[-1] > 1e-6:
                out.append(z)
    return [z for z in out if z <= z_end + 1e-6]


def check_sheer_sampling(zs):
    """Worst per-segment rise on this station list, in metres. RED if it exceeds
    the cap's headroom, because that is a visible slot rather than a rounding."""
    worst, at = 0.0, 0.0
    for a, b in zip(zs, zs[1:]):
        rise = abs(sheer(b) - sheer(a))
        if rise > worst:
            worst, at = rise, a
    if worst > CAP_HEADROOM + 1e-9:
        raise SystemExit(
            "sheer sampling too coarse: %.4f m rise at z=%.2f exceeds the %.3f m "
            "the cap can hide" % (worst, at, CAP_HEADROOM))
    return worst, at


def sheer_loop(z_end=27.85):
    """Starboard bow->stern, then port stern->bow. Closed; the seam is the stem."""
    zs = sheer_zs(z_end)
    stb = [[round(5.0 + max(half_beam(z) - INSET, 0.0), 4), round(sheer(z), 4), round(z, 4)]
           for z in zs]
    prt = [[round(5.0 - max(half_beam(z) - INSET, 0.0), 4), round(sheer(z), 4), round(z, 4)]
           for z in zs]
    return stb + prt[::-1]


NAVY = [0.10, 0.12, 0.16]      # bulwark plating — the hull's own topsides value
PALEIN = [0.63, 0.62, 0.57]    # the bulwark's INBOARD face — a deck reads as a deck
OCHRE = [0.62, 0.36, 0.11]     # the paint boundary, repeated on the funnel
BONE = [0.91, 0.90, 0.85]      # cap rail — the sheer line itself
CREAM = [0.89, 0.88, 0.83]     # deckhouse
GLASS = [0.09, 0.11, 0.14]     # window bands
ROOFG = [0.30, 0.32, 0.34]     # boat deck — the dark step between two pale tiers
ROOFW = [0.52, 0.54, 0.56]     # wheelhouse roof — a value clear of the boat deck
BLACK = [0.11, 0.11, 0.12]
GUARD = [0.34, 0.35, 0.37]     # rubbing strake body — a value break, not a black bar
GUARDTOP = [0.62, 0.63, 0.64]  # its top chamfer: one light line 0.7 m under the sheer
GREYST = [0.24, 0.25, 0.27]    # bare steelwork — gallows heels, doublers, brackets


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


## THE BOAT DECK SLOPES AFT, 0.24 m over its 8.1 m, and that is a silhouette
## decision as much as a drainage one: seen in profile the lower tier's side is
## the one face of the deckhouse whose rake is edge-on, so without a sloping top
## edge it is a rectangle - which is exactly the read the room primitive was
## deleted for. Every level above it is solved from `bd()` rather than restated.
BD_F, BD_A = 2.74, 2.50
BD_ZF, BD_ZA = 17.05, 25.15


def bd(z):
    return round(BD_F + (BD_A - BD_F) * (z - BD_ZF) / (BD_ZA - BD_ZF), 4)


def deck_top(z):
    return round(bd(z) + 0.065, 4)   # plate mid-surface plus half its 0.13 thickness


## The bridge-front bulwark round the open forward end of the boat deck. Second
## `edges[]` run, same primitive, hand path: 0.9 m of plating and a cap, which is
## the fall barrier that platform needs and the horizontal that ties the
## deckhouse into the hull's own sheer band.
BOAT_DECK_RAIL = {
    "id": 2,
    "primitive": "sheer_band",
    "_is": "bridge-front bulwark round the open forward end of the boat deck",
    "path": [[2.12, deck_top(18.95) + 0.90, 18.95],
             [2.12, deck_top(17.00) + 0.90, 17.00],
             [7.88, deck_top(17.00) + 0.90, 17.00],
             [7.88, deck_top(18.95) + 0.90, 18.95]],
    "closed": False,
    "base_y": 2.66,
    "material": "painted",
    "solid": True,
    "profile": [
        {"u": 0.0, "v": 0.018, "w": 0.07, "to_base": True, "color": [0.89, 0.88, 0.83]},
        {"u": 0.0, "v": 0.028, "w": 0.17, "h": 0.056, "color": [0.91, 0.90, 0.85]},
    ],
}



# ── the rubbing strake ───────────────────────────────────────────────
## COMPONENTS.md lists the rubbing strake as one of the ten parts the sweep
## primitive absorbs, and this is that entry used for what it is for: the hull
## sides are otherwise one unbroken 2.8 m of navy from the boot top to the sheer
## stripe, and at a squint that is a single mass with no relief in it.
##
## TWO THINGS ARE MEASURED HERE RATHER THAN DRAWN BY EYE, and they are the whole
## reason the numbers below are a table and not a formula:
##
##  1. THE PLAN LINE IS THE SHELL AT THE STRAKE'S OWN HEIGHT, not at the deck.
##     The topsides flare: on this hull the section pulls in 0.188 m per metre of
##     depth over the parallel body and 0.668 m/m at z=4, so a band hung 0.62 m
##     under the deck edge on the DECK's half-beam would float up to 120 mm off
##     the shell. Every x below is `StructureEdge.deck_half_beam_at(z, deck_y-d)`
##     read out of the hull the game builds (.probe dump, 2026-08-10).
##  2. IT CANNOT FOLLOW THE SHEER, and that is the loft's constraint, not a
##     choice. `deck_y` is flat — the hull has no sheer in it, which is the whole
##     reason the bulwark cap carries the curve — so a strake swept along the
##     sheer would leave the shell entirely and hang 2.7 m in the air at the stem.
##     What it CAN do is rise as the shell allows: `d` shrinks from 0.62 m aft to
##     0.30 m at the stem, so the band lifts 0.32 m forward and echoes the sheer
##     without ever leaving the plating.
##
## Sampled at 14 stations a side rather than the bulwark's 30: the section here
## is CONSTANT, so it rides the tangent and simply tilts, and none of the
## per-station step the `to_base` plating has to hide applies to it.
STRAKE = [
    (0.15, 0.2883, 0.1608), (0.80, 0.3235, 0.8528), (1.60, 0.3656, 1.6944),
    (2.60, 0.4160, 2.7315), (4.00, 0.4819, 4.1583), (5.20, 0.5332, 4.3568),
    (6.40, 0.5780, 4.5725), (8.00, 0.6200, 4.8835), (13.00, 0.6200, 4.8835),
    (18.00, 0.6200, 4.8835), (22.00, 0.6200, 4.8835), (24.00, 0.6200, 4.8835),
    (25.80, 0.6200, 4.8022), (27.30, 0.6200, 4.7344),
]


def strake_side(side):
    """Starboard runs bow->stern, PORT runs stern->bow, and the direction is not
    cosmetic: `u` is measured off the sweep's own frame, whose lateral axis is
    +x when the run heads +z. A port run authored bow->stern would put the whole
    profile's outboard offset INBOARD, i.e. inside the hull."""
    out = [[round(5.0 + side * hb, 4), round(DECK_PLAN_Y - d, 4), z]
           for z, d, hb in STRAKE]
    return out if side > 0.0 else out[::-1]


## ── SOLID: FALSE, AND IT IS NOT LAZINESS ────────────────────────────────────
## The band's inboard face is ON the shell, which is where a bolted-on belting
## belongs — and a collider there OVERLAPS THE LOFT, which `hull_sheer_test`'s
## plan-clearance check forbids and caught: 54 shell triangles inside plan boxes
## on the first draft. The two ways out are to stand the strake 60 mm off the
## plating it is supposed to be bolted to, or to say what it actually is.
## `SWEEP_COLLIDER_MIN_M`'s own note names this case exactly — "a surface
## treatment on something that already collides" — and the something is the
## hull. No body can reach it: it is outboard of the shell, 0.6 m below a deck
## edge that carries a 1.0-2.9 m bulwark. So it draws and does not collide, and
## the geometry stays true instead of being bent around a test.
##
## TWO OPEN RUNS, not one loop, for the same kind of reason: a closed loop puts
## a chord straight across the transom 0.3 m INSIDE the hull and another across
## the stem. Belting that stops at the stem and the transom corner is what a
## working boat carries anyway.
def rubbing_strake(eid, side, name):
    return {
        "id": eid,
        "primitive": "sheer_band",
        "_is": ("rubbing strake, %s — the sacrificial belting that takes the quay. "
                "A swept section on the shell's own line, 0.29 m under the deck edge "
                "at the stem and 0.62 m under it aft, so it lifts forward without "
                "ever leaving the plating." % name),
        "path": strake_side(side),
        "closed": False,
        "material": "painted",
        "solid": False,
        "profile": [
            ## 115 mm proud x 200 mm tall — COMPONENTS.md's 60-150 x 80-200 mm band,
            ## with its inboard face ON the shell so it reads as bolted to it.
            ##
            ## LIGHTER than the topsides, not darker, and that is the whole point of
            ## drawing it. A black belting is what a real trawler carries and it is
            ## what this was first given — against 0.11-value navy plating it
            ## photographed as nothing at all, because value contrast is the only
            ## contrast a squint can see. 0.34 against 0.11 is a break; 0.06 against
            ## 0.11 is a rumour.
            {"u": 0.0575, "v": 0.0, "w": 0.115, "h": 0.20, "color": GUARD},
            ## The top chamfer, for LIGHT rather than for steel: a horizontal face
            ## 0.7 m under the cap catches the sun where the topsides do not.
            {"u": 0.048, "v": 0.121, "w": 0.096, "h": 0.045, "color": GUARDTOP},
        ],
    }


# ── the bow: rake and flare, as far as a plate can carry it ───────────────
## WHAT IS HONESTLY FIXABLE HERE AND WHAT IS NOT.
##
## The hull's STEM — everything below the deck edge — is lofted by
## `HullStations` from `fine_entry`'s bow taper and is near plumb. Nothing in a
## structure plan can rake it; that is the loft's, and it is the one part of
## "the stem is blunt and near-vertical" this file cannot answer. What a plan
## owns is everything ABOVE the deck, and on a working boat that is most of what
## a raked stem actually looks like: the bulwark at the bow is a flared, raked
## plate that leads the stem head and carries the sheer up to it.
##
## So the bow bulwark forward of z=5.6 is not the plumb swept band — a `to_base`
## rect is PLUMB IN WORLD SPACE by construction and can never rake — it is raked
## plate, three quads a side, and the numbers are:
##   FLARE  0.06 m at z=5.6 growing to 0.58 m at the stem head, so the cap stands
##          that far outboard of the deck edge it rises from;
##   RAKE   0 m at z=5.6 growing to 1.10 m, so the cap LEADS its own foot by more
##          than a metre — 21 degrees of forward rake over the 2.95 m of bulwark.
## Both are powers of the same normalised run, so the structure fairs into the
## swept band at z=5.6 instead of stepping into it.
BOW_Z = 5.6            # where flare and rake are both zero and the sweep takes over
BOW_LAP = 0.15         # the plate laps the swept band by this much, so no seam shows
FLARE_MAX, FLARE_EXP = 0.50, 1.5
RAKE_MAX, RAKE_EXP = 1.10, 1.7
BOW_FOOT = -0.10       # the plate's foot, just clear of the deck plane
PROUD = 0.03           # stood off the shell so it never shares a plane with it
STEM_Z = 0.35          # the stem head: the fore end of the bow structure


def bow_t(z):
    return max(0.0, min(1.0, (BOW_Z - z) / BOW_Z))


def flare(z):
    return 0.06 + FLARE_MAX * bow_t(z) ** FLARE_EXP


def rake(z):
    return RAKE_MAX * bow_t(z) ** RAKE_EXP


def bow_foot(z, side):
    return (round(5.0 + side * (half_beam(z) + PROUD), 4), BOW_FOOT, round(z, 4))


## The plating's top edge is the CAP'S TOP FACE — sheer(z) + CAP_H — because the
## swept band's cap spans exactly path.y .. path.y + CAP_H and the two have to
## meet at the lap. Drawn 20 mm higher, as it first was, the bow cap stepped
## visibly over the swept one at z=5.75 in every profile frame.
def bow_head(z, side, drop=0.0):
    return (round(5.0 + side * (half_beam(z) + PROUD + flare(z)), 4),
            round(sheer(z) + CAP_H - drop, 4), round(z - rake(z), 4))


## Stations: the deck edge KINKS at z=4 (half-beam goes from 1.12*z to
## 4.48+0.13*(z-4)), so a quad may not span it, and the sheer's own curvature
## wants one more break forward of that.
BOW_STATIONS = [BOW_Z + BOW_LAP, 4.0, 2.0, STEM_Z]


def _shift(pt, dx, side):
    return (round(pt[0] + side * dx, 4), pt[1], pt[2])


## A point on the bow plate's own surface, `drop` metres of HEIGHT below its top
## edge, shifted `dx` outboard. The plate is a bilinear patch that rakes forward
## and flares outward as it rises, so a band across it is not "the same corners
## moved down" — that draws a full-height panel, which is exactly what the first
## attempt at the sheer stripe did and it photographed as a bow painted ochre
## from the deck up. It has to be interpolated along the patch.
def bow_band_pt(z, side, drop, dx=0.0):
    foot, head = bow_foot(z, side), bow_head(z, side)
    span = head[1] - foot[1]
    f = 1.0 if span <= 1e-6 else max(0.0, min(1.0, 1.0 - drop / span))
    pt = [foot[i] + (head[i] - foot[i]) * f for i in range(3)]
    pt[0] += side * dx
    return tuple(round(v, 4) for v in pt)


def bow_structure(bow_closed):
    """Raked, flared bow bulwark: four skins a side — plating, its pale inboard
    face, the ochre sheer stripe and the cap — plus the stem face across it.

    THE STRIPE AND THE LINING ARE NOT DECORATION. The swept band aft of z=5.6
    carries an ochre stripe outboard and a pale face inboard; drawn without
    them the bow was a navy slab that stopped both of those lines dead at a
    vertical seam amidships, which photographs as damage rather than as a bow.
    A paint boundary that stops halfway along a hull is worse than no paint
    boundary."""
    out = []
    pid = 140
    for side in (-1.0, 1.0):
        name = "port" if side < 0 else "starboard"
        for a, b in zip(BOW_STATIONS, BOW_STATIONS[1:]):
            fa, fb = bow_foot(a, side), bow_foot(b, side)
            ha, hb_ = bow_head(a, side), bow_head(b, side)
            out.append(plate(
                pid, "bow bulwark, %s — raked %.2f m forward and flared %.2f m out"
                % (name, rake(b) - rake(a), flare(b) - flare(a)),
                [fa, fb, hb_, ha], 0.10, NAVY))
            ## The cap rail over it. The swept band's cap is the lightest line on
            ## the hull and the reason the sheer reads at all; the bow is where
            ## that line does its most work, so it does not stop at z=5.6.
            out.append(plate(
                pid + 1, "bow cap rail, %s" % name,
                [_cap_pt(a, side, -1.0), _cap_pt(b, side, -1.0),
                 _cap_pt(b, side, 1.0), _cap_pt(a, side, 1.0)],
                CAP_H, BONE))
            ## The ochre sheer stripe — the same 0.23 m section the swept band
            ## carries, so the paint boundary runs unbroken transom to stem.
            out.append(plate(
                pid + 2, "bow sheer stripe, %s" % name,
                [bow_band_pt(a, side, STRIPE_LO, STRIPE_U),
                 bow_band_pt(b, side, STRIPE_LO, STRIPE_U),
                 bow_band_pt(b, side, STRIPE_HI, STRIPE_U),
                 bow_band_pt(a, side, STRIPE_HI, STRIPE_U)],
                0.024, OCHRE))
            ## The pale inboard face, matching the swept band's, so the trough a
            ## crew works in is one value the whole length of the boat.
            out.append(plate(
                pid + 3, "bow bulwark inboard face, %s" % name,
                [_shift(fa, -0.075, side), _shift(fb, -0.075, side),
                 _shift(hb_, -0.075, side), _shift(ha, -0.075, side)],
                0.026, PALEIN))
            pid += 4
    if True:
        out.append(plate(
            152, "stem face — the bulwark closed across the stem head, raked "
                 "1.10 m forward over its 2.95 m and flaring out as it rises",
            [bow_foot(STEM_Z, -1.0), bow_foot(STEM_Z, 1.0),
             bow_head(STEM_Z, 1.0), bow_head(STEM_Z, -1.0)], 0.10, NAVY))
            ## The cap ACROSS the stem head. Its outboard edge is the forward one:
            ## the two side runs' caps meet it there, so the bone line is continuous
            ## round the bow instead of stopping either side of it.
        fwd_p = _cap_pt(STEM_Z, -1.0, 1.0)
        fwd_s = _cap_pt(STEM_Z, 1.0, 1.0)
        aft_p = _cap_pt(STEM_Z, -1.0, -1.0)
        aft_s = _cap_pt(STEM_Z, 1.0, -1.0)
        out.append(plate(
            154, "stem face, sheer stripe",
            [bow_band_pt(STEM_Z, -1.0, STRIPE_LO), bow_band_pt(STEM_Z, 1.0, STRIPE_LO),
             bow_band_pt(STEM_Z, 1.0, STRIPE_HI), bow_band_pt(STEM_Z, -1.0, STRIPE_HI)],
            0.024, OCHRE, offset_z=-0.075))
        out.append(plate(
            153, "stem head cap — the cap rail carried across the stem",
            [fwd_p, fwd_s,
             (aft_s[0], aft_s[1], round(aft_s[2] + 0.26, 4)),
             (aft_p[0], aft_p[1], round(aft_p[2] + 0.26, 4))], CAP_H, BONE))
    return out


def _cap_pt(z, side, out_sign):
    """A corner of the bow cap: the head point, moved 0.11 m inboard or 0.15 m
    outboard, at the cap's mid-thickness."""
    x, y, zz = bow_head(z, side, drop=CAP_H * 0.5)
    return (round(x + side * (0.15 if out_sign > 0 else -0.11), 4), y, zz)


## Where the sheer stripe's edges sit, as a DROP below the plating's top edge.
## The swept band puts it at sheer-0.27 .. sheer-0.04 (a rect at v -0.155, h 0.23
## about a path at sheer), and bow_head is now sheer + CAP_H, so:
STRIPE_LO = CAP_H + 0.27
STRIPE_HI = CAP_H + 0.04
## 0.075 outboard, not 0.062: the plating is 0.10 thick, so its outer face is at
## 0.05, and a 0.024 stripe centred at 0.062 lands its inner face EXACTLY on that
## plane. Coplanar solids z-fight, and this pair did — the stripe broke into
## flickering fragments along the bow in every render. 0.075 puts it 13 mm proud.
STRIPE_U = 0.075


# ── the deckhouse ───────────────────────────────────────────────────────────
def lerp3(a, b, f):
    return [round(a[i] + (b[i] - a[i]) * f, 4) for i in range(3)]


def _sub(a, b, f):
    return tuple(a[i] + (b[i] - a[i]) * f for i in range(3))


def _normal(ring):
    d1 = [ring[2][i] - ring[0][i] for i in range(3)]
    d2 = [ring[3][i] - ring[1][i] for i in range(3)]
    n = (d1[1] * d2[2] - d1[2] * d2[1],
         d1[2] * d2[0] - d1[0] * d2[2],
         d1[0] * d2[1] - d1[1] * d2[0])
    m = math.sqrt(sum(v * v for v in n)) or 1.0
    return [v / m for v in n]


# ── THE WINDOW TREATMENT, one rule for every tier ───────────────────────────
##
## The wheelhouse used to be the only tier with glass in it: a dark band between
## a coaming and a header. The lower tier had punched holes and nothing behind
## them, so at every range they read as pale rectangles the value of the plating
## — as holes, which is exactly what they were. Both tiers now get the same part:
##
##   * the window run is ONE band, not a row of separate punches;
##   * a dark GLASS pane sits REVEAL inboard of the shell plane and LAPS past the
##     opening on every side, so the reveal is real depth and no daylight leaks
##     round the pane where it meets the plating;
##   * cream MULLIONS stand IN the reveal, at the shell plane — proud of the
##     glass, shy of the coaming, which is where a mullion is;
##   * a three-plate wheelhouse face also gets a CORNER PILLAR at each end. Two
##     recessed panes meeting at a corner leave a REVEAL-square notch, and the
##     pillars are what close it.
##
## A DOOR keeps its punched opening and gets no glass: a door is a hole you walk
## through, and tests/plan_interior_test.gd marches a player capsule through one.
REVEAL = 0.10      # how far the glass sits behind the shell plane
GLASS_T = 0.03     # the pane
GLASS_LAP = 0.12   # how far the pane runs on past the opening, hidden behind it
MULL_HW = 0.05     # half-width of a mullion
POST_HW = 0.065    # half-width of a corner pillar
## A post BRIDGES the reveal: its outer face stands POST_PROUD off the shell
## plane (a hair proud of the 0.09 coaming, so nothing is coplanar) and its
## inner face lands on the glass. A post that only straddled the shell plane
## left a gap either side of it, and at a grazing angle — the port beam onto a
## forward-raked screen — the eye looked THROUGH those gaps and the whole band
## broke into fine dark hatching. Measured on the first render of this change.
POST_PROUD = 0.05
POST_T = POST_PROUD + REVEAL
POST_MID = (REVEAL - POST_PROUD) * 0.5   # how far inboard the post's mid-plane sits

## Sized against the 1.8 m figure: a 0.72 m light with its sill at 1.30 m puts a
## standing person's eye (1.60 m) in the middle of the glass. Same two numbers on
## every tier of every vessel.
SILL, LIGHT_H = 1.30, 0.72

## DOORS, sized against the same figure BY MEASUREMENT — tests/plan_interior_test.gd
## marches a player capsule (0.70 m across, 1.8 m tall, standing on a walk deck
## 0.09 m above the plan's deck plane) through every one of them.
##
## A doorway in a RAKED plate is a LEANING SLOT. Its jambs are rectangles in the
## plate's own (u, v) parameters, and this casing's sides run 7.31 m at the foot
## and 8.11 m at the top, so a jamb travels along the wall between a player's
## feet and their head. What a player can use is the INTERSECTION of the opening
## over their own height, and the 0.85 m side doors measured a walkable column of
## 0.000 m — a 1.8 m figure could not get through either of them at any lateral
## position. Their heads were worse: 1.95 m of opening measured along a tumbled-
## home plate put the lintel at 1.78 m, under the 1.89 m a standing figure needs.
## Nothing about the vessel looked wrong; the aft door, in a plate with almost no
## lean, worked, so the fixture had one usable door and read as if it had three.
DOOR_W, DOOR_H = 1.30, 2.25
AFT_DOOR_W, AFT_DOOR_H = 1.20, 2.15


def _ppoint(c, u, v):
    """StructureBaker.plate_point — the bilinear patch at (u, v)."""
    return _sub(_sub(c[0], c[1], u), _sub(c[3], c[2], u), v)


def _subquad(c, u0, u1, v0, v1):
    """StructureBaker.plate_subquad."""
    return [_ppoint(c, u0, v0), _ppoint(c, u1, v0),
            _ppoint(c, u1, v1), _ppoint(c, u0, v1)]


def _refs(c):
    """StructureBaker.plate_ref_lengths — mean u edge, mean v edge, in metres."""
    return ((math.dist(c[0], c[1]) + math.dist(c[3], c[2])) * 0.5,
            (math.dist(c[0], c[3]) + math.dist(c[1], c[2])) * 0.5)


def _outward(ring, inside):
    """The plate normal pointing AWAY from a point known to be inside the tier."""
    n = _normal(ring)
    mid = _ppoint(ring, 0.5, 0.5)
    away = sum(n[i] * (mid[i] - inside[i]) for i in range(3))
    return n if away > 0.0 else [-v for v in n]


def _offset_ring(ring, n, d):
    return [tuple(p[i] + n[i] * d for i in range(3)) for p in ring]


def _centroid(rings):
    pts = [p for r in rings for p in r]
    return [sum(p[i] for p in pts) / len(pts) for i in range(3)]


def band_glass(pid, shell, inside, opening, what):
    """The recessed pane behind a PUNCHED band in a shell plate."""
    ul, vl = _refs(shell)
    off, w = opening["offset"], opening["width"]
    sill, h = opening["sill"], opening["height"]
    ring = _subquad(shell,
                    max((off - GLASS_LAP) / ul, 0.0), min((off + w + GLASS_LAP) / ul, 1.0),
                    max((sill - GLASS_LAP) / vl, 0.0), min((sill + h + GLASS_LAP) / vl, 1.0))
    return plate(pid, what, _offset_ring(ring, _outward(shell, inside), -REVEAL), GLASS_T, GLASS)


def band_mullions(pid, shell, inside, opening, count):
    """Posts standing in the reveal of a punched band, bridging it."""
    ul, vl = _refs(shell)
    n = _outward(shell, inside)
    off, w = opening["offset"], opening["width"]
    v0, v1 = opening["sill"] / vl, (opening["sill"] + opening["height"]) / vl
    out = []
    for k in range(1, count + 1):
        um = (off + w * k / (count + 1.0)) / ul
        d = MULL_HW / ul
        ring = _offset_ring(_subquad(shell, um - d, um + d, v0, v1), n, -POST_MID)
        out.append(plate(pid + k - 1, "window mullion, standing in the reveal",
                         ring, POST_T, CREAM, solid=False))
    return out


def face_glass(pid, band, inside, what):
    """The pane for a three-plate face: the coaming and the header keep the shell
    plane, the glass drops REVEAL behind them and grows GLASS_LAP past the band
    top and bottom so it is hidden behind them instead of leaving a slot."""
    _, vl = _refs(band)
    ring = _subquad(band, 0.0, 1.0, -GLASS_LAP / vl, 1.0 + GLASS_LAP / vl)
    return plate(pid, what, _offset_ring(ring, _outward(band, inside), -REVEAL), GLASS_T, GLASS)


## Mullions across a three-plate face's band, plus a corner pillar at each end.
## Derived from the BAND, not authored beside it, so a post cannot drift off a
## wheelhouse face that gets re-raked.
def face_posts(pid, band, inside, count):
    ul, _ = _refs(band)
    n = _outward(band, inside)
    out = []
    for k in range(1, count + 1):
        f = k / (count + 1.0)
        d = MULL_HW / ul
        ring = _offset_ring(_subquad(band, f - d, f + d, 0.0, 1.0), n, -POST_MID)
        out.append(plate(pid + len(out), "window mullion, standing in the reveal",
                         ring, POST_T, CREAM, solid=False))
    d = 2.0 * POST_HW / ul
    for u0, u1 in ((0.0, d), (1.0 - d, 1.0)):
        ring = _offset_ring(_subquad(band, u0, u1, 0.0, 1.0), n, -POST_MID)
        out.append(plate(pid + len(out), "wheelhouse corner pillar",
                         ring, POST_T, CREAM, solid=False))
    return out


def plate(pid, what, ring, thickness, color, openings=None, material="painted",
          solid=True, offset_z=0.0):
    props = {
        "__is": what,
        "primitive": "plate",
        "corners": [[round(v + (offset_z if i == 2 else 0.0), 4)
                     for i, v in enumerate(p)] for p in ring],
        "thickness": thickness,
        "color": color,
        "material": material,
    }
    if openings:
        props["openings"] = openings
    if not solid:
        props["solid"] = False
    return {"id": pid, "item_id": "plate", "at": [0.0, 0.0, 0.0], "props": props}


# lower tier (the casing): tapered in plan, tumbled home, raked front, top edge
# falling aft with the boat deck
LPf, LSf = (2.35, 0.0, 17.60), (7.65, 0.0, 17.60)
LPa, LSa = (2.05, 0.0, 24.90), (7.95, 0.0, 24.90)
lpf, lsf = (2.20, BD_F, 17.05), (7.80, BD_F, 17.05)   # front overhangs 0.55 m forward
lpa, lsa = (1.92, BD_A, 25.15), (8.08, BD_A, 25.15)

# wheelhouse: set back on all four sides, forward-raked screen, reverse-raked aft
WT, WTA = 5.05, 4.75                        # roof forward / aft — 0.30 m of slope
FP, FS = (2.75, bd(19.00), 19.00), (7.25, bd(19.00), 19.00)
AP, AS = (2.60, bd(23.40), 23.40), (7.40, bd(23.40), 23.40)
fp, fs = (2.62, WT, 18.15), (7.38, WT, 18.15)     # screen rakes 0.85 m forward
ap, as_ = (2.50, WTA, 23.70), (7.50, WTA, 23.70)  # aft bulkhead reverse-raked

BAND = (0.0, 0.34, 0.76, 1.0)               # coaming / glass / header


## Each lower-tier face: its ring, its openings, and how many mullions stand in
## its window band. The three punched lights a side are ONE band now — a
## continuous dark run reads as glazing at the range these vessels are seen at,
## where three separate holes read as three holes.
LOWER_FACES = [
    (100, "lower tier, raked front — the top overhangs 0.55 m forward", [LSf, LPf, lpf, lsf],
     [{"type": "window", "offset": 1.55, "width": 2.35, "sill": SILL, "height": LIGHT_H}], 1),
    (101, "lower tier, port side — tapered in plan and tumbled home", [LPf, LPa, lpa, lpf],
     [{"type": "window", "offset": 1.25, "width": 3.55, "sill": SILL, "height": LIGHT_H},
      {"type": "door", "offset": 5.95, "width": DOOR_W, "sill": 0.0, "height": DOOR_H}], 2),
    (102, "lower tier, starboard side", [LSa, LSf, lsf, lsa],
     [{"type": "door", "offset": 0.95, "width": DOOR_W, "sill": 0.0, "height": DOOR_H},
      {"type": "window", "offset": 2.85, "width": 3.55, "sill": SILL, "height": LIGHT_H}], 2),
    ## The aft bulkhead faces the working deck and carries the door and nothing
    ## else. That is not an oversight and it is not a punched-hole holdout: a
    ## trawler's after casing bulkhead is where the gear comes aboard, and a
    ## light there is a light waiting to be broken by a full cod end.
    (103, "lower tier, aft bulkhead — the working deck door", [LPa, LSa, lsa, lpa],
     [{"type": "door", "offset": 2.45, "width": AFT_DOOR_W, "sill": 0.0, "height": AFT_DOOR_H}], 0),
]
GLASS_ID = 400      # lower-tier panes and their mullions
POST_ID = 420       # wheelhouse mullions and corner pillars


def deckhouse():
    out = []
    inside = _centroid([ring for _, _, ring, _, _ in LOWER_FACES])
    gid = GLASS_ID
    for pid, what, ring, openings, mullion_count in LOWER_FACES:
        out.append(plate(pid, what, ring, 0.10, CREAM, openings))
        for opening in openings:
            if opening["type"] != "window":
                continue
            out.append(band_glass(gid, ring, inside, opening,
                                  "%s — GLASS, recessed %.2f m in the reveal"
                                  % (what.split(" — ")[0], REVEAL)))
            gid += 1
            if mullion_count:
                out.extend(band_mullions(gid, ring, inside, opening, mullion_count))
                gid += mullion_count
    out.append(plate(104, "boat deck — the lower tier's roof, sloping 0.24 m aft",
                     [(2.06, bd(16.91), 16.91), (1.78, bd(25.29), 25.29),
                      (8.22, bd(25.29), 25.29), (7.94, bd(16.91), 16.91)], 0.13, ROOFG))

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
    posts = {"screen": 3, "port": 3, "stbd": 3, "aft": 2}
    house_inside = _centroid([f[3](1) for f in faces])
    pid = POST_ID
    for key, base, what, ring in faces:
        for i in range(3):
            ## The middle band is the GLASS and it no longer sits in the shell
            ## plane: face_glass drops it REVEAL behind the coaming and the
            ## header and laps it under both, so the band is a hole with glass
            ## at the bottom of it rather than a dark stripe painted on.
            if i == 1:
                out.append(face_glass(base + i, ring(1), house_inside,
                                      "%s, GLASS BAND, recessed %.2f m in the reveal"
                                      % (what, REVEAL)))
                continue
            out.append(plate(base + i, "%s, %s" % (what, names[i]),
                             ring(i), thicks[i], colors[i]))
        made = face_posts(pid, ring(1), house_inside, posts[key])
        out.extend(made)
        pid += len(made)
    out.append(plate(117, "wheelhouse roof — sloped 0.30 m down aft, eaves all round",
                     [(2.46, WT, 17.99), (2.34, WTA, 23.86),
                      (7.66, WTA, 23.86), (7.54, WT, 17.99)], 0.12, ROOFW))

    # funnel: four tapering plates raked aft under a black cap
    fb, ft = 23.70, 24.10
    ab, at_ = 25.10, 25.30
    FTOP = 5.35
    BD = round((bd(fb) + bd(ab)) * 0.5 - 0.04, 4)   # sits on the sloping boat deck
    out.append(plate(118, "funnel, forward face — tapered and raked aft",
                     [(5.90, BD, fb), (4.10, BD, fb), (4.40, FTOP, ft), (5.60, FTOP, ft)], 0.07, OCHRE))
    out.append(plate(119, "funnel, port face",
                     [(4.10, BD, fb), (4.10, BD, ab), (4.40, FTOP, at_), (4.40, FTOP, ft)], 0.07, OCHRE))
    out.append(plate(120, "funnel, starboard face",
                     [(5.90, BD, ab), (5.90, BD, fb), (5.60, FTOP, ft), (5.60, FTOP, at_)], 0.07, OCHRE))
    out.append(plate(121, "funnel, aft face",
                     [(4.10, BD, ab), (5.90, BD, ab), (5.60, FTOP, at_), (4.40, FTOP, at_)], 0.07, OCHRE))
    out.append(plate(122, "funnel cap",
                     [(4.34, FTOP, 24.04), (4.34, FTOP, 25.36),
                      (5.66, FTOP, 25.36), (5.66, FTOP, 24.04)], 0.32, BLACK, solid=False))
    return out


# ── the rig, re-belayed ─────────────────────────────────────────────────────
## Both masts RAKE AFT. Everything carried on one is solved from `mast_at`, not
## restated: a raked mast with a level spreader is the tell that a rig was
## authored by moving numbers rather than by stepping a spar.
MAST_FOOT = (5.0, 0.0, 16.4)
MAST_LEN = 9.0
MAST_RAKE = 0.95 / MAST_LEN            # ~6 degrees aft
AFT_FOOT = (5.0, 4.78, 22.95)
AFT_LEN = 3.0
AFT_RAKE = 0.35 / AFT_LEN


def mast_at(h):
    return (MAST_FOOT[0], round(h, 4), round(MAST_FOOT[2] + h * MAST_RAKE, 4))


def aft_at(h):
    return (AFT_FOOT[0], round(AFT_FOOT[1] + h, 4), round(AFT_FOOT[2] + h * AFT_RAKE, 4))


MASTHEAD = mast_at(8.4)
AFT_MASTHEAD = aft_at(AFT_LEN)


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
    A(spar(200, "mast - tapered, 9.0 m above its foot, raked 6 degrees aft", MAST_FOOT,
           [[0, 0, 0], [0, MAST_LEN, round(MAST_LEN * MAST_RAKE, 4)]], 0.14,
           taper=0.5, sides=8, **STEEL))
    A(spar(201, "mast spreader - carries the floodlights", mast_at(6.48),
           [[-1.7, 0, 0], [1.7, 0, 0]], 0.063, sides=6, **STEEL))
    A(spar(202, "radome", mast_at(7.74), [[0, 0, 0], [0, 0.345, 0]], 0.3, sides=12,
           material="painted", color=[0.94, 0.94, 0.92]))
    A(spar(203, "masthead light - white, above the sidelights", mast_at(9.0),
           [[0, 0, 0], [0, 0.26, 0]], 0.098, sides=8, **WHITE))
    for iid, dx in ((204, -1.02), (205, 1.02)):
        m = mast_at(6.48)
        A(spar(iid, "whip antenna", (round(m[0] + dx, 4), m[1], m[2]),
               [[0, 0, 0], [0, 1.9, 0]], 0.014, sides=4, **DARK))
    for iid, dx in ((206, -1.36), (207, 1.36)):
        m = mast_at(6.34)
        A(spar(iid, "deck floodlight, aimed forward and down",
               (round(m[0] + dx, 4), m[1], m[2]),
               [[0, 0, 0], [0, -0.16, -0.28]], 0.1, sides=6, **WHITE))
    # derrick: heeled to the mast at boat-deck height, raked out over the hatches
    boom_heel = mast_at(2.72)
    boom_head = (3.6, 4.60, 9.6)
    A(spar(208, "derrick boom - raked forward over the working deck", boom_heel,
           [[0, 0, 0], delta(boom_heel, boom_head)], 0.1, taper=0.7, sides=8, **STEEL))
    lift_foot = mast_at(8.3)
    A(wire(209, "topping lift - running rigging under load, barely slack", lift_foot,
           [[0, 0, 0], delta(lift_foot, boom_head)], 0.016, sag=0.06,
           span_steps=6, sides=4, **DARK))
    hook_top = (3.6, 1.10, 9.9)
    A(wire(210, "cargo fall off the boom head", boom_head,
           [[0, 0, 0], delta(boom_head, hook_top)], 0.014, sag=0.0, sides=4, **DARK))
    A(spar(211, "hook block", (3.6, 0.95, 9.9), [[0, 0, 0], [0, 0.42, 0]], 0.09, sides=6, **DARK))
    ## THE GALLOWS, TIED INTO THE DECK.
    ##
    ## A trawl gallows is not a pole. It is a leg standing on a DOUBLER that
    ## spreads its load into the deck plating, with a HEEL fin welded fore and
    ## aft of it and a BRACKET back to the bulwark, because a gallows takes the
    ## whole pull of a warp on a rolling boat and a bare tube in a socket would
    ## fold. Drawn as four red poles they read as scaffolding dropped on the
    ## deck; every piece below is the steelwork that a real one has and that
    ## COMPONENTS.md's bracket/gusset row calls "most of why CG steelwork looks
    ## like cardboard".
    ##
    ## The two on a side are also TIED TOGETHER at the head. That is a real
    ## member — it is what stops a gallows racking fore and aft — and it is the
    ## piece that turns two poles into one frame at a squint.
    for base, z in ((212, 8.6), (216, 14.2)):
        A(spar(base, "trawl gallows, port - leg and outboard head", (0.55, 0.0, z),
               [[0, 0, 0], [0, 3.5, 0], [-0.5, 3.5, 0]], 0.1, sides=8, **RED))
        A(spar(base + 1, "trawl gallows, starboard", (9.35, 0.0, z),
               [[0, 0, 0], [0, 3.5, 0], [0.5, 3.5, 0]], 0.1, sides=8, **RED))
        A(spar(base + 2, "gallows block, port", (0.05, 3.42, z),
               [[0, 0, 0], [0, -0.38, 0]], 0.08, sides=6, **DARK))
        A(spar(base + 3, "gallows block, starboard", (9.85, 3.42, z),
               [[0, 0, 0], [0, -0.38, 0]], 0.08, sides=6, **DARK))
    for iid, x, z in ((160, 0.55, 8.6), (164, 9.35, 8.6),
                      (168, 0.55, 14.2), (172, 9.35, 14.2)):
        side = -1.0 if x < 5.0 else 1.0
        inboard = x - side * 0.42      # the bulwark's inboard face, 0.42 m outboard
        A(plate(iid, "gallows doubler — the plate that spreads the leg's load "
                     "into the deck",
                [(x - 0.55, 0.012, z - 0.55), (x + 0.55, 0.012, z - 0.55),
                 (x + 0.55, 0.012, z + 0.55), (x - 0.55, 0.012, z + 0.55)],
                0.06, GREYST))
        A(plate(iid + 1, "gallows heel — the fore-and-aft fin welded each side "
                         "of the leg",
                [(x, 0.03, z - 0.85), (x, 0.03, z + 0.85),
                 (x, 1.28, z + 0.22), (x, 1.28, z - 0.22)],
                0.06, GREYST))
        A(plate(iid + 2, "gallows bracket — the knee back to the bulwark",
                [(x, 0.52, z - 0.05), (inboard, 0.98, z - 0.05),
                 (inboard, 1.46, z - 0.05), (x, 1.46, z - 0.05)],
                0.05, GREYST))
        A(spar(iid + 3, "gallows heel casting", (x, 0.0, z),
               [[0, 0, 0], [0, 0.62, 0]], 0.185, taper=0.6, sides=8,
               material="painted", color=GREYST))
    for iid, x in ((176, 0.55), (177, 9.35)):
        A(spar(iid, "gallows head tie — the fore-and-aft member that makes two "
                    "legs one frame", (x, 3.42, 8.6),
               [[0, 0, 0], [0, 0, 5.6]], 0.075, sides=6, **RED))
    ## THE ONE PIECE OF THE HEELWORK THAT IS VISIBLE FROM OUTSIDE THE BOAT.
    ## The doubler, the heel fin and the bulwark knee all live below 1.5 m, and
    ## the bulwark at z=8.6 is 1.54 m — so from every canonical camera angle
    ## except the plan they are behind it, and the legs still read as poles.
    ## This is the member that fixes the outside view: a raking strut off the
    ## head, down and away from its pair, landing ON the swept cap. It is also
    ## the brace a real gallows needs most, because the pull it takes is
    ## fore-and-aft.
    for iid, x, z, zc in ((178, 0.55, 8.6, 7.1), (179, 9.35, 8.6, 7.1),
                          (180, 0.55, 14.2, 15.7), (181, 9.35, 14.2, 15.7)):
        side = -1.0 if x < 5.0 else 1.0
        foot = (round(5.0 + side * 4.84, 4), round(sheer(zc) + 0.10, 4), zc)
        A(spar(iid, "gallows strut — the fore-and-aft brace, made fast to the "
                    "bulwark cap", (x, 3.05, z),
               [[0, 0, 0], delta((x, 3.05, z), foot)], 0.07, sides=6, **RED))
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
    A(spar(229, "exhaust pipe, out of the funnel top", (5.0, 5.35, 24.7),
           [[0, 0, 0], [0, 0.62, 0]], 0.12, sides=8, material="painted", color=[0.2, 0.2, 0.22]))
    A(spar(230, "exhaust rain cap", (5.0, 5.97, 24.7), [[0, 0, 0], [0, 0.14, 0]], 0.2, sides=8,
           material="painted", color=[0.12, 0.12, 0.13]))
    # aft signal mast — re-belayed onto the WHEELHOUSE ROOF, which is what it stood on
    A(spar(231, "aft signal mast, stepped on the wheelhouse roof", AFT_FOOT,
           [[0, 0, 0], [0, AFT_LEN, round(AFT_LEN * AFT_RAKE, 4)]], 0.09,
           taper=0.6, sides=8, **STEEL))
    A(spar(232, "aft mast crosstree", aft_at(1.9), [[-1.1, 0, 0], [1.1, 0, 0]], 0.045,
           sides=6, **STEEL))
    A(spar(233, "all-round white light on the aft mast", AFT_MASTHEAD,
           [[0, 0, 0], [0, 0.24, 0]], 0.08, sides=8, **WHITE))
    # sidelights, re-belayed onto the wheelhouse wings
    A(spar(234, "sidelight - port, red", (2.61, 3.50, 18.69), [[0, 0, 0], [0, 0.3, 0]], 0.1,
           sides=8, material="painted", color=[0.86, 0.13, 0.11]))
    A(spar(235, "sidelight - starboard, green", (7.39, 3.50, 18.69), [[0, 0, 0], [0, 0.3, 0]], 0.1,
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
               material="wood", color=[0.40, 0.39, 0.35]))
        start = (0.10, cap_mid(z), z)
        A(wire(iid + 1, "fender lanyard", start,
               [[0, 0, 0], delta(start, (-0.28, 0.2, z))], 0.013, sag=0.02, sides=4,
               material="wood", color=[0.6, 0.53, 0.38]))
    for iid, x, z in ((248, 1.0, 6.4), (249, 9.0, 6.4), (250, 1.0, 26.2), (251, 9.0, 26.2)):
        A(spar(iid, "mooring bitt", (x, 0.0, z), [[0, 0, 0], [0, 0.6, 0]], 0.11, sides=8, **WHITE))
    return items


## THE BREAKWATER, and the honest reason it is four diagonal walls.
##
## A forward-pointing V across the foredeck is a real fitting: it throws a
## boarding sea outboard before it reaches the winch and the hatches, which is
## exactly what an open working deck under a 2.9 m bow bulwark needs, and it is
## the only thing standing on the long empty foredeck.
##
## It is ALSO the four 45-degree walls `scripts/apps/structure_studio.gd`'s own
## self-check reads off this file to prove it bounds a diagonal in WORLD space
## rather than in the wall's own frame. Those used to be the bow stem walls, and
## the sheer band replaced them. Rather than drop that coverage silently or leave
## the studio probe red, the fixture keeps four diagonals — as a fitting the boat
## wants, not as a stub. The coupling is still wrong the other way round: an app
## self-check should not be able to break because a fixture was redesigned, and
## it should build or own its own diagonals.
##
## Geometry: apex (5, 4.4), wings out to (1, 8.4) and (9, 8.4) — a true 45 degree
## run, length 4*sqrt(2), stopping 0.9 m short of the bulwark so the deck drains.
BREAKWATER = [
    {"id": 4, "start": [1.0, 0, 8.4], "axis": "+x-z", "length": 5.65685,
     "height": 1.0, "thickness": 0.18, "color": [0.19, 0.22, 0.26], "openings": []},
    {"id": 5, "start": [9.0, 0, 8.4], "axis": "-x-z", "length": 5.65685,
     "height": 1.0, "thickness": 0.18, "color": [0.19, 0.22, 0.26], "openings": []},
    {"id": 6, "start": [1.0, 1.0, 8.4], "axis": "+x-z", "length": 5.65685,
     "height": 0.09, "thickness": 0.42, "color": [0.91, 0.90, 0.85], "openings": []},
    {"id": 7, "start": [9.0, 1.0, 8.4], "axis": "-x-z", "length": 5.65685,
     "height": 0.09, "thickness": 0.42, "color": [0.91, 0.90, 0.85], "openings": []},
]

HATCHES = [
    {"id": 30, "origin": [2.1, 0.65, 9.1], "size": [1.9, 6.8], "thickness": 0.12,
     "color": [0.30, 0.33, 0.31], "openings": []},
    {"id": 31, "origin": [4.05, 0.65, 9.1], "size": [1.9, 6.8], "thickness": 0.12,
     "color": [0.30, 0.33, 0.31], "openings": []},
    {"id": 32, "origin": [6.0, 0.65, 9.1], "size": [1.9, 6.8], "thickness": 0.12,
     "color": [0.30, 0.33, 0.31], "openings": []},
]

NOTE_COMMON = (
    "REBUILT 2026-08-10 after the room purge took the deckhouse, then given its BOW, its "
    "BELTING and its GALLOWS STEELWORK the same day. Six things carry this hull:\n\n"
    "1. THE BULWARK IS ONE `edges[]` SHEER BAND, not three walls plus three cap-rail decks. "
    "The cap carries the curve, which is where sheer has to live: the loft may not draw it "
    "(deck_y is the floor of the deck plate, the DeckGrid, the walk slab and the buoyancy "
    "lever - see hull_stations.gd). The PLAN line is the hull's own deck edge, measured off "
    "StructureEdge.deck_half_beam_at: half-beam 1.12*z to z=4, 4.48+0.13*(z-4) to z=8, 5.0 "
    "aft of that, at every height above the deck.\n\n"
    "2. THE SHEER IS AUTHORED, AND THAT IS DELIBERATE. `sheer_bulwark_spec` derives it from "
    "the hull - freeboard x fine_entry's bow_keel_rise - and that gives 0.896 m forward, "
    "0.28 m aft, with the low point exactly AMIDSHIPS because sheer_rise_at is symmetric in "
    "|z|. On a 28 m hull that reads as polite. A working boat's sheer is asymmetric: the low "
    "point sits about two thirds aft and the stem lifts several times what the transom does. "
    "This path puts the low point at z=19.5 (70% aft) with 1.85 m of rise forward and 0.52 m "
    "aft. The bulwark is 1.00 m at the low point, which is the fall-barrier dimension the "
    "1.8 m figure sets and is NOT authored down. `sheer_bulwark_spec` has no knob that scales "
    "the derived curve, so an authored path is the only way to say this from data.\n\n"
    "   THE SAMPLING IS SOLVED, NOT PICKED, and `check_sheer_sampling()` in the generator "
    "REFUSES to write a fixture that breaks it. A `to_base` band takes its height at the "
    "segment's HIGHER end, so it over-runs the true curve at the low end by exactly that "
    "segment's rise; keep the rise under the cap's headroom (CAP_H - OVERLAP = 0.080 m) and "
    "the step hides inside the cap, let it past and a slot of daylight opens between the "
    "plating and the cap. Worst segment on this path: 0.0784 m at z=8. Coarsening the flat "
    "part of the run from 0.7 m stations to 1.05 m is where the triangles for the belting "
    "and the bow came from - 16 stations off the open path, 24 off the loop.\n\n"
    "3. THE BOW RAKES AND FLARES, AS FAR AS A PLAN CAN CARRY IT. The hull's STEM - everything "
    "below the deck edge - is lofted by HullStations from fine_entry's bow taper and is near "
    "plumb; NOTHING in a structure plan can rake it, and that is the honest limit here. What "
    "a plan owns is everything above the deck, and on a working boat that is most of what a "
    "raked stem looks like. Forward of z=5.6 the bulwark is therefore RAKED PLATE and not the "
    "swept band, because a `to_base` rect is PLUMB IN WORLD SPACE by construction and can "
    "never lean: three quads a side carrying flare 0.06 m -> 0.50 m and rake 0 -> 1.10 m, so "
    "the cap leads its own foot by more than a metre - 21 degrees over 2.95 m of bulwark - "
    "and a stem face shuts the loop across the head. Each quad wears four skins, plating, "
    "the pale inboard face, the ochre sheer stripe and the bone cap, so neither the paint "
    "boundary nor the trough stops at a seam amidships.\n\n"
    "4. THE HULL SIDE HAS RELIEF. A third `edges[]` run is the RUBBING STRAKE, which "
    "COMPONENTS.md lists as one of the ten parts the sweep primitive absorbs: 115 mm proud x "
    "200 mm tall with a light top chamfer. Its plan line is the shell AT THE STRAKE'S OWN "
    "HEIGHT, measured rather than taken from the deck, because the topsides flare 0.188 m per "
    "metre of depth over the parallel body and 0.668 m/m at z=4 and a band hung on the deck's "
    "half-beam would float up to 120 mm off the plating. It CANNOT follow the sheer - deck_y "
    "is flat, which is the whole reason the cap carries the curve - so it rises as the shell "
    "allows instead, 0.62 m under the deck aft and 0.30 m at the stem. It is LIGHTER than the "
    "topsides, not darker: drawn black, as a real trawler's belting is, it photographed as "
    "nothing at all against 0.11-value navy.\n\n"
    "5. THE GALLOWS ARE TIED INTO THE DECK. Four red poles is what they were. A trawl gallows "
    "takes the whole pull of a warp on a rolling boat, so each leg now stands on a DOUBLER "
    "that spreads its load into the plating, with a heel casting, a fore-and-aft HEEL FIN, a "
    "KNEE back to the bulwark, a fore-and-aft STRUT off the head onto the swept cap, and a "
    "HEAD TIE joining its pair. The strut is the piece that matters from outside the boat: "
    "everything else lives below 1.5 m and the bulwark at z=8.6 is 1.54 m, so from every "
    "canonical camera but the plan the heelwork is behind it.\n\n"
    "6. COLOUR DOES VALUE WORK, FOR FREE. The bucket key is material alone, so every colour "
    "here rides in the vertex stream: dark navy plating that merges into the hull's own "
    "topsides, an ochre sheer stripe standing 24 mm proud as the deliberate paint boundary, a "
    "bone cap rail so the curve itself is the lightest line on the hull, a grey belting "
    "breaking the topsides, a cream deckhouse against a dark grey boat deck, and near-black "
    "glass bands. Squinted, that is five values instead of one.\n\n"
    "THE DECKHOUSE IS RAKED PLATES, NEVER A BOX. A lower tier tapered in plan, tumbled home, "
    "with a front that overhangs 0.55 m forward; a wheelhouse SET BACK on all four sides with "
    "a 0.85 m forward-raked windscreen, a reverse-raked aft bulkhead and a roof sloping 0.30 m "
    "down aft; four tapering funnel plates raked aft under a black cap.\n\n"
    "WINDOWS ARE THE SAME PART ON EVERY TIER, 2026-08-10. They were not: the wheelhouse had a "
    "dark band and the lower tier had punched holes with nothing behind them, which at every "
    "range read as pale rectangles the value of the plating - as holes, not as glass. One rule "
    "now, on both tiers: the run is ONE band, not three separate punches; a dark GLASS pane "
    "sits 0.10 m inboard of the shell plane and laps 0.12 m past the opening all round so the "
    "reveal is real depth and no daylight leaks round the pane; cream MULLIONS stand IN the "
    "reveal, bridging it from the shell face to the glass - a post that only straddled the "
    "shell plane left a gap either side of itself and the whole band broke into fine dark "
    "hatching when a grazing camera looked along it; and each wheelhouse face gets a CORNER "
    "PILLAR at either end, which is what closes the notch two recessed panes leave where they "
    "meet at a corner. The aft casing bulkhead keeps its door and no light at all: that is "
    "where the gear comes aboard.\n\n"
    "DOORS ARE 1.30 x 2.25 m ON THE SIDES AND 1.20 x 2.15 m AFT, and that is a measurement, "
    "not a taste. A doorway in a raked plate is a LEANING SLOT - its jambs are rectangles in "
    "the plate's own (u, v) parameters, and this casing's sides run 7.31 m at the foot and "
    "8.11 m at the top - so what a player can use is the INTERSECTION of the opening over "
    "their own height. tests/plan_interior_test.gd measured the 0.85 x 1.95 m side doors that "
    "were here at a walkable column of 0.000 m and a lintel at 1.78 m, against the 1.89 m a "
    "1.8 m figure standing on the walk deck needs: neither of them could be walked through, at "
    "any lateral position. The aft door, in a plate with almost no lean, worked - so the "
    "vessel had one usable door and read as if it had three.\n\n"
    "THE RIG IS RE-BELAYED. The aft signal mast and the sidelights stand on the wheelhouse "
    "roof and its wings; the exhaust comes out of the funnel top; the derrick heels to the "
    "mast at boat-deck height; the shrouds and the three fender lanyards land on the SWEPT "
    "cap, so their ends move with the curve; the samson post is 1.90 m because the bow "
    "bulwark it stands in is taller than the old one, and the forestay is made fast to its "
    "head. Both masts RAKE AFT and everything carried on one is solved from the rake rather "
    "than restated. A line to nowhere is the one thing a rig may not have.\n\n"
    "THE BREAKWATER is four 45 degree walls, and it is the one piece of this fixture with a "
    "second, uncomfortable reason to exist: scripts/apps/structure_studio.gd's self-check "
    "reads FOUR DIAGONALS off this file to prove it bounds a raked wall in world space. It is "
    "a real fitting - a V across an open working deck throws a boarding sea outboard before it "
    "reaches the winch - so it is here as one, not as a stub, and it was NOT re-raked into "
    "plate for the same reason: tests/plan_collision_physics_test.gd sweeps the surplus of "
    "those four bounding boxes for phantom solids, and new geometry in that volume is exactly "
    "what that sweep is looking for. The coupling is still wrong the other way round and "
    "should be fixed there: an app self-check must not go red because a fixture was "
    "redesigned.\n\n"
    "COST, on RenderingServer's own counters over the four canonical views: DRAW CALLS "
    "UNCHANGED at 8 undressed / 16 with the shadow pass, because three swept runs, sixty "
    "plates and a dozen colours all bucket on MATERIAL alone. Triangles: see "
    "tests/trawler_render_capture.gd's budget, which both fixtures are inside - the coarser "
    "sheer sampling paid for the bow, the belting and the gallows steelwork.\n\n"
    "GENERATED by tools/gen_trawler_fixtures.py, which is where the sheer curve's constants, "
    "the bow's flare and rake laws and the sampling guard live and where they should be "
    "retuned. The JSON is the interface; the generator is the provenance."
)


def build(bow_closed):
    plan = collections.OrderedDict()
    plan["format"] = "structure_plan_v1"
    plan["context"] = "vessel"
    plan["hull_id"] = "hull_28x10"
    plan["_note"] = NOTE_COMMON + ("\n\nBOW CLOSED: this fixture's SWEPT BAND runs the whole "
        "LOOP, stem included, so under the raked bow plate there is a plumb bulwark round the "
        "stem as well. tests/plan_collision_physics_test.gd marches a player capsule out "
        "through both stems of THIS file, and that is why the swept loop is kept here rather "
        "than left to the plate alone." if bow_closed else
        "\n\nBOW OPEN — AND THAT NOW MEANS LESS THAN IT DID, WHICH IS WORTH SAYING PLAINLY. "
        "This fixture's SWEPT BAND still runs from z=5 aft and its pair's runs the whole loop; "
        "that is still the one flag between the two files. But the raked bow plate added on "
        "2026-08-10 stands on BOTH of them, and it closes the stem — so a body can no longer "
        "walk out over the bow of this one either, and the fall-protection difference the two "
        "files used to carry is gone. It was traded knowingly: the alternative, drawn and "
        "photographed, was a stem with a 0.84 m notch in it and two flared plates reading as "
        "fins, which is not a bow. If that distinction is wanted back it belongs in a third "
        "fixture with no bow structure at all, not in a notch in this one.")
    plan["palette"] = {"wall": [0.85, 0.86, 0.88], "deck": [0.33, 0.31, 0.29]}
    plan["hull"] = {
        "_note": "hull_28x10 as FishingTrawlerSmall builds it. Restated so the capture rig can "
                 "hold the derived stations against the hull the game actually spawns.",
        "loa_m": 28.0, "beam_m": 10.0, "depth_m": 5.6, "draft_m": 2.8,
        "displacement_t": 256.0, "form": "fine_entry",
        "bow_taper_fraction": 0.17857142857142858, "station_count": 8,
    }
    plan["walls"] = BREAKWATER
    plan["decks"] = HATCHES
    plan["stairs"] = []
    plan["items"] = deckhouse() + bow_structure(bow_closed) + rig()
    edge = bulwark_edge()
    if not bow_closed:
            ## Open bow: one run down each side, stem left clear. The forward end no
            ## longer needs the 0.85 m RETURN across the deck it used to carry — the
            ## raked bow plate laps it by BOW_LAP and is what the sweep now runs into,
            ## so there is nothing guillotined to hide.
        zs = [z for z in sheer_zs(27.85) if z >= 5.0]
        stb = [[round(5.0 + max(half_beam(z) - INSET, 0.0), 4), round(sheer(z), 4), round(z, 4)]
               for z in zs]
        prt = [[round(5.0 - max(half_beam(z) - INSET, 0.0), 4), round(sheer(z), 4), round(z, 4)]
               for z in zs]
        edge["path"] = stb + prt[::-1]
        edge["closed"] = False
    plan["edges"] = [edge, rubbing_strake(3, 1.0, "starboard"),
                     rubbing_strake(4, -1.0, "port"), BOAT_DECK_RAIL]
    return plan


worst_rise, worst_at = check_sheer_sampling(sheer_zs(27.85))
print("sheer sampling: worst segment rise %.4f m at z=%.2f, cap headroom %.3f m"
      % (worst_rise, worst_at, CAP_HEADROOM))

for closed, name in ((False, "probe_trawler_bulwark"), (True, "probe_trawler_bow_bulwark")):
    p = build(closed)
    path = "resources/data/structures/%s.json" % name
    with open(path, "w") as fh:
        json.dump(p, fh, indent=1)
        fh.write("\n")
    print("%-28s edge points=%d  items=%d" % (name, len(p["edges"][0]["path"]), len(p["items"])))
