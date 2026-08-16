extends Node

## Photographs a vessel built from a `structure_plan_v1` data object.
##
## This is the instrument the ship-parts work runs on: a plan goes in, a set of
## canonical-angle PNGs and a set of machine-checkable claims come out. No UI,
## no clicking, no display — the loop an agent can run and a human can review.
##
##   tools/capture.sh                       # every fixture
##   tools/capture.sh demo_workboat         # one, by stem
##
## Runs in the SCENE lane, not `--script`. `VesselSpawn` reaches BoatBody, which
## transitively names the WorldGateway autoload, and `--script` registers no
## autoloads — so this must boot as a main scene or it cannot compile.
##
## Views use the project's vessel orientation: bow -Z, stern +Z, port -X,
## starboard +X.

const TestReport := preload("res://tests/support/test_report.gd")
const CaptureSubject := preload("res://tests/support/capture_subject.gd")

## ── THE SUBJECT WAS NEVER HELD STILL BY ITS `freeze`, AND ON THIS RIG THAT DID
##    NOT MATTER — MEASURED 2026-08-16 ──────────────────────────────────────────
##
## `1bec073` established the mechanism for three rigs: `BoatBody`'s
## `automatic_physics_lod` defaults `true`, and one second after a hull enters the
## tree `_update_automatic_physics_quality()` runs `freeze = physics_quality ==
## SLEEP` — i.e. **`freeze = false`** — silently revoking a capture rig's own
## freeze. This file was the last shipped rig that had never disabled it, and
## `STATE.md` opened it as a milestone on the strength of that grep.
##
## **The frames were never compromised, and NOT for the reason the other rigs
## were safe.** `hull_visual_capture` was latent-but-safe on a timer margin —
## 0.93 s against a 1.0 s threshold, one settle short. This rig has no margin at
## all: it holds each hull in the tree for eight settles, and measured with
## `tests/_vrc_still_probe.gd` (a subclass, so it photographs THIS `_capture_plan`
## rather than a copy of it) the LOD timer crosses 1.0 s **between the third and
## fourth grab of the first fixture** once `_physics_process` is allowed to run.
##
## What actually held the hull is the line three below `add_child`:
##
##     boat.process_mode = Node.PROCESS_MODE_DISABLED
##
## `CollisionObject3D.disable_mode` defaults to `DISABLE_MODE_REMOVE`, so a
## disabled `BoatBody` is **taken out of the physics space entirely**. Measured,
## same probe, calling the LOD update by hand on the rig as it stands:
## `freeze=false quality=FULL in_space=false`, and the origin holds
## −5.719999790 in all nine float digits across 139 physics frames. The freeze was
## decorative; the process mode was the whole defence, and nothing in this file
## said so.
##
## **And this rig is the DRIFT case, violently.** With `process_mode` left alone
## so the body stays in its space, the same probe measures the LOD firing on its
## own and the hull rising **1.742 m across its eight grabs at +2.17 m/s** — up,
## not down, because `StripBuoyancyComponent` is live here (this stage is in the
## main world, unlike `hull_visual_capture`'s `own_world_3d` viewport, which
## free-falls 951 mm instead). It is not the 1.15 mm the three fixed rigs drifted:
## this rig deliberately sinks the hull by `deck_y` — 5.72 m on the workboat — to
## bring the deck to y = 0, so the whole hull is submerged and the transient is
## the full ascent to equilibrium. A run that lost the process mode would produce
## frames with the hull climbing out of the plan.
##
## So `CaptureSubject.hold_still` goes in, and it is not a formality: it removes
## the single line of defence's status as the only one. `capture_subject_still_test`
## is the scored unit for what it guarantees; do not inline the recipe.

const OUT_DIR := "res://screenshots/studio"
const SETTLE_FRAMES := 6

## Fixture plans. A capture is only evidence if the same input always produces
## the same framing, so the angles are fixed and the names are stable —
## re-running overwrites rather than accumulating, which is what makes two runs
## diffable.
const FIXTURES: Array[String] = [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_trawler_bow_bulwark.json",
	"res://resources/data/structures/probe_ferry_catamaran.json",
	"res://resources/data/structures/probe_spar_kit.json",
	"res://resources/data/structures/probe_ferry_catamaran_trim.json",
	## The largest hull in the catalog, 150 x 32 m, and the first thing built on
	## it: a geared container feeder. It is here because the kit had never been
	## exercised at five times the trawler's length — a 21 m accommodation block,
	## a stow of 16 m containers and a cell-guide rack are all things that only
	## exist at this size.
	"res://resources/data/structures/probe_container_feeder.json",
	## The sheer pair, and they are meant to be looked at SIDE BY SIDE:
	## probe_sheer_bulwark__profile_port.png against
	## probe_sheer_bulwark_flat__profile_port.png. One boolean apart — the control
	## holds the cap at a constant height and is the two-parallel-bars shape every
	## other fixture in this folder reads as. They arrived here from a throwaway
	## rig of their own, which existed only because `StructureBaker` could not
	## read `edges[]`; it can now, so they are photographed by the one real rig
	## and are subject to every claim it makes about every other vessel.
	"res://resources/data/structures/probe_sheer_bulwark.json",
	"res://resources/data/structures/probe_sheer_bulwark_flat.json",
]

## A long lens rather than a wide one: 35° keeps the perspective flat enough
## that a hull's sheer and proportions read true, which is the whole point of a
## reference comparison. Framing is then solved from the lens, not guessed.
const FOV_DEGREES := 35.0
const FRAME_MARGIN := 1.12

## azimuth (deg, 0 = dead astern looking forward), elevation (deg).
const VIEWS: Array[Dictionary] = [
	# Port is -X, so a port profile needs the camera at -X: azimuth 270, not 90.
	# At 90 this shot was labelled "port" while showing the starboard side — a
	# reference photograph that lies about which side you are looking at is worse
	# than no photograph.
	{"name": "profile_port", "azimuth": 270.0, "elevation": 3.0},
	{"name": "bow_quarter", "azimuth": 145.0, "elevation": 16.0},
	{"name": "stern_quarter", "azimuth": 35.0, "elevation": 16.0},
	{"name": "plan", "azimuth": 90.0, "elevation": 88.0},
]

