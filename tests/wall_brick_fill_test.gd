extends Node

## Lane B. **A BRICK THAT SAYS IT IS A WALL DRAWS ONE, AND YOU CANNOT WALK
## THROUGH IT.**
##
## Lane B, not A, because the land path is `BuildingCache` -> `BuildingFitout`
## -> `brick_door.gd:96`, which names the `WorldGateway` autoload as a bare
## compile-time identifier; under `--script` that is `Identifier not found` and
## the cascade takes this file with it. Same reason as `roof_seat_test`.
##
## ── WHAT WENT WRONG, AND WHY NOTHING CAUGHT IT ──────────────────────────────
##
## `wall_text_sm`, `wall_text` and `wall_text_lg` are tagged **`wall`** and
## reserve 2, 6 and 18 cells of a wall course. `BrickCatalog.create_visual` drew
## a `Label3D` for them and **not one mesh**. Measured on the only building
## there is, off the drawn nodes:
##
##   warehouse front elevation, x 19..24 at z=16
##     block@1 block@2 wall_text_lg@3 wall_text_lg@4 wall_text_lg@5  top y 2.750
##   its neighbours, x 12..14 and 29..31
##     block@1 ... block@5                                            top y 5.750
##
## Six columns three courses short: a **6 x 3 m hole in the warehouse's front
## elevation, hidden behind the word WAREHOUSE**, with one 4x4 roof plate
## standing over nothing. `roof_seat_test` printed it as a diagnostic and
## deliberately refused to assert on it, because a missing wall is not a roof
## defect. This file is where it is asserted.
##
## Nothing caught it because every check that ran over that warehouse asked
## about DATA (does the blueprint parse, round-trip, cache, resolve its pad) or
## about the roof. `building_interior_test`'s point scan comes closest and
## cannot see this one: it scans at the heights a standing player occupies, and
## the hole starts 3 m up. REALITY.md §4b, a whole property with no check
## pointed at it.
##
## ── THE FORMULATION, AND THE THREE THAT WERE REJECTED ───────────────────────
##
## **REJECTED — "every cell a brick reserves has geometry in it."** False for
## every brick in the game at the shipped constants and honestly so:
## `BrickCatalog.size_m` draws a 0.5 m brick on `BuildingGrid`'s 1.0 m lattice,
## so a 6-cell brick draws 3.0 m centred in a 6.0 m claim and the outer columns
## are empty by arithmetic. Requiring it would demand this unit be red until an
## OPEN OWNER DECISION (CONVENTIONS §3a, the brick cell) is settled — a red that
## says nothing about walls. The same objection kills "the column reaches the
## head its neighbours reach": the fixed sign columns top out at 5.250 against
## 5.750 and that 0.500 m **is** the open decision, the same gap that stands
## between every pair of bricks in that arm.
##
## **REJECTED — "the wall behind the sign is there because the blueprint puts a
## wall brick in those cells."** That reads the answer out of the document that
## caused the fault. `warehouse.json` DOES carry a brick in all 18 cells — a
## `wall_text_lg` — so a check of that shape reports a closed elevation on the
## building with the hole in it. Nothing below reads a brick id out of a
## blueprint to decide whether wall exists; the only thing read from a layout is
## WHERE a placement sits, and every "is there wall here" comes from
## `MeshInstance3D.global_transform * get_aabb()`.
##
## **REJECTED — "the sign draws a plate."** That is the fix restated
## (REALITY.md §4a). It would stay green on a plate one centimetre tall.
##
## **THE PROPERTY THIS FILE HOLDS:** *a brick tagged `wall` draws, and collides
## as, the whole of the brick it declares itself to be.* The reference is
## `BrickCatalog.size_m` of that same brick, so both sides move together and the
## claim is scale-free: it reads the same at the shipped 0.5 m brick, at the
## 1.0 m brick of arm (b), and on a vessel. It needs no edit whichever way the
## owner decides.
##
## And its other half, because the fix has two cases and only one of them is a
## wall: a sign MOUNTED on somebody else's brick (`sign_id` / `attach_sign`)
## must draw letters and **no** backer. It reserves no cells, so a slab there
## would stand over its neighbours' cells. The editor already routes a player's
## click both ways — dropped on an existing brick a sign attaches to that host,
## dropped on empty cells it is placed and takes them — and only the placed case
## is a wall.

