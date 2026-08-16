class_name PlanOutfit
extends RefCounted

## Measures a StructurePlan the way VesselOutfit measures a BrickLayout, so the
## registration rule evaluator in VesselCompliance can judge a Structure Studio
## ship. Nothing here is vessel-specific: a plan is a plan, and every quantity
## below is read off geometry or off the part catalog, never off a ship type.
##
## ── Why this file exists ────────────────────────────────────────────────────
##
## `DeckFitout.apply_plan` used to return a hardcoded `{"outfit_ok": true}` and
## never call a validator, while persistence and deployment ran
## `BrickLayout.from_dict` on a plan dict, got an empty layout, failed the helm
## rule and refused. So a plan ship could be drawn and could be neither saved,
## spawned, crewed nor sold. Both halves are wired now — `apply_plan` and
## `compliance_for_layout` both route a `structure_plan_v1` document here — and
## this paragraph is kept as the reason the file exists, not as a live defect.
##
## The rule evaluator itself needs NO changes. All ELEVEN kinds in
## `VesselCompliance._evaluate_rule` read six dictionaries — `brick_counts`,
## `tag_counts`, `tag_positions`, `positions`, `capacity`, `max_ratings` — plus
## the VesselOutfit-shaped `accepted_slots` / `usage` / `capabilities`. This file
## populates exactly those, from `plan.items` and the plan's walls/decks/stairs.
##
## `tag_positions` and the `tag_side` kind arrived 2026-08-15 with the fix for
## STATE.md 2f: the two sidelight rules and `white_above_sidelights` addressed
## brick IDS, which no part can carry, so a plan failed 5 of `general_vessel`'s 8
## rules whatever was fitted. Measured through `VesselSpawn` -> `apply_plan`,
## 3 of 8. The law did not move — a plan vessel still has to carry a red light to
## port, a green one to starboard and a white one above both — only its address
## did, from an id one vocabulary holds to a tag both do.
##
## ── The seam a later wave closes ────────────────────────────────────────────
##
## `VesselCompliance.validate()` takes `layout: BrickLayout` and cannot be handed
## a plan. `compliance()` below is the plan-side twin of that function: it calls
## the SAME `VesselCompliance._evaluate_rule` and the SAME `VesselCompliance._result`,
## so the checklist, the message strings and the report shape cannot drift. The
## wave that owns `vessel_compliance.gd` collapses the two by adding:
##
##     static func validate_plan(
##         plan: StructurePlan, hull_id: String, registration_id: String,
##         grid: DeckGrid = null,
##     ) -> Dictionary:
##         return PlanOutfit.compliance(plan, hull_id, registration_id, grid)
##
## and the wave that owns `deck_fitout.gd` replaces the hardcoded caps in
## `apply_plan` with:
##
##     var declared := registration_id.strip_edges()
##     if declared.is_empty() and boat.has_meta("registration_id"):
##         declared = str(boat.get_meta("registration_id"))
##     var report := PlanOutfit.compliance(plan, hull_id, declared, g)
##     var caps: Dictionary = report.get("capabilities", {}).duplicate(true)
##     caps["outfit_ok"] = bool(report.get("ok", false))
##     caps["structure_plan"] = true
##     caps["plan_entities"] = plan.entity_count()
##     # mount only report.accepted_slots — item IDS, see below
##
## ── Slots are item IDs, not cells ───────────────────────────────────────────
##
## `accepted_slots` holds plan item ids (ints), where the brick path holds
## `Vector3i` cells. A plan item has a float position and two fittings may share
## a cell (a lamp hosted on a mast), so a cell cannot identify a mount. The id
## is the plan's own identity and survives a save. No rule kind inspects the
## elements — `slot_count` only counts them — so this costs the evaluator nothing.
##
## ── What is measured from GEOMETRY, with no items at all ────────────────────
##
## `doors` is an enclosure fact and a plan draws it: a door is an opening of
## type "door" cut into a wall or a deck, counted off the drawing.
##
## `has_cabin` is MEASURED off the drawing — see `enclosure` below for the
## criterion and for what it costs. The paragraph that used to stand here said it
## was not measurable, and that was a category error worth spelling out because
## it is the kind this project keeps making: it read "no primitive DECLARES
## enclosure" as "enclosure is not MEASURABLE".
##
## The room primitive was the plan's own DECLARATION of a cabin — it expanded to
## walls + floor + ceiling and `open_faces` named the sides that were missing —
## and deleting it (2026-08-10) was right: it could only draw a box, so every
## deckhouse built from one came out a shed. What it took with it was the
## declaration, not the fact. A plan still draws walls with positions, extents
## and openings, decks with origins and sizes, and plates with four corners
## apiece, and whether those close a volume is a question about that drawing with
## exactly one right answer. The old wording turned "the document no longer says
## `room`" into "the geometry cannot be asked", and on the strength of it
## `passenger_vessel/cabin` was closed to every plan a player could draw, for
## every plan, permanently — the owner's central premise failing quietly behind
## an honest-sounding refusal.
##
## The bar the old paragraph set is the right bar and `plan_compliance_test`
## still holds this to it: the brick-era rule `door_n >= 1 or wall_n >= 8`
## passed on eight roofless walls, a fence sold as accommodation. `enclosure`
## refuses that case for the reason a person would give — a fence has no deck
## over it and the sky is not a ceiling — rather than by not asking.
##
## PAST TENSE SINCE 2026-08-16, AND THE OLD PARAGRAPH WAS WRONG ABOUT ITS OWN
## CITATION. That rule is no longer live anywhere: `VesselOutfit` reads
## `BrickShellClassifier.enclosure` now (commit `ed72b86`), and it was measured
## to be worse than this paragraph claimed — one `block_door` standing alone on
## an open deck reported a cabin, not merely eight roofless walls. The claim
## that `plan_compliance_test` "holds this to it" was FALSE of the brick side:
## that test pins the PLAN side, and no test in this repo asserted anything
## about the brick reading at all until `brick_enclosure_test` existed. A
## header that cites a test as covering a rule it does not cover is worse than
## a header that says nothing — it is what let the wrong answer ship for days.
##
## ── Scale (CONVENTIONS §3a) ─────────────────────────────────────────────────
##
## One world unit is one metre. Plan coordinates are metres; deck-grid cells are
## `WorldUnits.DECK_CELL_M` (0.5 m) and exist only because the cell-counting
## rules (`tag_side`, `white_above_sidelights`, cargo area) are written in
## cells. `StructurePlan.plan_to_cell` is the only converter used.

## ── "On the hull", for a plan ───────────────────────────────────────────────
##
## THE ONE PREDICATE is `on_hull_point` / `off_hull_entities` below, and the
## question it asks is NOT "is this over the deck". That question has a right
## answer for a BRICK, which occupies a cell (`BrickLayout.cell_on_grid`), and no
## right answer for a plan, which is authored in free metres. Measured over the
## 19 shipped fixtures — 2342 entities, 15 057 drawn boxes,
## `tests/_plan_fence_facts.gd` — **61 entities have a corner outside the deck
## rectangle and 10 lie entirely outside it**, and they are not mistakes:
##
##     +4.000 m  critic_barge            deck plate outboard of the side   ⚠ WRONG, SEE BELOW
##     +2.000 m  critic_yacht            deck plate outboard of the side   ⚠ WRONG, SEE BELOW
##     +0.683 m  probe_trawler_bulwark   bow cap rail / stem head cap
##     +0.580 m  demo_workboat           davit block
##     +0.220 m  probe_ferry_catamaran_trim  rubbing strake, forward
##
## ⚠ THE TOP TWO ROWS WERE NOT OUTBOARD OF ANYTHING — MEASURED 2026-08-16
##
## Both were re-measured through `PieceKit.resolve_placement`
## (`tests/_wave_trim_audit.gd`) and their port/starboard excursion is **0.000 m**.
## The whole 4.000 m and 2.000 m is in **-Z, forward of the stem**:
## `critic_barge` placement 1 is a `trim_band` coaming drawing a plate at
## z -4.00 .. 4.00, and `critic_yacht` placement 9 a `trim_band` strake at
## z -2.00 .. 6.00, on decks that begin at z = 0. In `screenshots/critic/` they
## are a thin unsupported spar standing out over the water ahead of the bow, in
## both the profile and the plan view of each vessel.
##
## The cause is in the fixtures and it has been fixed there: `facing` yaws the
## piece-local +X RUN AXIS as well as the outward normal, so facing 90 marches a
## run forward, and both placements were anchored at the forward end of the run
## they were meant to cover. They are re-anchored aft; nothing in this file
## changed and nothing needed to.
##
## What this paragraph should be read for is the SHAPE of the mistake, because it
## is the one REALITY §2 warns about and it happened here. The fence's justifying
## example — "a rubbing strake stands proud by definition" — is an argument about
## the ATHWARTSHIPS axis, and it was used to wave through two excursions that were
## entirely in the fore-and-aft one. A margin of `half_beam` is the right size for
## something bolted to a hull's side and four times too big for anything hanging
## off a bow, and because the two worst rows in its own evidence table were the
## bug rather than the feature, "zero of 2342 shipped entities are refused" was
## measuring a fence calibrated against a defect. The margin is UNTOUCHED — moving
## it to make these two red would be the tuning the same section forbids — and the
## property they actually violate is asked separately, by
## `plan_hull_bounds_test._test_trim_is_trim_on_something`: trim is trim ON
## something, and every corner of every trim run has to reach it.
##
## NOT CHECKED, and left standing rather than quietly assumed: the three
## surviving rows have NOT been re-measured per axis, and the counts above — 2342
## entities, 61 with a corner outside, 10 wholly outside — were taken before the
## two placements moved and are stale by at least those two. Re-run
## `tests/_plan_fence_facts.gd` before quoting any of them.
##
## A stem rakes forward of the forward perpendicular, a cap rail overhangs the
## plating it caps, a rubbing strake stands proud by definition, and a davit
## swings out over the water. **Containment in the deck rejects real ships** —
## 61 entities on the every-corner reading, 10 on the any-corner one. Loosening
## a containment rule until it agreed would be REALITY.md §2, a metric tuned to
## a known answer.
##
## So the fence is not the deck. It is the VESSEL:
##
##     deck rectangle  x in [0, width * CELL_M], z in [0, length * CELL_M]
##     envelope        that rectangle grown by `grid.half_beam` on all four sides
##
## `half_beam` is the hull's own half-breadth — a field `DeckGrid` publishes,
## `width * CELL_M * 0.5` — not a constant chosen here. It scales with the ship
## (5 m on the 28 m trawler, 16 m on the 150 m feeder) and it is the natural size
## of the things that hang off a hull's side. Measured against it: **zero of 2342
## shipped entities are refused**, the worst standing 4.000 m clear of a 5.00 m
## bound, while the off-hull slab in `tests/_placement_grid_survey.gd` stands
## **890 m** clear. That is not a threshold separating near misses from far ones;
## it is the gap between "bolted to this boat" and "authored for a different one".
##
## EVERY corner has to be inside, not merely one of them — `on_hull_points`
## below, and it is the half the numbers argue for rather than the wording. A
## wall has extent: bounds-checking one point of a footprint passed an entire
## 119-check file on the buildings side (STATE.md 2, M3). Read the loose way
## round, a 900 m wall with one end bolted to the deck is "on the hull" and the
## slab comes straight back — measured, `tests/_plan_fence_facts.gd` §E: a
## 900 m wall started at (2, 0, 2) bakes a **902 m** AABB, and the any-corner
## reading refuses none of it while the every-corner reading refuses it. Both
## readings cost the same on shipped data: zero.
##
## Two things this deliberately does NOT do:
##   • It does not test the bow taper. The taper is a CELL STAIRCASE
##     approximating a curve, and the entities above cross it on purpose.
##     Growing a staircase by a metre and calling the result a hull outline
##     would be a second derivation of `DeckGrid.cell_shape` with none of its
##     meaning.
##   • It does not read `plan.hull_grid()`. THE CALLER STATES THE DECK — the same
##     argument `BrickLayout.set_brick` makes, and it is checkable here too:
##     `hull_grid()` always passes `beam * 0.5` as the bow taper while
##     `PassengerCatamaran.make_grid()` passes 0.0, so reading the plan's own
##     grid cuts a triangle off each bow corner of a bridge deck that has none.
##     `hull_grid`'s own header already says "do not read this grid for cell
##     shapes; ask the vessel for that one".
##
## ── The band this fence is NOT ──────────────────────────────────────────────
##
## Below it sits an older, finer gradient over ITEMS ONLY, and it is deliberate:
## a slot fitting whose origin cell is off the deck is a WARNING, a cargo item
## covering a cell outside the exposed deck is an ERROR. A deckhouse fitting
## overhanging the sheer is normal; a container floating beside the ship is not.
## That gradient is kept exactly as it was. What was wrong with it is that it had
## a SILENT third case, and the third case is where the compliance-counted parts
## live: measured over the catalog, `helm_console` warns, `net_drum` warns,
## `hold_coaming` errors, and the remaining **12 parts say nothing at all —
## including `bollard_pair` (tag "mooring") and `lantern_all_round` (tag
## "nav_white")**, which are exactly the fittings `general_vessel` counts. The
## fence above closes that at the "is it on the boat at all" level, for every
## entity kind and not just for items; it does not flatten the finer band into it.