## Where the 1.8 m figure stands, in PLAN space, per fixture stem.
##
## A fixed spot is not safe across fixtures and this is the proof: (2.5, 7.0) is
## clear open deck on the 28 m hulls, but on the catamaran it lands at plan
## (10.5, 29.5) — inside the main saloon, under deck plate 30. The figure
## rendered perfectly and appeared in NONE of the four ferry frames, which is
## exactly the failure mode CONVENTIONS §3a says a scale reference must not
## have. Both ferry fixtures shipped that way. A capture with no visible figure
## has no absolute scale, so the spot is data now, one entry per fixture.
##
## ⚠ AND "ONE ENTRY PER FIXTURE" WAS NOT TRUE, AND NOTHING SAID SO — 2026-08-16
##
## The dictionary carried two stems. Every OTHER fixture — including the three
## `critic_*` plans photographed into `screenshots/critic/` by the subclass in
## `tests/support/` — fell through to the default, and the default is not a
## per-fixture decision, it is the absence of one. On `critic_ferry` the default
## spot (2.5, 0, 7.0) lands at plan z = 7.0 m inside a saloon that resolves to
## x 1.00..9.00, z 5.50..23.50, under a roof at y = 2.50: the figure rendered
## perfectly and appeared in NONE of the four frames. All four `critic_ferry`
## frames therefore had no absolute scale, which is the exact failure this
## comment block already described and which the rig still could not detect,
## because NOTHING COUNTED THE FIGURE'S PIXELS. The note was true and the check
## was missing — REALITY §4b, a whole property with no check pointed at it.
##
## `_shoot` now photographs every view TWICE, once with the figure hidden, and
## fails the frame if hiding it changes nothing. `_fittings_shot` and
## `_hold_shot` have counted figure pixels for months; this is that, in the rig
## every other rig was copied from.
const FIGURE_SPOT := {
	"probe_ferry_catamaran": Vector3(12.0, 0.0, 39.0),
	"probe_ferry_catamaran_trim": Vector3(12.0, 0.0, 39.0),
	## The six that had no entry and fell through to the default. They are written
	## down at the value they were already being shot at, which is NOT a no-op:
	## the default is the absence of a decision and could move under any of them,
	## and each of these was then MEASURED at that value rather than assumed.
	## Figure pixels over profile / bow_quarter / stern_quarter / plan, 2026-08-16:
	##
	##   demo_workboat            (unlisted)  79 /  ? /   0 / 79   ← see below
	##   probe_trawler_bulwark        63 / 139 / 218 / 228
	##   probe_trawler_bow_bulwark    63 / 132 / 218 / 228
	##   probe_spar_kit              421 / 332 / 219 / 412
	##   probe_sheer_bulwark         151 / 714 / 426 / 557
	##   probe_sheer_bulwark_flat    272 / 895 / 424 / 561
	##
	## `demo_workboat__stern_quarter` is 0 px and has been since this rig existed:
	## the deckhouse stands between an after quarter and the working deck the
	## figure is on. It is the same geometry the ferry has, at a smaller scale.
	##
	## ⚠ AND "MEASURED AT THAT VALUE" MEANT MEASURED FOR VISIBILITY ONLY, WHICH
	## IS NOT THE SAME PROPERTY — 2026-08-16.
	##
	## Two of the six were standing INSIDE a wall at the value written above.
	## `probe_trawler_bulwark` and `probe_trawler_bow_bulwark` both carry a
	## V-shaped breakwater across the fore end of the working deck — `walls[]` 1
	## and 2, from (1, 8.4) and (9, 8.4) on the diagonal axes, 0.18 m thick, 1.0 m
	## high, meeting on the centreline at z = 4.4. The spot (2.5, 0, 7.0) sits
	## 0.071 m off that plating's centre line, which has a 0.09 m half-thickness:
	## inside it, by geometry that can be done on paper.
	##
	## Both measured 63 / 139 / 218 / 228 px and passed every check, because 63 px
	## is what the top 0.8 m of a figure looks like over a 1.0 m breakwater cap,
	## and a pixel counter cannot tell that from a figure standing beside it. No
	## frame closes that gap; `_check_figure_stands` does, and it is why this table
	## can now be wrong in a way that reddens rather than in a way that ships.
	##
	## MOVED 2026-08-16 to the spot their piece-built sister already stands on.
	## Same hull, same breakwater, same fish hatch, same bulwark: three fixtures
	## that exist to be laid beside each other, and a scale figure standing
	## somewhere different on each is a difference that is not a difference. Shot
	## at four candidates each, profile / bow_quarter / stern_quarter / plan:
	##
	##     (2.50, 0.00,  7.0)  AUTHORED, in the breakwater   63 / 139 / 218 / 228
	##     (5.00, 0.00,  7.0)  centreline working deck      122 / 125 /  72 / 201
	##     (1.35, 0.00, 12.5)  port side deck               178 / 285 /   0 / 297
	##     (8.65, 0.00, 12.5)  starboard side deck          333 / 174 / 152 / 298
	##     (5.00, 0.65, 12.5)  the fish hatch cover — KEPT  594 / 420 / 254 / 394
	##
	## `(5.0, 0, 7.0)` is not a legal alternative either — it is standing in the
	## SAMSON POST (`items[]` id 149, a 0.30 m tube 1.90 m tall at z = 6.6) with the
	## TRAWL WINCH DRUM (id 135, 0.84 m across and 3.0 m wide at y 0.62) through its
	## shins. It measured 122 px in profile and would have passed the pixel check
	## exactly as the breakwater spot did, which is the same defect a second time on
	## the same vessel and the reason the geometry is now asked as well.
	"demo_workboat": Vector3(2.5, 0.0, 7.0),
	"probe_trawler_bulwark": Vector3(5.0, 0.65, 12.5),
	"probe_trawler_bow_bulwark": Vector3(5.0, 0.65, 12.5),
	"probe_spar_kit": Vector3(2.5, 0.0, 7.0),
	"probe_sheer_bulwark": Vector3(2.5, 0.0, 7.0),
	"probe_sheer_bulwark_flat": Vector3(2.5, 0.0, 7.0),
	## The three critic fixtures, read off their own resolved geometry
	## (`tests/_wave_trim_audit.gd`) rather than guessed. All three are 28 x 10 m
	## hulls, so the deck rectangle is x 0..10, z 0..28 and z = 0 is the BOW.
	##
	## critic_ferry: the saloon fills x 1.00..9.00 over z 5.50..23.50 and the
	## default spot is inside it. The clear deck is the foredeck forward of the
	## saloon front (z < 5.50) and the quarterdeck aft of it (z > 23.50).
	##
	## AND THE SPOT HAD TO BE MEASURED VIEW BY VIEW, WHICH IS ITSELF THE FINDING.
	## Both quarters shoot from STARBOARD (azimuth 145 and 35 both resolve to +X)
	## and the profile from port, and the saloon is 2.5 m tall over 8.0 m of a
	## 10.0 m beam and 18.0 m of a 28.0 m deck — so it stands between an aft
	## quarter and anything forward of it. Measured, 2026-08-16, figure pixels over
	## profile / bow_quarter / stern_quarter / plan:
	##
	##     (5.0, 0, 25.5)  quarterdeck   895 /   0 / 732 / 538
	##     (5.0, 0,  3.0)  foredeck      895 / 941 /   0 / 538
	##     (5.0, 0,  1.6)  hard forward  892 / 829 /  21 / 341
	##
	## Every point of open deck on this vessel is on one of those two regions, so
	## there is no spot the two quarters share. 1.6 m — jammed against the stem —
	## is the first place the figure's HEAD clears the saloon roof on the stern
	## quarter's sight line, and it buys 21 px, 2% of what the same figure is worth
	## in profile. The natural foredeck spot is kept instead, and the stern quarter
	## prints its zero. That zero is the shed this wave was sent to look at, said
	## as a measurement rather than as an adjective: from an after quarter, this
	## ferry hides a person standing on its own deck completely.
	"critic_ferry": Vector3(5.0, 0.0, 3.0),
	## critic_yacht: the coachroof runs z 7.50..17.50 and the port/stbd bulwarks
	## z 6.00..22.00. z = 3.0 is forward of both, on the open foredeck.
	"critic_yacht": Vector3(5.0, 0.0, 3.0),
	## critic_barge: the hopper occupies the middle of the deck and the casing
	## z 19.50..26.50. The foredeck forward of the coamings is clear.
	"critic_barge": Vector3(5.0, 0.0, 2.0),
	## The default spot (2.5, 0, 7.0) is not on this ship at all: at z = 7 the
	## 150 m hull's deck edge runs x 8.34 .. 23.66, so the figure would stand in
	## open air off the port bow. It goes on the FORECASTLE, sky behind it and
	## the whole 150 m of ship running away aft — which is the one place a 1.8 m
	## figure still resolves against a vessel this size.
	##
	## ⚠ AND THIS IS THE CASE `_check_figure_on_the_ship` WAS BUILT FOR — the
	## sentence above was written from a look at the deck grid and nothing held
	## the fixture to it. Measured through the built hull's own stations,
	## 2026-08-16: the default puts the figure at ship-local x −13.500 against a
	## half-breadth of 7.000 m at that station — **6.500 m of open water** — and
	## it is the only spot in the whole fleet the check refuses. Note the two
	## numbers do not agree: the deck grid's 8.34 makes it 5.84 m out and the loft
	## makes it 6.50 m, because the grid's chamfer and the loft's taper are
	## separate producers (see `FIGURE_OFF_SHIP_MAX`). Either way it is water.
	##
	## ⚠ AND IT WAS AT (11.0, 3.46, 10.0), WHICH IS THE THIRD INSTANCE OF THE SAME
	## DEFECT — FOUND BY `_check_figure_stands`, NOT BY LOOKING, 2026-08-16.
	##
	## Two things wrong with that value, and neither is visible in any frame:
	##
	##   • FLOATING by 0.064 m. The fo'c'sle deck is SHEERED — it is `items[]`
	##     plates, not a `decks[]` slab, and its collider top falls from 3.444 at
	##     z = 9 to 3.396 at z = 10 to 3.325 at z = 14. 3.46 is not the height of
	##     the deck anywhere under the figure.
	##   • BLOCKED by `items[]` 682, the WARPING DRUM — a 0.92 m tube standing
	##     1.55 m at (11.4, 10.6). True clearance to the drum's own cylinder is
	##     0.04 m; the collider is the tube's box, so the check reads it as
	##     contact. Either way the figure is standing with its shoulder against a
	##     windlass drum, which is not where a person stands.
	##
	## Moved 1.5 m outboard and sat on the deck's measured top: CLEAR, nearest
	## structure 1.23 m, gap -0.000 m.
	"probe_container_feeder": Vector3(9.5, 3.396, 10.0),
	## `probe_plate_deckhouse` is photographed by `structure_plate_capture`, which
	## is a subclass of this file and whose fixture is destined to become another
	## entry in FIXTURES once the plate primitive lands here. Its spot lives in
	## this table for that reason: one table, and no third copy to drift.
	##
	## Derived from the resolved geometry, not guessed. The deckhouse's lower tier
	## is a raked front whose top overhangs 0.45 m FORWARD of its foot, so the
	## structure reaches z = 14.55 even though it stands on z = 15.00; the port
	## and starboard bulwarks are `walls[]` at x 0.30 and 9.70, 0.95 m high, and
	## the bulwark knuckle plates flare to x 0.05 and 9.95. Mid-foredeck on the
	## centreline is 4.52 m from the nearest structure of any height, with open
	## sky over it and nothing overhanging.
	##
	## Measured against the default it had been falling through to, profile /
	## bow_quarter / stern_quarter / plan:
	##
	##     (2.5, 0, 7.0)   the default    149 / 703 / 240 / 510
	##     (5.0, 0, 10.0)  chosen         128 / 667 / 404 / 514
	##
	## The default is not blocked on this fixture — it is simply nobody's
	## decision, and it sits 2.02 m from the port bulwark where the centreline
	## spot sits 4.52 m from everything. The trade is 21 px of profile for 164 px
	## of stern quarter and a figure that is not tucked against a rail.
	"probe_plate_deckhouse": Vector3(5.0, 0.0, 10.0),
}
const FIGURE_SPOT_DEFAULT := Vector3(2.5, 0.0, 7.0)

## The one that must be VISIBLE, not merely present. Held so `_shoot` can take a
## reference frame without it.
##
## ONE FLOOR FOR BOTH RIGS. `piece_kit_capture` measured the same property a
## second time with its own sampler (every other pixel, 0.03 delta) and its own
## floor of 12, so the fleet was judged by two numbers that could not be
## compared: 12-of-230k samples against 1-of-921k pixels. The measurement is the
## parent's now — stride 1, `FIGURE_PIXEL_DELTA` — and there is one floor.
##
## ⚠ AND THE FLOOR IS 1, BECAUSE A PIXEL FLOOR CANNOT BE A FLEET CONSTANT.
##
## It was raised to 12 on this argument: across every 28 m fixture and every
## candidate spot measured on 2026-08-16, an asserted view either counted 0 (the
## figure is inside something, or off the ship) or counted 63 and up, so the band
## between was empty and anything in it would be a finding.
##
## Then it was run over the fleet, and `probe_container_feeder__plan` went RED at
## 2 px — REALITY §4d, a claim verified on one class of hull and extrapolated to
## a hull five times longer. `_shoot` frames every view to the VESSEL, so the
## metres-per-pixel scale is a property of the subject: on `hull_28x10` the frame
## is about 0.031 m/px and a 1.8 m figure in plan is a 30-px disc, while on
## `hull_150x32` it is about 0.13 m/px and the same figure is under ten. Diffing
## the old spot against the new one on that fixture's plan frame moves FIVE
## pixels in total, so its plan view has never carried more than about three, at
## any spot anyone has authored.
##
## Raising the floor would therefore have failed the 150 m ship for being 150 m
## long, and the fix would have been to move the figure until the number went up
## — which is the metric choosing the subject all over again, and is what this
## whole change is about. The floor states the property honestly instead: the
## failure mode this check exists for is ZERO, and every instance it has ever
## caught was zero in all four views. THAT `probe_container_feeder__plan` CARRIES
## A TWO-PIXEL SCALE FIGURE IS A REAL DEFECT — it satisfies "is there a scale
## reference in this picture" and no person can use it — but it is a defect in
## how a 150 m vessel is framed, not in where its figure stands, and it wants a
## fourth view or a crop rather than a threshold.
const MIN_FIGURE_PIXELS := 1

## Any channel differing by more than this counts as changed — one step above the
## renderer's own dither. `_check_render_noise` measures what that dither actually
## is rather than assuming it.
const FIGURE_PIXEL_DELTA := 0.02

## ── THE FIGURE IS STANDING ON THE DECK, NOT IN IT ───────────────────────────
##
## Everything above measures a FRAME, and a frame cannot answer this. The pixel
## check asks "is there a scale reference in this picture"; it does not ask "is
## the scale reference standing on the deck", and the difference has shipped three
## times in this repo — a figure 0.071 m inside a 0.18 m breakwater on two
## fixtures, and a figure floating 0.064 m over a sheered fo'c'sle with its
## shoulder in a warping drum on a third. All three measured well over the floor
## in every view, because the top of a figure over a bulwark cap looks exactly
## like a whole figure beside one to a pixel counter.
##
## So the geometry is asked instead. `StructureBaker.collect_colliders` is the
## same call `_check_fall_protection` already makes on this plan, and
## `entity_colliders` `resolved()`s it first — so a piece placement is measured as
## the plates it becomes and not as the node it was authored as. Containment is
## `_guarded`'s test, each box in ITS OWN yawed frame: the trawlers' 45-degree
## breakwater has axis-aligned bounds 4.12 m square, and a check that used those
## bounds would call the whole forward working deck blocked.
##
## Two claims, because there are two ways a spot goes wrong:
##
##   • EMBEDDED — the body intersects a collider. Sampled up the capsule's axis
##     and at four points on its radius, because a figure whose ankle is in a
##     coaming and a figure whose chest is in a bulkhead are both defects.
##   • FLOATING — whatever is under the feet is more than `FIGURE_FLOAT_MAX`
##     below them. `StructureBaker._plate_span` reads a deck's `origin.y` as the
##     plate's TOP and hangs the thickness BELOW it, so a spot computed as
##     `origin.y + thickness` floats by exactly the thickness — 0.12 m on the
##     trawler's fish hatch — and a bulwark hides the feet from every asserted
##     view, so no frame would ever show it. This is the only thing that can.
##
## The tolerance is 0.05 m and it is a RESOLUTION argument, not a taste one: at
## the tightest framing this rig uses, a 28 m vessel spans about 900 px, so one
## pixel is 0.031 m and 0.05 m is under two. `probe_piece_house` stands 0.035 m
## over a sloped roof tile — recorded, looked at, one pixel — and passes; the
## fo'c'sle's 0.064 m does not.
##
## ── AND IT DID NOT ANSWER WHETHER THE FIGURE IS ON THE SHIP AT ALL — CLOSED
##    BELOW, 2026-08-16 ─────────────────────────────────────────────────────────
##
## THE FIGURE MAY STILL BE OFF THE SHIP, is how this section read, and it was
## right: nothing under the feet is read as "the hull deck", because y = 0 IS the
## hull deck in this rig's stage space and most fixtures' figures stand straight
## on it with no plan entity underneath. A spot in open water at y = 0 passes both
## claims above, and the pixel check likes it MORE — a figure against open sky is
## the most visible thing this rig can photograph. `_check_figure_on_the_ship` is
## the answer and `FIGURE_OFF_SHIP_MAX` is its bound; both are argued below.
##
## The colliders are also conservative in two known ways, and both make this
## STRICTER than the geometry: a round tube's collider is its box (the container
## feeder's warping drum reads as contact at 0.04 m of true clearance), and a
## sloped run is stepped into boxes that over-cover by about half a step. A
## refusal within a few centimetres of a fitting is therefore a refusal to stand
## against that fitting, which is the right answer for a scale figure anyway.
const FIGURE_FLOAT_MAX := 0.05
## The capsule's own radius. The body is sampled here rather than at the 0.30 m
## the deck-sweep probes use: a probe looking for somewhere to stand wants a
## margin, a check judging where the figure IS must not invent one.
const FIGURE_BODY_RADIUS := 0.22
const FIGURE_BODY_LO := 0.10
const FIGURE_BODY_HI := 1.70
const FIGURE_BODY_STEP := 0.20