## ── WHY THIS FILE COUNTS ITS OWN CHECKS ────────────────────────────────────
##
## Almost every check below lives inside a loop over a collection this file
## DISCOVERS: the bricks tagged `wall`, the bricks `is_wall_text` answers for,
## the shipped blueprints, the wall bricks a fit-out placed. So the number of
## checks executed is a function of what the catalogue happened to contain, and
## a run that asked none of them printed exactly like a run that asked all of
## them (REALITY.md §4f).
##
## Measured, not argued. Dropping `wall` from `wall_text_lg`'s tags — the tag on
## the very brick this file was written to catch, the warehouse's name board —
## takes the run from **22 checks to 21 and it reports PASS both times**. The
## whole-brick draw check for that brick does not fail; it stops existing. The
## population floors below (`walls.size() > 0`, `mounts > 0`, `ids.size() > 0`,
## `placed.size() > 0`) do not see it either: each catches a collection that
## went EMPTY, and this one merely got smaller.
##
## `EXPECTED_CHECKS` is what closes that. The catalogue is a literal, the
## blueprint set is on disk and the vessel arm is one synthetic layout, so the
## count is a constant and any drift in it — up OR down — is a fact about this
## suite that a human should look at. Re-freeze it deliberately, in the same
## commit as the checks you add, never after the fact.
##
## Floors and the budget are not redundant. A floor catches a collection that
## went empty; the budget catches a check that stopped being reached for any
## other reason, including one whose collection is still full.

const TestReport := preload("res://tests/support/test_report.gd")

## Floating point only. Every number compared here is a sum of exact
## binary-representable cell arithmetic; the observed residual is ~1e-7.
const EPS := 0.0005

## Measured 2026-08-16 against the shipped catalogue and blueprint set: 5 bricks
## tagged `wall`, 3 wall-mounted text bricks, 1 blueprint (`warehouse`) placing
## 255 wall bricks, one synthetic `hull_90x24` vessel. **23 checks**, the budget
## counting itself.
const EXPECTED_CHECKS := 23

## A hull with room on deck for a 6 x 3 x 1 brick and its control.
const HULL_ID := "hull_90x24"

var _t: RefCounted
var _host: Node3D


func _ready() -> void:
	_t = TestReport.new("wall_brick_fill_test")
	_host = Node3D.new()
	add_child(_host)

	_catalogue()
	_land()
	await _vessel()

	## The budget, counting itself, and OUTSIDE `_vessel()` on purpose: that arm
	## early-returns after a failed check, and the count is worth having on a run
	## that bailed as much as on one that finished.
	## `check_count()` is the number recorded BEFORE this line, so the run total
	## is one more.
	var ran: int = _t.check_count() + 1
	_t.check(
		"the run executed its whole check budget (%d of %d — re-freeze "
			% [ran, EXPECTED_CHECKS]
			+ "EXPECTED_CHECKS in the commit that changes it, never after the fact)",
		ran == EXPECTED_CHECKS)

	_host.free()
	_t.finish(get_tree())


