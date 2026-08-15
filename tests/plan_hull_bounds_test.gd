extends Node

## Lane B. Does a StructurePlan authored against the wrong hull reach the world?
##
## The survey (`tests/_placement_grid_survey.gd` §7–8) measured that
## `StructurePlan.add_wall` / `add_deck` / `add_stair` / `add_piece` / `add_item`
## refuse nothing and that the baker DRAWS AND COLLIDES whatever they are given:
## a 4 × 4 m bake became **910 × 910 m** and 1 collider became **17**. Nothing
## downstream refused it either — `PlanOutfit.validate` looked only at ITEMS, and
## only at two of the three bands it could have (slot → warning, cargo → error,
## everything else silent), so the parts a registration actually counts —
## `bollard_pair` (tag "mooring") and `lantern_all_round` (tag "nav_white") —
## were never asked where they were.
##
## ── Why this is lane B and not lane A ────────────────────────────────────────
##
## Because the producer is not where the bug lives (REALITY.md §3). Asking
## `StructureBaker.collect_colliders` for a shorter list proves nothing: the
## thing that puts a 910 m slab of walk collider in open water is
## `DeckFitout.apply_plan`, and the only honest place to read the answer is the
## shapes `PhysicsServer3D` is actually holding on the vessel's WalkDeck. §1 goes
## `VesselSpawn.instantiate` → `apply_plan` → `PhysicsServer3D` and counts them.
##
## ── What "on the hull" means, and what it is not ─────────────────────────────
##
## `PlanOutfit.on_hull_point` is the predicate and `plan_outfit.gd`'s header
## carries the measurement. In one line: the deck rectangle grown by the hull's
## OWN half-breadth, and EVERY corner of everything an entity draws has to be
## inside it. It is not containment in the deck, because 61 of the 2342 entities
## in the shipped fixtures put a corner outside the deck rectangle on purpose —
## a stem rakes, a cap rail overhangs, a rubbing strake stands proud, a davit
## swings out. §3 holds the fence in the ACCEPTING direction and §4 asserts that
## every shipped fixture survives untouched, because a fence that reddens real
## ships is a worse defect than the one it fixes.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/plan_hull_bounds_test.tscn

const TestReport := preload("res://tests/support/test_report.gd")
const PO := preload("res://scripts/ship/plan_outfit.gd")

const HULL := "hull_28x10"
const REGISTRATION := "general_vessel"
const PLAN_PREFIX := "BrickCol_plan_"
const STRUCTURES := "res://resources/data/structures/"

## The survey's off-hull coordinates, verbatim.
const OFF := Vector3(900.0, 0.0, 900.0)

var _t: RefCounted


func _ready() -> void:
	_t = TestReport.new("plan_hull_bounds_test")
	await _test_the_slab_never_reaches_the_physics_world()
	_test_gear_in_the_sea_cannot_certify_a_vessel()
	_test_the_fence_is_the_whole_entity()
	_test_the_item_gradient_is_unchanged()
	_test_shipped_fixtures_survive()
	_t.finish(get_tree())


# ── 1. The 910 m slab, through the path the game runs ────────────────────────