## ── THE FIGURE IS ON THE SHIP, NOT IN THE WATER BESIDE IT ───────────────────
##
## The two checks above are both satisfied by a spot in open water. `y = 0` is
## the deck plane in this rig's stage space, so "there is nothing under the feet"
## and "the feet are on the deck" are the same reading, and a figure that is
## simply beside the hull has clear air around it and open sky behind it — it
## passes the embedded check by definition and scores its BEST pixel count in
## every view. Three separate mechanisms all say yes to the one case none of them
## can see.
##
## ── WHERE THE HALF-BREADTH COMES FROM, AND WHY NOT FROM THE DECK RECTANGLE ──
##
## The rig positions the figure at `offset + spot`, and `offset` is
## `(-grid.half_beam, 0, -grid.half_loa)` off `HullRegistry.make_grid`. Testing
## that spot against a rectangle built from the same `grid.half_beam` would be one
## derivation checking itself — it can only ever say "the number I placed you with
## is the number I placed you with" — and it is wrong on its face anyway, because
## **the bow tapers**. Measured on the three hulls this fleet uses, deck-level
## half-breadth against the grid's constant half_beam:
##
##     critic_barge   spot 2.0 m from the stem   hull 2.000 m   grid 5.000 m
##     critic_ferry   spot 3.0 m from the stem   hull 3.000 m   grid 5.000 m
##     feeder         spot 10.0 m from the stem  hull 10.000 m  grid 16.000 m
##
## A rectangle would call a point 4.9 m off the centreline at `critic_barge`'s
## station "on the deck" when the hull there is 2.0 m wide — nearly three metres
## of open water, at the one place on a vessel where the outline moves fastest.
##
## So the outline comes from the HULL, and specifically from the station table the
## BUILT vessel carries — `boat.hull_stations` off the `VesselSpawn` path this
## rig already stands up — rather than from `plan.hull_stations()`. Both were
## available and they are not the same artefact: the plan's is a RE-DERIVATION
## from catalog numbers for the `--script` lane, and `_check_hull_restatement`
## twenty lines up exists precisely to hold it against the built one. Asserting
## against the re-derivation would put the same numbers on both sides of two
## different checks; asserting against the built hull asks the loft.
##
## The value is the widest half-breadth over the section's levels, interpolated
## between the two bracketing stations exactly as the shell's quad strip
## interpolates between them — so it is the hull's own plan silhouette and not a
## sample of one height of it.
##
## **The catamaran is the one place that table is not the drawn loft, and it is
## still the right table.** `PassengerCatamaran` assigns `hull_stations =
## profile.make_stations()` — the full-beam AGGREGATE — and lofts the visible
## shell twice from a separate demihull table at ±hull_offset. The demihull table
## would call the entire bridge deck open water, and the bridge deck is where
## people stand. The aggregate tapers at the ends where the bridge deck (built by
## `make_grid` with a 0.0 bow taper) is rectangular, so on that vessel this check
## is STRICTER than the deck near the stem. Both ferry figures stand at z_ship
## +16.5 m, 4.16 m inside the bound; if a future spot goes forward on a catamaran
## this is the first thing to re-read.
##
## ── HOW STRICT, AGAINST THE DECK A BUILDER IS ACTUALLY OFFERED ──────────────
##
## Two producers describe one outline — `DeckGrid.cell_shape` (what a player may
## build on) and the station table (what this check reads) — so the honest
## question is whether this refuses a cell the grid offers. Swept over every cell
## row of every hull in the fleet by `tests/_figure_offship_survey.gd`, worst
## overhang of the grid past the loft, at the outer cell EDGE and at the cell
## CENTRE the figure would actually stand on:
##
##     hull_28x10      bow_taper_cells 10   edge +0.250 m   centre −0.000 m
##     hull_150x32     bow_taper_cells 32   edge +0.250 m   centre +0.000 m
##     hull_45x16_cat  bow_taper_cells  0   edge +6.889 m   centre +6.639 m
##
## On the two monohulls the check refuses **nothing** a builder can stand on: the
## grid's square cell overhangs the loft's chamfer by half a cell at the bow
## shoulder, and the centre of that cell lands on the loft to within a rounding
## error. The 0.05 m tolerance is margin on top of an exact fit, which is the
## strongest thing that can be said for a bound.
##
## The catamaran is the exception and the number is large: `make_grid` and
## `HullPhysicsProfile.make_stations` disagree about that vessel's plan outline by
## **6.639 m at the stem**, one saying the bridge deck is rectangular and the
## other tapering it. Two producers of one outline that disagree by nearly seven
## metres is REALITY §4a, and it is not this wave's to settle — recorded here with
## the measurement so the next reader does not have to find it twice.
##
## ── THE BOUND, AND WHAT IT EXCLUDES ─────────────────────────────────────────
##
## 0.05 m, outboard of the hull's own widest plating at that station, and it is
## the same RESOLUTION argument that sets `FIGURE_FLOAT_MAX`: at the tightest
## framing this rig uses a 28 m vessel spans about 900 px, so one pixel is
## 0.031 m and 0.05 m is under two. A figure less than two pixels outboard of the
## ship's plating cannot be told from one standing on it in any frame this rig
## shoots, so failing it would be failing something no view can resolve. (On the
## 150 m ship one pixel is about 0.13 m, so there the bound is well under a single
## pixel — this is strictest, in pixels, on the smallest vessel.)
##
## **"Widest plating", not "deck edge", is the geometry half of the bound and it
## is worth more than the tolerance is.** `base_widths` in
## `HullStations._assign_form_sections` gives the two rubbing-strake levels
## `shoulder_width`, which stands PROUD of the deck edge: measured through the
## built hulls, 5.150 m against a 5.000 m deck edge on `hull_28x10` and 8.160
## against 8.000 on `hull_45x16_cat` — **0.150 m and 0.160 m of hull outboard of
## the sheer line**, and 0.000 on `hull_150x32`, which has none. A figure 0.1 m
## outboard of the sheer line on a trawler is standing over the strake, on the
## ship's own plating, and a deck-edge bound would have called it open water.
## Taking the widest level rather than a fixed pad also means this term is
## re-measured per hull instead of being a constant somebody has to maintain.
##
## WHAT THE BOUND EXCLUDES, said plainly: a figure standing on anything that
## cantilevers more than 0.05 m outboard of the hull's widest plating — a bridge
## wing, a boarding platform, a gangway, an accommodation ladder. No fixture in
## this fleet has one, and every authored spot clears the bound by at least
## 2.000 m (`critic_barge`, on the centreline 2.0 m from the stem, is the
## tightest). If such a structure is ever built, the answer is to ask the PLAN for
## it — the `edges[]` / `items[]` colliders are already collected two functions up
## — and not to widen this number, because a wider number buys back the open
## water this check exists to refuse.
##
## WHAT IT DOES NOT ANSWER, so nobody reads it as more than it is:
##
##   • it says the figure is over the HULL, not over walkable deck. A spot inside
##     the hull outline but over an open hold or a moon pool passes here; that is
##     the floating check's question and it is asked separately.
##   • a plan with no hull (`context != "vessel"`, or a hull that will not
##     instantiate) is SKIPPED with a printed line rather than passed silently.
##     Every fixture the five rigs photograph carries a hull today, so the skip
##     path is currently dead — which is exactly why it prints.
##
## ── MUTATION-VERIFIED, THREE WAYS, 2026-08-16 ───────────────────────────────
##
##   A. `probe_container_feeder` moved to the parent default (2.5, 0, 7.0) —
##      the case this was built for. **35 checks, 1 FAILED**, against 35 / 0 on
##      the authored spot: *x=−13.500, half-breadth 7.000, +6.500 m outboard*.
##      Both older figure checks stayed GREEN in the same run — "clear of the
##      plan's own geometry" and "stands on something (gap +0.000)" — which is
##      this section's whole argument, measured rather than asserted.
##   B. `demo_workboat` moved to (5.0, 0, −3.0), three metres ahead of the stem
##      on the centreline. **36 checks, 1 FAILED**, and the failure is entirely
##      the LONGITUDINAL term: *+0.000 m outboard, +3.000 m past the ends*. A
##      transverse-only check would have passed a figure standing in open water
##      ahead of the bow, because the loft's forward section has no width.
##   C. `_hull_half_breadth_at` replaced by `beam_m * 0.5` — the deck rectangle
##      this section refuses — with mutation A's spot still in place. **35
##      checks, 0 FAILED: it goes GREEN on the defect**, reading a half-breadth
##      of 16.000 where the hull is 7.000. That is the rectangle being blind by
##      construction (REALITY §8), and it is why the outline is the loft's.
const FIGURE_OFF_SHIP_MAX := 0.05