## ── 1. THE CATALOGUE — every brick that declares itself a wall ──────────────
##
## Run over the whole catalogue and not over the ids this wave touched (§3c).
func _catalogue() -> void:
	var ids := BrickCatalog.ids()
	ids.sort()
	var walls: Array[String] = []
	for id_v in ids:
		if BrickCatalog.has_tag(str(id_v), "wall"):
			walls.append(str(id_v))
	_t.check("the catalogue declares bricks tagged `wall` to check (%d of %d)"
		% [walls.size(), ids.size()], walls.size() > 0)

	for id in walls:
		var visual := BrickCatalog.create_visual(id, {})
		_host.add_child(visual)
		var drawn := _bounds(visual)
		var sz := BrickCatalog.size_m(id)
		_t.check(
			"%s says it is a wall and draws one — drawn %.3f x %.3f m of a "
			% [id, drawn.size.x, drawn.size.y]
			+ "declared %.3f x %.3f m brick, from %d meshes"
				% [sz.x, sz.y, _meshes(visual).size()],
			_meshes(visual).size() > 0
				and drawn.size.x >= sz.x - EPS
				and drawn.size.y >= sz.y - EPS)
		_host.remove_child(visual)
		visual.free()

	## The other half. A mounted plaque reserves nothing and must add nothing.
	var mounts := 0
	for id in ids:
		var brick_id := str(id)
		if not BrickCatalog.is_wall_text(brick_id):
			continue
		mounts += 1
		var mounted := BrickCatalog.create_visual(brick_id, {"mounted": true})
		_host.add_child(mounted)
		var lettering := _visuals(mounted).size() - _meshes(mounted).size()
		_t.check(
			"%s mounted on another brick paints letters and adds no wall "
			% brick_id
			+ "(%d meshes, %d non-mesh visuals)"
				% [_meshes(mounted).size(), lettering],
			_meshes(mounted).size() == 0 and lettering > 0)
		_host.remove_child(mounted)
		mounted.free()
	_t.check("the catalogue carries wall-mounted text bricks to check (%d)" % mounts,
		mounts > 0)


## ── 2. LAND — every shipped blueprint, through the fit-out and the cache ────
func _land() -> void:
	var ids := BuildingBlueprintCatalog.ids()
	_t.check("the building catalogue ships blueprints to check (%d)" % ids.size(),
		ids.size() > 0)
	for blueprint_id in ids:
		var layout := BuildingBlueprintCatalog.by_id(blueprint_id)
		if layout == null:
			_t.fail("blueprint %s must load" % blueprint_id)
			continue
		_land_one(blueprint_id, layout)