## Compliance tags that make an item's deck footprint count against the cargo
## budget. Both are catalog tags, so a new hold part needs no code here.
const CARGO_TAGS: Array[String] = ["cargo", "bulk_hold"]

## Footprint approximation: which primitive scalars widen a spec's XZ box, and
## by what fraction of their value. Unlisted scalars (sides, rails, post_pitch,
## sag, toe_height) do not move the footprint enough to matter and are ignored.
const AABB_INFLATE_XZ := {"radius": 1.0, "thickness": 0.5, "width": 0.5}
## Scalars that raise the top of the box above its points.
const AABB_EXTEND_UP: Array[String] = ["height"]
## Tolerance for the deck-shadow polygon, in the cross-product units of metres².
## A cell centre this close to an edge is inside it — the AABB reading it
## replaces was inclusive on its bounds and staying inclusive keeps yaw 0 exact.
const SHADOW_EPS := 1e-9

## The kit is preloaded rather than named: `part_catalog.gd` declares
## `class_name PartCatalog` but is newer than the project's global class cache,
## and a script that names an unregistered global fails to COMPILE. Preloading
## binds to the file and is correct either way.
const Parts := preload("res://scripts/construction/part_catalog.gd")


# ── "On the hull": the one predicate ────────────────────────────────────────

## Is this plan-space XZ point inside the vessel's envelope? See the header for
## why the envelope is the deck rectangle grown by the hull's own half-breadth
## and not the deck itself.
static func on_hull_point(grid: DeckGrid, x: float, z: float) -> bool:
	if grid == null:
		return false
	var m := WorldUnits.DECK_CELL_M
	var margin := grid.half_beam
	return (
		x >= -margin
		and x <= float(grid.width) * m + margin
		and z >= -margin
		and z <= float(grid.length) * m + margin
	)


