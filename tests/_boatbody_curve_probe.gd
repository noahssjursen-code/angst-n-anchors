extends Node

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
## Lane B: instantiates a real BoatBody.
##
## `_collider_build_probe` measured raw `add_child` / `body_add_shape`; it never
## touches `BoatBody`, so its table cannot move no matter what BoatBody does.
## This is the same curve taken at the ENTRY POINT the wave named —
## `BoatBody.add_walk_brick_collider` — on a boat that is in the tree with a live
## physics space on its WalkDeck, which is the state the shipyard editor, the
## replication service and every in-tree re-fit-out leave it in.
##
##   unbatched  N add_walk_brick_collider calls, exactly as callers made them
##              before this change.
##   batched    the same N calls inside begin/end_walk_collider_batch. The
##              `end` — which puts the body back in its space and makes Jolt
##              build the compound ONCE — is inside the timer.
##
## Then, so a "fast" run that attached nothing cannot be reported as a win, both
## bodies are read back: shape count off PhysicsServer3D, and a capsule marched
## at a wall must be stopped at the same distance by both.

const COUNTS := [500, 2000, 4000, 8000]
const BOX := Vector3(0.4, 0.3, 0.1)


func _ready() -> void:
	print("%8s %14s %14s %10s %14s" % ["boxes", "unbatched ms", "batched ms", "speedup", "ensure ms"])
	var rows: Array = []
	for count_variant in COUNTS:
		var n := int(count_variant)
		var a := await _time(n, false)
		var b := await _time(n, true)
		var e := await _time_ensure(n)
		rows.append([n, a, b])
		print("%8d %14.1f %14.1f %10.1fx %14.1f" % [n, a, b, a / maxf(b, 0.001), e])
	var first := rows[0] as Array
	var last := rows[rows.size() - 1] as Array
	print("")
	print("500 -> 8000 (16x boxes; 16 == linear, 256 == quadratic): unbatched x%.1f  batched x%.1f"
		% [float(last[1]) / float(first[1]), float(last[2]) / float(first[2])])
	print("")
	await _agree(600)
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
	## The WalkDeck re-parent is deferred; without an idle frame it is still a
	## child of the boat and out of the tree, which is the FAST path by accident
	## and would make every row of this table meaningless.
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	return boat


func _time(count: int, batched: bool) -> float:
	var boat := await _make_boat()
	var t0 := Time.get_ticks_usec()
	if batched:
		boat.begin_walk_collider_batch()
	for i in count:
		boat.add_walk_brick_collider("curve_%d" % i, _centre(i), BOX, 17.0)
	if batched:
		boat.end_walk_collider_batch()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_drop(boat)
	await get_tree().physics_frame
	return ms


## `add_walk_brick_collider` opens with `ensure_walk_deck()`. This times ONLY
## those N calls, against a WalkDeck that already carries N children — if the
## batched column is still bending, this column says whether the bend is the
## physics or the bookkeeping around it.
func _time_ensure(count: int) -> float:
	var boat := await _make_boat()
	boat.begin_walk_collider_batch()
	for i in count:
		boat.add_walk_brick_collider("curve_%d" % i, _centre(i), BOX, 17.0)
	boat.end_walk_collider_batch()
	var t0 := Time.get_ticks_usec()
	for _i in count:
		boat.ensure_walk_deck()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_drop(boat)
	await get_tree().physics_frame
	return ms


func _drop(boat: BoatBody) -> void:
	var walk := boat.get_walk_deck()
	if walk != null and is_instance_valid(walk):
		walk.get_parent().remove_child(walk)
		walk.queue_free()
	boat.queue_free()


## Both ways, then interrogated. A speed-up that lost collision is not one.
func _agree(count: int) -> void:
	## The two boats are held 500 m apart. Stacked at the origin their shapes
	## interleave, `intersect_shape`'s result cap truncates, and the march reads
	## a DIFFERENT stopping distance for the two — which looks exactly like the
	## optimisation having moved a wall. It had not; the instrument had.
	var slow := await _make_boat(Vector3.ZERO)
	for i in count:
		slow.add_walk_brick_collider("curve_%d" % i, _centre(i), BOX, 17.0)
	var fast := await _make_boat(Vector3(500.0, 0.0, 0.0))
	fast.begin_walk_collider_batch()
	for i in count:
		fast.add_walk_brick_collider("curve_%d" % i, _centre(i), BOX, 17.0)
	fast.end_walk_collider_batch()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var slow_walk := slow.get_walk_deck()
	var fast_walk := fast.get_walk_deck()
	print("[agree] WalkDeck shape count   unbatched %d   batched %d" % [
		PhysicsServer3D.body_get_shape_count(slow_walk.get_rid()),
		PhysicsServer3D.body_get_shape_count(fast_walk.get_rid())])
	print("[agree] WalkDeck space valid   unbatched %s   batched %s" % [
		str(PhysicsServer3D.body_get_space(slow_walk.get_rid()).is_valid()),
		str(PhysicsServer3D.body_get_space(fast_walk.get_rid()).is_valid())])
	var state := slow_walk.get_world_3d().direct_space_state
	print("[agree] capsule stopped at     unbatched %.2f m   batched %.2f m" % [
		_march(state, slow_walk, Vector3.ZERO),
		_march(state, fast_walk, Vector3(500.0, 0.0, 0.0))])
	var mismatched := 0
	var slow_rid := slow_walk.get_rid()
	var fast_rid := fast_walk.get_rid()
	var n := mini(PhysicsServer3D.body_get_shape_count(slow_rid),
		PhysicsServer3D.body_get_shape_count(fast_rid))
	for i in n:
		var a: Transform3D = PhysicsServer3D.body_get_shape_transform(slow_rid, i)
		var b: Transform3D = PhysicsServer3D.body_get_shape_transform(fast_rid, i)
		var da: Variant = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(slow_rid, i))
		var db: Variant = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(fast_rid, i))
		if not a.is_equal_approx(b) or str(da) != str(db):
			mismatched += 1
	print("[agree] shape i disagrees      %d of %d (transform or half-extents)" % [mismatched, n])
	_drop(slow)
	_drop(fast)
	await get_tree().physics_frame


## Walks a 0.3 m capsule at the face of the box at index 0.
func _march(state: PhysicsDirectSpaceState3D, who: Node, origin: Vector3) -> float:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 0.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collide_with_bodies = true
	q.collision_mask = 0xFFFFFFFF
	## A box handed to add_walk_brick_collider in boat-local coordinates lands at
	## the boat's world origin plus those coordinates.
	var from := origin + _centre(0) - Vector3(0.0, 0.0, 1.2)
	for i in 121:
		var f := float(i) * 0.01
		q.transform = Transform3D(Basis.IDENTITY, from + Vector3(0.0, 0.0, f))
		for hit_variant in state.intersect_shape(q, 64):
			var hit := hit_variant as Dictionary
			if hit.get("collider") != who:
				continue
			## Which shape stopped it, by name. A stop on WalkHullCollider or on
			## the deck slab is not a stop on a brick collider, and reporting the
			## distance without the name would hide that.
			var owner_node := (who as CollisionObject3D).shape_owner_get_owner(
				(who as CollisionObject3D).shape_find_owner(int(hit.get("shape", -1)))) as Node
			print("[agree]   stopped by %s at %.2f m"
				% ["<unknown>" if owner_node == null else str(owner_node.name), f])
			return f
	return -1.0
