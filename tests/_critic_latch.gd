extends Node

## CRITIC SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
## Lane B. Attacks BoatBody.begin/end_walk_collider_batch (commit 316202a).
##
## Three questions, all measured, none reasoned:
##   A. Does a GDScript runtime error inside the fit-out loop abort the enclosing
##      function, so `end_walk_collider_batch()` is never reached?
##   B. If a batch is ever left open, what is the blast radius and does anything
##      recover it?
##   D. plan_collision_physics_test §5 asserts `body_get_space(rid).is_valid()`.
##      Is "a valid space" the same claim as "the world's space"?

const FIXTURE := "res://resources/data/structures/probe_trawler_bow_bulwark.json"
const HULL_ID := "hull_28x10"
const REGISTRATION := "fishing_vessel"
const PLAN_PREFIX := "BrickCol_plan_"
const CAPSULE_RADIUS := 0.3
const CAPSULE_HEIGHT := 0.8
const CAPSULE_Y := 0.55
const MARCH_STEP := 0.02

var _boxes: Array = []
var _reached_after_error := false
var _offset := Vector3.ZERO


func _ready() -> void:
	var layout := _load_layout()
	var plan := StructurePlan.from_dict(layout)
	_boxes = StructureBaker.collect_colliders(plan)
	print("[setup] fixture bakes %d collider boxes" % _boxes.size())

	# ── A. abort semantics ───────────────────────────────────────────────────
	var boat_a: Node3D = VesselSpawn.instantiate(HULL_ID, layout, REGISTRATION)
	add_child(boat_a)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("\n=== A. does a runtime error between begin and end abort the close? ===")
	print("[A] depth before          %d" % int(boat_a.get("_walk_collider_batch_depth")))
	_abort_inside_batch(boat_a as BoatBody)
	print("[A] line after the error reached: %s" % str(_reached_after_error))
	print("[A] depth after           %d   (0 == the batch closed)"
		% int(boat_a.get("_walk_collider_batch_depth")))
	var wa := (boat_a.call("get_walk_deck") as CollisionObject3D)
	print("[A] WalkDeck space valid  %s"
		% str(PhysicsServer3D.body_get_space(wa.get_rid()).is_valid()))
	boat_a.queue_free()
	await get_tree().physics_frame

	# ── B. blast radius of one unbalanced begin ──────────────────────────────
	print("\n=== B. one unbalanced begin, then the production refit path ===")
	var boat: Node3D = VesselSpawn.instantiate(HULL_ID, layout, REGISTRATION)
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	_offset = _measure_offset(walk)
	print("[B] plan->world offset %s" % str(_offset))
	_report(boat, walk, "healthy, freshly spawned")

	## Exactly the state an aborted loop leaves behind. Nothing else touched.
	(boat as BoatBody).begin_walk_collider_batch()
	_report(boat, walk, "batch opened and never closed")

	DeckFitout.apply_plan(boat as BoatBody, plan)
	_report(boat, walk, "after a full production apply_plan")

	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_report(boat, walk, "after 5 more physics frames")

	DeckFitout.apply_plan(boat as BoatBody, plan)
	await get_tree().physics_frame
	_report(boat, walk, "after a SECOND full apply_plan")

	(boat as BoatBody).clear_walk_brick_colliders()
	(boat as BoatBody).ensure_walk_deck()
	await get_tree().physics_frame
	_report(boat, walk, "after clear_walk_brick_colliders + ensure_walk_deck")
	boat.queue_free()
	await get_tree().physics_frame

	# ── D. is "a valid space" the property §5 needs? ─────────────────────────
	print("\n=== D. §5's space check against a body in a valid FOREIGN space ===")
	var boat_d: Node3D = VesselSpawn.instantiate(HULL_ID, layout, REGISTRATION)
	add_child(boat_d)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var wd := boat_d.call("get_walk_deck") as CollisionObject3D
	DeckFitout.apply_plan(boat_d as BoatBody, plan)
	_section_five(wd, "control: real apply_plan, untouched")
	_march_report(wd, "control")

	## What a mutation of `end_walk_collider_batch` that restored the WRONG space
	## would leave — a perfectly valid RID that no player is ever in.
	var foreign := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(foreign, true)
	PhysicsServer3D.body_set_space(wd.get_rid(), foreign)
	_section_five(wd, "MUTANT: body moved into a fresh valid space")
	_march_report(wd, "mutant")
	PhysicsServer3D.free_rid(foreign)
	boat_d.queue_free()
	await get_tree().physics_frame
	get_tree().quit()


## The shape of the failure the batch cannot survive: any runtime error in the
## loop body. `apply_plan` indexes `box["size"]` and `box["center"]` on a
## Dictionary it did not build; `apply_sync` calls into `mount_item_gameplay`.
func _abort_inside_batch(boat: BoatBody) -> void:
	boat.begin_walk_collider_batch()
	var d := {}
	var v: Vector3 = d["size"]
	_reached_after_error = true
	print("[A] unreachable, v=%s" % str(v))
	boat.end_walk_collider_batch()


