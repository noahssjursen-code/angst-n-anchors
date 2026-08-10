class_name PlanOutfit
extends RefCounted

## Measures a StructurePlan the way VesselOutfit measures a BrickLayout, so the
## registration rule evaluator in VesselCompliance can judge a Structure Studio
## ship. Nothing here is vessel-specific: a plan is a plan, and every quantity
## below is read off geometry or off the part catalog, never off a ship type.
##
## ── Why this file exists ────────────────────────────────────────────────────
##
## `DeckFitout.apply_plan` returns a hardcoded `{"outfit_ok": true}` and never
## calls a validator, while persistence and deployment run `BrickLayout.from_dict`
## on a plan dict, get an empty layout, fail the helm rule and refuse. So a plan
## ship can be drawn and can be neither saved, spawned, crewed nor sold.
##
## The rule evaluator itself needs NO changes. All ten kinds in
## `VesselCompliance._evaluate_rule` read five dictionaries — `brick_counts`,
## `tag_counts`, `positions`, `capacity`, `max_ratings` — plus the
## VesselOutfit-shaped `accepted_slots` / `usage` / `capabilities`. This file
## populates exactly those, from `plan.items` and the plan's rooms/walls/decks.
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
## `has_cabin` and `doors` are enclosure facts, and a plan draws enclosure. The
## brick-era `has_cabin` was `door_n >= 1 or wall_n >= 8`, which passes on eight
## roofless walls — a fence sold as accommodation. Here a cabin is a ROOM
## (see `cabin_rooms`), because a room is the plan's declaration of enclosure:
## it expands to walls + floor + ceiling, and `open_faces` names the sides that
## are missing. Loose walls carry no roof and never make a cabin on their own.
##
## ── Scale (CONVENTIONS §3a) ─────────────────────────────────────────────────
##
## One world unit is one metre. Plan coordinates are metres; deck-grid cells are
## `WorldUnits.DECK_CELL_M` (0.5 m) and exist only because the cell-counting
## rules (`brick_side`, `white_above_sidelights`, cargo area) are written in
## cells. `StructurePlan.plan_to_cell` is the only converter used.

## A cabin is a space a 1.8 m person can stand in — the same figure every
## capture carries.
const CABIN_MIN_HEADROOM_M := 1.8
## Two square metres: enough floor for one person to be inside rather than under.
const CABIN_MIN_FLOOR_M2 := 2.0
## A corridor is a room with both ends open (StructurePlan). Through-passage is
## circulation, not accommodation, so a cabin needs three of its four sides.
const CABIN_MIN_CLOSED_FACES := 3
const ROOM_FACES: Array[String] = ["n", "s", "e", "w"]

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


# ── VesselOutfit-shaped validation ──────────────────────────────────────────

## Returns { ok, errors, warnings, budget, usage, accepted_slots, capabilities }
## — the exact contract of `VesselOutfit.validate`, for a plan.
static func validate(
	plan: StructurePlan,
	hull_id: String,
	grid: DeckGrid = null,
	policy_caps: Dictionary = {},
) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var declared_hull := hull_id
	if declared_hull.is_empty() and plan != null:
		declared_hull = plan.hull_id
	var id := HullRegistry.resolve_network_hull_id(declared_hull)
	var budget := VesselOutfit.budget_for_hull(id, policy_caps)
	var g := grid if grid != null else HullRegistry.make_grid(id)
	if plan == null:
		return _result(true, errors, warnings, budget, {}, _empty_slots(), {})

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
		if not Parts.has(part_id):
			## Never silent: an unknown fitting is measured as nothing, and the
			## builder is told which one and why.
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
	var cabins := cabin_rooms(plan).size()
	var capabilities := {
		"cargo_cells": accepted_cells.size(),
		"cargo_budget": cargo_max,
		"exposed_deck_cells": int(budget.get("exposed_deck_cells", 0)),
		"has_cabin": cabins > 0,
		"has_helm": (accepted_slots["helm"] as Array).size() >= 1,
		"has_crane": (accepted_slots["crane"] as Array).size() >= 1,
		"has_fishing": (accepted_slots["fishing"] as Array).size() >= 1,
		"has_tow": (accepted_slots["tow"] as Array).size() >= 1,
		"doors": door_count(plan) + door_items,
		"windows": opening_count(plan, StructurePlan.OPENING_WINDOW),
		"helms": (accepted_slots["helm"] as Array).size(),
		## The brick path's "brick_count" is "how many pieces is this made of".
		## A plan's pieces are its entities.
		"brick_count": plan.entity_count(),
		"max_stack_y": max_stack_cells(plan, g),
		## Plan-native extras. Nothing in the catalog reads them yet; they cost
		## nothing and a `metric_range` rule can name them the day it wants to.
		"cabins": cabins,
		"items": plan.items.size(),
		"plan_entities": plan.entity_count(),
		"structure_plan": true,
	}
	return _result(
		errors.is_empty(), errors, warnings, budget, usage, accepted_slots, capabilities
	)