## ── WHICH VIEWS THE FIGURE IS REQUIRED IN, AND WHY NOT ALL FOUR ─────────────
##
## Every view MEASURES the figure and prints the count. Only these two are held
## to it, and the split is not a convenience:
##
##   • `profile_port` and `plan` see the whole deck BY CONSTRUCTION. One looks
##     along the port side, the other straight down. The only way to hide a
##     figure from either is to put it inside something — under a roof, in a
##     wheelhouse — which is exactly the defect CONVENTIONS §3a records twice and
##     exactly the defect this check exists to catch. Both historical instances
##     (the wheelhouse spot, and the ferry catamaran's saloon) were invisible in
##     all four views, these two included.
##
##   • `bow_quarter` and `stern_quarter` both shoot from starboard at 16°
##     elevation, so a deckhouse standing between the camera and the figure
##     eclipses it. That is a fact about the VESSEL, not about the placement, and
##     it has no legal fix: measured on `critic_ferry`, whose saloon covers 8.0 m
##     of a 10.0 m beam and 18.0 m of a 28.0 m deck, a figure on the foredeck is
##     0 px from the stern quarter and one on the quarterdeck is 0 px from the
##     bow quarter, and every point of open deck on that vessel is in one of
##     those two regions. Failing the frame would be failing the rig for the
##     ship's proportions, which is REALITY §2 from the other direction.
##
## THE FIRST RUN OF THIS CHECK FOUND TWO SHIPPED FRAMES WITH NO FIGURE AT ALL —
## `demo_workboat__stern_quarter` and `probe_container_feeder__stern_quarter`,
## both 0 px — and six of the nine shipped fixtures with no authored spot. The
## quarters are printed rather than asserted; those two zeroes are real and are
## in every log line this rig writes.
##
## ── THE ARGUMENT ABOVE WAS ATTACKED ON 2026-08-16, AND IT HELD ──────────────
##
## `piece_kit_capture` asserted all FOUR views for a while, and that rule had a
## consequence: it was the reason `probe_piece_trawler`'s figure went onto the
## fish hatch rather than the port side deck, because the port side deck measures
## `stern_quarter = 0`. A check that changes the subject to satisfy itself is
## REALITY §2, so before making the two rigs agree the two-view claim was put to
## the test: FIND A SPOT HIDDEN FROM BOTH `profile_port` AND `plan` THAT A PERSON
## CAN STILL SEE. If one exists, "hidden from both means inside something" is
## false and the strict rule is the right one.
##
## `tests/_figure_roof_sweep.gd` searched for it mechanically rather than by
## guessing: sweep a fixture's resolved colliders for standing surfaces, keep the
## points that are clear of geometry and ROOFED (which is the only way to hide
## from an 88-degree plan view), then cast exact slab-intersection sight lines at
## knee, chest and head height along all four camera directions. Swept over
## `demo_workboat`, both trawler fixtures, both catamarans and `probe_spar_kit`;
## it offered 25 candidates on `demo_workboat` and 227 on the catamaran, and six
## of them were SHOT — profile / bow_quarter / stern_quarter / plan:
##
##     demo_workboat  (2.25, 0.0, 12.25)    0 / 0 /  96 / 0
##     demo_workboat  (3.25, 0.0, 13.25)    0 / 0 / 148 / 0
##     demo_workboat  (6.25, 0.0, 10.75)    0 / 0 /  46 / 0
##     demo_workboat  (7.25, 0.0, 12.25)    0 / 0 / 131 / 0
##     catamaran      (4.25, 3.0, 26.75)    0 / 0 /  33 / 0
##     catamaran      (2.75, 0.0, 31.75)    0 / 0 /  23 / 0
##
## Every one hidden from both asserted views and counted in the stern quarter —
## and every one of them a crop away from being nothing. `demo_workboat`'s
## `decks[]` 5 is the DECKHOUSE ROOF and not a canopy: the figure is standing in
## the saloon and the stern quarter is seeing a slice of an orange capsule
## THROUGH THE OPEN DOORWAY, 148 samples of it. The catamaran's promenade spots
## are 7 x 6 and 6 x 5 px of scalp through a door of their own. THE SWEEP FINDS
## DOORS, because a doorway is a hole in the collider set and a sight line goes
## through it; a person looking at the frame sees no scale reference at all.
##
## So the attack failed, twice, on two unrelated vessels, and it failed usefully.
## Hidden from `profile_port` AND `plan` still means inside something — and the
## obvious relaxation, "visible in at least ONE view", would have PASSED a figure
## standing inside a deckhouse at 148 px. NOT TESTED: `probe_container_feeder`
## and the three `critic_*` plans, whose sweeps did not finish (the feeder is
## 3084 boxes over a 32 x 150 m deck). The subclass now inherits this list
## instead of restating a stricter one.
const FIGURE_REQUIRED_VIEWS := ["profile_port", "plan"]

var _t: RefCounted
var _camera: Camera3D
var _stage: Node3D
var _figure: Node3D

## Where the figure ACTUALLY stands, in plan metres — authored or defaulted. Held
## so `_check_figure_stands` judges the position the figure is at rather than the
## table it was supposed to come from. That distinction is not pedantry: the
## "authored, not defaulted" check spent a commit reading a table that could not
## contain the answer while the figure stood somewhere else entirely.
var _figure_at := Vector3.ZERO

## The same placement in SHIP-LOCAL metres — `offset + _figure_at`, which is where
## the figure node actually sits, because the hull stands at x = z = 0 on this
## stage. Read from the position rather than recomputed from the table, for the
## reason `_figure_at` exists at all.
var _figure_ship_xz := Vector2.ZERO

## The station table of the hull this rig BUILT, or null when the plan has no
## hull. The authority for the vessel's plan outline — see `FIGURE_OFF_SHIP_MAX`.
var _hull_stations: HullStations = null

## Renderer counters for the fixture currently on the stage. A MeshInstance3D is
## NOT a draw call — these come off RenderingServer's own per-frame counters,
## sampled after frame_post_draw so the frame they describe is the frame that was
## just photographed. Max over the four canonical views: culling makes the number
## view-dependent, and the worst view is the one a budget has to survive.
var _draw_calls := 0
var _primitives := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("vessel_render_capture")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_hide_autoload_ui()

	var wanted := _requested_stems()
	var ran := 0
	for fixture in FIXTURES:
		var stem := fixture.get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(stem):
			continue
		await _capture_plan(fixture, stem)
		ran += 1

	if ran == 0:
		_t.fail("no fixture matched %s" % [wanted])
	_t.finish(get_tree())


## The scene lane boots the real autoloads, and several of them (GameMenu,
## DebugHud, LoadingGate) draw a HUD over everything. That HUD landed in the
## first captures — a currency chip floating over the vessel. A reference
## comparison must contain the vessel and nothing else.
func _hide_autoload_ui() -> void:
	for child in get_tree().root.get_children():
		if child == self:
			continue
		_hide_canvas_items(child)