func _land_one(blueprint_id: String, layout: BuildingLayout) -> void:
	var fitout := BuildingFitout.build(layout, true)
	_host.add_child(fitout)
	var grid := layout.grid()

	## Every placed wall brick: what it draws, and where.
	## key "<brick_id>_<x,y,z>" -> { id, cell, aabb }
	var placed: Dictionary = {}
	var short_drawn := PackedStringArray()
	for child in fitout.get_children():
		if not (child is Node3D) or str(child.name) == "Collision":
			continue
		var parsed := _parse_node_name(str(child.name))
		if parsed.is_empty():
			continue
		var brick_id := str(parsed["id"])
		if not BrickCatalog.has(brick_id) or not BrickCatalog.has_tag(brick_id, "wall"):
			continue
		var aabb := _bounds(child)
		var sz := BrickCatalog.size_m(brick_id)
		placed[str(child.name)] = {"id": brick_id, "cell": parsed["cell"], "aabb": aabb}
		if aabb.size.x < sz.x - EPS or aabb.size.y < sz.y - EPS:
			short_drawn.append("%s draws %.3f x %.3f of %.3f x %.3f"
				% [str(child.name), aabb.size.x, aabb.size.y, sz.x, sz.y])

	_t.check("blueprint %s: the fit-out places wall bricks to measure (%d)"
		% [blueprint_id, placed.size()], placed.size() > 0)
	_t.check("blueprint %s: every wall brick the fit-out places draws the whole "
		% blueprint_id
		+ "brick (%d of %d short: %s)"
			% [short_drawn.size(), placed.size(), _first(short_drawn, 4)],
		short_drawn.is_empty())

	## THE ONE YOU STAND ON (REALITY.md §3b). The collider is a second
	## derivation of the same declaration and it drifted once already — the flat
	## roof thinned its box without moving it. A wall you can see and walk
	## through is the same defect wearing the other face: `_needs_collider`
	## answered `false` for anything tagged `text`, so the warehouse's name board
	## would have become a 6 x 3 m doorway the moment it was drawn.
	var body := fitout.get_node_or_null("Collision")
	var shapes: Dictionary = {}
	if body != null:
		for c in body.get_children():
			var shape_node := c as CollisionShape3D
			if shape_node == null:
				continue
			var raw := str(shape_node.name)
			if raw.begins_with("Shape_"):
				shapes[raw.substr(6)] = shape_node
	var uncollided := PackedStringArray()
	var mismatched := PackedStringArray()
	var compared := 0
	for key_v in placed.keys():
		var rec := placed[key_v] as Dictionary
		## `block_45` and friends carry a convex hull, not a box; their shape is
		## the diagonal half of the cell by design and is not this file's claim.
		if BrickCatalog.has_tag(str(rec["id"]), "diagonal_plan"):
			continue
		var shape_node := shapes.get(str(key_v), null) as CollisionShape3D
		if shape_node == null:
			uncollided.append(str(key_v))
			continue
		var box := shape_node.shape as BoxShape3D
		if box == null:
			uncollided.append("%s (not a box)" % str(key_v))
			continue
		compared += 1
		var drawn: AABB = rec["aabb"]
		var centre := drawn.position + drawn.size * 0.5
		if shape_node.position.distance_to(centre) > EPS \
				or absf(box.size.x - drawn.size.x) > EPS \
				or absf(box.size.y - drawn.size.y) > EPS:
			mismatched.append("%s: box %s at %s vs drawn %s at %s"
				% [str(key_v), str(box.size.snappedf(0.001)),
					str(shape_node.position.snappedf(0.001)),
					str(drawn.size.snappedf(0.001)), str(centre.snappedf(0.001))])
	_t.check("blueprint %s: every wall brick you can see is a wall you are "
		% blueprint_id
		+ "stopped by (%d with no collider: %s)"
			% [uncollided.size(), _first(uncollided, 4)],
		uncollided.is_empty())
	_t.check("blueprint %s: the wall you stand on is the wall you see — %d boxes, "
		% [blueprint_id, compared]
		+ "%d disagree: %s" % [mismatched.size(), _first(mismatched, 3)],
		compared > 0 and mismatched.is_empty())

	## The game does not reach a blueprint through `BuildingFitout` — it goes
	## through `BuildingCache.instance`, which flattens the tree and throws the
	## per-brick names away (REALITY.md §3). The names are gone; the BOXES are
	## not, so every wall measured above is looked for in the stamp by geometry.
	var stamped := BuildingCache.instance(layout, false)
	_host.add_child(stamped)
	var stamp_boxes: Dictionary = {}
	for mi in _meshes(stamped):
		var a: AABB = mi.global_transform * mi.get_aabb()
		stamp_boxes[_aabb_key(a)] = true
	var missing := PackedStringArray()
	for key_v in placed.keys():
		var rec := placed[key_v] as Dictionary
		if not stamp_boxes.has(_aabb_key(rec["aabb"] as AABB)):
			missing.append(str(key_v))
	_t.check("blueprint %s: the stamp the game builds draws every wall the "
		% blueprint_id
		+ "fit-out draws (%d of %d missing from %d stamped meshes: %s)"
			% [missing.size(), placed.size(), stamp_boxes.size(), _first(missing, 4)],
		missing.is_empty())
	_host.remove_child(stamped)
	stamped.free()

	_host.remove_child(fitout)
	fitout.free()


