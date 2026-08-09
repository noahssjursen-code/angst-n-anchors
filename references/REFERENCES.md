# Reference vessels

**These are evidence, not targets.** Owner direction, 2026-08-09: *"do not tailor these boats,
make parts that people can build custom ships from."*

Nothing here is a ship to replicate. Each photograph is read to answer one question — *what kit
would a player need in order to build this, or anything like it?* A part earns its place by
appearing across unrelated vessel types, and it must be parametric and composable. If a part is
only useful for one boat in this folder, it is the wrong part.

The test of the vocabulary is not "can we reproduce R1". It is "can a player who has never seen
R1 build something equally convincing, and something completely different, from the same kit."

Each entry is read off a photograph the owner supplied, not from memory. Drop new images in this
folder and add an entry.

**The container's egress proxy blocks image hosts** — `curl` gets 403 on CONNECT and WebFetch
returns `EGRESS_BLOCKED`. References must arrive as files, not URLs.

---

## R1 — Fast passenger catamaran ferry
*Aresa 2300 FCAT type · "MOMITAN CUATRO" · reg. 2ª AT-3-2-04 · red/white*

Closest hull: `hull_45x16_cat` (45 × 16 units — reads as a 45 m vessel against the 1.8 m figure).

**Hull and geometry**
- Twin demihulls with **very fine, sharply raked bows** and a pronounced forefoot knuckle —
  nothing like the 45° prismatic bow every catalogue hull currently has.
- **Hard chines and knuckle lines** running the full length. The hull is *faceted*, and the
  facets catch light differently. This is a huge part of why the real thing reads as fast and
  our box does not.
- Bridging deck between the hulls with a raised tunnel arch.

**Superstructure**
- Long low passenger saloon, **continuous dark window band** running ~70% of length.
- Wheelhouse forward and raised, with a **strongly raked windscreen** and wraparound glass.
- Upper deck aft, open, fully railed.

**Fittings**
- Raked **radar mast** on the wheelhouse roof, carrying radome, whip antennas, nav lights.
- **Two exhaust stacks** aft, red with horizontal white bands.
- **Tube guardrails** everywhere along the upper deck — prominent, and the single most
  identifying small detail.
- **Liferaft canisters** (white cylinders) on the upper deck aft.
- Boarding gate in the bulwark; anchor recess at the bow; deck lights; fenders.

---

## R2 — Small blue trawler / cutter
*Northern European inshore fishing boat, cut out on white*

Closest hull: `hull_28x10` (reads as 28 m; the reference is smaller, so this is the honest
comparison for *proportion*, not size).

**Hull and geometry**
- **Very pronounced sheer** — the bow rises dramatically. This is the defining line of the
  whole vessel and it is exactly what we currently cannot draw.
- Strong bow flare; visible **rubbing strake** along the topsides.
- Blue topsides, **cream/yellow bulwark cap band**, white superstructure.

**Superstructure**
- Small wheelhouse set aft of midships, windows on all faces, low.

**Fittings — this vessel is almost entirely fittings**
- **Two masts** — forward mast plus a shorter aft mast.
- **Trawl gallows / A-frames** and **derrick booms** with blocks and tackle.
- **Standing and running rigging** — wires everywhere. A trawler without rigging is a hull with
  a shed on it, which is precisely our current failure.
- **Net drums and net bundles** on the working deck.
- Thin **exhaust pipe** beside the wheelhouse.
- **Tyre fenders** hung over the side (three visible).
- Radar on the mast; deck floodlights on both masts.

---

## R3 — Aquaculture work catamaran
*"NABCAT" · Norwegian fish-farm service vessel · teal/blue/white*

Closest hull: `hull_45x16_cat`.

**Hull and geometry**
- Catamaran with a broad bridging deck and a large clear working deck forward.
- **Swept colour division** — a teal band curving up over a blue underbody with white above.

**Superstructure**
- Wide, aft-set wheelhouse with **panoramic windows** and bridge wings.

**Fittings**
- **Large articulated knuckle-boom crane** on the foredeck — the dominant visual element.
- Mast with radar above the wheelhouse.
- Bulwarks around the working deck; railings on the upper deck.
- Working-deck floodlights.

---

## What the three references have in common

Ranked by how often absence explains "it looks wrong":

| Part | R1 | R2 | R3 |
|---|---|---|---|
| Mast + radar | ● | ●● | ● |
| Tube railings | ●● | ● | ● |
| Bulwark + cap rail | ● | ●● | ●● |
| Crane / derrick / gallows | — | ●● | ●● |
| Exhaust stack | ●● | ● | ● |
| Rigging (wire) | — | ●● | — |
| Fenders | ● | ●● | ● |
| Window band | ●● | ● | ●● |
| Liferafts | ●● | — | ● |

**All three are unbuildable today for the same reason**: `items[]` has no reader, no catalog,
and integer-cell positions. Masts, railings, cranes, stacks and fenders are the entire visible
difference between these vessels and our boxes.

## The finding that was not in the earlier list

**Two of the three get most of their identity from PAINT, not geometry.**

R1 is a red hull with a white superstructure and a swept white flash along the topsides. R3 is a
teal band curving over blue under white. Neither is a flat single colour per surface — both are
*regions* of colour with a curved boundary crossing flat plating.

We currently allow one colour per material per surface, and the surface key is
`"<material>_<rrggbb>"`, so every extra colour costs a draw call. That is the wrong constraint
to have chosen. Once colour moves into vertex data — the work already in flight — a swept
two-tone with a curved boundary costs *nothing*: it is a per-vertex value on plating we already
emit.

So the visual gap is not only "we lack parts". It is:

1. **Fittings** — masts, railings, cranes, stacks (the `items[]` mechanism).
2. **Paint regions** — swept colour boundaries across flat plating (vertex colour).
3. **Faceting and rake** — chines, knuckles, raked windscreens (angled/sloped primitives).
4. **Sheer** — R2's defining line, and we have proved it cannot come from the hull loft.

Items 2 and 4 are both cheap and both were missing from the parts-only framing of the problem.

---

## The kit these three imply

Derived by asking what is *shared*, then generalised until nothing in it names a specific boat.
This is the deliverable — a builder's kit, not three models.

**Primitives** (new geometry the baker must emit)

| Primitive | Parameters | What it becomes in a player's hands |
|---|---|---|
| **Spar** | two endpoints, radius, side count, optional taper | mast, post, boom, derrick, gallows leg, davit, stanchion, exhaust stack, vent, jackstaff, antenna, crane pedestal |
| **Railing run** | polyline, height, post pitch, rail count | guardrail, walkway rail, upper-deck rail, ladder cage |
| **Wire** | two endpoints, sag, radius | standing rigging, running rigging, stays, lifelines |
| **Sloped / raked plate** | quad corners, thickness | raked windscreen, chine facet, knuckle, transom rake, funnel taper |
| **Sheer band** | deck-edge polyline with per-station height | the bulwark cap that carries the sheer curve the loft cannot |

Five primitives. Between them they account for every fitting in all three references, and none
of them names a vessel type.

**Composites** (catalog entries assembled from primitives — data, not code)
A-frame gallows, knuckle-boom crane, derrick with topping lift, davit pair, radar mast with
platform, funnel with cap, liferaft cradle, tyre-fender string, net drum, winch.

A player composing an A-frame from two spars and a wire is doing the same thing the catalog does
— the catalog just saves them the work. That is the difference between a kit and a model set.

**Paint** (no geometry at all)
Region assignment per plate with a curved boundary, carried in vertex colour. This is what makes
R1 red-and-white and R3 teal-and-blue, and it costs nothing once colour leaves the surface key.