## Every XZ point of an entity that has to land on the vessel.
##
## `boxes` are the oriented collider boxes `StructureBaker.entity_colliders`
## emits for that entity — the boxes the plan really draws and really collides,
## so this cannot drift from the geometry (§3b). All four XZ corners of every box
## are taken, never the centre: a wall has extent, and bounds-checking one point
## is the mutation that passed an entire 119-check file on the buildings side.
##
## `item` widens that, and it has to. `StructureBaker._item_colliders` emits
## boxes for exactly two primitives — `plate` and solid `spar`. A `bollard_pair`,
## a `lantern_all_round` and a `helm_console` emit NONE, and those are precisely
## the parts a registration counts, so a fence read off colliders alone would let
## a boat whose whole legal outfit is in the sea straight through — the plan-side
## twin of STATE.md 2c. An item therefore contributes its own extent as well, and
## WHICH extent depends on what draws it — see `item_hull_points`.
static func hull_test_points(
	plan: StructurePlan, kind: String, entity: Dictionary, boxes: Array
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var c: Vector3 = box["center"]
		var s: Vector3 = box["size"]
		var basis := Basis(Vector3.UP, deg_to_rad(float(box.get("yaw_deg", 0.0))))
		for corner_i in 4:
			var corner := c + basis * Vector3(
				(s.x * 0.5) if (corner_i & 1) != 0 else (-s.x * 0.5),
				0.0,
				(s.z * 0.5) if (corner_i & 2) != 0 else (-s.z * 0.5),
			)
			out.append(Vector2(corner.x, corner.z))
	if kind != "item" or plan == null:
		return out
	out.append_array(item_hull_points(plan, entity))
	return out


## The XZ extent of ONE item, in plan metres — and the reason it is not one line.
##
## A plan item is drawn one of two ways and only one of them is in the catalog.
## `StructureBaker._item_layers` draws `plate`, `spar` and `wire` straight from
## the item's OWN props, while every other `item_id` goes through
## `PartCatalog.expand_props`. Those two disagree, and measuring it is how these
## nine shipped entities were found:
##
##     demo_workboat #265  wire  "fender lanyard"  points [[0,0,0],[0.33,-1.08,0]]
##
## The `wire` PART declares `run`/`rise`/`sag`/`radius` and no `points`, so
## `expand_props` drops the prop (it says so, in `prop_warnings`, which nothing
## reads) and falls back to the catalog default `run` of **8.0 m**. A 0.33 m
## lanyard measured as an 8 m one lands 8 m off the side of a 10 m boat, and the
## fence refused all nine of them. Nothing was wrong with the fixtures: the
## catalog was answering for geometry it does not draw.
##
## So: a baker primitive is measured off the path the BAKER draws, and everything
## else off the catalog that expands it. Sag is ignored deliberately: `wire_path`
## bends downward under gravity in Y only, so it cannot move an XZ point, and for
## a height reading the unsagged endpoints ARE the top.
##
## ── ONE DERIVATION, and what it cost to get here ────────────────────────────
##
## That branch used to live in this function alone. `item_footprint_cells` and
## `max_stack_cells` asked `part_local_aabb` about EVERY item, including a
## `wire`, and got the catalog's answer for geometry the baker does not take from
## the catalog. Measured on the shipped fixtures before this changed
## (`tests/_plan_wire_aabb.gd`), the overstatement was exactly the catalog's
## default `rise`:
##
##     demo_workboat          wire #256  +4.00 m over a drawn top of 4.50 m
##     probe_trawler_bulwark  wire  #98  +4.00 m over a drawn top of 8.30 m
##
## THE WIRE WAS THE SMALL HALF. The same reading was applied to every `spar`
## item, and `spar` was a catalog id too, so 844 shipped spars were measured with
## the part's default `length` of 6.0 m stacked on top of wherever they stood.
## `max_stack_cells` — the plan's air draught — came out:
##
##                            reported        drawn top (bake AABB)
##     demo_workboat          31 cells 15.5 m      10.04 m
##     probe_trawler_bulwark  30 cells 15.0 m       9.26 m
##
## i.e. 5.5 m and 6.0 m of air draught that no fixture draws. It now reports 20
## and 18 cells, which floor to the bake AABB exactly. Nothing consumes
## `capabilities.max_stack_y` today (no registration rule names it), which is
## why a number that wrong sat unread — §3d from the other end.
##
## `item_local_points` below is now the single producer and these three are its
## only readers. A `plate` item gained a reading it never had (`part_local_aabb`
## was asked about the id "plate", which is not a catalog part, so it answered
## `ok=false` and a plate contributed nothing to either number).
##
## An item that yields nothing at all falls back to its origin, which is still
## the position the builder typed — so an uncatalogued fitting cannot be a hole
## in the fence.
static func item_hull_points(plan: StructurePlan, item: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in item_world_points(plan, item):
		out.append(Vector2(point.x, point.z))
	if out.is_empty():
		var origin := plan.item_transform(item).origin
		out.append(Vector2(origin.x, origin.z))
	return out


## THE ONE DERIVATION of what a plan item occupies: its own extreme points, in
## PLAN metres. Read by `item_hull_points` (the hull fence), by
## `item_footprint_cells` (cargo deck cells) and by `max_stack_cells` (air
## draught), so a fitting cannot be three different sizes in one file.
##
## A BAKER PRIMITIVE is measured off the geometry `StructureBaker` draws for it —
## the plate's own corners, the spar's or wire's own polyline — because that is
## what lands in the world.
##
## A CATALOG PART is measured off `part_local_aabb`, which bounds the resolved
## primitive specs and then inflates by radius and thickness. That is a
## CONSERVATIVE box around the drawn geometry rather than the drawn geometry
## itself, and it is named here rather than quietly equated: it over-covers, which
## is the safe side for a fence and for a cargo footprint, and no shipped fixture
## places a catalog part today (all 1752 shipped items are raw primitives), so
## nothing measured is calibrated on it.
static func item_world_points(plan: StructurePlan, item: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	if plan == null:
		return out
	var xform := plan.item_transform(item)
	var props := StructurePlan.item_props(item)
	var primitive := StructureBaker.item_primitive(item)
	if primitive == "plate":
		for point in StructureBaker.plate_corners(props):
			out.append(xform * point)
		return out
	if primitive == "spar" or primitive == "wire":
		for point in StructureBaker.spar_path(props):
			out.append(xform * point)
		return out
	var box := part_local_aabb(str(item.get("item_id", "")), props)
	if not bool(box.get("ok", false)):
		return out
	var mn: Vector3 = box["min"]
	var mx: Vector3 = box["max"]
	for corner_i in 8:
		out.append(xform * Vector3(
			mx.x if (corner_i & 1) != 0 else mn.x,
			mx.y if (corner_i & 2) != 0 else mn.y,
			mx.z if (corner_i & 4) != 0 else mn.z,
		))
	return out


## Does EVERYTHING this entity draws stand on the vessel? See the header for why
## it is every point and not any point.
##
## An entity with no test points at all — a wire, a non-solid spar, a plate the
## baker refused — puts nothing in the world and is left alone: it is not
## standing anywhere, so there is nothing to refuse. Items never reach that case,
## because an item with no boxes still contributes its origin.
static func on_hull_points(points: PackedVector2Array, grid: DeckGrid) -> bool:
	if grid == null or points.is_empty():
		return true
	for point in points:
		if not on_hull_point(grid, point.x, point.y):
			return false
	return true


## Every entity of `plan` that does not stand on the vessel, as
## `[{kind, id, index, at, message}, …]`.
##
## `index` is the entity's position within its own collection of the RESOLVED
## plan, and it — not `id` — is what the partition removes by; see
## `StructurePlan.without_entities` for why.
static func off_hull_entities(plan: StructurePlan, grid: DeckGrid) -> Array:
	var out: Array = []
	if plan == null or grid == null:
		return out
	## Resolved once, here, and the resolved plan is what is walked. That is not
	## tidiness: `resolved()` re-runs the whole piece kit and re-reports every
	## refusal it finds, so resolving four times down one validation prints four
	## copies of every kit error. It returns its argument untouched when `pieces`
	## is empty.
	var resolved := StructureBaker.resolved(plan)
	var by_kind := {
		"wall": resolved.walls, "deck": resolved.decks, "stair": resolved.stairs,
		"item": resolved.items, "edge": resolved.edges,
	}
	for row_variant in StructureBaker.entity_colliders(resolved):
		var row := row_variant as Dictionary
		var kind := str(row["kind"])
		var index := int(row["index"])
		var collection := by_kind.get(kind, []) as Array
		var entity: Dictionary = (
			collection[index] as Dictionary if index < collection.size() else {}
		)
		var points := hull_test_points(resolved, kind, entity, row["boxes"] as Array)
		if on_hull_points(points, grid):
			continue
		var at := Vector3(points[0].x, 0.0, points[0].y)
		if not (row["boxes"] as Array).is_empty():
			at = ((row["boxes"] as Array)[0] as Dictionary)["center"]
		out.append({
			"kind": kind,
			"id": int(row["id"]),
			"index": index,
			"at": at,
			"message": off_hull_reason(grid, kind, int(row["id"]), at),
		})
	return out


## Human-readable refusal for one entity, in the builder's words — the plan-side
## twin of `BrickLayout.off_grid_reason`. It names WHAT, WHERE and the deck it
## missed, because "invalid placement" sends the next reader nowhere.
static func off_hull_reason(grid: DeckGrid, kind: String, id: int, at: Vector3) -> String:
	var m := WorldUnits.DECK_CELL_M
	return (
		"%s %d at (%.1f, %.1f, %.1f) m is not on the %.1f x %.1f m hull"
		% [kind.capitalize(), id, at.x, at.y, at.z, float(grid.width) * m, float(grid.length) * m]
	)


## One sentence for the whole set, shaped like `VesselOutfit`'s off-deck error so
## a plan-built vessel and a brick-built one tell the builder the same thing.
static func off_hull_error(off: Array) -> String:
	var named := PackedStringArray()
	for row in off:
		if named.size() >= 4:
			break
		named.append(str((row as Dictionary)["message"]))
	var tail := ""
	if off.size() > named.size():
		tail = " (+%d more)" % (off.size() - named.size())
	return (
		"%d plan %s off the hull and %s not built: %s%s"
		% [
			off.size(),
			"entity is" if off.size() == 1 else "entities are",
			"it is" if off.size() == 1 else "they are",
			" · ".join(named),
			tail,
		]
	)


## The plan with everything `off_hull_entities` named removed — RESOLVED, so a
## piece placement is measured and dropped as the plates it actually becomes.
##
## This is the half that makes the refusal real. `DeckFitout.apply_plan` bakes
## and collides whatever it is handed, so an error on its own leaves the geometry
## in the world; the wave that fixed the brick side proved the same point with a
## mutation (STATE.md 2c, M3 — keeping the error but dropping the skip left 7 of
## 8 legal requirements met by bricks in the sea).
static func on_hull_plan(plan: StructurePlan, grid: DeckGrid) -> StructurePlan:
	if plan == null:
		return plan
	var resolved := StructureBaker.resolved(plan)
	return _without(resolved, off_hull_entities(resolved, grid))


## The partition, given a report `off_hull_entities` has already produced. Split
## out so a caller that needs BOTH the report and the plan pays for one pass.
static func _without(resolved: StructurePlan, off: Array) -> StructurePlan:
	if off.is_empty():
		return resolved
	var drop := {}
	for row_variant in off:
		var row := row_variant as Dictionary
		var kind := str(row["kind"])
		if not drop.has(kind):
			drop[kind] = {}
		(drop[kind] as Dictionary)[int(row["index"])] = true
	return resolved.without_entities(drop)


# ── VesselOutfit-shaped validation ──────────────────────────────────────────

## Returns { ok, errors, warnings, budget, usage, accepted_slots, capabilities }
## — the exact contract of `VesselOutfit.validate`, for a plan.
static func validate(
	plan: StructurePlan,
	hull_id: String,
	grid: DeckGrid = null,
	policy_caps: Dictionary = {},
) -> Dictionary:
	var declared_hull := hull_id
	if declared_hull.is_empty() and plan != null:
		declared_hull = plan.hull_id
	var id := HullRegistry.resolve_network_hull_id(declared_hull)
	var budget := VesselOutfit.budget_for_hull(id, policy_caps)
	var g := grid if grid != null else HullRegistry.make_grid(id)
	if plan == null:
		return _result(
			true, PackedStringArray(), PackedStringArray(), budget, {}, _empty_slots(), {}
		)
	## THE VESSEL FENCE, taken once and before anything is measured. See the
	## header for what it asks; `_validate_built` is what it hands the answer to.
	var resolved_plan := StructureBaker.resolved(plan)
	var off_hull := off_hull_entities(resolved_plan, g)
	return _validate_built(plan, _without(resolved_plan, off_hull), off_hull, g, budget)


## `validate` with the fence already taken, so a caller that needs BOTH the
## report and the partitioned plan pays for ONE pass over the geometry.
## Measured on `probe_container_feeder` (617 entities, 3084 boxes): the fence
## costs 93 ms, about what `collect_colliders` costs, and `compliance` used to
## run it twice.
##
## `plan` is the AUTHORED document and `built` the partitioned RESOLVED one, and
## both are needed. The item loop walks the authored items on purpose: a piece
## placement resolves to `plate` items the part catalog has never heard of, and
## measuring those would bury a builder in "no part plate in the catalog"
## warnings for a deckhouse they built out of the kit's own pieces.
static func _validate_built(
	plan: StructurePlan,
	built: StructurePlan,
	off_hull: Array,
	g: DeckGrid,
	budget: Dictionary,
) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	## An entity that stands nowhere on the hull is not judged, it is REFUSED —
	## and as an ERROR, not a warning, because the question it fails is not "is
	## this fitting a little outboard" (see the header: real ships are) but "is
	## any of this on the boat at all".
	##
	## The skip is the half that matters, and the brick side proved it with a
	## mutation: keeping the error while still MEASURING the strays left 7 of 8
	## legal requirements met by gear in the sea (STATE.md 2c, M3). `bollard_pair`
	## and `lantern_all_round` are the parts `general_vessel` counts, and nothing
	## in this file used to ask where they were.
	var off_hull_items := {}
	for row_variant in off_hull:
		var row := row_variant as Dictionary
		if str(row["kind"]) == "item":
			off_hull_items[int(row["id"])] = true
	var judged := built
	if not off_hull.is_empty():
		errors.append(off_hull_error(off_hull))

	## One pass over items: slot candidates, cargo footprints, unknown parts.
	var slot_items := {"fishing": [], "helm": [], "crane": [], "tow": []}
	var cargo_items: Array = []
	var door_items := 0
	for raw in plan.items:
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		var part_id := str(item.get("item_id", ""))
		var item_id := int(item.get("id", -1))
		if off_hull_items.has(item_id):
			## Already named in the one error above. Measured as nothing, so it
			## cannot take a slot, buy a cargo cell or satisfy a legal rule.
			continue
		if not Parts.has(part_id):
			## A RAW PRIMITIVE IS NOT AN UNKNOWN FITTING. An item whose props (or
			## whose id) name one of the baker's own primitives is drawn and
			## collided from those props — 916 of the shipped fleet's items are
			## spelled that way — and it carries no compliance identity by
			## construction: no tags, no rating, no seats. Measuring it as nothing
			## is correct; SAYING it could not be measured is not, and it would put
			## 916 lines in the builder's report.
			if StructureBaker.item_draws_as_primitive(item):
				continue
			## Everything else is never silent: an unknown fitting is measured as
			## nothing, and the builder is told which one and why.
			warnings.append(
				"Plan item %d: no part \"%s\" in the catalog — not measured."
				% [item_id, part_id]
			)
			continue
		## A prop the part has no parameter for is a typo, and a typo that
		## resolves to a default in silence is how a builder ends up with a
		## 12 m hold they asked to be 8 m. Named here, item and prop both.
		for message in prop_warnings(part_id, StructurePlan.item_props(item)):
			warnings.append("Plan item %d: %s" % [item_id, message])
		var slot := Parts.outfit_slot_of(part_id)
		if slot_items.has(slot):
			(slot_items[slot] as Array).append(item_id)
			if not _is_over_deck(plan, item, g):
				warnings.append(
					"Plan item %d (%s) is not over the vessel's deck."
					% [item_id, Parts.display_name(part_id)]
				)
		if Parts.has_tag(part_id, "door"):
			door_items += 1
		for tag in CARGO_TAGS:
			if Parts.has_tag(part_id, tag):
				cargo_items.append(item)
				break

	## THE ROOF THAT DOES NOT MEET ITS WALL. A warning and not an error, because
	## the drawing is buildable and a player may well want an open-sided tier —
	## but never silent, which is what it was. See `roof_gaps`: the gap is a thin
	## wedge at a roof/wall junction seen edge-on, invisible in every render this
	## project has ever taken, and it un-rooms the compartment underneath it.
	##
	## Read off the AUTHORED plan and not off `judged`, unlike `doors` below: a
	## resolved plan has no `pieces[]` left to ask about, and a placement is the
	## only thing that carries a rake.
	for gap_variant in roof_gaps(plan):
		var gap := gap_variant as Dictionary
		warnings.append(
			"Piece %s (%s, rake %+d): the roof stops %.2f m short of this wall's"
			% [
				str(gap["id"]), str(gap["piece"]), int(gap["rake"]),
				float(gap["short_m"]),
			]
			+ " head — open sky along %d of its %d stations."
			% [int(gap["stations"]), ROOF_STATIONS]
			+ " Take the deck over it %d cell(s) further out (that overhang is the eave)."
			% int(ceil(float(gap["short_m"]) / (WorldUnits.DECK_CELL_M) - 0.001))
		)

	var accepted_slots := _empty_slots()
	for slot in ["fishing", "helm", "crane", "tow"]:
		_take_slots(
			slot_items[slot] as Array,
			int(budget.get(slot, 0)),
			accepted_slots[slot] as Array,
			errors,
			_slot_label(slot),
		)

	## Cargo is the UNION of the deck cells the accepted cargo items cover, so
	## stacking a second hold over the first buys no capacity — a property the
	## brick path's per-zone sum does not have.
	var cargo_max := int(budget.get("cargo_cells", 0))
	var accepted_cells := {}
	var claimed_cells := {}
	for item in cargo_items:
		var item_id := int((item as Dictionary).get("id", -1))
		var cells := item_footprint_cells(plan, item as Dictionary, g)
		var off_deck := false
		for cell in cells:
			claimed_cells[cell] = true
			if not g.has_deck_cell(cell):
				off_deck = true
		if cells.is_empty():
			warnings.append("Cargo item %d covers no deck cells." % item_id)
			continue
		if off_deck:
			errors.append("Cargo item %d covers cells outside the exposed deck." % item_id)
			continue
		var merged := accepted_cells.duplicate()
		for cell in cells:
			merged[cell] = true
		if merged.size() > cargo_max:
			errors.append(
				"Cargo exceeds hull budget (%d / %d cells). Shrink or remove holds."
				% [merged.size(), cargo_max]
			)
			continue
		accepted_cells = merged
		(accepted_slots["cargo_item_ids"] as Array).append(item_id)

	var usage := {
		"fishing": (slot_items["fishing"] as Array).size(),
		"helm": (slot_items["helm"] as Array).size(),
		"cargo_cells": claimed_cells.size(),
		"crane": (slot_items["crane"] as Array).size(),
		"tow": (slot_items["tow"] as Array).size(),
		"accepted_cargo_cells": accepted_cells.size(),
	}
	## READ OFF `judged`, like `doors` below and for the same reason: a deckhouse
	## that is not on the boat is not accommodation on this boat. It used to read
	## the AUTHORED plan, which cost nothing while the answer was hardcoded false
	## and would have certified a cabin drawn 900 m off the bow the moment it was
	## not.
	var enclosed := enclosure(judged)
	var capabilities := {
		"cargo_cells": accepted_cells.size(),
		"cargo_budget": cargo_max,
		"exposed_deck_cells": int(budget.get("exposed_deck_cells", 0)),
		"has_cabin": bool(enclosed.get("cabin", false)),
		"has_helm": (accepted_slots["helm"] as Array).size() >= 1,
		"has_crane": (accepted_slots["crane"] as Array).size() >= 1,
		"has_fishing": (accepted_slots["fishing"] as Array).size() >= 1,
		"has_tow": (accepted_slots["tow"] as Array).size() >= 1,
		## Read off `judged`: a door cut into a wall that is not on the boat is not
		## a door onto anything.
		"doors": door_count(judged) + door_items,
		"windows": opening_count(judged, StructurePlan.OPENING_WINDOW),
		"helms": (accepted_slots["helm"] as Array).size(),
		## The brick path's "brick_count" is "how many pieces is this made of".
		## A plan's pieces are its entities.
		"brick_count": plan.entity_count(),
		"max_stack_y": max_stack_cells(plan, g),
		## Plan-native extras. Nothing in the catalog reads them yet; they cost
		## nothing and a `metric_range` rule can name them the day it wants to.
		## `cabins` is the COUNT `enclosure` found and `cabin_area_m2` the largest
		## one's standable floor — the numbers a licence that wants two cabins, or
		## eight square metres of them, would be written against.
		"cabins": int(enclosed.get("cabins", 0)),
		"cabin_area_m2": float(enclosed.get("area_m2", 0.0)),
		"cabin_why": str(enclosed.get("why", "")),
		"items": plan.items.size(),
		"plan_entities": plan.entity_count(),
		"structure_plan": true,
	}
	return _result(
		errors.is_empty(), errors, warnings, budget, usage, accepted_slots, capabilities
	)


# ── VesselCompliance._measure-shaped metrics ────────────────────────────────

## Returns { brick_counts, tag_counts, tag_positions, positions, capacity,
## max_ratings, usage, capabilities, accepted_slots, grid } — the exact
## dictionary `VesselCompliance._evaluate_rule` reads. `brick_counts` and
## `positions` are keyed by PART id, which is what a plan's `item_id` is, so a
## rule written against a brick id matches a part of the same id and nothing
## else — which is precisely why the shipped sidelight rules do not use one.
## `tag_counts` and `tag_positions` are keyed by COMPLIANCE TAG, the address both
## build paths answer to.
static func measure(plan: StructurePlan, grid: DeckGrid, outfit: Dictionary) -> Dictionary:
	var brick_counts := {}
	var tag_counts := {}
	var tag_positions := {}
	var positions := {}
	var capacity := {}
	var max_ratings := {}
	if plan != null:
		for raw in plan.items:
			if not (raw is Dictionary):
				continue
			var item := raw as Dictionary
			var part_id := str(item.get("item_id", ""))
			if not Parts.has(part_id):
				continue
			var cell := item_cell(plan, item, grid)
			brick_counts[part_id] = int(brick_counts.get(part_id, 0)) + 1
			if not positions.has(part_id):
				positions[part_id] = []
			(positions[part_id] as Array).append(cell)
			var compliance_data := Parts.compliance_of(part_id)
			var rating := int(compliance_data.get("equipment_rating", 0))
			for tag in Parts.tags_of(part_id):
				var key := str(tag)
				tag_counts[key] = int(tag_counts.get(key, 0)) + 1
				## Same loop as the count, for the same reason
				## `VesselCompliance._measure_equipment` does it: a rule that
				## counts a tag and a rule that LOCATES it must be looking at one
				## set of fittings (REALITY.md §3b).
				if not tag_positions.has(key):
					tag_positions[key] = []
				(tag_positions[key] as Array).append(cell)
				max_ratings[key] = maxi(int(max_ratings.get(key, 0)), rating)
			var seats := int(compliance_data.get("passenger_capacity", 0))
			if seats != 0:
				capacity["passenger_capacity"] = (
					int(capacity.get("passenger_capacity", 0)) + seats
				)
	var usage: Dictionary = (outfit.get("usage", {}) as Dictionary).duplicate(true)
	var capabilities: Dictionary = (outfit.get("capabilities", {}) as Dictionary).duplicate(true)
	for field in capacity.keys():
		usage[field] = int(capacity[field])
	return {
		"brick_counts": brick_counts,
		"tag_counts": tag_counts,
		"tag_positions": tag_positions,
		"positions": positions,
		"capacity": capacity,
		"max_ratings": max_ratings,
		"usage": usage,
		"capabilities": capabilities,
		"accepted_slots": outfit.get("accepted_slots", {}),
		"grid": grid,
	}


## Plan-side twin of `VesselCompliance.validate`, evaluating the SAME rules
## through the SAME evaluator. Returns the same report dictionary, plus one
## plan-only key: `off_hull`, the fence rows this function has already taken.
##
## ── Why the report carries the fence ────────────────────────────────────────
##
## `structure_studio` needs BOTH answers on every rebake — which entities will
## not be built, and whether the plan certifies — and computing them separately
## means taking the SAME partition twice. Measured on `probe_container_feeder`
## (617 entities, 3084 boxes), `tests/_compliance_cost.gd`, quiet tree:
##
##     fence alone (off_hull_entities)      99.88 ms
##     compliance() (its own fence)        120.11 ms
##     both, separately                    219.98 ms
##
## So the VERDICT half — `measure` plus eight rule evaluations — is ~20 ms, and
## the fence is the other 100. Against a whole studio rebake of that plan
## (`tests/_studio_rebake_cost.gd`, one process, 9 reps, two runs):
##
##     rebake, fence only (the studio at c531076)   321.7 / 342.2 ms
##     rebake, this shared pass                     342.4 / 365.4 ms   +6.4 % / +6.8 %
##     rebake, fence AND its own compliance         427.4 / 460.0 ms  +32.9 % / +34.4 %
##
## Publishing the rows this function already holds is the difference between
## those last two lines, and it is the same fix this function's own body records
## making one level down ("running it twice cost 190 ms of the 277 ms").
##
## It is also the REALITY.md §3b half: a panel that says "1 OFF THE HULL" and a
## verdict that judges a different partition are two measurements of one
## question, and this repo has fixed that shape three times.
static func compliance(
	plan: StructurePlan,
	hull_id: String,
	registration_id: String,
	grid: DeckGrid = null,
) -> Dictionary:
	var declared_hull := hull_id
	if declared_hull.is_empty() and plan != null:
		declared_hull = plan.hull_id
	var id := HullRegistry.resolve_network_hull_id(declared_hull)
	var g := grid if grid != null else HullRegistry.make_grid(id)
	var registration := VesselRegistrationCatalog.resolved_registration(registration_id)
	var caps: Dictionary = registration.get("budget_caps", {})
	## ONE fence pass for the whole report. `validate` would take its own, and
	## `measure` below needs the SAME partition — running it twice cost 190 ms of
	## the 277 ms this function spent on `probe_container_feeder`.
	var resolved_plan := StructureBaker.resolved(plan)
	var off_hull := off_hull_entities(resolved_plan, g)
	var built := _without(resolved_plan, off_hull)
	var outfit := (
		_validate_built(plan, built, off_hull, g, VesselOutfit.budget_for_hull(id, caps))
		if plan != null
		else validate(plan, id, g, caps)
	)
	var checklist: Array[Dictionary] = []
	var errors: PackedStringArray = (outfit.get("errors", PackedStringArray()) as PackedStringArray).duplicate()
	var warnings: PackedStringArray = (outfit.get("warnings", PackedStringArray()) as PackedStringArray).duplicate()
	if registration.is_empty():
		errors.append("Choose a vessel registration before building.")
		return _with_fence(
			VesselCompliance._result(
				outfit, registration_id, false, checklist, errors, warnings
			),
			off_hull,
		)
	## MEASURED ON THE HULL, not on the document. `measure` is what feeds
	## `brick_counts`, `tag_counts` and `positions` to the rule evaluator, so a
	## bollard 900 m off the bow counted toward "at least four mooring points" and
	## a lantern in the sea satisfied "white masthead light" — the plan-side twin
	## of the certified-empty vessel (STATE.md 2b/2c), and the reason this reads
	## the partitioned plan rather than the authored one.
	var metrics := measure(built, g, outfit)
	var registration_ok := true
	for raw in registration.get("rules", []) as Array:
		if not (raw is Dictionary):
			continue
		var item := VesselCompliance._evaluate_rule(raw as Dictionary, metrics, outfit)
		checklist.append(item)
		if not bool(item.get("ok", false)):
			registration_ok = false
			errors.append(
				str(item.get("message", item.get("label", "Registration requirement failed")))
			)
	return _with_fence(
		VesselCompliance._result(
			outfit, registration_id, registration_ok, checklist, errors, warnings
		),
		off_hull,
	)


## Attaches the fence rows to a finished report. Separate so `_result`'s
## signature stays exactly what `vessel_compliance.gd` declares it to be — the
## header on that function records a wave that died changing it and took two
## test units NOTRUN with it.
static func _with_fence(report: Dictionary, off_hull: Array) -> Dictionary:
	report["off_hull"] = off_hull
	return report


# ── Enclosure, read off geometry ────────────────────────────────────────────

## The raster the columns below are counted on, in metres. HALF a deck cell, and
## that is the number the resolution limit is stated in: a cell is solid when any
## drawn box OVERLAPS it, so a wall thinner than the raster still blocks (a
## default wall is 1/6 m and would fall between centre samples) at the price of
## each wall end bleeding up to half a cell into the gap beside it. Measured on
## the synthetic ring (`plan_enclosure_test`): a 1.0 m hole reads as open,
## a 0.5 m hole reads as CLOSED. So this reading cannot see a slot narrower than
## 2 * CABIN_CELL_M, it is stated here rather than discovered later, and halving
## the constant halves the slot at four times the cost.
const CABIN_CELL_M := 0.25
## `scenes/shared/player.tscn` is 1.8 m (CONVENTIONS §3a) and a compartment they
## cannot stand up in is not accommodation. The same figure `plan_interior_test`
## and `piece_interior_test` march through these deckhouses with.
const CABIN_MIN_HEADROOM_M := 1.8
## The smallest compartment on any vessel is the heads — 0.9–1.4 x 0.8–1.2 m per
## `references/COMPONENTS.md`, which is the smallest space a person can turn
## round in. Under this and the enclosed pocket is a void, not a room.
const CABIN_MIN_AREA_M2 := 1.2
## Two solids whose spans meet within this are one solid. `StructureBaker.SKIN_EPS`
## is 0.01: abutting plates deliberately overlap by that much, and a joint must
## not read as a crack the weather gets through.
const CABIN_MERGE_M := 0.02
## How far a DOOR may stand from the air it opens onto, in raster cells. A
## doorway is cut INTO the shell, so the air on its inboard face is one or two
## cells away through the plating. Widening it to 3 or 4 cells changes no answer
## on any shipped fixture, measured — the fleet does not sit near this bound.
const CABIN_ACCESS_CELLS := 2
## 4-connectivity for the column flood. Diagonal leakage is deliberately not
## modelled: two boxes meeting at a corner leave no passage.
const CABIN_NEIGHBORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


## Does this plan draw an enclosed compartment a person could live in?
##
## See `enclosure` for the criterion. This is the boolean the registration
## evaluator reads; everything that makes it true or false is in there.
static func has_cabin(plan: StructurePlan) -> bool:
	return bool(enclosure(plan).get("cabin", false))


## THE ENCLOSURE READING. Returns
## `{cabin, cabins, area_m2, floor_y, roof_y, why}`.
##
## ── The criterion, and why this one ─────────────────────────────────────────
##
## **A cabin is a pocket of air inside the drawing that the sky cannot reach,
## tall enough to stand in, big enough to turn round in, with a door into it.**
## Nothing here asks what a primitive is CALLED.
##
## Each clause is there because dropping it admits something a builder would not
## call accommodation, and every one of them is checked by
## `tests/plan_enclosure_test.gd` against a plan built to break it — and shown
## RED by deleting the clause:
##
##   sky cannot reach it   the fence. Eight walls in a ring with a door and no
##                         deck over them is refused because the air inside them
##                         runs straight up to the sky — which is the reason a
##                         person would give, and it is the same reason that
##                         refuses a ring whose fourth side is missing (the air
##                         goes out sideways instead).
##   tall enough           a locker, a void under a boat deck, the 0.9 m gap
##                         between two tiers. 1.8 m or it is not a room.
##   big enough            the 0.5 m² pocket between a mast foot and a casing.
##   a way in              a shipping container is an enclosed steel box with
##                         2.39 m of headroom and 14 m² of floor, and it is not a
##                         cabin. So is a sealed funnel casing and so is a hold.
##                         What separates accommodation from a box is that you
##                         can get into it, and the plan records exactly that.
##                         A DOOR, not a window: see `_is_way_in`, and the funnel
##                         trunk with a scuttle in it that made the distinction
##                         necessary.
##
## ── What it still gets wrong, named rather than left to be found ────────────
##
## Every one of these came out of `tests/_enclosure_adversary.gd`, which exists
## to get a wrong `true` out of this function:
##
##  • A SHIPPING CONTAINER WITH ITS DOORS DRAWN reads as a cabin — 11.5 m² of
##    floor, 2.29 m of headroom, two door openings. There is no geometry that
##    separates it from a compartment, because there is none: a converted box IS
##    accommodation on real ships. No shipped fixture hits this (the container
##    feeder draws 350 container plates and cuts openings in exactly one of
##    them, the house front), and the only fix would be a `container` tag on the
##    part — a data question, not a geometry one.
##  • A FULL-HEIGHT SHELTER DECK — bulwark raised to the deckhead all round,
##    with a door — reads as a cabin. It is enclosed, floored, roofed and
##    enterable, so this is arguably right; it is listed because a builder might
##    call it a covered working deck. The 1.2 m bulwark under the same deck is
##    correctly refused.
##  • A SLOT NARROWER THAN 0.5 m reads as closed. See `CABIN_CELL_M`.
##  • The way-in test asks whether a door stands within two raster cells of the
##    enclosed air, which is a blob and not a direction. A door in an internal
##    bulkhead therefore opens onto BOTH compartments it separates — correct —
##    and a door within 0.5 m of a sealed void beside the room it really opens
##    onto would open onto that too. No fixture does this and the fix is to
##    step along the plate's own normal instead.
##
## ── A door is a CLOSURE, not a hole ─────────────────────────────────────────
##
## The one place this reading edits the drawing. `wall_panels` subtracts a door
## from the plating, so the boxes the baker emits have a genuine 1.2 x 2.1 m gap
## in them — correct for collision, and it would leak every cabin in the fleet
## through its own front door. The format already names the difference and this
## uses the format's own word: `door` and `window` are leaves and glass and are
## filled back in, `hole` and `stairwell` are holes and are left open. So a
## deckhouse with a companionway hatch in its roof is measured as open through
## that hatch, which is what a hatch is.
##
## SEALING AND ACCESS ARE NOT THE SAME QUESTION and are two predicates, not one:
## `_is_closure` (door or window) decides what closes the envelope, `_is_way_in`
## (door only) decides what lets a person through it. They were one predicate
## until the adversarial pass, and conflating them was worth a wrong yes on a
## funnel trunk with a scuttle in it. Varying them together also produced a
## confident wrong conclusion about the fleet on the way — REALITY.md §4e, vary
## ONE input.
##
## ── Why a flood over COLUMNS and not a level-by-level reading ───────────────
##
## The first cut looked for a horizontal ceiling plane and asked whether the ring
## under it closed. It reported false on every deckhouse in the repo. A
## `deck_tile` at `fall 2` drops 0.25 m across its run and `roof_slope` is a
## slope by definition, so there IS no plane at which the whole ceiling is solid
## — and a reading that needed one was the room primitive's shed assumption
## wearing a different hat. What replaced it assumes nothing about shape:
##
##   1. every collider box the plan draws is painted into the XZ raster, each
##      column keeping the y SPANS it covers;
##   2. the spans are merged, and what is left between them are the column's AIR
##      intervals. The last one runs to infinity: that is the sky. Below y = 0 is
##      the vessel's own deck (or, for a building, the ground) and is solid —
##      the same closed floor `BrickShellClassifier` gives the brick path, which
##      has been flooding air from the sides and the sky to tell an interior
##      brick from an exterior one since long before this function existed;
##   3. air intervals in neighbouring columns are connected when their spans
##      overlap. Flood in from every column at the raster edge and every column
##      standing next to one with no structure in it at all — see
##      `_flood_outside` for why the sky needs no seed of its own;
##   4. what the flood never reached is enclosed. Group it, measure each group's
##      standable floor, and ask whether a closure opens onto it.
##
## THE BOXES ARE THE DRAWING (REALITY.md §3b). They come from
## `StructureBaker.collect_colliders`, which is what the player walks into, so a
## wall that stops reaching the deckhead in the baker stops enclosing here in the
## same commit. There is no second geometry here to drift — the only thing this
## file computes is the raster.
##
## ── Measured ────────────────────────────────────────────────────────────────
##
## Over the 18 shipped `structure_plan_v1` fixtures (`tests/_enclosure_probe.gd`;
## the nineteenth file in that directory is `probe_edge_runs`, which is not a
## plan), **10 report a cabin and 8 do not**. True: demo_workboat,
## probe_trawler_bulwark, probe_trawler_bow_bulwark, probe_piece_house,
## probe_piece_trawler, probe_piece_tug, probe_plate_deckhouse,
## probe_ferry_catamaran(_trim) and probe_container_feeder — whose 242.5 m²
## compartment at y 0.00..3.70 is the accommodation block, entered through the
## two doors cut in the house front at z = 16.5 (item 111), not the cargo hold.
## False: the two bulwark-only fixtures, the spar kit, the diagonal-wall probe,
## the AO junction and the three `critic_*` piece studies, none of which closes a
## volume it also lets you into.
##
## That is an INDEPENDENT check on the answer rather than a calibration:
## `plan_interior_test` and `piece_interior_test` march a 1.8 m capsule through
## five of those deckhouses on the real `PhysicsServer3D` body and find floors
## and passable doorways, and this agrees with all five without being told.
##
## Cost, one process, llvmpipe: 4–130 ms for a hand-authored vessel, 220–230 ms
## for the two catamarans and **~1.8 s for `probe_container_feeder`** — 617
## entities and 3070 collider boxes, the largest plan in the repo and about five
## times the next one. It is linear in painted columns, and that plan paints
## 70 526 of them. That is the honest number and it is not comfortable: a whole
## studio rebake of the same plan is 342 ms, so on THAT plan this reading is the
## dominant cost of a validate. The lever is `CABIN_CELL_M` — at 0.5 m the feeder
## falls to ~0.5 s and the slot this reading cannot see doubles to 1.0 m, which
## is a hole you can walk through. The resolution was chosen for the answer, not
## for the clock.
static func enclosure(plan: StructurePlan) -> Dictionary:
	var empty := {
		"cabin": false, "cabins": 0, "area_m2": 0.0, "floor_y": 0.0, "roof_y": 0.0,
	}
	if plan == null:
		return _enclosure_result(empty, "no plan")
	var resolved := StructureBaker.resolved(plan)
	var boxes := StructureBaker.collect_colliders(_sealed_plan(resolved))
	if boxes.is_empty():
		return _enclosure_result(empty, "the plan draws nothing")

	## 1. The raster, and one column of solid spans per cell it touches.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var centre: Vector3 = box["center"]
		var reach := _box_reach(box)
		lo = Vector2(minf(lo.x, centre.x - reach.x), minf(lo.y, centre.z - reach.y))
		hi = Vector2(maxf(hi.x, centre.x + reach.x), maxf(hi.y, centre.z + reach.y))
	lo -= Vector2(CABIN_CELL_M, CABIN_CELL_M)
	hi += Vector2(CABIN_CELL_M, CABIN_CELL_M)
	var w := int(ceil((hi.x - lo.x) / CABIN_CELL_M)) + 1
	var h := int(ceil((hi.y - lo.y) / CABIN_CELL_M)) + 1
	var solid := {}
	for box_variant in boxes:
		_paint_column_spans(box_variant as Dictionary, solid, lo, w, h)

	## 2. The air between the solids. `air[column]` is [lo0, hi0, lo1, hi1, …] and
	## its last interval runs to INF — the sky.
	var air := {}
	var state := {}
	for key in solid.keys():
		var gaps := _air_intervals(solid[key] as PackedFloat32Array)
		air[key] = gaps
		var flags := PackedByteArray()
		flags.resize(gaps.size() / 2)
		state[key] = flags

	## 3. Flood the outside in.
	_flood_outside(air, state, w, h)

	## 4. What is left. Every group is measured; the report names the largest.
	var closures := _closure_points(resolved)
	var cabins := 0
	var best := empty.duplicate()
	var best_walled := empty.duplicate()
	for key in air.keys():
		var flags: PackedByteArray = state[key]
		for i in flags.size():
			if flags[i] != 0:
				continue
			var group := _enclosed_group(air, state, w, h, int(key), i)
			if float(group["area_m2"]) < CABIN_MIN_AREA_M2:
				continue
			if float(group["area_m2"]) > float(best_walled["area_m2"]):
				best_walled = group
			if not _has_closure(group["columns"] as Dictionary, closures, lo, w, group):
				continue
			cabins += 1
			if float(group["area_m2"]) > float(best["area_m2"]):
				best = group
	if cabins > 0:
		best["cabin"] = true
		best["cabins"] = cabins
		return _enclosure_result(best, "%.1f m2 of standable enclosed floor, y %.2f..%.2f" % [
			float(best["area_m2"]), float(best["floor_y"]), float(best["roof_y"])
		])
	if float(best_walled["area_m2"]) > 0.0:
		best_walled["cabins"] = 0
		return _enclosure_result(
			best_walled,
			"%.1f m2 is enclosed at y %.2f..%.2f but no door opens onto it"
				% [float(best_walled["area_m2"]), float(best_walled["floor_y"]),
					float(best_walled["roof_y"])],
		)
	return _enclosure_result(empty, "nothing the plan draws closes a volume over %.1f m2 %s" % [
		CABIN_MIN_AREA_M2, "with %.1f m of headroom" % CABIN_MIN_HEADROOM_M
	])


static func _enclosure_result(report: Dictionary, why: String) -> Dictionary:
	var out := report.duplicate()
	out.erase("columns")
	out["why"] = why
	return out


## One enclosed pocket, grown from `(column, interval)` through every neighbouring
## air interval whose span overlaps. `area_m2` counts only the columns with
## standing headroom — the eave of a sloped roof is part of the compartment and
## is not floor a person can use.
static func _enclosed_group(
	air: Dictionary, state: Dictionary, w: int, h: int, start_column: int, start_i: int
) -> Dictionary:
	var queue: Array[Vector2i] = [Vector2i(start_column, start_i)]
	(state[start_column] as PackedByteArray)[start_i] = 1
	var read_i := 0
	var columns := {}
	var standable := {}
	var y_lo := INF
	var y_hi := -INF
	while read_i < queue.size():
		var node: Vector2i = queue[read_i]
		read_i += 1
		var gaps: PackedFloat32Array = air[node.x]
		var y0 := gaps[node.y * 2]
		var y1 := gaps[node.y * 2 + 1]
		columns[node.x] = true
		if y1 - y0 >= CABIN_MIN_HEADROOM_M:
			standable[node.x] = true
		y_lo = minf(y_lo, y0)
		y_hi = maxf(y_hi, y1)
		var x := node.x % w
		var z := node.x / w
		for offset in CABIN_NEIGHBORS:
			var nx: int = x + offset.x
			var nz: int = z + offset.y
			if nx < 0 or nz < 0 or nx >= w or nz >= h:
				continue
			var n_column: int = nz * w + nx
			var n_gaps: Variant = air.get(n_column, null)
			if n_gaps == null:
				continue
			var n_spans: PackedFloat32Array = n_gaps
			var n_flags: PackedByteArray = state[n_column]
			for j in n_flags.size():
				if n_flags[j] != 0:
					continue
				if minf(y1, n_spans[j * 2 + 1]) - maxf(y0, n_spans[j * 2]) > 0.0:
					n_flags[j] = 1
					queue.append(Vector2i(n_column, j))
	return {
		"cabin": false, "cabins": 0,
		"area_m2": float(standable.size()) * CABIN_CELL_M * CABIN_CELL_M,
		"floor_y": y_lo, "roof_y": y_hi, "columns": columns,
	}


## Mark every air interval the sky reaches. `state` carries 1 for "reached", and
## the same byte is reused by `_enclosed_group` to mark a pocket already counted:
## once the flood is done, a 0 can only be enclosed air.
##
## ── THE SKY NEEDS NO SEED OF ITS OWN, and finding that out is why ──────────
##
## This used to seed the top interval of EVERY column as well — "the sky is
## outside" stated directly. Mutating that branch away was expected to redden
## the fence case and did not: `plan_enclosure_test` stayed green and all 18
## shipped fixtures plus 12 synthetic cases came back byte-identical. A mutation
## that passes is a finding (REALITY.md §8), and the finding here is that the
## branch could not fail, for a reason worth writing down rather than restoring:
##
##   every column's LAST interval runs to +INF, so the last intervals of two
##   neighbouring columns always overlap. The sky is therefore ONE connected
##   component across every column that has any structure in it, and the raster
##   is padded by a cell — so the columns just inside the padding always have a
##   structureless neighbour and always seed. One seed reaches all of it.
##
## The branch was deleted rather than kept as belt and braces, because a line
## that cannot fail is a line the next reader will believe is load-bearing.
static func _flood_outside(air: Dictionary, state: Dictionary, w: int, h: int) -> void:
	var queue: Array[Vector2i] = []
	for key in air.keys():
		var column := int(key)
		var x := column % w
		var z := column / w
		var flags: PackedByteArray = state[key]
		var open_side := x <= 0 or z <= 0 or x >= w - 1 or z >= h - 1
		if not open_side:
			for offset in CABIN_NEIGHBORS:
				## A column no box touches is open air from the deck to the sky, so
				## everything beside it is outside. Those columns are not in `air` at
				## all, which is why this asks rather than walking them.
				if not air.has((z + offset.y) * w + (x + offset.x)):
					open_side = true
					break
		if not open_side:
			continue
		for i in flags.size():
			if flags[i] == 0:
				flags[i] = 1
				queue.append(Vector2i(column, i))
	var read_i := 0
	while read_i < queue.size():
		var node: Vector2i = queue[read_i]
		read_i += 1
		var gaps: PackedFloat32Array = air[node.x]
		var y0 := gaps[node.y * 2]
		var y1 := gaps[node.y * 2 + 1]
		var x := node.x % w
		var z := node.x / w
		for offset in CABIN_NEIGHBORS:
			var nx: int = x + offset.x
			var nz: int = z + offset.y
			if nx < 0 or nz < 0 or nx >= w or nz >= h:
				continue
			var n_column: int = nz * w + nx
			var n_gaps: Variant = air.get(n_column, null)
			if n_gaps == null:
				continue
			var n_spans: PackedFloat32Array = n_gaps
			var n_flags: PackedByteArray = state[n_column]
			for i in n_flags.size():
				if n_flags[i] != 0:
					continue
				if minf(y1, n_spans[i * 2 + 1]) - maxf(y0, n_spans[i * 2]) > 0.0:
					n_flags[i] = 1
					queue.append(Vector2i(n_column, i))


## The gaps between a column's merged solid spans, above the plan's y = 0 plane.
## `spans` arrives as [lo, hi, lo, hi, …] sorted by `lo`.
static func _air_intervals(spans: PackedFloat32Array) -> PackedFloat32Array:
	var gaps := PackedFloat32Array()
	var cursor := 0.0
	var run_lo := 0.0
	var run_hi := -INF
	for i in spans.size() / 2:
		var lo := spans[i * 2]
		var hi := spans[i * 2 + 1]
		if run_hi > -INF and lo <= run_hi + CABIN_MERGE_M:
			run_hi = maxf(run_hi, hi)
			continue
		if run_hi > 0.0:
			if run_lo - cursor > CABIN_MERGE_M:
				gaps.append(cursor)
				gaps.append(run_lo)
			cursor = maxf(cursor, run_hi)
		run_lo = lo
		run_hi = hi
	if run_hi > 0.0:
		if run_lo - cursor > CABIN_MERGE_M:
			gaps.append(cursor)
			gaps.append(run_lo)
		cursor = maxf(cursor, run_hi)
	gaps.append(cursor)
	gaps.append(INF)
	return gaps


## Paint one collider box into the columns it covers, keeping the spans sorted by
## their bottom so `_air_intervals` needs no sort of its own. A column carries a
## handful of spans, so the insertion is cheaper than sorting 70 000 small arrays
## with a comparator — measured at 443 ms of the container feeder's 1.6 s before
## this was inlined.
static func _paint_column_spans(
	box: Dictionary, solid: Dictionary, lo: Vector2, w: int, h: int
) -> void:
	var centre: Vector3 = box["center"]
	var size: Vector3 = box["size"]
	var top := centre.y + size.y * 0.5
	## Everything below the deck plane is the hull, and the hull is the floor.
	if top <= 0.0:
		return
	var bottom := centre.y - size.y * 0.5
	var yaw := deg_to_rad(float(box.get("yaw_deg", 0.0)))
	var cs := cos(yaw)
	var sn := sin(yaw)
	var reach := _box_reach(box)
	## Half a cell, projected: a box is solid in every cell it OVERLAPS, so a
	## wall thinner than the raster still blocks. See CABIN_CELL_M.
	var pad := CABIN_CELL_M * 0.5 * (absf(cs) + absf(sn))
	var half_x := size.x * 0.5 + pad
	var half_z := size.z * 0.5 + pad
	var x0 := maxi(0, int(floor((centre.x - reach.x - lo.x) / CABIN_CELL_M)))
	var x1 := mini(w - 1, int(floor((centre.x + reach.x - lo.x) / CABIN_CELL_M)))
	var z0 := maxi(0, int(floor((centre.z - reach.y - lo.y) / CABIN_CELL_M)))
	var z1 := mini(h - 1, int(floor((centre.z + reach.y - lo.y) / CABIN_CELL_M)))
	for x in range(x0, x1 + 1):
		var px := lo.x + (float(x) + 0.5) * CABIN_CELL_M - centre.x
		for z in range(z0, z1 + 1):
			var pz := lo.y + (float(z) + 0.5) * CABIN_CELL_M - centre.z
			if absf(px * cs - pz * sn) > half_x or absf(px * sn + pz * cs) > half_z:
				continue
			var key := z * w + x
			if not solid.has(key):
				var first := PackedFloat32Array()
				first.append(bottom)
				first.append(top)
				solid[key] = first
				continue
			var spans: PackedFloat32Array = solid[key]
			var at := spans.size()
			while at >= 2 and spans[at - 2] > bottom:
				at -= 2
			## A Packed array held in a Dictionary is shared, not copied: the two
			## inserts below land in the dictionary's own array. Measured, because
			## copy-on-write makes the opposite equally plausible.
			spans.insert(at, bottom)
			spans.insert(at + 1, top)


## Half-extent of a yawed collider box in world XZ.
static func _box_reach(box: Dictionary) -> Vector2:
	var size: Vector3 = box["size"]
	var yaw := deg_to_rad(float(box.get("yaw_deg", 0.0)))
	var cs := absf(cos(yaw))
	var sn := absf(sin(yaw))
	return Vector2(
		size.x * 0.5 * cs + size.z * 0.5 * sn, size.x * 0.5 * sn + size.z * 0.5 * cs
	)


## Is a door or a window cut into the shell around this pocket?
static func _has_closure(
	columns: Dictionary, closures: Array, lo: Vector2, w: int, group: Dictionary
) -> bool:
	var floor_y := float(group["floor_y"])
	var roof_y := float(group["roof_y"])
	for closure_variant in closures:
		var at: Vector3 = (closure_variant as Dictionary)["at"]
		if at.y < floor_y or at.y > roof_y:
			continue
		var cx := int(floor((at.x - lo.x) / CABIN_CELL_M))
		var cz := int(floor((at.z - lo.y) / CABIN_CELL_M))
		for dx in range(-CABIN_ACCESS_CELLS, CABIN_ACCESS_CELLS + 1):
			for dz in range(-CABIN_ACCESS_CELLS, CABIN_ACCESS_CELLS + 1):
				if columns.has((cz + dz) * w + (cx + dx)):
					return true
	return false


# ── Does the roof meet the wall it sits on? ─────────────────────────────────

## The pieces whose top edge is a WALL HEAD — the joint a roof lands on. A
## `deck_tile` and a `roof_slope` are roofs, not walls; a `trim_band` has no
## height and cannot rake.
const ROOF_WALL_PIECES: Array[String] = ["wall_panel", "wall_glazed", "corner_45"]
## Stations along a wall head, taken between 0.15 and 0.85 of its run. The ends
## belong to whatever is butted against them, and a neighbour's collider standing
## at the corner would answer for a roof that is not there.
const ROOF_STATIONS := 9
const ROOF_FIRST_STATION := 0.15
const ROOF_LAST_STATION := 0.85
## Two floats computed by different expressions meeting at a joint. Flush within
## this is flush; a boundary sample is otherwise a coin toss.
const ROOF_FLUSH_M := 0.02
## How far PAST the wall's own lean the "is this wall roofed at all" reference
## stands. Quarter of a cell inboard of the foot line: inside the compartment at
## any rake, and far enough in that a roof edge landing exactly on the foot line
## still answers yes.
##
## Measured from the head and from the wall's DECLARED rake, not from the head
## plate's own bottom corners — a `wall_glazed`'s highest plate is its HEADER,
## whose bottom edge is the top of the glass band and not the wall's foot at all.
## Taking the reference from there put it 0.35 m inboard of a head that needed
## 0.75, and the reading went silent on `critic_coaster`'s wheelhouse front with
## its roof strip deleted — a mutation that PASSED, which is a finding and not a
## relief (REALITY standing order 8).
const ROOF_REF_INBOARD_M := 0.25
## A `corner_45` head moves along its facet's diagonal, so a rake of r eighth-
## cells displaces it by r * 0.125 * sqrt(2) rather than r * 0.125.
const ROOF_DIAGONAL := 1.4142135623730951
const ROOF_BISECT_STEPS := 8

## Every raked wall piece whose roof stops short of its own head, as
## `[{piece, id, rake, short_m, at, stations}, …]`, worst first. Empty for a plan
## with no placements — nothing else in the format can express this.
##
## ── The defect, and what the constraint actually is ─────────────────────────
##
## A raked wall's TOP EDGE stands `rake * 0.125 m` outboard of its foot, because
## `rake` is counted in EIGHTH-cells. A `deck_tile`'s edges land only on the
## 0.5 m node lattice: `span` and `depth` are whole cells and `lift` moves the
## tile in Y, never in Z. So a roof edge is FLUSH with a raked wall head at
## `rake` multiples of 4 and at no other value.
##
## THAT IS NOT THE CONSTRAINT, and reading it as one costs the kit twelve of its
## seventeen rake values for nothing. Flush is not required — a roof that
## OVERHANGS the head seals just as well, and the kit's own `deck_tile` text
## calls that overhang the EAVE. Swept over the whole rake set against eaves of
## 0, 1 and 2 cells, four wall heights, three `head` trims and two ring sizes
## (`tests/plan_roof_seal_test.gd`), the answer is one inequality and nothing
## else moves it:
##
##     gap = max(0, rake * 0.125 - eave_cells * 0.5)
##
## So one cell of eave carries rake 1..4, two cells carry 5..8, and a NEGATIVE
## rake — the head tumbling home — needs no eave at all. `height`, `head` and
## `span` change nothing: the lean is in plan, and Y is reachable at every
## eighth-cell because `deck_tile.lift` counts the same unit the wall's `head`
## does.
##
## Measured on a shipped fixture rather than only on a synthetic ring:
## `critic_coaster` seals at rake 1, 2, 3 AND 4 with its roof untouched, and
## first opens at rake 5 by 0.126 m (`tests/_roof_gap_inventory.gd`). Its
## wheelhouse front is authored at +4 on the record that "+2 was blocked"; +2 is
## not blocked and never was.
##
## Named limit, because it decides which houses can take a one-cell eave from a
## SINGLE tile: `deck_tile.span` is a declared set {1,2,3,4,6,8,12,16} and holds
## no 10, so a ring 3, 6, 8 or 12 cells wide cannot be roofed one cell larger all
## round by one tile. It can be by two — a `depth 1` strip laid over the head,
## which is exactly what `critic_coaster` does — so this is a convenience limit
## and not a blocker.
##
## What that leaves is a COMPOSITION fault between two placements, which no
## per-piece constraint can see — a piece's constraints are expressions over its
## OWN parameters, and the roof is a different placement. It cannot be refused at
## the piece, and it must not be prevented by deleting rake values that work.
## So it is measured, on the boxes the plan actually draws, and the builder is
## told which wall and by how much.
##
## ── The reading ─────────────────────────────────────────────────────────────
##
## For each station on the head: is the column at the head open to the sky? If
## the column one lean plus a quarter-cell further inboard is NOT open, the wall
## is roofed and its head should be too — the distance between the two is the
## wedge, bisected. If that reference is open as well, nothing roofs this wall
## (a bulwark, a coaming, an open tier) and that is not this defect.
##
## The wall's OWN boxes are excluded, by the ids its placement resolved into, so
## a wall cannot answer for its own head.
static func roof_gaps(plan: StructurePlan) -> Array:
	if plan == null or plan.pieces.is_empty():
		return []
	var resolved := StructureBaker.resolved(plan)
	## One flat list, each box tagged with the item that drew it, so a wall can be
	## excluded from the reading of its own head by INDEX rather than by rebuilding
	## the list per wall — which on `probe_piece_trawler` was 32 copies of two
	## thousand boxes and most of this function's cost.
	var all_boxes: Array = []
	var owners := PackedInt32Array()
	for row_variant in StructureBaker.entity_colliders(_sealed_plan(resolved)):
		var row := row_variant as Dictionary
		var owner := int(row["id"]) if str(row["kind"]) == "item" else -1
		for box_variant in row["boxes"] as Array:
			all_boxes.append(box_variant)
			owners.append(owner)

	## The ids each placement resolved into, replaying `resolve_document`'s own
	## counter — an id is an address the plan does not guarantee unique
	## (REALITY §4b), so this walks the placements in order rather than matching.
	var next_id := 1
	for item_variant in plan.items:
		if item_variant is Dictionary:
			next_id = maxi(next_id, int((item_variant as Dictionary).get("id", 0)) + 1)
	var out: Array = []
	for placement_variant in plan.pieces:
		var placement := placement_variant as Dictionary
		var result := PieceKit.resolve_placement(placement, next_id)
		var own := {}
		for item_variant in result["items"] as Array:
			own[int((item_variant as Dictionary)["id"])] = true
		next_id = int(result["next_id"])
		if not ROOF_WALL_PIECES.has(str(placement.get("piece", ""))):
			continue
		var head := _piece_head(result["items"] as Array)
		if head.size() != 4:
			continue
		## Only what can possibly answer: standing at or above the head, and within
		## reach of it in plan. One pass over the boxes per wall instead of a copy.
		var mid := (head[0] + head[1] + head[2] + head[3]) * 0.25
		## The pad has to clear the furthest the reading can sample: the widest
		## legal lean (rake 8 on a diagonal facet, 1.414 m) plus the reference
		## inset, with a cell of slack.
		var span := maxf(
			(head[3] - head[2]).length(), (head[2] - head[1]).length()
		) * 0.5 + 8.0 * 0.125 * ROOF_DIAGONAL + ROOF_REF_INBOARD_M + 0.5
		var head_y := maxf(head[2].y, head[3].y)
		var boxes: Array = []
		for index in all_boxes.size():
			if own.has(owners[index]):
				continue
			var box := all_boxes[index] as Dictionary
			var centre: Vector3 = box["center"]
			var size: Vector3 = box["size"]
			if centre.y + size.y * 0.5 < head_y - ROOF_FLUSH_M:
				continue
			var reach := _box_reach(box)
			if absf(centre.x - mid.x) > span + reach.x:
				continue
			if absf(centre.z - mid.z) > span + reach.y:
				continue
			boxes.append(box)
		var rake := _piece_rake(placement)
		var lean := absf(float(rake)) * 0.125 * (
			ROOF_DIAGONAL if str(placement.get("piece", "")) == "corner_45" else 1.0
		)
		var gap := _head_gap(
			boxes, head, float(placement.get("facing", 0)),
			lean + ROOF_REF_INBOARD_M,
		)
		if float(gap["short_m"]) <= 0.0:
			continue
		gap["piece"] = str(placement.get("piece", ""))
		gap["id"] = placement.get("id", -1)
		gap["rake"] = rake
		out.append(gap)
	out.sort_custom(func(a, b): return float(a["short_m"]) > float(b["short_m"]))
	return out


## The four corners, in plan metres, of the placement's HIGHEST plate — indices
## 2 and 3 are its top edge. Taken off the items the placement ALREADY resolved
## into, so this costs no second resolve; `PieceKit.placed_corners` re-resolves
## the whole placement per step, which on a seven-plate `wall_glazed` is seven.
##
## The highest plate and not the first: `wall_glazed`'s first plate is its
## COAMING, and measuring a ribbon window's sill against the roof would report a
## whole wheelhouse of gaps that are not there.
static func _piece_head(items: Array) -> PackedVector3Array:
	var best := PackedVector3Array()
	var best_y := -INF
	for item_variant in items:
		var item := item_variant as Dictionary
		var props := item["props"] as Dictionary
		var raw: Variant = props.get("corners", null)
		if not (raw is Array) or (raw as Array).size() != 4:
			continue
		var xform := Transform3D(
			Basis.from_euler(
				Vector3(0.0, deg_to_rad(float(item["yaw"])), 0.0), EULER_ORDER_YXZ
			),
			StructurePlan.vec3_of(item["at"]),
		)
		var corners := PackedVector3Array()
		for triple_variant in raw as Array:
			var triple := triple_variant as Array
			corners.append(xform * Vector3(
				float(triple[0]), float(triple[1]), float(triple[2])
			))
		var y := maxf(corners[2].y, corners[3].y)
		if y > best_y:
			best_y = y
			best = corners
	return best


static func _piece_rake(placement: Dictionary) -> int:
	var params: Dictionary = (
		placement.get("params", {}) as Dictionary
		if placement.get("params") is Dictionary else {}
	)
	var worst := 0
	for key in ["rake", "rake_a", "rake_b"]:
		if not params.has(key):
			continue
		var value := roundi(float(params[key]))
		if absi(value) > absi(worst):
			worst = value
	return worst


## {short_m, at, stations} for one wall head. `short_m` is 0.0 when every station
## is either sealed or standing under open sky with nothing roofing the wall.
static func _head_gap(
	boxes: Array, head: PackedVector3Array, facing: float, reach: float
) -> Dictionary:
	var inboard := Basis.from_euler(
		Vector3(0.0, deg_to_rad(facing), 0.0), EULER_ORDER_YXZ
	) * Vector3(0.0, 0.0, 1.0)
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var open := 0
	for index in ROOF_STATIONS:
		var t := ROOF_FIRST_STATION + (ROOF_LAST_STATION - ROOF_FIRST_STATION) * (
			(float(index) + 0.5) / float(ROOF_STATIONS)
		)
		var top := head[2].lerp(head[3], t)
		if _covered(boxes, top):
			continue
		## Past the wall's own lean and a quarter-cell further: air that belongs to
		## the compartment this wall encloses, whichever way the head leans.
		var reference := top + inboard * reach
		if not _covered(boxes, reference):
			continue
		open += 1
		var near := top
		var far := reference
		for _step in ROOF_BISECT_STEPS:
			var mid := (near + far) * 0.5
			if _covered(boxes, mid):
				far = mid
			else:
				near = mid
		var short := Vector2(far.x - top.x, far.z - top.z).length()
		if short > worst:
			worst = short
			worst_at = top
	if worst <= ROOF_FLUSH_M:
		return {"short_m": 0.0, "at": Vector3.ZERO, "stations": 0}
	return {"short_m": worst, "at": worst_at, "stations": open}


## Is anything at or above this point in its own column? The question is "is this
## open to the sky", so a box that CONTAINS the point counts exactly as much as
## one standing over it — which also makes the answer independent of how thick a
## roof plate is and of whether its slab is centred on the surface it draws.
static func _covered(boxes: Array, p: Vector3) -> bool:
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var centre: Vector3 = box["center"]
		var size: Vector3 = box["size"]
		if centre.y + size.y * 0.5 < p.y:
			continue
		var yaw := deg_to_rad(float(box.get("yaw_deg", 0.0)))
		var dx := p.x - centre.x
		var dz := p.z - centre.z
		var cs := cos(yaw)
		var sn := sin(yaw)
		if absf(dx * cs - dz * sn) > size.x * 0.5:
			continue
		if absf(dx * sn + dz * cs) > size.z * 0.5:
			continue
		return true
	return false


## The plan with every door and window filled back in, so the enclosure reading
## sees the shell rather than the holes cut through it. See the header on
## `enclosure`. Nothing is duplicated that does not change: an entity with no
## closures is passed through by reference.
static func _sealed_plan(plan: StructurePlan) -> StructurePlan:
	var out := StructurePlan.new()
	out.context = plan.context
	out.hull_id = plan.hull_id
	out.hull = plan.hull
	out.palette = plan.palette
	out.edges = plan.edges
	out.stairs = plan.stairs
	out.walls = _sealed_entities(plan.walls)
	out.decks = _sealed_entities(plan.decks)
	out.items = _sealed_items(plan.items)
	return out


static func _sealed_entities(collection: Array) -> Array:
	var out: Array = []
	for raw in collection:
		if not (raw is Dictionary):
			continue
		var entity := raw as Dictionary
		var openings: Variant = entity.get("openings", [])
		if not (openings is Array):
			out.append(entity)
			continue
		var kept := _holes_only(openings as Array)
		if kept.size() == (openings as Array).size():
			out.append(entity)
			continue
		var copy := entity.duplicate(false)
		copy["openings"] = kept
		out.append(copy)
	return out


static func _sealed_items(collection: Array) -> Array:
	var out: Array = []
	for raw in collection:
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		var props: Variant = item.get("props", null)
		if not (props is Dictionary):
			out.append(item)
			continue
		var openings: Variant = (props as Dictionary).get("openings", null)
		if not (openings is Array):
			out.append(item)
			continue
		var kept := _holes_only(openings as Array)
		if kept.size() == (openings as Array).size():
			out.append(item)
			continue
		var copy := item.duplicate(false)
		var sealed_props := (props as Dictionary).duplicate(false)
		sealed_props["openings"] = kept
		copy["props"] = sealed_props
		out.append(copy)
	return out


static func _holes_only(openings: Array) -> Array:
	var out: Array = []
	for raw in openings:
		if not (raw is Dictionary):
			continue
		if not _is_closure(raw as Dictionary):
			out.append(raw)
	return out


## A door or a window is a fitted leaf and a pane; a hole and a stairwell are
## holes. The format's own four names, used as the format uses them. This is the
## SEALING question — what closes the weather envelope.
static func _is_closure(opening: Dictionary) -> bool:
	var type := str(opening.get("type", StructurePlan.OPENING_DOOR))
	return type == StructurePlan.OPENING_DOOR or type == StructurePlan.OPENING_WINDOW


## ...and this is the ACCESS question, which is NOT the same one: a window seals
## the envelope and is not a way in. The two were one predicate until an
## adversarial pass (`tests/_enclosure_adversary.gd`) drew a 1.6 x 1.6 x 5 m
## funnel trunk with a 0.4 m scuttle in it and got a cabin out of it. Splitting
## them refuses that and costs nothing measurable: over all 18 shipped fixtures
## the same 10 report a cabin, with the same areas to 0.1 m², because a
## deckhouse a person uses has a door in it. A wheelhouse whose only opening is
## glazing is now refused, and that is the intended reading — you cannot get into
## it.
static func _is_way_in(opening: Dictionary) -> bool:
	return str(opening.get("type", StructurePlan.OPENING_DOOR)) == StructurePlan.OPENING_DOOR


## Where every door and window the plan cuts stands, in plan metres. Walls carry
## theirs on the run; a plate carries them in its own parametric space, which is
## the only place they can be — a raked deckhouse front is not a vertical
## rectangle and `plate_point` is the baker's own resolution of that surface.
static func _closure_points(plan: StructurePlan) -> Array:
	var out: Array = []
	for raw in plan.walls:
		if not (raw is Dictionary):
			continue
		var wall := raw as Dictionary
		var start := StructurePlan.vec3_of(wall.get("start"))
		var run := StructurePlan.wall_run(str(wall.get("axis", "x")))
		for opening_variant in wall.get("openings", []) as Array:
			if not (opening_variant is Dictionary):
				continue
			var opening := opening_variant as Dictionary
			if not _is_way_in(opening):
				continue
			out.append({"at": start + run * _closure_u(opening) + Vector3(
				0.0, _closure_v(opening), 0.0
			)})
	for raw in plan.items:
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		var openings: Variant = props.get("openings", null)
		if not (openings is Array) or (openings as Array).is_empty():
			continue
		var corners := StructureBaker.plate_corners(props)
		if corners.size() != 4:
			continue
		var ref := StructureBaker.plate_ref_lengths(corners)
		if ref.x <= 0.0 or ref.y <= 0.0:
			continue
		var xform := plan.item_transform(item)
		for opening_variant in openings as Array:
			if not (opening_variant is Dictionary):
				continue
			var opening := opening_variant as Dictionary
			if not _is_way_in(opening):
				continue
			out.append({"at": xform * StructureBaker.plate_point(
				corners,
				clampf(_closure_u(opening) / ref.x, 0.0, 1.0),
				clampf(_closure_v(opening) / ref.y, 0.0, 1.0),
			)})
	return out


static func _closure_u(opening: Dictionary) -> float:
	return float(opening.get("offset", 0.0)) + float(opening.get("width", 1.0)) * 0.5


static func _closure_v(opening: Dictionary) -> float:
	var type := str(opening.get("type", StructurePlan.OPENING_DOOR))
	var sill := float(opening.get("sill", 1.0 if type == StructurePlan.OPENING_WINDOW else 0.0))
	var height := float(opening.get(
		"height", 2.2 if type == StructurePlan.OPENING_DOOR else 1.2
	))
	return sill + height * 0.5


## Every opening of `type` the plan cuts — on a wall, on a deck, or in a PLATE
## item.
##
## ── The third collection, and why it was missing ────────────────────────────
##
## This walked `walls` and `decks` only. `_closure_points` — the other reading of
## the same drawing, forty lines up — walks walls AND item plates, because that
## is where the openings ARE on anything built out of the piece kit: a
## `wall_panel` with `opening: "door"` resolves into an `items[]` plate carrying
## `props.openings`, and no `walls[]` entry is ever written. So the two readings
## of one drawing disagreed, which is REALITY §4a: `enclosure` counted the door
## and said "cabin", `opening_count` did not and said "doors: 0".
##
## Measured over the shipped fleet: `probe_piece_house`, `probe_piece_trawler`,
## `probe_piece_tug`, `probe_container_feeder` and `critic_coaster` all reported
## `has_cabin = true` with `doors = 0`. The `passenger_vessel` licence carries
## BOTH — `cabin` (capability) and `egress` (`doors >= 1`) — so a piece-built
## passenger vessel passed the cabin rule and failed the egress rule with two
## real doors drawn in it, and the studio's advice sent the builder to cut a door
## they had already cut.
##
## An item is counted only when it DRAWS AS A PLATE, which is the same test
## `_closure_points` uses: a fitting from the parts catalogue is a part, and door
## FITTINGS are counted separately in `_validate_built` off the catalogue's
## `door` tag. Nothing is counted twice — a plate is not in the catalogue and a
## catalogue part draws no `props.openings`.
##
## RESOLVED FIRST, for the same reason `entity_colliders` is: a piece placement
## measured as the node it stands on is measured as nothing. `resolved()` returns
## its argument untouched when there are no placements, so the path
## `_validate_built` takes — which hands in an already-resolved plan — pays for a
## null check. Without it `door_count` on an AUTHORED piece plan answers 0 for
## the same reason this whole function was wrong, one level further out.
static func opening_count(plan: StructurePlan, type: String) -> int:
	if plan == null:
		return 0
	plan = StructureBaker.resolved(plan)
	var n := 0
	for collection in [plan.walls, plan.decks]:
		for raw in collection as Array:
			if not (raw is Dictionary):
				continue
			n += _openings_of_type((raw as Dictionary).get("openings", []), type)
	for raw in plan.items:
		if not (raw is Dictionary):
			continue
		var item := raw as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		n += _openings_of_type(
			StructurePlan.item_props(item).get("openings", []), type
		)
	return n


static func _openings_of_type(openings: Variant, type: String) -> int:
	if not (openings is Array):
		return 0
	var n := 0
	for raw in openings as Array:
		if not (raw is Dictionary):
			continue
		if str((raw as Dictionary).get("type", "")) == type:
			n += 1
	return n


## Doors drawn into the structure. Door FITTINGS are counted separately in
## `validate`, because a door item is a part and this function is geometry only.
static func door_count(plan: StructurePlan) -> int:
	return opening_count(plan, StructurePlan.OPENING_DOOR)


# ── Item geometry ───────────────────────────────────────────────────────────

## The deck cell an item stands in. This is the only place a float plan
## position becomes an integer cell, and it is lossy on purpose: the rules that
## want a cell (`brick_side`, `white_above_sidelights`) want the coarse answer.
static func item_cell(plan: StructurePlan, item: Dictionary, grid: DeckGrid) -> Vector3i:
	if plan == null or grid == null:
		return Vector3i.ZERO
	return StructurePlan.plan_to_cell(plan.item_transform(item).origin, grid)


## Deck cells (y = 0) the item's own geometry covers, in plan space. Empty when
## the part is unknown or expands to nothing.
##
## A cell counts when its CENTRE lies under the part. Cover-any-overlap was the
## first cut and it charged a 4 × 8 m hold for 45 m² of deck, because a 0.12 m
## coaming skin reached across two more cell boundaries. Nobody should pay a
## cell for a skin, and centre-in-box is the same rule a rasteriser uses for
## area.
##
## "Under the part" means under the part's own SHADOW — the XZ projection of the
## rotated box, a convex polygon — never the world-axis-aligned box around it.
## The AABB reading re-quantised the free rotation the item schema exists to
## allow: measured against this same 8 × 4 m hold, it charged 128 cells at yaw 0,
## 216 at 15° (the catalog's own default yaw_step), and 324 at 45° — 2.53× the
## deck it covers, for turning it. A rule that fines a builder for an angle hands
## the quantisation straight back, so the shadow is what is measured. Yaw 0 and
## 90 are unchanged by construction: there the shadow IS the AABB.
static func item_footprint_cells(
	plan: StructurePlan, item: Dictionary, grid: DeckGrid
) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if plan == null or grid == null:
		return out
	var corners := PackedVector2Array()
	for point in item_world_points(plan, item):
		corners.append(Vector2(point.x, point.z))
	if corners.is_empty():
		return out
	var shadow := _shadow_hull(corners)
	var lo := Vector2.INF
	var hi := -Vector2.INF
	for point in shadow:
		lo = lo.min(point)
		hi = hi.max(point)
	var cell_lo := StructurePlan.plan_to_cell(Vector3(lo.x, 0.0, lo.y), grid)
	var cell_hi := StructurePlan.plan_to_cell(Vector3(hi.x, 0.0, hi.y), grid)
	var m := WorldUnits.DECK_CELL_M
	for ix in range(cell_lo.x, cell_hi.x + 1):
		for iz in range(cell_lo.z, cell_hi.z + 1):
			var center := Vector2((float(ix) + 0.5) * m, (float(iz) + 0.5) * m)
			if _shadow_covers(shadow, center):
				out.append(Vector3i(ix, 0, iz))
	return out


## Convex hull of the projected corners (Andrew's monotone chain), in the XZ
## plane — Vector2(x, z). Collinear points are dropped, so a shadow with no area
## degenerates honestly to two points or one rather than pretending to be a
## polygon.
static func _shadow_hull(points: PackedVector2Array) -> PackedVector2Array:
	var sorted: Array[Vector2] = []
	for point in points:
		sorted.append(point)
	sorted.sort_custom(
		func(a: Vector2, b: Vector2) -> bool:
			return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	var hull := PackedVector2Array()
	for half in 2:
		var start := hull.size()
		var order := range(sorted.size()) if half == 0 else range(sorted.size() - 1, -1, -1)
		for i in order:
			var point: Vector2 = sorted[i]
			while (
				hull.size() - start >= 2
				and _cross(hull[hull.size() - 2], hull[hull.size() - 1], point) <= SHADOW_EPS
			):
				hull.remove_at(hull.size() - 1)
			hull.append(point)
		hull.remove_at(hull.size() - 1)
	if hull.size() == 2 and hull[0].is_equal_approx(hull[1]):
		hull.remove_at(1)
	return hull


## Does the shadow cover this point? Boundary counts, matching the inclusive
## bounds the AABB reading used. A degenerate shadow (a line, a point) has no
## area and covers a cell centre only when the centre lies exactly on it.
static func _shadow_covers(hull: PackedVector2Array, point: Vector2) -> bool:
	var n := hull.size()
	if n == 0:
		return false
	if n == 1:
		return hull[0].distance_squared_to(point) <= SHADOW_EPS
	if n == 2:
		if absf(_cross(hull[0], hull[1], point)) > SHADOW_EPS:
			return false
		var along := (point - hull[0]).dot(hull[1] - hull[0])
		return along >= -SHADOW_EPS and along <= hull[0].distance_squared_to(hull[1]) + SHADOW_EPS
	## Orientation-agnostic: inside means every edge turns the same way.
	var lo := INF
	var hi := -INF
	for i in n:
		var side := _cross(hull[i], hull[(i + 1) % n], point)
		lo = minf(lo, side)
		hi = maxf(hi, side)
	return lo >= -SHADOW_EPS or hi <= SHADOW_EPS


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


## Conservative box around a part's own expanded geometry, in part-local metres.
## Returns { ok, min, max, errors, warnings }. It reads the resolved primitive
## specs, so a part that grows with a `$length` parameter grows here too — the
## footprint cannot be inflated by a prop the geometry does not honour, and a
## prop that names no parameter comes back in `warnings` instead of vanishing.
static func part_local_aabb(part_id: String, props: Dictionary = {}) -> Dictionary:
	var result := Parts.expand_props(part_id, props)
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	var warnings: PackedStringArray = result.get("warnings", PackedStringArray())
	var specs: Array = result.get("specs", [])
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var any := false
	for spec_raw in specs:
		var spec := spec_raw as Dictionary
		var def: Dictionary = Parts.PRIMITIVES.get(str(spec.get("primitive", "")), {})
		var fields: Dictionary = def.get("fields", {})
		var points: Array[Vector3] = []
		var inflate := 0.0
		var rise := 0.0
		for key in fields.keys():
			var name := str(key)
			if not spec.has(name):
				continue
			match str(fields[name]):
				"point":
					points.append(spec[name] as Vector3)
				"points":
					for point in spec[name] as PackedVector3Array:
						points.append(point)
				"scalar":
					var value := absf(float(spec[name]))
					if AABB_INFLATE_XZ.has(name):
						inflate = maxf(inflate, value * float(AABB_INFLATE_XZ[name]))
					if AABB_EXTEND_UP.has(name):
						rise = maxf(rise, value)
		## A tapered spar is widest at its far end.
		if spec.has("taper"):
			inflate *= maxf(float(spec["taper"]), 1.0)
		for point in points:
			any = true
			lo = lo.min(point - Vector3(inflate, 0.0, inflate))
			hi = hi.max(point + Vector3(inflate, rise, inflate))
	if not any:
		return {
			"ok": false, "min": Vector3.ZERO, "max": Vector3.ZERO,
			"errors": errors, "warnings": warnings,
		}
	return {"ok": true, "min": lo, "max": hi, "errors": errors, "warnings": warnings}


## Props keys that name a declared parameter of the part. Anything else in the
## bag (colour region, label, whatever a later feature adds) is not a parameter
## and must not make `expand_checked` fail — but it must not be swallowed
## either, which is why the catalog does the filtering and reports what it
## dropped. Use `prop_warnings()` for the report; this returns the values only.
static func param_overrides(part_id: String, props: Dictionary) -> Dictionary:
	return Parts.params_from_props(part_id, props)["params"] as Dictionary


## What `param_overrides` had to reject, in the builder's words. A numeric prop
## naming no parameter is a typo — it used to resolve to the default in total
## silence, because filtering the key also swallowed `expand_checked`'s own
## "no parameter X" error.
static func prop_warnings(part_id: String, props: Dictionary) -> PackedStringArray:
	return Parts.params_from_props(part_id, props)["warnings"] as PackedStringArray


## Highest point the plan reaches, in deck-grid cells above the deck plane.
static func max_stack_cells(plan: StructurePlan, grid: DeckGrid) -> int:
	if plan == null:
		return 0
	var top := 0.0
	for raw in plan.walls:
		var wall := raw as Dictionary
		top = maxf(top, StructurePlan.vec3_of(wall.get("start")).y + float(wall.get("height", 0.0)))
	for raw in plan.decks:
		top = maxf(top, StructurePlan.vec3_of((raw as Dictionary).get("origin")).y)
	for raw in plan.stairs:
		var stair := raw as Dictionary
		top = maxf(
			top, StructurePlan.vec3_of(stair.get("start")).y + float(stair.get("height", 0.0))
		)
	for raw in plan.items:
		var item := raw as Dictionary
		## The item's own points are already in PLAN space, so this reads the
		## drawn top directly. The old line added a LOCAL reach to a WORLD origin,
		## which is only the same number while the item is unpitched and unrolled.
		top = maxf(top, plan.item_transform(item).origin.y)
		for point in item_world_points(plan, item):
			top = maxf(top, point.y)
	return int(floor(maxf(top, 0.0) / WorldUnits.DECK_CELL_M))


# ── Internals ───────────────────────────────────────────────────────────────

static func _is_over_deck(plan: StructurePlan, item: Dictionary, grid: DeckGrid) -> bool:
	return grid.has_deck_cell(item_cell(plan, item, grid))


static func _empty_slots() -> Dictionary:
	## Same keys VesselOutfit publishes — the zone lists stay empty because a
	## plan has no container pads or bulk-hold zones; its holds are items.
	return {
		"fishing": [],
		"helm": [],
		"crane": [],
		"tow": [],
		"cargo_item_ids": [],
		"container_pad_indices": [],
		"cargo_zone_indices": [],
		"bulk_hold_indices": [],
	}


static func _slot_label(slot: String) -> String:
	match slot:
		"fishing":
			return "Fishing"
		"helm":
			return "Helm"
		"crane":
			return "Crane"
		"tow":
			return "Tow gear"
	return slot.capitalize()


## Mirrors VesselOutfit._take_slots, including its message, so an over-budget
## plan and an over-budget brick layout tell the builder the same thing.
static func _take_slots(
	candidates: Array,
	max_n: int,
	accepted: Array,
	errors: PackedStringArray,
	label: String,
) -> void:
	for i in range(candidates.size()):
		if accepted.size() < max_n:
			accepted.append(candidates[i])
		else:
			errors.append(
				"%s exceeds hull budget (%d / %d). Remove extras — only accepted mounts go live."
				% [label, candidates.size(), max_n]
			)
			return


static func _result(
	ok: bool,
	errors: PackedStringArray,
	warnings: PackedStringArray,
	budget: Dictionary,
	usage: Dictionary,
	accepted_slots: Dictionary,
	capabilities: Dictionary,
) -> Dictionary:
	return {
		"ok": ok,
		"errors": errors,
		"warnings": warnings,
		"budget": budget,
		"usage": usage,
		"accepted_slots": accepted_slots,
		"capabilities": capabilities,
	}