## ── 3. VESSELS — the same bricks on a 0.5 m deck lattice, in physics ────────
##
## The land collider and the vessel collider are two consumers of one
## declaration and they disagreed: `building_fitout._needs_collider` refused
## anything tagged `text`, and `deck_fitout._collider_spec` returned a ZERO box
## for the same four ids. This arm goes through `VesselSpawn` -> `apply_sync`,
## which is the call the shipyard makes, and reads the shapes off `WalkDeck`.
##
## A synthetic layout and not a prebuilt vessel because no prebuilt carries a
## wall text brick — asserting over the fleet would be a check with an empty
## universe (REALITY.md §4), and this way the population is stated in the
## message.
func _vessel() -> void:
	var boat := VesselSpawn.instantiate(HULL_ID, {"hull_id": HULL_ID, "cells": {}}, "general_vessel")
	if not _t.check("a hull spawns to build the wall text on", boat != null):
		return
	_host.add_child(boat)
	var grid := DeckFitout.grid_for_boat(boat)
	if not _t.check("the spawned hull has a deck grid", grid != null):
		boat.queue_free()
		await get_tree().process_frame
		return

	var origin := Vector3i(int(grid.width / 2) - 3, 0, int(grid.length / 2))
	var layout := BrickLayout.new()
	layout.hull_id = HULL_ID
	var placed := layout.place_footprint(origin, "wall_text_lg", 0, grid, {"text": "TEST"})
	if not _t.check("a wall text brick can be placed on a deck (%s at %s)"
			% ["wall_text_lg", str(origin)], placed):
		boat.queue_free()
		await get_tree().process_frame
		return

	DeckFitout.apply_sync(boat, layout, grid)
	await get_tree().process_frame

	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	var drawn := _bounds(root) if root != null else AABB()
	var sz := BrickCatalog.size_m("wall_text_lg")
	_t.check("a wall text brick fitted to a vessel draws the whole brick "
		+ "(drawn %.3f x %.3f m of a declared %.3f x %.3f m brick)"
			% [drawn.size.x, drawn.size.y, sz.x, sz.y],
		drawn.size.x >= sz.x - EPS and drawn.size.y >= sz.y - EPS)

	var walk := boat.get_walk_deck()
	var boxes: Array[Vector3] = []
	if walk != null:
		for child in walk.get_children():
			var cs := child as CollisionShape3D
			if cs == null or not str(cs.name).contains("wall_text_lg"):
				continue
			var box := cs.shape as BoxShape3D
			if box != null:
				boxes.append(box.size)
	_t.check("a wall text brick fitted to a vessel stands in physics "
		+ "(%d shapes: %s)" % [boxes.size(), str(boxes)],
		boxes.size() == 1
			and absf(boxes[0].x - sz.x) <= EPS
			and absf(boxes[0].y - sz.y) <= EPS)

	## The floor mark is the control: it is tagged `text` too, it is NOT a wall,
	## and it must stay walk-through. Without this the vessel claim above is
	## satisfiable by giving every text brick a collider.
	var deck_layout := BrickLayout.new()
	deck_layout.hull_id = HULL_ID
	if deck_layout.place_footprint(origin, "deck_text", 0, grid, {"text": "TEST"}):
		DeckFitout.apply_sync(boat, deck_layout, grid)
		await get_tree().process_frame
		var marks := 0
		var walk2 := boat.get_walk_deck()
		if walk2 != null:
			for child in walk2.get_children():
				var cs := child as CollisionShape3D
				if cs != null and str(cs.name).contains("deck_text"):
					marks += 1
		_t.check("a painted deck mark is still paint (%d colliders)" % marks, marks == 0)
	else:
		_t.fail("the deck text control brick must place")

	boat.queue_free()
	await get_tree().process_frame


## ── PLUMBING ───────────────────────────────────────────────────────────────


## Geometry, rounded to the millimetre, as an identity. Used to find a box in a
## flattened stamp that has no names left in it.
func _aabb_key(a: AABB) -> String:
	return "%.3f,%.3f,%.3f|%.3f,%.3f,%.3f" % [
		a.position.x, a.position.y, a.position.z,
		a.size.x, a.size.y, a.size.z,
	]


## "<brick_id>_<x,y,z>" — a brick id may itself contain underscores, so cut at
## the LAST one, and the tail must parse as three integers.
func _parse_node_name(raw: String) -> Dictionary:
	var cut := raw.rfind("_")
	if cut <= 0:
		return {}
	var parts := raw.substr(cut + 1).split(",")
	if parts.size() != 3:
		return {}
	for p in parts:
		if not p.is_valid_int():
			return {}
	return {
		"id": raw.substr(0, cut),
		"cell": Vector3i(int(parts[0]), int(parts[1]), int(parts[2])),
	}


func _first(items: PackedStringArray, n: int) -> String:
	if items.is_empty():
		return "none"
	var out := PackedStringArray()
	for i in mini(n, items.size()):
		out.append(items[i])
	return ", ".join(out)


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = aabb
			first = false
		else:
			out = out.merge(aabb)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _visuals(node: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		out.append(node as VisualInstance3D)
	for child in node.get_children():
		out.append_array(_visuals(child))
	return out
