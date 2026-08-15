extends SceneTree

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
##
## WHY DOES BUILDING THE COLLISION COST SECONDS, AND IS IT LINEAR IN THE BOX
## COUNT? `_plate_cost_probe` measured 2109 ms to put the 150 m feeder's 2448
## boxes into a physics world BEFORE the finer dice and 3673 ms for 3086 boxes
## after — 1.26x the boxes for 1.74x the time. If that is superlinear then the
## collider count is worth more than its face value and the dice has to be priced
## against a curve, not against a ratio.
##
## So: identical boxes, only the COUNT varied, timed three ways.
##
##   named    exactly what `BoatBody.add_walk_brick_collider` does — set a unique
##            name, then add_child. This is production.
##   unnamed  add_child with no name set, which is what a careless caller does.
##   server   PhysicsServer3D.body_add_shape straight onto one body, no nodes at
##            all. This is the floor: what the physics engine itself charges.
##
## If `named` and `unnamed` curve and `server` does not, the cost is the SCENE
## TREE, not the physics, and it is paid by every collider-heavy vessel whatever
## the dice does.

const COUNTS := [500, 1000, 2000, 4000, 8000]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("%8s %10s %10s %10s %12s %12s"
		% ["boxes", "named ms", "unnamed ms", "server ms", "named us/box", "srv us/box"])
	for count_variant in COUNTS:
		var count := int(count_variant)
		var named := _time_nodes(count, true)
		var unnamed := _time_nodes(count, false)
		var server := _time_server(count)
		print("%8d %10.1f %10.1f %10.1f %12.2f %12.2f"
			% [count, named, unnamed, server,
			   named * 1000.0 / float(count), server * 1000.0 / float(count)])
	quit()


func _time_nodes(count: int, named: bool) -> float:
	var body := StaticBody3D.new()
	root.add_child(body)
	var t0 := Time.get_ticks_usec()
	for i in count:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.4, 0.3, 0.1)
		cs.shape = shape
		cs.position = Vector3(float(i % 40) * 0.5, float(i / 40) * 0.3, 0.0)
		cs.rotation_degrees = Vector3(0.0, 17.0, 0.0)
		if named:
			cs.name = "BrickCol_plan_%d" % i
		body.add_child(cs)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	body.free()
	return ms


func _time_server(count: int) -> float:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	var t0 := Time.get_ticks_usec()
	for i in count:
		var shape := PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, Vector3(0.2, 0.15, 0.05))
		PhysicsServer3D.body_add_shape(body, shape, Transform3D(
			Basis(Vector3.UP, deg_to_rad(17.0)),
			Vector3(float(i % 40) * 0.5, float(i / 40) * 0.3, 0.0)))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)
	return ms