func _hide_canvas_items(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = false
		return
	for child in node.get_children():
		_hide_canvas_items(child)


## `-- <stem> <stem>` selects a subset; no args means everything.
func _requested_stems() -> PackedStringArray:
	var stems := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if not text.begins_with("--"):
			stems.append(text)
	return stems


func _capture_plan(path: String, stem: String) -> void:
	print("[capture] %s" % stem)

	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		_t.fail("%s: plan is not a JSON object" % stem)
		return
	var data := raw as Dictionary
	if not _t.check("%s: is a structure plan" % stem, StructurePlan.is_plan(data)):
		return

	var plan := StructurePlan.from_dict(data)
	_t.check("%s: plan has entities" % stem, plan.entity_count() > 0)

	_figure = null
	_hull_stations = null
	_stage = Node3D.new()
	add_child(_stage)
	_light_the_stage()

	# The plan is authored in grid-corner space; the studio centres it on the
	# hull with this offset, and a capture that used a different one would be
	# photographing something the builder never sees.
	var offset := Vector3.ZERO
	var deck_y := 0.0
	if plan.context == "vessel" and plan.hull_id != "":
		var grid := HullRegistry.make_grid(plan.hull_id)
		if grid != null:
			offset = Vector3(-grid.half_beam, 0.0, -grid.half_loa)
			deck_y = grid.deck_y
			_check_hull_derivation(plan, stem, grid)
			var boat: Node3D = VesselSpawn.instantiate(plan.hull_id, {}, "")
			if _t.check("%s: hull %s instantiates" % [stem, plan.hull_id], boat != null):
				_stage.add_child(boat)
				## HOLD THE SUBJECT STILL — see "THE SUBJECT WAS NEVER HELD STILL
				## BY ITS `freeze`" at the top of this file. `freeze = true` is not
				## what was holding this hull, and `process_mode` below is not
				## interchangeable with this call: one takes the body out of the
				## space, the other stops the LOD from ever running.
				CaptureSubject.hold_still(boat)
				boat.position = Vector3(0.0, -deck_y, 0.0)
				boat.process_mode = Node.PROCESS_MODE_DISABLED
				_hull_stations = boat.get("hull_stations") as HullStations
				_check_hull_restatement(plan, stem, boat)

	_add_scale_figure(offset, stem)

	var built: Node3D = StructureBaker.bake(plan, offset)
	if not _t.check("%s: plan bakes to a node" % stem, built != null):
		return
	_stage.add_child(built)

	var meshes := _count_meshes(built)
	_t.check("%s: bake produced geometry (%d surfaces)" % [stem, meshes], meshes > 0)

	# Draw-call budget is the governing constraint — harbours are full of these.
	# A merged bake should stay in the tens, not the hundreds. If this trips,
	# something stopped merging.
	_t.check("%s: bake stays merged (%d mesh instances)" % [stem, meshes], meshes <= 64)

	var bounds := _world_bounds(_stage)
	_t.check("%s: vessel has a real extent" % stem, bounds.size.length() > 1.0)

	_check_fittings(plan, stem)
	_check_edges(plan, stem)
	_check_rigging_attaches(plan, stem)
	_check_figure_stands(plan, stem)
	_check_fall_protection(plan, stem)

	_draw_calls = 0
	_primitives = 0
	for view in VIEWS:
		await _shoot(bounds, "%s__%s" % [stem, view["name"]], view)
	print("  [cost] %s  draw_calls=%d  triangles=%d  surfaces=%d" % [
		stem, _draw_calls, _primitives, meshes,
	])
	_check_cost(stem, meshes)

	_stage.queue_free()
	_stage = null
	_figure = null
	await get_tree().process_frame


## ── The hull a plan lofts is the hull the game builds ───────────────────────
##
## `edges[].from_hull` lofts a bulwark off `HullStations`, and a plan reaches
## those without naming a vessel script (the `--script` lane cannot — CONVENTIONS
## §2), so `StructurePlan.make_hull_stations` re-derives them from catalog
## numbers. A re-derivation nobody checks is a second hull that only LOOKS like
## the first, and the two would drift silently: a bulwark lofted off the wrong
## deck sits in mid-air, and at capture resolution mid-air by 120 mm is
## invisible.
##
## This is the SCENE lane, so here the real hull can be built and the derivation
## held against it. Two claims, and between them they pin every number the
## conversion uses:
##
##   • the grid — `half_beam`, `half_loa` and the build plane. The build plane is
##     `StructurePlan.BUILD_PLANE_M` above `HullStations.deck_y`, which is the
##     same 0.12 four vessel scripts pass to `DeckGrid.from_hull` and which
##     `hull_stations.gd`'s own sheer note names. It is a restated constant, so
##     it is worth exactly what checks it, and this is what checks it.
##   • the plan's `hull` block against the stations the hull actually carries.
##     This claim is inherited from `tests/structure_sheer_capture.gd`, which was
##     deleted when the `edges[]` seam landed. Deleting its rig must not delete
##     its guarantee.
func _check_hull_derivation(plan: StructurePlan, stem: String, grid: DeckGrid) -> void:
	if plan.edges.is_empty():
		return
	var derived := plan.hull_grid()
	if not _t.check("%s: the plan can loft its own hull" % stem, derived != null):
		return
	_t.check(
		"%s: derived grid matches the built one (half_beam %.3f/%.3f, half_loa %.3f/%.3f, deck_y %.3f/%.3f)"
		% [
			stem, derived.half_beam, grid.half_beam,
			derived.half_loa, grid.half_loa, derived.deck_y, grid.deck_y,
		],
		is_equal_approx(derived.half_beam, grid.half_beam)
		and is_equal_approx(derived.half_loa, grid.half_loa)
		and absf(derived.deck_y - grid.deck_y) < 1e-3
	)


func _check_hull_restatement(plan: StructurePlan, stem: String, boat: Node3D) -> void:
	if plan.hull.is_empty():
		return
	var built: HullStations = boat.get("hull_stations") as HullStations
	if not _t.check("%s: the built hull carries its stations" % stem, built != null):
		return
	var derived := plan.hull_stations()
	if not _t.check("%s: the plan's hull block lofts" % stem, derived != null):
		return
	_t.check(
		"%s: restated hull matches the built one (loa %.3f/%.3f, beam %.3f/%.3f, deck_y %.3f/%.3f)"
		% [
			stem, derived.length_m, built.length_m, derived.beam_m, built.beam_m,
			derived.deck_y, built.deck_y,
		],
		absf(derived.length_m - built.length_m) < 1e-3
		and absf(derived.beam_m - built.beam_m) < 1e-3
		and absf(derived.deck_y - built.deck_y) < 1e-3
	)
	## The sheer itself, which is the only thing `from_hull` is for. Both ends,
	## because a hull whose forward sheer matched and whose aft sheer did not
	## would draw a bulwark that is right at the stem and wrong at the transom.
	_t.check(
		"%s: restated sheer matches (%.3f/%.3f m forward, %.3f/%.3f m aft)"
		% [
			stem, derived.sheer_forward_m, built.sheer_forward_m,
			derived.sheer_aft_m, built.sheer_aft_m,
		],
		absf(derived.sheer_forward_m - built.sheer_forward_m) < 1e-3
		and absf(derived.sheer_aft_m - built.sheer_aft_m) < 1e-3
	)


## ── Cost ────────────────────────────────────────────────────────────────────
##
## `draw_calls` is the number this fixture drew BEFORE it carried a single
## fitting, measured on the renderer's own counter. Dressing a vessel must not
## move it: the baker buckets on MATERIAL ALONE and every fitting in these
## fixtures is painted / steel / wood, the three buckets each plan already had.
## Introduce a fourth material and this goes red by exactly one — which is the
## whole point of asserting the pre-dressing number rather than a round budget.
##
## `triangles` is the dressed measurement plus ~8%: geometry is what a rig
## actually costs, and the number is here so the cost is visible in the diff
## rather than discovered in a harbour.
const COST_BUDGET := {
	## Refreshed after the room purge and the rebuild on sheer band + raked plate.
	## Draw calls did NOT move on any of the three — a deckhouse in plates and a
	## rubbing strake reuse the material buckets the vessel already had. Triangles
	## roughly tripled, which is what superstructure and a swept hull strake cost
	## and is the trade this project made deliberately: geometry is cheap, a new
	## material bucket is not. Values are measured, then given ~8% headroom.
	"demo_workboat": {"draw_calls": 8, "triangles": 34000},
	"probe_trawler_bulwark": {"draw_calls": 8, "triangles": 33200},
	"probe_trawler_bow_bulwark": {"draw_calls": 8, "triangles": 36900},
	"probe_ferry_catamaran": {"draw_calls": 10, "triangles": 19000},
	"probe_spar_kit": {"draw_calls": 9, "triangles": 9400},
	"probe_ferry_catamaran_trim": {"draw_calls": 10, "triangles": 19600},
	## The 150 m ship, MEASURED on the same counters. 7 undressed draw calls / 14
	## with the shadow pass, and it is drawing 14 — so this line has NO slack in
	## it, which is the assertion: 603 fittings, 253 containers, 779 edge boxes
	## and ten container liveries all bucket on MATERIAL alone, and introducing a
	## fifth material anywhere on this vessel turns it red by exactly one.
	## Triangles are the measurement plus ~8%, as for every other row.
	"probe_container_feeder": {"draw_calls": 7, "triangles": 29700},
	## The sheer pair carries ONE material and therefore one bucket, over a bare
	## hull. 6 is what the hull plus a whole 76 m bulwark loop drew, measured —
	## not a round number left loose. Put the cap in a second material and this
	## goes red by one, which is the assertion: colour is free and a MATERIAL is
	## not, and a bulwark is the easiest place in the codebase to forget that.
	"probe_sheer_bulwark": {"draw_calls": 6, "triangles": 13200},
	"probe_sheer_bulwark_flat": {"draw_calls": 6, "triangles": 13200},
}


func _check_cost(stem: String, meshes: int) -> void:
	if not COST_BUDGET.has(stem):
		return
	var budget := COST_BUDGET[stem] as Dictionary
	## x2 for the same reason as triangles: the shadow pass issues its own draw
	## calls over the same surfaces. The vessel did not get more expensive when
	## the sun learned to cast.
	var calls := int(budget["draw_calls"]) * 2
	_t.check(
		"%s: %d draw calls against the %d it drew undressed" % [stem, _draw_calls, calls],
		_draw_calls <= calls
	)
	## Budgets are x2 because the sun now casts shadows, and a shadow map is a
	## second pass over the same geometry — RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
	## counts a triangle once per pass, not once per mesh. The scene did not get
	## heavier; the counter started telling the truth about what is drawn.
	var tris := int(budget["triangles"]) * 2
	_t.check("%s: %d triangles, budget %d" % [stem, _primitives, tris], _primitives <= tris)
	## A `meshes <= 4` check was written here and deleted after it survived its
	## own mutant. Retinting a mast into a fourth material bucket took this
	## fixture from 3 surfaces to 4 and from 8 draw calls to 9: the draw-call
	## line above went red, this one did not, because MATERIALS has exactly four
	## entries and every unknown name falls back to "painted" — so no plan can
	## ever push it over. It would only fail if the BAKER regressed, which no
	## fixture edit can provoke. That is a blind check, not a cheap one, and the
	## draw-call assertion already covers the same regression with a number that
	## moves. `meshes <= 64` above still catches a total loss of merging.
	print("  [cost] %s  bake surfaces=%d (bounded by MATERIALS, not asserted)" % [stem, meshes])


## ── Every fitting draws ─────────────────────────────────────────────────────
##
## An items[] entry whose primitive the baker cannot read emits nothing at all,
## silently — the baker's own note records `polyline_of` once drawing every wire
## as nothing because a PackedVector3Array is not an Array. A fixture full of
## fittings that renders as a bare hull is the failure this catches.
func _check_fittings(plan: StructurePlan, stem: String) -> void:
	var drawable := 0
	var mute := 0
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var primitive := StructureBaker.item_primitive(item)
		match primitive:
			"spar", "wire":
				# A swept tube needs at least two path nodes or it emits nothing.
				if StructureBaker.spar_path(StructurePlan.item_props(item)).size() >= 2:
					drawable += 1
				else:
					mute += 1
			"plate":
				# Four free corners, so a plate's silent-nothing case is a
				# degenerate quad rather than a short path. The rooms that used to
				# build superstructure are gone; every deckhouse is plates now, and
				# this check called all 104 of the ferry's MUTE until it learned
				# the primitive — a rig that does not know a primitive reports the
				# vessel using it as broken.
				if StructureBaker.plate_corners(StructurePlan.item_props(item)).size() == 4:
					drawable += 1
				else:
					mute += 1
			_:
				mute += 1
	if plan.items.is_empty():
		return
	_t.check(
		"%s: all %d fittings resolve to a drawn tube (%d mute)" % [stem, plan.items.size(), mute],
		mute == 0 and drawable == plan.items.size()
	)


## ── Every edge draws, and what it draws is what it collides ─────────────────
##
## The same failure as `_check_fittings`, one primitive along: an `edges[]` entry
## the baker cannot resolve emits NOTHING, silently, and a fixture whose whole
## subject is a bulwark then photographs a bare hull. A `from_hull` edge has one
## more way to come out empty than a hand-written one — the hull may not resolve
## at all — and that is the case worth catching, because the picture it produces
## is a perfectly good photograph of the wrong thing.
##
## The second claim is the one the seam exists for. `StructureEdge` derives the
## colliders from the boxes it drew rather than from a second pass over the path,
## and this holds the BAKER to that: every corner of every drawn box must lie
## inside some collider the baker emits. It is a coverage claim, not a count, and
## a count is what a re-derivation would still satisfy.
const EDGE_COVER_SLACK := 1e-4


func _check_edges(plan: StructurePlan, stem: String) -> void:
	if plan.edges.is_empty():
		return
	var mute := 0
	var uncollided := 0
	var boxes: Array = []
	for edge_variant in plan.edges:
		var edge := edge_variant as Dictionary
		var drawn := StructureBaker.edge_boxes(plan, edge)
		if drawn.is_empty():
			mute += 1
			continue
		## A run that declares itself solid and emits no collider is a wall you
		## can walk through; one that declares `solid: false` (paint, a boot top)
		## is opted out on purpose and its boxes are not part of the claim below.
		if StructureBaker.edge_collider_boxes(plan, edge).is_empty():
			if bool(edge.get("solid", true)):
				uncollided += 1
			continue
		boxes.append_array(drawn)
	_t.check(
		"%s: all %d edge runs draw (%d mute, %d boxes)"
		% [stem, plan.edges.size(), mute, boxes.size() ],
		mute == 0
	)
	_t.check(
		"%s: every solid edge run collides (%d silent)" % [stem, uncollided],
		uncollided == 0
	)
	if boxes.is_empty():
		return
	var colliders := StructureBaker.collect_colliders(plan)
	var outside := 0
	var first := Vector3.ZERO
	for box_variant in boxes:
		for corner in _box_corners(box_variant as Dictionary):
			if _near_solid_exact(colliders, corner):
				continue
			if outside == 0:
				first = corner
			outside += 1
	_t.check(
		"%s: every drawn edge corner is inside a collider (%d loose, first %v)"
		% [stem, outside, first],
		outside == 0
	)


func _box_corners(box: Dictionary) -> Array:
	var centre := box["center"] as Vector3
	var half := (box["size"] as Vector3) * 0.5
	var basis := box.get("basis", Basis.IDENTITY) as Basis
	var out: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(centre + basis * Vector3(half.x * sx, half.y * sy, half.z * sz))
	return out


## Containment with a float epsilon and nothing more — RIG_TOL's 0.3 m of grace
## would let a collider miss the geometry by a hand's breadth and still pass.
func _near_solid_exact(colliders: Array, point: Vector3) -> bool:
	for collider_variant in colliders:
		var collider := collider_variant as Dictionary
		var half := (collider["size"] as Vector3) * 0.5 + Vector3.ONE * EDGE_COVER_SLACK
		if _in_box(collider, point, half):
			return true
	return false


## ── Rigging is made fast to something ───────────────────────────────────────
##
## A stay whose end floats in mid-air renders as a line to nowhere, and at
## capture resolution it looks exactly like a stay that is made fast. Every wire
## end must land on a spar's own polyline or inside plan geometry. Caught three
## real ones: a forestay ending on empty centreline (the plan has no bow
## fitting — it got a samson post), a davit fall hanging free, and a backstay
## 0.15 m short of the transom cap.
##
## probe_spar_kit is out of scope and stays that way: it is the PRIMITIVE
## exerciser, not a vessel, and five of its ten wire ends are deliberately made
## fast to nothing — a stowed mooring line running off the plan, shrouds landing
## where no fitting exists. That is correct for a fixture whose job is to prove
## sag reaches zero, and it would be a defect on a ship. Naming the exemption is
## the honest version of scoping; silently skipping it is not.
const RIG_TOL := 0.3
const RIG_EXEMPT := ["probe_spar_kit"]


func _check_rigging_attaches(plan: StructurePlan, stem: String) -> void:
	if RIG_EXEMPT.has(stem):
		print("  [rig] %s: primitive probe, wire ends deliberately free — not checked" % stem)
		return
	var spar_paths: Array = []
	var wire_ends: Array = []
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var primitive := StructureBaker.item_primitive(item)
		if primitive != "spar" and primitive != "wire":
			continue
		var path := StructureBaker.spar_path(StructurePlan.item_props(item))
		if path.size() < 2:
			continue
		var xform := plan.item_transform(item)
		var world := PackedVector3Array()
		for point in path:
			world.append(xform * point)
		if primitive == "wire":
			wire_ends.append(world[0])
			wire_ends.append(world[world.size() - 1])
		else:
			spar_paths.append(world)
	if wire_ends.is_empty():
		print("  [rig] %s: no wire in this fixture — nothing checked" % stem)
		return
	var colliders := StructureBaker.collect_colliders(plan)
	var loose := 0
	var first := Vector3.ZERO
	for end_variant in wire_ends:
		var end := end_variant as Vector3
		if _near_polyline(spar_paths, end) or _near_solid(colliders, end):
			continue
		if loose == 0:
			first = end
		loose += 1
	_t.check(
		"%s: all %d wire ends made fast (%d loose, first %v)" % [
			stem, wire_ends.size(), loose, first,
		],
		loose == 0
	)


func _near_polyline(paths: Array, point: Vector3) -> bool:
	for path_variant in paths:
		var path := path_variant as PackedVector3Array
		for index in range(path.size() - 1):
			if Geometry3D.get_closest_point_to_segment(
				point, path[index], path[index + 1]
			).distance_to(point) <= RIG_TOL:
				return true
	return false


func _near_solid(colliders: Array, point: Vector3) -> bool:
	for collider_variant in colliders:
		var collider := collider_variant as Dictionary
		var size := (collider["size"] as Vector3) * 0.5 + Vector3.ONE * RIG_TOL
		if _in_box(collider, point, size):
			return true
	return false


## `yaw_deg` follows wall_yaw_deg: a +Y rotation of theta takes +X to
## (cos, 0, -sin), which is Godot's own `rotated(Vector3.UP, theta)`. So world
## to box-local is a rotation by MINUS the stored yaw.
func _in_box(collider: Dictionary, point: Vector3, half: Vector3) -> bool:
	var centre := collider["center"] as Vector3
	var delta := point - centre
	var yaw := deg_to_rad(float(collider.get("yaw_deg", 0.0)))
	if not is_zero_approx(yaw):
		delta = delta.rotated(Vector3.UP, -yaw)
	return absf(delta.x) <= half.x and absf(delta.y) <= half.y and absf(delta.z) <= half.z


## ── Fall protection ─────────────────────────────────────────────────────────
##
## The complaint this answers is literal: a passenger walks off the ferry's
## upper deck. Each run below is an EXPOSED EDGE in plan space — `a` to `b` with
## `in` pointing to the guarded side — walked at 0.1 m stations. A station is
## guarded when some collider the baker actually emits covers a point within
## GUARD_REACH inboard, at a height between GUARD_LO and GUARD_HI above the deck
## the person is standing on. A bulwark satisfies it, a guardrail satisfies it,
## a painted stripe does not.
##
## Stairwell holes are edges too, with `in` pointing AWAY from the hole.
##
## Deliberately not listed: the trawlers' stems. probe_trawler_bulwark's bow is
## open BY DESIGN — closing it is the entire difference between that fixture and
## probe_trawler_bow_bulwark, whose own note already carries a 20 001-station
## measurement of the same claim. Restating it here would be duplicate coverage
## dressed up as new coverage.
const GUARD_REACH := 0.6
const GUARD_LO := 0.85
const GUARD_HI := 1.25
const GUARD_STATION := 0.1
const GUARD_PROBE := 0.05

const FALL_EDGES := {
	"demo_workboat": [
		# Upper deck plate 5: x 1..9, z 8..16, top face y 3.0.
		{"y": 3.0, "a": [1.0, 8.0], "b": [9.0, 8.0], "in": [0.0, 1.0]},
		{"y": 3.0, "a": [9.0, 8.0], "b": [9.0, 16.0], "in": [-1.0, 0.0]},
		{"y": 3.0, "a": [9.0, 16.0], "b": [1.0, 16.0], "in": [0.0, -1.0]},
		{"y": 3.0, "a": [1.0, 16.0], "b": [1.0, 8.0], "in": [1.0, 0.0]},
		# Stairwell hole x 4..5.5, z 10..13. Stair 8 runs +z and tops out at
		# z = 13, so that edge is the arrival and carries no rail.
		{"y": 3.0, "a": [4.0, 10.0], "b": [4.0, 13.0], "in": [-1.0, 0.0]},
		{"y": 3.0, "a": [4.0, 10.0], "b": [5.5, 10.0], "in": [0.0, -1.0]},
		{"y": 3.0, "a": [5.5, 10.0], "b": [5.5, 13.0], "in": [1.0, 0.0]},
	],
	"probe_ferry_catamaran": [],
	"probe_ferry_catamaran_trim": [],
}

## The sheer pair, which carry nothing but ONE `edges[]` entry each. This is
## therefore the claim that `StructureBaker.collect_colliders` actually reads
## edges — delete that loop and every station below goes unguarded at once.
##
## It is the bulwark's own plating being walked into: the run lines sit just
## OUTBOARD of the path (which is itself inset half a plate thickness from the
## deck edge), so the first inboard probe lands in the middle of the plate rather
## than beside it. Both sides start at z = 6, aft of the 5 m bow taper — forward
## of that the deck edge is not at x = 0 and a straight run would be probing open
## water. The stems are covered by `structure_sheer_test`'s body march instead,
## which is the right instrument for a curve that is not axis-aligned.
const SHEER_FALL_EDGES: Array = [
	{"y": 0.0, "a": [-0.05, 6.0], "b": [-0.05, 27.9], "in": [1.0, 0.0]},
	{"y": 0.0, "a": [10.05, 6.0], "b": [10.05, 27.9], "in": [-1.0, 0.0]},
	{"y": 0.0, "a": [0.3, 28.05], "b": [9.7, 28.05], "in": [0.0, -1.0]},
]

## Both ferry fixtures are the same vessel below id 100, so they share one list.
const FERRY_FALL_EDGES: Array = [
	# Main deck, hull edge. Bulwarks 1/2/3 only run z 4..41; the bow and stern
	# bridging decks carry the new guardrail runs instead.
	{"y": 0.0, "a": [0.2, 0.4], "b": [0.2, 44.6], "in": [1.0, 0.0]},
	{"y": 0.0, "a": [15.8, 0.4], "b": [15.8, 44.6], "in": [-1.0, 0.0]},
	{"y": 0.0, "a": [0.2, 0.4], "b": [15.8, 0.4], "in": [0.0, 1.0]},
	{"y": 0.0, "a": [0.2, 44.6], "b": [15.8, 44.6], "in": [0.0, -1.0]},
	# Promenade, deck plate 30: x 1.2..14.8, z 7..37, top face y 3.0.
	{"y": 3.0, "a": [1.2, 7.0], "b": [14.8, 7.0], "in": [0.0, 1.0]},
	{"y": 3.0, "a": [14.8, 7.0], "b": [14.8, 37.0], "in": [-1.0, 0.0]},
	{"y": 3.0, "a": [14.8, 37.0], "b": [1.2, 37.0], "in": [0.0, -1.0]},
	{"y": 3.0, "a": [1.2, 37.0], "b": [1.2, 7.0], "in": [1.0, 0.0]},
	# Stairwell hole, realigned onto stair 50: x 11.4..13.2, z 32.6..36.6. The
	# stair tops out at z = 32.6, so THAT edge is the arrival.
	{"y": 3.0, "a": [11.4, 32.6], "b": [11.4, 36.6], "in": [-1.0, 0.0]},
	{"y": 3.0, "a": [11.4, 36.6], "b": [13.2, 36.6], "in": [0.0, 1.0]},
	{"y": 3.0, "a": [13.2, 32.6], "b": [13.2, 36.6], "in": [1.0, 0.0]},
	# Sun deck, deck plate 31: x 1.6..14.4, z 9..33, top face y 6.0.
	{"y": 6.0, "a": [1.6, 9.0], "b": [14.4, 9.0], "in": [0.0, 1.0]},
	{"y": 6.0, "a": [14.4, 9.0], "b": [14.4, 33.0], "in": [-1.0, 0.0]},
	{"y": 6.0, "a": [14.4, 33.0], "b": [1.6, 33.0], "in": [0.0, -1.0]},
	{"y": 6.0, "a": [1.6, 33.0], "b": [1.6, 9.0], "in": [1.0, 0.0]},
]


func _fall_edges(stem: String) -> Array:
	if stem.begins_with("probe_ferry_catamaran"):
		return FERRY_FALL_EDGES
	if stem.begins_with("probe_sheer_bulwark"):
		return SHEER_FALL_EDGES
	return FALL_EDGES.get(stem, []) as Array


func _check_fall_protection(plan: StructurePlan, stem: String) -> void:
	var runs := _fall_edges(stem)
	if runs.is_empty():
		return
	var colliders := StructureBaker.collect_colliders(plan)
	var stations := 0
	var bare := 0
	var first := Vector3.ZERO
	for run_variant in runs:
		var run := run_variant as Dictionary
		var deck_y := float(run["y"])
		var a := _xz(run["a"])
		var b := _xz(run["b"])
		var inward := _xz(run["in"]).normalized()
		var length := a.distance_to(b)
		var steps := maxi(1, int(ceil(length / GUARD_STATION)))
		for index in steps + 1:
			var here := a.lerp(b, float(index) / float(steps))
			stations += 1
			if _guarded(colliders, here, inward, deck_y):
				continue
			if bare == 0:
				first = Vector3(here.x, deck_y, here.y)
			bare += 1
	_t.check(
		"%s: %d/%d exposed-edge stations unguarded (first %v)" % [
			stem, bare, stations, first,
		],
		bare == 0
	)


func _xz(value: Variant) -> Vector2:
	var list := value as Array
	return Vector2(float(list[0]), float(list[1]))


## Not inside anything, and not hanging over anything. See the note above
## `FIGURE_FLOAT_MAX` for why a frame cannot answer either question.
##
## The cost is printed on every run because "assert the geometry too" is only a
## good trade while it is cheap, and a number in the log is the only thing that
## keeps that honest as the fixtures grow. Measured 2026-08-16 on the heaviest
## fixture in the fleet — `probe_container_feeder`, 603 items, 3084 collider
## boxes — this is single-digit milliseconds against a four-view capture that
## takes tens of seconds, and `_check_fall_protection` was already paying the same
## `collect_colliders` call four lines further down.
func _check_figure_stands(plan: StructurePlan, stem: String) -> void:
	var started := Time.get_ticks_usec()
	var colliders := StructureBaker.collect_colliders(plan)

	var inside := ""
	var y := FIGURE_BODY_LO
	while y <= FIGURE_BODY_HI and inside.is_empty():
		for offset in [
			Vector3.ZERO,
			Vector3(FIGURE_BODY_RADIUS, 0.0, 0.0), Vector3(-FIGURE_BODY_RADIUS, 0.0, 0.0),
			Vector3(0.0, 0.0, FIGURE_BODY_RADIUS), Vector3(0.0, 0.0, -FIGURE_BODY_RADIUS),
		]:
			var point: Vector3 = _figure_at + Vector3(0.0, y, 0.0) + (offset as Vector3)
			var hit: Variant = _collider_containing(colliders, point)
			if hit != null:
				var box := hit as Dictionary
				var centre := box["center"] as Vector3
				var size := box["size"] as Vector3
				inside = "a box %.2f x %.2f x %.2f centred %v, at body height %.2f m" % [
					size.x, size.y, size.z, centre, y,
				]
				break
		y += FIGURE_BODY_STEP

	_t.check(
		"%s: the 1.8 m figure at %v is clear of the plan's own geometry%s"
			% [stem, _figure_at, "" if inside.is_empty() else " — INSIDE " + inside],
		inside.is_empty(),
	)

	var surface := _surface_under(colliders, _figure_at)
	var gap := _figure_at.y - surface
	_t.check(
		"%s: the figure stands on something (surface y=%.3f, gap %+.3f m, allowed %.2f)"
			% [stem, surface, gap, FIGURE_FLOAT_MAX],
		gap <= FIGURE_FLOAT_MAX,
	)
	print("  [stands] %s  spot %v  %d collider boxes  %.1f ms" % [
		stem, _figure_at, colliders.size(), float(Time.get_ticks_usec() - started) / 1000.0,
	])
	_check_figure_on_the_ship(stem)


## The figure is over the hull — see `FIGURE_OFF_SHIP_MAX` for where the outline
## comes from and what the bound excludes.
##
## Two overhangs, because a spot leaves the ship in two directions and only one of
## them is about beam. TRANSVERSE is |x| against the hull's half-breadth at this
## station. LONGITUDINAL is how far the spot is forward of the stem or aft of the
## transom, and without it the transverse test has a hole big enough to walk
## through: the loft's forward section collapses to zero half-beam AT the stem, so
## a figure standing on the centreline in open water fifty metres ahead of the bow
## would be compared against a half-breadth of ~0 with |x| = 0 and pass.
func _check_figure_on_the_ship(stem: String) -> void:
	if _hull_stations == null or _hull_stations.stations.is_empty():
		print("  [onship] %s: SKIPPED — this plan builds no hull, so there is no"
			% stem + " outline to be inside")
		return
	var x := _figure_ship_xz.x
	var z := _figure_ship_xz.y
	var first := float(_hull_stations.stations[0]["z"])
	var last := float(_hull_stations.stations[_hull_stations.stations.size() - 1]["z"])
	var long_over := maxf(first - z, z - last)
	var half_breadth := _hull_half_breadth_at(z)
	var beam_over := absf(x) - half_breadth
	var worst := maxf(beam_over, long_over)
	_t.check(
		(
			"%s: the figure stands ON the ship (ship-local x=%+.3f z=%+.3f, hull"
			+ " half-breadth %.3f m at that station, %+.3f m outboard, %+.3f m past"
			+ " the ends, allowed %.2f)"
		) % [stem, x, z, half_breadth, beam_over, long_over, FIGURE_OFF_SHIP_MAX],
		worst <= FIGURE_OFF_SHIP_MAX,
	)
	print("  [onship] %s  ship-local (%+.3f, %+.3f)  half-breadth %.3f  outboard %+.3f  ends %+.3f"
		% [stem, x, z, half_breadth, beam_over, long_over])


## The hull's widest plan half-breadth at ship-local Z.
##
## Interpolated PER LEVEL between the two bracketing stations and then maximised,
## which is the loft's own surface: `MeshBuilder.lofted_hull_shell` joins level j
## of station i to level j of station i+1, so the silhouette between two stations
## is the linear blend of their sections and not either one of them. Sampling a
## single height instead would read the deck edge and miss the rubbing strake,
## which is the 0.150 m that makes the bound argue.
func _hull_half_breadth_at(z: float) -> float:
	var list: Array = _hull_stations.stations
	var count := list.size()
	if count == 1:
		return _widest_level(list[0]["section"] as Array, list[0]["section"] as Array, 0.0)
	var i := 0
	while i < count - 2 and float(list[i + 1]["z"]) < z:
		i += 1
	var z0 := float(list[i]["z"])
	var z1 := float(list[i + 1]["z"])
	var t := clampf((z - z0) / maxf(z1 - z0, 1e-6), 0.0, 1.0)
	return _widest_level(list[i]["section"] as Array, list[i + 1]["section"] as Array, t)


func _widest_level(a: Array, b: Array, t: float) -> float:
	var best := 0.0
	for j in range(mini(a.size(), b.size())):
		best = maxf(best, lerpf((a[j] as Vector2).y, (b[j] as Vector2).y, t))
	return best


## The collider a point is inside, or null. Yaw-correct, for `_guarded`'s reason.
func _collider_containing(colliders: Array, point: Vector3) -> Variant:
	for collider_variant in colliders:
		var collider := collider_variant as Dictionary
		var centre := collider["center"] as Vector3
		var size := collider["size"] as Vector3
		if point.y < centre.y - size.y * 0.5 or point.y > centre.y + size.y * 0.5:
			continue
		var flat := Vector3(point.x - centre.x, 0.0, point.z - centre.z)
		var yaw := deg_to_rad(float(collider.get("yaw_deg", 0.0)))
		if not is_zero_approx(yaw):
			flat = flat.rotated(Vector3.UP, -yaw)
		if absf(flat.x) <= size.x * 0.5 and absf(flat.z) <= size.z * 0.5:
			return collider
	return null


## The highest thing in the PLAN under the figure's feet, or the hull deck.
##
## y = 0 is the hull deck in this rig's stage space — `_capture_plan` bakes the
## plan at the origin and lowers the HULL by `deck_y` to meet it — so a spot with
## nothing of the plan's under it is standing on the ship, not in the air, and
## reports 0.0. That is why this returns a height rather than a boolean: on the
## container feeder the answer is a swept `items[]` plate at 3.396 and on the
## ferry it is the hull.
func _surface_under(colliders: Array, at: Vector3) -> float:
	var best := 0.0
	for collider_variant in colliders:
		var collider := collider_variant as Dictionary
		var centre := collider["center"] as Vector3
		var size := collider["size"] as Vector3
		var top := centre.y + size.y * 0.5
		if top > at.y + FIGURE_FLOAT_MAX or top <= best:
			continue
		var flat := Vector3(at.x - centre.x, 0.0, at.z - centre.z)
		var yaw := deg_to_rad(float(collider.get("yaw_deg", 0.0)))
		if not is_zero_approx(yaw):
			flat = flat.rotated(Vector3.UP, -yaw)
		if absf(flat.x) > size.x * 0.5 + FIGURE_BODY_RADIUS:
			continue
		if absf(flat.z) > size.z * 0.5 + FIGURE_BODY_RADIUS:
			continue
		best = top
	return best


func _guarded(colliders: Array, at: Vector2, inward: Vector2, deck_y: float) -> bool:
	var y_lo := deck_y + GUARD_LO
	var y_hi := deck_y + GUARD_HI
	var probes := int(GUARD_REACH / GUARD_PROBE)
	for step in range(1, probes + 1):
		var offset := inward * (GUARD_PROBE * float(step))
		var point := Vector3(at.x + offset.x, 0.0, at.y + offset.y)
		for collider_variant in colliders:
			var collider := collider_variant as Dictionary
			var centre := collider["center"] as Vector3
			var size := collider["size"] as Vector3
			if centre.y + size.y * 0.5 < y_lo or centre.y - size.y * 0.5 > y_hi:
				continue
			var flat := Vector3(point.x - centre.x, 0.0, point.z - centre.z)
			var yaw := deg_to_rad(float(collider.get("yaw_deg", 0.0)))
			if not is_zero_approx(yaw):
				flat = flat.rotated(Vector3.UP, -yaw)
			if absf(flat.x) <= size.x * 0.5 and absf(flat.z) <= size.z * 0.5:
				return true
	return false


## A 1.8 m figure on deck, in every frame.
##
## Without one, a capture has no absolute scale and a superstructure can be
## proportioned entirely wrong while looking plausible — which is exactly what
## happened. `scenes/shared/player.tscn` is a 1.8-tall capsule with its eye at
## 1.6, so world units are real metres FOR A HUMAN. Hull geometry is not on that
## scale: the catalog calls `hull_28x10` "14.0 × 5.0 m" but draws it 28 units
## long, so next to a 1.8 m player it reads as a 28 m vessel. Anything built on a
## hull must be sized against the figure, not against the catalog's display name.
##
## Matches the studio's own `_build_scale_mannequin` so a plan looks the same
## height in a capture as it does while you are drawing it.
func _add_scale_figure(offset: Vector3, stem: String) -> void:
	var figure := Node3D.new()
	figure.name = "ScaleFigure"

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.5
	body.mesh = capsule
	body.position = Vector3(0.0, 0.75, 0.0)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.95, 0.55, 0.1)
	body.material_override = suit
	figure.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.66, 0.0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.70, 0.55)
	head.material_override = skin
	figure.add_child(head)

	# Stand it on the open forward working deck. The first attempt put it at
	# z = 18, which is inside the wheelhouse on the trawler fixtures — the figure
	# rendered and was invisible in every frame, which is the one failure mode a
	# scale reference must not have. This spot is clear of the bow bulwark run,
	# the hatch coaming and the deckhouse on all three fixtures; a plan that
	# builds over it will need the figure placed from the plan rather than fixed.
	#
	# The deck plane is y = 0 in stage space: this rig bakes the plan at the
	# origin and lowers the HULL by deck_y to meet it, rather than raising the
	# plan the way `DeckFitout.apply_plan` does. Adding deck_y here left the
	# figure hanging in the air above the mast.
	var spot: Variant = _figure_spot(stem)
	_figure_at = (spot if spot != null else FIGURE_SPOT_DEFAULT) as Vector3
	figure.position = offset + _figure_at
	_figure_ship_xz = Vector2(figure.position.x, figure.position.z)
	_stage.add_child(figure)
	_figure = figure
	_t.check(
		"%s: the figure's spot is authored, not defaulted" % stem,
		spot != null,
	)