## The plan the survey built: one 4 × 4 m deck on the hull, plus a wall, a deck
## and a stair 900 m away. Both numbers are asserted at both ends — the drawn
## AABB and the collider count — because a fix that dropped the colliders and
## kept the mesh would leave a 910 m slab of visible steel over the sea.
func _test_the_slab_never_reaches_the_physics_world() -> void:
	var plan := _slab_plan()
	var grid := HullRegistry.make_grid(HULL)
	var raw_boxes := StructureBaker.collect_colliders(plan)
	var raw_aabb := _bake_aabb(plan)
	_t.equal("as authored, the plan collides in 17 boxes", raw_boxes.size(), 17)
	_t.near("as authored, the bake is 910 m across X", raw_aabb.size.x, 910.0, 0.01)
	_t.near("as authored, the bake is 910 m across Z", raw_aabb.size.z, 910.0, 0.01)

	var built := PO.on_hull_plan(plan, grid)
	var kept := StructureBaker.collect_colliders(built)
	var kept_aabb := _bake_aabb(built)
	_t.equal("on the hull, the plan collides in 1 box", kept.size(), 1)
	_t.near("on the hull, the bake is 4 m across X", kept_aabb.size.x, 4.0, 0.01)
	_t.near("on the hull, the bake is 4 m across Z", kept_aabb.size.z, 4.0, 0.01)
	_t.check(
		"and the box that survived is the one that was on the hull",
		kept.size() == 1 and ((kept[0] as Dictionary)["center"] as Vector3).distance_to(
			Vector3(2.0, 2.925, 2.0)
		) < 0.2
	)

	## Named, one error, in the builder's words — the plan-side twin of
	## `BrickLayout.off_grid_reason`.
	var outfit := PO.validate(plan, HULL, grid)
	_t.check("the plan is refused", not bool(outfit["ok"]))
	var joined := " | ".join(outfit["errors"] as PackedStringArray)
	_t.check(
		"and the refusal names the entity, where it is, and the deck it missed",
		joined.contains("Wall")
		and joined.contains("900.0)")
		and joined.contains("10.0 x 28.0 m hull")
	)

	## THE PRODUCTION PATH. Not the dictionary in the middle. `VesselSpawn`
	## instantiates the hull and runs `DeckFitout.apply_plan`; what is asserted is
	## what `PhysicsServer3D` is holding afterwards.
	var boat: Node3D = VesselSpawn.instantiate(HULL, plan.to_dict(), REGISTRATION)
	if not _t.check("VesselSpawn.instantiate returned a vessel", boat != null):
		return
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	if not _t.check("the vessel has a WalkDeck body", walk != null):
		boat.queue_free()
		return
	var rid := walk.get_rid()
	var plan_shapes := 0
	var worst := 0.0
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner_node: Node = walk.shape_owner_get_owner(walk.shape_find_owner(i)) as Node
		if owner_node == null or not str(owner_node.name).begins_with(PLAN_PREFIX):
			continue
		plan_shapes += 1
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, i)
		var world := walk.global_transform * xf
		worst = maxf(worst, maxf(absf(world.origin.x), absf(world.origin.z)))
	_t.equal("PhysicsServer3D holds exactly one plan shape for this vessel", plan_shapes, 1)
	_t.check(
		"and no plan shape stands more than the hull's length from it (%.1f m)" % worst,
		worst < 30.0
	)

	## AND WHAT IT DRAWS, on the same vessel. Found by mutation: baking the
	## authored plan while colliding the partitioned one left every check above
	## green and put 910 x 910 m of visible steel over the sea. A collider count
	## is not a drawing.
	var fitout := boat.get_node_or_null("DeckFitout")
	if _t.check("the vessel has a DeckFitout root", fitout != null):
		var drawn := _merge(fitout)
		_t.check(
			"and what it DRAWS is hull-sized, not 910 m across (%.1f x %.1f m)"
				% [drawn.size.x, drawn.size.z],
			drawn.size.x < 30.0 and drawn.size.z < 40.0
		)
	boat.queue_free()


# ── 2. The certified vessel with its gear in the sea ─────────────────────────