# ── VesselCompliance._measure-shaped metrics ────────────────────────────────

## Returns { brick_counts, tag_counts, positions, capacity, max_ratings, usage,
## capabilities, accepted_slots, grid } — the exact dictionary
## `VesselCompliance._evaluate_rule` reads. `brick_counts` and `positions` are
## keyed by PART id, which is what a plan's `item_id` is, so a rule written
## against a brick id matches a part of the same id and nothing else.
static func measure(plan: StructurePlan, grid: DeckGrid, outfit: Dictionary) -> Dictionary:
	var brick_counts := {}
	var tag_counts := {}
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
		"positions": positions,
		"capacity": capacity,
		"max_ratings": max_ratings,
		"usage": usage,
		"capabilities": capabilities,
		"accepted_slots": outfit.get("accepted_slots", {}),
		"grid": grid,
	}


## Plan-side twin of `VesselCompliance.validate`, evaluating the SAME rules
## through the SAME evaluator. Returns the same report dictionary.
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
	var outfit := validate(plan, id, g, caps)
	var checklist: Array[Dictionary] = []
	var errors: PackedStringArray = (outfit.get("errors", PackedStringArray()) as PackedStringArray).duplicate()
	var warnings: PackedStringArray = (outfit.get("warnings", PackedStringArray()) as PackedStringArray).duplicate()
	if registration.is_empty():
		errors.append("Choose a vessel registration before building.")
		return VesselCompliance._result(outfit, registration_id, false, checklist, errors, warnings)
	var metrics := measure(plan, g, outfit)
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
	return VesselCompliance._result(
		outfit, registration_id, registration_ok, checklist, errors, warnings
	)


# ── Enclosure, read off geometry ────────────────────────────────────────────

## Rooms that actually enclose someone: standing headroom, real floor area, and
## at most one open face. `open_faces` is the plan's own record of the sides a
## room does NOT have, so this is a reading of the drawing, not a guess.
static func cabin_rooms(plan: StructurePlan) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if plan == null:
		return out
	for raw in plan.rooms:
		if not (raw is Dictionary):
			continue
		var room := raw as Dictionary
		var size := StructurePlan.vec3_of(room.get("size"), Vector3.ZERO)
		if size.y < CABIN_MIN_HEADROOM_M:
			continue
		if size.x * size.z < CABIN_MIN_FLOOR_M2:
			continue
		if closed_faces(room) < CABIN_MIN_CLOSED_FACES:
			continue
		out.append(room)
	return out


## How many of a room's four sides carry a wall. Unknown face names in
## `open_faces` are ignored rather than trusted — a typo must not open a wall.
static func closed_faces(room: Dictionary) -> int:
	var open := {}
	var raw: Variant = room.get("open_faces", [])
	if raw is Array:
		for entry in raw as Array:
			var face := str(entry).strip_edges().to_lower()
			if ROOM_FACES.has(face):
				open[face] = true
	return ROOM_FACES.size() - open.size()


## Every opening of `type` on a wall, a room face or a deck.
static func opening_count(plan: StructurePlan, type: String) -> int:
	if plan == null:
		return 0
	var n := 0
	for collection in [plan.walls, plan.rooms, plan.decks]:
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
	var box := part_local_aabb(str(item.get("item_id", "")), StructurePlan.item_props(item))
	if not bool(box.get("ok", false)):
		return out
	var xform := plan.item_transform(item)
	var mn: Vector3 = box["min"]
	var mx: Vector3 = box["max"]
	var corners := PackedVector2Array()
	for corner_i in 8:
		var corner := xform * Vector3(
			mx.x if (corner_i & 1) != 0 else mn.x,
			mx.y if (corner_i & 2) != 0 else mn.y,
			mx.z if (corner_i & 4) != 0 else mn.z,
		)
		corners.append(Vector2(corner.x, corner.z))
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
	for raw in plan.rooms:
		var room := raw as Dictionary
		top = maxf(
			top,
			StructurePlan.vec3_of(room.get("origin")).y
				+ StructurePlan.vec3_of(room.get("size"), Vector3.ZERO).y
		)
	for raw in plan.decks:
		top = maxf(top, StructurePlan.vec3_of((raw as Dictionary).get("origin")).y)
	for raw in plan.stairs:
		var stair := raw as Dictionary
		top = maxf(
			top, StructurePlan.vec3_of(stair.get("start")).y + float(stair.get("height", 0.0))
		)
	for raw in plan.items:
		var item := raw as Dictionary
		var box := part_local_aabb(str(item.get("item_id", "")), StructurePlan.item_props(item))
		var reach := 0.0
		if bool(box.get("ok", false)):
			reach = maxf(0.0, (box["max"] as Vector3).y)
		top = maxf(top, plan.item_transform(item).origin.y + reach)
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