## The authored spot for a fixture, in plan metres, or `null` when nobody has
## decided one and the default is about to be used.
##
## ⚠ THIS IS A METHOD AND NOT `FIGURE_SPOT.get(stem)` FOR A MEASURED REASON.
##
## `FIGURE_SPOT` is a `const`, and GDScript will not let a subclass extend one.
## Both subclasses of this rig photograph fixtures this file has never heard of
## and both therefore carry their OWN table — `piece_kit_capture`'s
## `PIECE_FIGURE_SPOT`. When the "authored, not defaulted" check went in it asked
## `FIGURE_SPOT.has(stem)` directly, so it read a table that could not contain
## the answer and reported `probe_piece_house` and `probe_piece_tug` as
## defaulted while both were standing exactly where their own rig had authored
## them. That is REALITY §3 from close range: the check was asserting against the
## artefact it could reach rather than the value the figure was actually placed
## from. It is one resolution now, and the position and the claim are read from
## the same call.
func _figure_spot(stem: String) -> Variant:
	return FIGURE_SPOT.get(stem)


func _light_the_stage() -> void:
	# DirectionalLight3D defaults shadow_enabled to FALSE. Every capture before
	# 2026-08-10 shipped with no shadows at all — no mast on the deck, no
	# deckhouse on the hull, nothing self-shadowing — which is most of why the
	# vessels read as flat grey blocks pasted onto a hull. Shadow is not a
	# finishing touch on a low-poly model; it is the only thing separating two
	# untextured surfaces that meet at an angle.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.4
	_stage.add_child(sun)

	# The fill deliberately casts nothing: two shadow sets from opposing angles
	# read as dirt, not as light.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -125.0, 0.0)
	fill.light_energy = 0.35
	_stage.add_child(fill)

	# A PALE SKY, not the dark studio this rig shot against until 2026-08-10.
	#
	# The question these photographs exist to answer is a silhouette question —
	# squint at it, does that read as a boat — and a silhouette is the BOUNDARY
	# between the subject and its ground. A near-black hull on a near-black
	# ground has no boundary to read. The sheer rig found this the hard way: its
	# first pass drew the curve correctly and photographed it as a grey wire on a
	# grey field, which is a bad photograph of a good curve, and a reference
	# photograph whose subject cannot be separated from its ground is not
	# evidence of anything. Against a light sky the vessel is a dark shape and its
	# top edge is the only thing the eye has to go on, which is exactly the test.
	#
	# The ambient is raised with it so the shadowed side does not go to black —
	# the shadows are still what separate two untextured surfaces meeting at an
	# angle (see the sun above), and they only read while there is light in them.
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.74, 0.80, 0.85)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.70, 0.78)
	environment.ambient_light_energy = 0.60
	env.environment = environment
	_stage.add_child(env)

	_camera = Camera3D.new()
	_camera.current = true
	_stage.add_child(_camera)