## The plan-side twin of STATE.md 2c. Every fitting `general_vessel` counts,
## authored once on the deck and once at coordinates that belong to no hull this
## boat has. The MEASUREMENT has to move and not merely the verdict, which is why
## the checklist is read rule by rule: keeping the error while still measuring
## the strays is exactly the mutation that left 7 of 8 legal requirements met by
## bricks in the sea on the brick side.
##
## `bollard_pair` and `lantern_all_round` are the two parts that were in the
## SILENT band — no slot, no cargo tag — so before this wave nothing anywhere
## asked where they were.
func _test_gear_in_the_sea_cannot_certify_a_vessel() -> void:
	var grid := HullRegistry.make_grid(HULL)
	var on_deck := _fitted_plan(Vector3.ZERO)
	var control := PO.compliance(on_deck, HULL, REGISTRATION, grid)
	_t.check("control: the helm rule passes with the gear on deck",
		bool(_rule(control, "helm").get("ok", false)))
	_t.check("control: the white masthead light rule passes",
		bool(_rule(control, "white_light").get("ok", false)))
	_t.check("control: four mooring points are counted",
		bool(_rule(control, "mooring_points").get("ok", false)))
	_t.check("control: no fitting is reported off the hull",
		PO.off_hull_entities(on_deck, grid).is_empty())

	var overboard := _fitted_plan(OFF)
	var report := PO.compliance(overboard, HULL, REGISTRATION, grid)
	_t.check("the same fittings 900 m away do not make a helm",
		not bool(_rule(report, "helm").get("ok", false)))
	_t.check("nor a white masthead light",
		not bool(_rule(report, "white_light").get("ok", false)))
	_t.check("nor four mooring points",
		not bool(_rule(report, "mooring_points").get("ok", false)))
	_t.check("the vessel is refused", not bool(report["ok"]))
	_t.check(
		"and the builder is told which fittings, not just that something is wrong",
		" | ".join(report["errors"] as PackedStringArray).contains("is not on the")
	)
	_t.check(
		"fewer requirements are met than with the same gear on deck",
		_passed(report) < _passed(control)
	)


# ── 3. A wall has extent, in both directions ─────────────────────────────────

## The fence asks about EVERY corner of everything an entity draws, not about one
## of them, and this is the pair that pins which reading is in force. Both walls
## start at the same place on the deck; the only difference is how far the far
## end goes. Under an any-corner reading the 900 m wall is "on the hull" because
## one end of it is, and the slab §1 measures comes straight back — measured,
## `tests/_plan_fence_facts.gd` §E: an on-deck plan carrying one such wall bakes
## a 902 m AABB and the any-corner reading refuses none of it.
##
## The accepting direction is asserted on the same primitive at the same origin,
## so a fence tightened until it refused everything would fail here.
func _test_the_fence_is_the_whole_entity() -> void:
	var grid := HullRegistry.make_grid(HULL)
	var short_wall := StructurePlan.new()
	short_wall.hull_id = HULL
	short_wall.add_wall(Vector3(2.0, 0.0, 2.0), "x", 6.0)
	_t.equal(
		"a 6 m wall from (2, 0, 2), which stays on the boat, is kept",
		PO.off_hull_entities(short_wall, grid).size(), 0
	)
	var long_wall := StructurePlan.new()
	long_wall.hull_id = HULL
	long_wall.add_wall(Vector3(2.0, 0.0, 2.0), "x", 900.0)
	_t.equal(
		"the SAME wall run out to 900 m, one end still bolted to the deck, is refused",
		PO.off_hull_entities(long_wall, grid).size(), 1
	)
	var long_bake := _bake_aabb(long_wall)
	_t.near("as authored it bakes its full 900 m of run", long_bake.size.x, 900.0, 0.01)
	_t.near(
		"partitioned, nothing of it is left to bake",
		_bake_aabb(PO.on_hull_plan(long_wall, grid)).size.x, 0.0, 0.01
	)

	## The overhang the fence exists NOT to refuse, stated as a property rather
	## than as a coordinate: a wall standing exactly one half-breadth outboard of
	## the side is the furthest thing the envelope admits, and it is admitted.
	var overhang := StructurePlan.new()
	overhang.hull_id = HULL
	overhang.add_wall(Vector3(-grid.half_beam, 0.0, 14.0), "x", grid.half_beam)
	_t.equal(
		"a wall hung a full half-breadth (%.1f m) outboard of the port side is kept"
			% grid.half_beam,
		PO.off_hull_entities(overhang, grid).size(), 0
	)
	var further := StructurePlan.new()
	further.hull_id = HULL
	further.add_wall(Vector3(-grid.half_beam - 1.0, 0.0, 14.0), "x", grid.half_beam)
	_t.equal(
		"the same wall one metre further out is refused",
		PO.off_hull_entities(further, grid).size(), 1
	)

	## A fitting the catalog has never heard of still has a position, and it is
	## the position the builder typed. `hull_test_points` falls back to the item
	## origin, so an uncatalogued part cannot be a hole in the fence.
	var stray := StructurePlan.new()
	stray.hull_id = HULL
	stray.add_item("winch_of_the_gods", OFF)
	_t.equal(
		"an uncatalogued fitting 900 m away is refused on its coordinates alone",
		PO.off_hull_entities(stray, grid).size(), 1
	)


