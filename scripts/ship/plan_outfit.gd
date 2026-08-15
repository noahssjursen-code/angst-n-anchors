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
## `has_cabin` is NOT measurable right now and is reported false for every plan.
## It used to mean "the plan contains a room", because the room primitive was
## the plan's own declaration of enclosure — it expanded to walls + floor +
## ceiling and `open_faces` named the sides that were missing. The room
## primitive was deleted (2026-08-10): it could only draw a box, so every
## deckhouse built from one came out a shed. Nothing that survives it declares
## enclosure, and the one thing this function must never do is go back to
## inferring a cabin from loose walls. The brick-era rule was
## `door_n >= 1 or wall_n >= 8`, which passes on eight roofless walls — a fence
## sold as accommodation, and the regression `plan_compliance_test` still pins.
## The wave that lands the sloped-plate primitive re-derives enclosure from it;
## until then a licence that requires a cabin cannot be met by a plan, and that
## refusal is honest rather than a wrong yes.
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
##     +4.000 m  critic_barge            deck plate outboard of the side
##     +2.000 m  critic_yacht            deck plate outboard of the side
##     +0.683 m  probe_trawler_bulwark   bow cap rail / stem head cap
##     +0.580 m  demo_workboat           davit block
##     +0.220 m  probe_ferry_catamaran_trim  rubbing strake, forward
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
	var capabilities := {
		"cargo_cells": accepted_cells.size(),
		"cargo_budget": cargo_max,
		"exposed_deck_cells": int(budget.get("exposed_deck_cells", 0)),
		"has_cabin": has_cabin(plan),
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
		"cabins": 0,
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

## No plan primitive declares enclosure since the room primitive was deleted, so
## this is false for every plan — deliberately, and see the header. Do NOT make
## it true by counting walls: a fence with a gate in it is not accommodation.
static func has_cabin(_plan: StructurePlan) -> bool:
	return false


## Every opening of `type` on a wall or a deck.
static func opening_count(plan: StructurePlan, type: String) -> int:
	if plan == null:
		return 0
	var n := 0
	for collection in [plan.walls, plan.decks]:
		for raw in collection as Array:
			if not (raw is Dictionary):
				continue
			var openings: Variant = (raw as Dictionary).get("openings", [])
			if not (openings is Array):
				continue
			for opening_raw in openings as Array:
				if not (opening_raw is Dictionary):
					continue
				if str((opening_raw as Dictionary).get("type", "")) == type:
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