func _shoot(bounds: AABB, name: String, view: Dictionary) -> void:
	var centre := bounds.get_center()
	var azimuth := deg_to_rad(float(view["azimuth"]))
	var elevation := deg_to_rad(float(view["elevation"]))

	var dir := Vector3(
		cos(elevation) * sin(azimuth),
		sin(elevation),
		cos(elevation) * cos(azimuth),
	)
	# Straight down would make `look_at` degenerate against UP.
	var up_hint := Vector3.UP if float(view["elevation"]) < 85.0 else Vector3.FORWARD
	var right := dir.cross(up_hint).normalized()
	var up := right.cross(dir).normalized()

	# Fitting the bounding SPHERE to the vertical FOV wastes most of a 16:9 frame
	# on a hull that is three times longer than it is tall. Project the eight
	# corners onto the camera's own right/up axes, then solve each axis against
	# its own field of view and take whichever needs more room.
	var half_v := deg_to_rad(FOV_DEGREES) * 0.5
	var aspect := float(get_viewport().size.x) / maxf(1.0, float(get_viewport().size.y))
	var tan_v := tan(half_v)
	var tan_h := tan_v * aspect

	var half_w := 0.0
	var half_h := 0.0
	var half_d := 0.0
	for i in 8:
		var corner := bounds.position + Vector3(
			bounds.size.x * float(i & 1),
			bounds.size.y * float((i >> 1) & 1),
			bounds.size.z * float((i >> 2) & 1),
		)
		var local := corner - centre
		half_w = maxf(half_w, absf(local.dot(right)))
		half_h = maxf(half_h, absf(local.dot(up)))
		half_d = maxf(half_d, absf(local.dot(dir)))

	var distance := maxf(half_h / tan_v, half_w / tan_h) * FRAME_MARGIN + half_d

	_camera.fov = FOV_DEGREES
	_camera.near = maxf(0.05, distance * 0.005)
	_camera.far = distance * 4.0
	_camera.position = centre + dir * distance
	_camera.look_at(centre, up_hint)

	## THE REFERENCE FRAME, AND WHY IT IS TAKEN EVERY TIME.
	##
	## CONVENTIONS §3a says every vessel capture carries a 1.8 m figure and that
	## the figure must be CHECKED VISIBLE, because the first placement put it
	## inside a wheelhouse where it rendered perfectly and appeared in no frame.
	## This rig placed the figure and then hoped. It shot four `critic_ferry`
	## frames with the figure under the saloon roof and passed all four.
	##
	## So the frame is shot twice: once with the figure hidden, once with it, and
	## the difference is the figure. That is a MEASUREMENT of the property the
	## convention states — "is there a scale reference in this picture" — and not
	## a restatement of the placement (REALITY §4a). Moving the spot to a
	## different hidden corner keeps the placement legal and still turns this red.
	if _figure != null:
		_figure.visible = false
		await _settle()
	var without := get_viewport().get_texture().get_image()
	if _figure != null:
		_figure.visible = true

	await _settle()

	_draw_calls = maxi(_draw_calls, int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)))
	_primitives = maxi(_primitives, int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
	)))

	var image := get_viewport().get_texture().get_image()
	await _check_render_noise(image)
	var out := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(out)
	_t.check("%s: capture written" % name, err == OK)

	# A capture that is a flat field of one colour is a failed render that looks
	# exactly like a successful one in a file listing. Refuse it.
	_t.check("%s: capture is not blank" % name, _distinct_colours(image) >= 8)

	var figure_px := 0
	if _figure != null:
		figure_px = _changed_pixels(without, image)
		if FIGURE_REQUIRED_VIEWS.has(str(view["name"])):
			_t.check(
				"%s: the 1.8 m scale figure is visible (%d px change when it is hidden)"
					% [name, figure_px],
				figure_px >= MIN_FIGURE_PIXELS,
			)
		elif figure_px < MIN_FIGURE_PIXELS:
			print("  [scale] %s: NO FIGURE IN THIS FRAME — the vessel's own structure"
				% name + " stands between it and the camera; see FIGURE_REQUIRED_VIEWS")

	## MEASURED, NOT ASSERTED, AND THAT IS DELIBERATE — see the note below
	## `_silhouette_contrast`. The number is on the record for every frame so a
	## dark-on-dark regression is visible in a log; it is not a gate condition,
	## because on this rig's white deckhouses it is not one.
	print("  %s  %dx%d  figure_px=%d  top_edge_contrast=%.2f:1" % [
		out, image.get_width(), image.get_height(), figure_px,
		_silhouette_contrast(image),
	])