# ── 4. The item gradient this wave deliberately did not flatten ──────────────

## Off-deck is a WARNING for a slot fitting and an ERROR for cargo, and that
## gradient was somebody's decision: a deckhouse fitting overhanging the sheer is
## normal, a container floating beside the ship is not. Both halves are asserted
## here so that collapsing either one into the new hull error turns this red.
func _test_the_item_gradient_is_unchanged() -> void:
	var grid := HullRegistry.make_grid(HULL)
	## A helm just outboard of the deck edge: still on the boat, so the hull fence
	## says nothing, and the older per-item check still warns.
	var nudged := StructurePlan.new()
	nudged.hull_id = HULL
	nudged.add_item("helm_console", Vector3(10.4, 0.0, 14.0))
	var nudged_outfit := PO.validate(nudged, HULL, grid)
	_t.check(
		"a helm just outboard of the deck edge is a WARNING, not an error",
		" | ".join(nudged_outfit["warnings"] as PackedStringArray)
			.contains("not over the vessel's deck")
	)
	_t.check("and it does not refuse the vessel", bool(nudged_outfit["ok"]))
	_t.check(
		"because it is still ON the boat",
		PO.off_hull_entities(nudged, grid).is_empty()
	)

	## Cargo hanging over the bow taper is still refused by its OWN message, not
	## folded into the hull error: it is on the boat, it is just not on deck.
	var overhang := StructurePlan.new()
	overhang.hull_id = HULL
	overhang.add_item("hold_coaming", Vector3(5.0, 0.0, 3.0), 0.0, {"length": 8.0, "width": 4.0})
	var cargo_outfit := PO.validate(overhang, HULL, grid)
	_t.check(
		"a hold over the bow taper is still refused as cargo, in the cargo words",
		" | ".join(cargo_outfit["errors"] as PackedStringArray)
			.contains("outside the exposed deck")
	)
	_t.check(
		"and it is refused by the cargo rule and not by the hull fence",
		PO.off_hull_entities(overhang, grid).is_empty()
	)


# ── 5. Shipped data refused: zero ────────────────────────────────────────────