func _load_layout() -> Dictionary:
	var text := FileAccess.get_file_as_string(FIXTURE)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _measure_offset(walk: CollisionObject3D) -> Vector3:
	var rid := walk.get_rid()
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner: Node = walk.shape_owner_get_owner(walk.shape_find_owner(i)) as Node
		if owner == null or not str(owner.name).begins_with(PLAN_PREFIX):
			continue
		var index := int(str(owner.name).substr(PLAN_PREFIX.length()))
		if index < 0 or index >= _boxes.size():
			continue
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, i)
		return (walk.global_transform * xf).origin - ((_boxes[index] as Dictionary)["center"] as Vector3)
	return Vector3.ZERO


func _plan_shape_count(walk: CollisionObject3D) -> int:
	var rid := walk.get_rid()
	var n := 0
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner: Node = walk.shape_owner_get_owner(walk.shape_find_owner(i)) as Node
		if owner != null and str(owner.name).begins_with(PLAN_PREFIX):
			n += 1
	return n


## How much of this body the physics WORLD can actually see. A shape on a body
## that is out of its space, or in someone else's, answers no query.
func _visible_hits(walk: CollisionObject3D, plan_only: bool) -> int:
	var state := get_viewport().find_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(24.0, 8.0, 40.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collide_with_bodies = true
	q.collision_mask = 0xFFFFFFFF
	q.transform = Transform3D(Basis.IDENTITY, walk.global_transform.origin)
	var n := 0
	for hit_variant in state.intersect_shape(q, 4096):
		var hit := hit_variant as Dictionary
		if hit.get("collider") != walk:
			continue
		if plan_only:
			var owner: Node = walk.shape_owner_get_owner(
				walk.shape_find_owner(int(hit.get("shape", -1)))) as Node
			if owner == null or not str(owner.name).begins_with(PLAN_PREFIX):
				continue
		n += 1
	return n


## The straight-wall control from plan_collision_physics_test §controls: the
## axis-aligned port bulwark, inboard face at plan x = 0.3. A capsule walking
## 2.0 m inboard->outboard must be stopped. Returns metres travelled.
func _march(walk: CollisionObject3D, z: float) -> float:
	var state := get_viewport().find_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collide_with_bodies = true
	q.collision_mask = 0xFFFFFFFF
	var from := Vector3(1.0, CAPSULE_Y, z) + _offset
	var motion := Vector3(-2.0, 0.0, 0.0)
	var steps := int(ceil(2.0 / MARCH_STEP))
	for i in steps + 1:
		var f := float(i) / float(steps)
		q.transform = Transform3D(Basis.IDENTITY, from + motion * f)
		for hit_variant in state.intersect_shape(q, 64):
			var hit := hit_variant as Dictionary
			if hit.get("collider") != walk:
				continue
			var owner: Node = walk.shape_owner_get_owner(
				walk.shape_find_owner(int(hit.get("shape", -1)))) as Node
			if owner == null or not str(owner.name).begins_with(PLAN_PREFIX):
				continue
			if i == 0:
				continue
			return f * 2.0
	return 2.0


func _march_report(walk: CollisionObject3D, label: String) -> void:
	var free_runs := 0
	var stations := 0
	var worst := 0.0
	var z := 7.0
	while z <= 24.0:
		var d := _march(walk, z)
		stations += 1
		worst = maxf(worst, d)
		if d >= 2.0:
			free_runs += 1
		z += 0.25
	print("[march:%s] %d/%d capsule stations walked the full 2.00 m outboard "
		% [label, free_runs, stations]
		+ "through the port bulwark (furthest %.2f m)" % worst)


func _report(boat: Node3D, walk: CollisionObject3D, label: String) -> void:
	var rid := walk.get_rid()
	print("[B] %-46s depth=%d space_valid=%s shapes=%d plan=%d visible_all=%d visible_plan=%d"
		% [
			label,
			int(boat.get("_walk_collider_batch_depth")),
			str(PhysicsServer3D.body_get_space(rid).is_valid()),
			PhysicsServer3D.body_get_shape_count(rid),
			_plan_shape_count(walk),
			_visible_hits(walk, false),
			_visible_hits(walk, true),
		])
	_march_report(walk, label.substr(0, 18))


## The three assertions §5 makes, run verbatim against whatever state the body
## is in, so a mutant can be scored by the real check rather than described.
func _section_five(walk: CollisionObject3D, label: String) -> void:
	var rid := walk.get_rid()
	var space_after := PhysicsServer3D.body_get_space(rid)
	var plan_shapes := _plan_shape_count(walk)
	var a := space_after.is_valid()
	var b := plan_shapes == _boxes.size()
	var c := _boxes.size() > 8
	print("[D] %-44s §5a space_valid=%s  §5b shapes %d==%d %s  §5c boxes>8 %s  => §5 %s"
		% [label, "PASS" if a else "FAIL", plan_shapes, _boxes.size(),
			"PASS" if b else "FAIL", "PASS" if c else "FAIL",
			"GREEN" if (a and b and c) else "RED"])