## Settle, then wait on the DRAW. Every byte-stable rig in this repo awaits
## `frame_post_draw`; every unstable one awaited `process_frame` and grabbed a
## draw out (CONVENTIONS §3). Factored out of `_shoot` so a subclass cannot copy
## half of it.
func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## ONCE PER RUN, AND IT IS THE CONTROL FOR EVERY FIGURE COUNT THIS RIG PRINTS.
##
## The whole scale check is a difference between two renders. If two renders of
## the SAME scene already differed, that difference would be measuring the
## renderer and every frame would pass on noise. This says whether llvmpipe is
## deterministic here rather than assuming it. Inherited from
## `piece_kit_capture`, which is where it was written and which had it for its own
## fixtures only — the property is the parent's, so the check is now too.
var _noise_measured := false


func _check_render_noise(reference: Image) -> void:
	if _noise_measured:
		return
	_noise_measured = true
	await _settle()
	var again := get_viewport().get_texture().get_image()
	var noise := _changed_pixels(reference, again)
	_t.check(
		"two renders of one unchanged frame are identical (%d px differ)" % noise, noise == 0
	)


func _distinct_colours(image: Image) -> int:
	var seen := {}
	var step := maxi(1, image.get_width() / 96)
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			seen[image.get_pixel(x, y).to_rgba32()] = true
			if seen.size() >= 64:
				return seen.size()
	return seen.size()


## How many pixels changed between two frames of the same view. Stride 1, for
## `hull_visual_capture`'s reason: a 1.8 m figure on a 150 m hull is a handful of
## pixels and subsampling can miss it entirely.
func _changed_pixels(before: Image, after: Image) -> int:
	if before.get_width() != after.get_width() or before.get_height() != after.get_height():
		return 0
	var n := 0
	for y in range(before.get_height()):
		for x in range(before.get_width()):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) > FIGURE_PIXEL_DELTA \
					or absf(a.g - b.g) > FIGURE_PIXEL_DELTA \
					or absf(a.b - b.b) > FIGURE_PIXEL_DELTA:
				n += 1
	return n


## ── WHY THIS IS PRINTED AND NOT ASSERTED ────────────────────────────────────
##
## `hull_visual_capture` holds its frames to `MIN_SILHOUETTE_CONTRAST = 3.0` on
## exactly this number, and it is right to: it photographs BARE HULLS, whose
## skyline is dark topsides, and it found real frames at 1.18:1 where the deck
## edge was not a line. This rig was measured against the same formula on
## 2026-08-16, on the twelve committed `screenshots/critic/` frames:
##
##     critic_ferry__profile_port  3.47:1     critic_yacht__profile_port  1.60:1
##     critic_ferry__plan          3.14:1     critic_yacht__plan          2.31:1
##     critic_ferry__bow_quarter   1.71:1     critic_yacht__bow_quarter   1.15:1
##     critic_ferry__stern_quarter 1.25:1     critic_yacht__stern_quarter 1.01:1
##     critic_barge__profile_port  3.14:1     critic_barge__bow_quarter   2.22:1
##     critic_barge__plan          2.29:1     critic_barge__stern_quarter 1.79:1
##
## Eight of twelve under the floor — and all twelve were then OPENED AND LOOKED
## AT, and every one of them reads: the vessel separates cleanly from the ground
## in all four views, the deck edge is a line, the deckhouse massing is legible.
## The divergence has a mechanical cause and it is not a defect in the frames.
## `_silhouette_contrast` samples the TOPMOST subject pixel of each column, and
## these fixtures put a NEAR-WHITE deckhouse roof on the skyline (`#e8e6df`,
## `#f2f0ea`) where a bare hull puts dark topsides. White on a pale overcast has
## a low WCAG ratio and a perfectly readable edge, because what separates it is
## shading and the dark hull under it, not luminance against the sky.
##
## Enforcing 3:1 here would therefore demand that deckhouses be painted darker to
## satisfy a number — an appearance decision taken by a scorer, which is
## precisely REALITY §2. The measurement stays, in every log line, because a
## re-darkened ground WOULD show up in it. The verdict does not.
func _silhouette_contrast(image: Image) -> float:
	var background := image.get_pixel(2, 2)
	var sum := Color(0.0, 0.0, 0.0)
	var n := 0
	for x in range(image.get_width()):
		for y in range(image.get_height()):
			var c := image.get_pixel(x, y)
			if (
				absf(c.r - background.r) > 0.02
				or absf(c.g - background.g) > 0.02
				or absf(c.b - background.b) > 0.02
			):
				sum += c
				n += 1
				break
	if n == 0:
		return 0.0
	var a := _relative_luminance(sum / float(n))
	var b := _relative_luminance(background)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


func _relative_luminance(c: Color) -> float:
	return (
		0.2126 * _linearize(c.r) + 0.7152 * _linearize(c.g) + 0.0722 * _linearize(c.b)
	)


func _linearize(channel: float) -> float:
	return (
		channel / 12.92
		if channel <= 0.04045
		else pow((channel + 0.055) / 1.055, 2.4)
	)


func _count_meshes(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		total += 1
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _world_bounds(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(node, boxes)
	if boxes.is_empty():
		return AABB()
	var out := boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out


## Lights and the environment are VisualInstance3Ds with their own AABBs; letting
## them into the merge blows the bounds up and pushes every camera miles back.
func _collect_bounds(node: Node, into: Array[AABB]) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if gi.visible:
			into.append(gi.global_transform * gi.get_aabb())
	for child in node.get_children():
		_collect_bounds(child, into)
