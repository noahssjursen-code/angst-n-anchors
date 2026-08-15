extends SceneTree

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
##
## `_collider_shape_probe` showed the whole quadratic is Jolt rebuilding a body's
## compound shape on every `body_add_shape` WHILE THE BODY IS IN A SPACE: 8000
## boxes cost 17942 ms in a space and 17.7 ms out of one.
##
## This probe asks the only question that matters for production: can a body that
## is ALREADY IN THE TREE be taken out of its space, loaded, and put back — and
## does the collision it ends up with behave identically to the collision it gets
## the slow way? Timing without that answer is worthless.
##
##   in_space   N CollisionShape3D added to a body in the tree. production today.
##   despaced   same body, same nodes, but body_set_space(rid, RID()) around the
##              loop and the space restored afterwards. The restore is INSIDE the
##              timer, so nothing is hidden.
##
## Then both bodies are interrogated through PhysicsDirectSpaceState3D: a point
## inside every box must be solid, a point in the gap between two boxes must be
## empty, and a capsule marched at a box must be stopped. If despaced disagrees
## with in_space on even one of those, the optimisation is not one.

const COUNTS := [500, 2000, 4000, 8000]
const BOX := Vector3(0.4, 0.3, 0.1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("%8s %14s %14s %10s" % ["boxes", "in_space ms", "despaced ms", "speedup"])
	var timings: Array = []
	for count_variant in COUNTS:
		var n := int(count_variant)
		var a := float(_build(n, false, false))
		var b := float(_build(n, true, false))
		timings.append([n, a, b])
		print("%8d %14.1f %14.1f %10.1fx" % [n, a, b, a / maxf(b, 0.001)])
	print("")
	var first := timings[0] as Array
	var last := timings[timings.size() - 1] as Array
	print("500 -> 8000 (16x boxes): in_space x%.1f   despaced x%.1f"
		% [float(last[1]) / float(first[1]), float(last[2]) / float(first[2])])
	print("")
	await _agree(400)
	quit()


func _box_xform(i: int) -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, deg_to_rad(17.0)),
		Vector3(float(i % 40) * 1.0, 0.55, float(i / 40) * 1.0))


func _build(count: int, despace: bool, keep: bool) -> Variant:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	root.add_child(body)
	var t0 := Time.get_ticks_usec()
	var space := RID()
	if despace:
		space = PhysicsServer3D.body_get_space(body.get_rid())
		PhysicsServer3D.body_set_space(body.get_rid(), RID())
	for i in count:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = BOX
		cs.shape = shape
		var xf := _box_xform(i)
		cs.position = xf.origin
		cs.rotation_degrees = Vector3(0.0, 17.0, 0.0)
		cs.name = "BrickCol_plan_%d" % i
		body.add_child(cs)
	if despace:
		PhysicsServer3D.body_set_space(body.get_rid(), space)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if keep:
		return body
	body.free()
	return ms


## Same box set built both ways; every query must agree.
func _agree(count: int) -> void:
	var slow := _build(count, false, true) as StaticBody3D
	var fast := _build(count, true, true) as StaticBody3D
	await physics_frame
	await physics_frame
	var state := root.world_3d.direct_space_state
	var slow_solid := 0
	var fast_solid := 0
	var slow_gap := 0
	var fast_gap := 0
	for i in count:
		var xf := _box_xform(i)
		if _hits(state, xf.origin, slow):
			slow_solid += 1
		if _hits(state, xf.origin, fast):
			fast_solid += 1
		## Boxes sit on a 1 m lattice and are 0.4 x 0.3 x 0.1 — half a metre
		## along +X from a centre is air unless the shapes are wrong.
		var gap := xf.origin + Vector3(0.5, 0.0, 0.5)
		if _hits(state, gap, slow):
			slow_gap += 1
		if _hits(state, gap, fast):
			fast_gap += 1
	print("[agree] centres solid  slow %d/%d   fast %d/%d" % [slow_solid, count, fast_solid, count])
	print("[agree] gaps solid     slow %d/%d   fast %d/%d" % [slow_gap, count, fast_gap, count])
	var slow_stop := _march(state, slow)
	var fast_stop := _march(state, fast)
	print("[agree] capsule march blocked  slow %s   fast %s" % [str(slow_stop), str(fast_stop)])
	print("[agree] shape counts   slow %d   fast %d" % [
		PhysicsServer3D.body_get_shape_count(slow.get_rid()),
		PhysicsServer3D.body_get_shape_count(fast.get_rid())])
	slow.free()
	fast.free()


func _hits(state: PhysicsDirectSpaceState3D, at: Vector3, who: Node) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = at
	q.collide_with_bodies = true
	q.collision_mask = 0xFFFFFFFF
	for hit_variant in state.intersect_point(q, 32):
		if (hit_variant as Dictionary).get("collider") == who:
			return true
	return false


## Walks a 0.3 m capsule at the face of box 0 and reports where it is stopped,
## or -1.0 if it goes clean through.
func _march(state: PhysicsDirectSpaceState3D, who: Node) -> float:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 0.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collide_with_bodies = true
	q.collision_mask = 0xFFFFFFFF
	var from := _box_xform(0).origin + Vector3(0.0, 0.0, -1.2)
	for i in 121:
		var f := float(i) * 0.01
		q.transform = Transform3D(Basis.IDENTITY, from + Vector3(0.0, 0.0, f))
		for hit_variant in state.intersect_shape(q, 32):
			if (hit_variant as Dictionary).get("collider") == who:
				return f
	return -1.0
