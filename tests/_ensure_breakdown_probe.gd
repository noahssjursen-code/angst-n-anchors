extends Node

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
## Lane B: instantiates a real BoatBody.
##
## TWO OPEN QUESTIONS, both of them things a previous run got wrong.
##
## 1. Caching the two named-shape lookups in `_ensure_walk_deck` changed the
##    `ensure ms` column by nothing at all — so `get_node_or_null` was not the
##    O(n) term and the diagnosis was wrong. This times each remaining statement
##    in `_ensure_walk_hull_collider` / `_sync_walk_deck_transform` separately,
##    against a WalkDeck already carrying N brick colliders, with the body IN a
##    live space (production state) and OUT of one (batch state).
##
## 2. The unbatched and batched bodies stop a capsule 0.02 m apart while every
##    shape transform and half-extent on them is identical. Something other than
##    the shapes differs. This prints the transforms of the body and of the shape
##    that stopped it, in world space, for both.

const COUNTS := [500, 2000, 4000, 8000]
const BOX := Vector3(0.4, 0.3, 0.1)


func _ready() -> void:
	print("== 1. what in ensure_walk_deck costs, per N calls (ms) ==")
	print("%8s %6s %10s %10s %10s %10s %10s %10s"
		% ["boxes", "space", "set_meta", "hull.pos", "hull.disab", "hull.size", "walk.xform", "ensure"])
	for count_variant in COUNTS:
		for in_space in [true, false]:
			await _breakdown(int(count_variant), in_space)
	print("")
	print("== 2. why the two marches disagree ==")
	await _march_diff(600)
	get_tree().quit()


func _centre(i: int) -> Vector3:
	return Vector3(float(i % 40) * 1.0 - 20.0, 1.0, float(i / 40) * 1.0 - 20.0)


func _make_boat(at: Vector3 = Vector3.ZERO) -> BoatBody:
	var boat := BoatBody.new()
	boat.freeze = true
	## `freeze` alone did not hold it: the two boats settled to y = -0.677 and
	## y = -0.366, and the capsule march then read two different stopping
	## distances against IDENTICAL shape sets. The subject was fine; the
	## instrument was dropping one boat further than the other.
	boat.gravity_scale = 0.0
	boat.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	add_child(boat)
	boat.global_position = at
	boat.ensure_walk_deck()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	return boat


func _loaded(count: int) -> BoatBody:
	var boat := await _make_boat()
	boat.begin_walk_collider_batch()
	for i in count:
		boat.add_walk_brick_collider("curve_%d" % i, _centre(i), BOX, 17.0)
	boat.end_walk_collider_batch()
	await get_tree().physics_frame
	return boat


func _breakdown(count: int, in_space: bool) -> void:
	var boat := await _loaded(count)
	var walk := boat.get_walk_deck()
	var hull := walk.get_node_or_null("WalkHullCollider") as CollisionShape3D
	var space := PhysicsServer3D.body_get_space(walk.get_rid())
	if not in_space:
		PhysicsServer3D.body_set_space(walk.get_rid(), RID())

	var meta_ms := _time(func() -> void: walk.set_meta("_boat_owner", boat), count)
	var pos := hull.position
	var pos_ms := _time(func() -> void: hull.position = pos, count)
	var dis_ms := _time(func() -> void: hull.disabled = false, count)
	var box := hull.shape as BoxShape3D
	var size := box.size
	var size_ms := _time(func() -> void: box.size = size, count)
	var xf := walk.global_transform
	var xform_ms := _time(func() -> void: walk.global_transform = xf, count)
	var ensure_ms := _time(func() -> void: boat.ensure_walk_deck(), count)

	if not in_space:
		PhysicsServer3D.body_set_space(walk.get_rid(), space)
	print("%8d %6s %10.1f %10.1f %10.1f %10.1f %10.1f %10.1f"
		% [count, "in" if in_space else "out",
		   meta_ms, pos_ms, dis_ms, size_ms, xform_ms, ensure_ms])
	_drop(boat)
	await get_tree().physics_frame


func _time(what: Callable, count: int) -> float:
	var t0 := Time.get_ticks_usec()
	for _i in count:
		what.call()
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _drop(boat: BoatBody) -> void:
	var walk := boat.get_walk_deck()
	if walk != null and is_instance_valid(walk):
		walk.get_parent().remove_child(walk)
		walk.queue_free()
	boat.queue_free()


func _march_diff(count: int) -> void:
	var slow := await _make_boat(Vector3.ZERO)
	for i in count:
		slow.add_walk_brick_collider("curve_%d" % i, _centre(i), BOX, 17.0)
	var fast := await _make_boat(Vector3(500.0, 0.0, 0.0))
	fast.begin_walk_collider_batch()
	for i in count:
		fast.add_walk_brick_collider("curve_%d" % i, _centre(i), BOX, 17.0)
	fast.end_walk_collider_batch()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_report(slow, "unbatched", Vector3.ZERO)
	_report(fast, "batched  ", Vector3(500.0, 0.0, 0.0))
	_drop(slow)
	_drop(fast)
	await get_tree().physics_frame


func _report(boat: BoatBody, label: String, origin: Vector3) -> void:
	var walk := boat.get_walk_deck()
	var rid := walk.get_rid()
	print("[%s] boat world %s   walkdeck world %s"
		% [label, str(boat.global_position), str(walk.global_transform.origin)])
	## Shape 0 on the body is the deck slab; find curve_0 by owner name.
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner_node := walk.shape_owner_get_owner(walk.shape_find_owner(i)) as Node
		if owner_node == null or str(owner_node.name) != "BrickCol_curve_0":
			continue
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, i)
		var half: Variant = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(rid, i))
		print("[%s] curve_0 shape index %d   body-local %s   world %s   half %s"
			% [label, i, str(xf.origin), str((walk.global_transform * xf).origin), str(half)])
		break
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 0.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collide_with_bodies = true
	q.collision_mask = 0xFFFFFFFF
	var from := origin + _centre(0) - Vector3(0.0, 0.0, 1.2)
	for i in 1201:
		var f := float(i) * 0.001
		q.transform = Transform3D(Basis.IDENTITY, from + Vector3(0.0, 0.0, f))
		for hit_variant in q_hits(q, walk):
			var owner_node := walk.shape_owner_get_owner(
				walk.shape_find_owner(int((hit_variant as Dictionary).get("shape", -1)))) as Node
			print("[%s] first contact at %.3f m, capsule centre z %.4f, on %s"
				% [label, f, from.z + f, "<unknown>" if owner_node == null else str(owner_node.name)])
			return
	print("[%s] never contacted" % label)


func q_hits(q: PhysicsShapeQueryParameters3D, who: Node) -> Array:
	var out: Array = []
	for hit_variant in get_viewport().world_3d.direct_space_state.intersect_shape(q, 64):
		if (hit_variant as Dictionary).get("collider") == who:
			out.append(hit_variant)
	return out