## Run over EVERY fixture, not the one being worked on (REALITY.md §3c). What is
## compared before and after the partition is what the fixture BUILDS — collider
## boxes and drawn vertices — not just the refusal list, because "refused
## nothing" and "changed nothing it builds" are two claims and only the second is
## what a player sees.
##
## The vertex half is not decoration. An earlier cut of this fence refused nine
## shipped `wire` items — three fender lanyards and six trawl warps — and the
## collider half stayed silent through all of it, because a wire is drawn and
## never collided (`StructureBaker.collect_colliders`, "A WIRE IS NEVER SOLID").
## Nine pieces of a shipped trawler's rigging would have vanished from the render
## with every collider count in the gate unmoved.
##
## The floors below are stated as "every vessel fixture on disk was measured",
## not as a remembered total, so adding a fixture cannot silently shrink the
## coverage this check claims.
func _test_shipped_fixtures_survive() -> void:
	var dir := DirAccess.open(STRUCTURES)
	if not _t.check("the structure fixtures are readable", dir != null):
		return
	var names := PackedStringArray()
	for f in dir.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	_t.check("there are fixtures to measure (%d)" % names.size(), names.size() >= 19)
	var vessel_fixtures := 0
	var measured := 0
	var entities := 0
	var vertices := 0
	var refused := 0
	var changed := PackedStringArray()
	for f in names:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRUCTURES + f))
		if not (parsed is Dictionary):
			continue
		var plan := StructurePlan.from_dict(parsed as Dictionary)
		if plan.context != "vessel" or plan.hull_id.is_empty():
			continue
		vessel_fixtures += 1
		var grid := HullRegistry.make_grid(plan.hull_id)
		if grid == null:
			continue
		measured += 1
		entities += StructureBaker.entity_colliders(plan).size()
		var off := PO.off_hull_entities(plan, grid)
		refused += off.size()
		var built := PO.on_hull_plan(plan, grid)
		var before := StructureBaker.collect_colliders(plan).size()
		var after := StructureBaker.collect_colliders(built).size()
		if before != after:
			changed.append("%s colliders %d -> %d" % [f, before, after])
		var drawn_before := _bake_vertices(plan)
		var drawn_after := _bake_vertices(built)
		if drawn_before != drawn_after:
			changed.append("%s vertices %d -> %d" % [f, drawn_before, drawn_after])
		vertices += drawn_before
	_t.equal(
		"every vessel fixture on disk resolved to a hull grid and was measured",
		measured, vessel_fixtures
	)
	_t.check("and there were some to measure (%d)" % measured, measured >= 16)
	_t.check("and they carry real geometry (%d entities)" % entities, entities >= 2000)
	_t.check("and they draw real geometry (%d vertices)" % vertices, vertices >= 100000)
	_t.equal("shipped structure entities refused by the hull fence", refused, 0)
	_t.equal(
		"and not one shipped fixture loses a collider or a vertex: %s" % " | ".join(changed),
		changed.size(), 0
	)


# ── Fixtures ─────────────────────────────────────────────────────────────────

## The survey's plan, VERBATIM, so the numbers this file asserts are the numbers
## `tests/_placement_grid_survey.gd` §8 printed and not a re-staging of them.
func _slab_plan() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	plan.add_deck(Vector3(0.0, 3.0, 0.0), Vector2(4.0, 4.0))
	plan.add_wall(OFF, "x", 10.0)
	plan.add_deck(OFF, Vector2(10.0, 10.0))
	plan.add_stair(OFF, "+x", 4.0)
	return plan


## Everything `general_vessel` can count on a plan, offset bodily by `shift`.
func _fitted_plan(shift: Vector3) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	plan.add_item("helm_console", shift + Vector3(4.6, 0.0, 24.0))
	for i in 4:
		plan.add_item(
			"bollard_pair", shift + Vector3(1.0 + float(i) * 0.6, 0.0, 4.0 + float(i) * 2.0)
		)
	plan.add_item("lantern_all_round", shift + Vector3(5.0, 6.0, 23.0))
	return plan


func _rule(report: Dictionary, rule_id: String) -> Dictionary:
	for raw in report.get("checklist", []) as Array:
		if str((raw as Dictionary).get("id", "")) == rule_id:
			return raw as Dictionary
	return {}


func _passed(report: Dictionary) -> int:
	var n := 0
	for raw in report.get("checklist", []) as Array:
		if bool((raw as Dictionary).get("ok", false)):
			n += 1
	return n


## Every vertex the plan draws. The measure a lost `wire` moves and a lost
## collider does not.
func _bake_vertices(plan: StructurePlan) -> int:
	var node := StructureBaker.bake(plan)
	var out := _count_vertices(node)
	node.free()
	return out


func _count_vertices(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
				if verts is PackedVector3Array:
					total += (verts as PackedVector3Array).size()
	for child in node.get_children():
		total += _count_vertices(child)
	return total


func _bake_aabb(plan: StructurePlan) -> AABB:
	var node := StructureBaker.bake(plan)
	var out := _merge(node)
	node.free()
	return out


func _merge(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var a := mi.mesh.get_aabb()
				a.position += mi.position
				if first:
					out = a
					first = false
				else:
					out = out.merge(a)
		var sub := _merge(child)
		if sub.size != Vector3.ZERO:
			if first:
				out = sub
				first = false
			else:
				out = out.merge(sub)
	return out
