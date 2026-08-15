extends Node

## SCRATCH PROBE (leading underscore — not a gate unit). Lane B.
##
## WHAT A STAMPED BUILDING COSTS, and what a port full of them costs. Runs
## identically on this tree and on a `git archive HEAD` copy, so the two columns
## are the same probe and not two descriptions of one.
##
## Three costs are separated on purpose, because they are paid at different
## moments and only the middle one is new:
##   BAKE      once per blueprint, in `_bake_prototype`
##   STAMP     per building, detached — the loop this wave changed
##   ENTER     per building, when the caller adds the root to the tree and the
##             StaticBody3D joins the physics space with its shapes already on
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_building_stamp_cost_probe.tscn

const PORT_SCALE := 20
const REPEATS := 12


func _ready() -> void:
	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		printerr("[probe] warehouse did not load")
		get_tree().quit(1)
		return

	## BAKE — first stamp after a clear pays for the prototype.
	BuildingCache.clear()
	var t0 := Time.get_ticks_usec()
	var first := BuildingCache.instance(layout, true)
	var bake_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	printerr("[cost] BAKE (first stamp after clear): %.2f ms" % bake_ms)
	printerr("[cost] first stamp: %d meshes, %d shapes on solid bodies, %d CollisionObject3D"
		% [_meshes(first), _shapes(first), _objects(first)])
	first.free()

	## STAMP — steady state, prototype warm, nothing added to the tree.
	var best := INF
	for r in REPEATS:
		var s0 := Time.get_ticks_usec()
		var node := BuildingCache.instance(layout, true)
		var ms := float(Time.get_ticks_usec() - s0) / 1000.0
		node.free()
		best = minf(best, ms)
	printerr("[cost] STAMP detached, best of %d: %.3f ms" % [REPEATS, best])

	## ENTER — the moment the caller adds it to the tree.
	var enter_best := INF
	for r in REPEATS:
		var node := BuildingCache.instance(layout, true)
		await get_tree().physics_frame
		var s0 := Time.get_ticks_usec()
		add_child(node)
		var ms := float(Time.get_ticks_usec() - s0) / 1000.0
		enter_best = minf(enter_best, ms)
		remove_child(node)
		node.free()
		await get_tree().physics_frame
	printerr("[cost] ENTER tree, best of %d: %.3f ms" % [REPEATS, enter_best])

	## PORT SCALE — the CURVE, and a control that varies exactly one input:
	## whether the building is asked for with collision at all (REALITY.md §4e).
	## Without it, "collision at port scale is expensive" cannot be told apart
	## from "717 meshes at port scale are expensive", which is what the totals
	## below are mostly made of.
	for n in [5, 10, 20, 40]:
		for want_collision in [false, true]:
			await get_tree().physics_frame
			var batch: Array = []
			var b0 := Time.get_ticks_usec()
			for i in n:
				var node := BuildingCache.instance(layout, want_collision)
				node.position = Vector3(float(i) * 60.0, 0.0, 0.0)
				add_child(node)
				batch.append(node)
			var ms := float(Time.get_ticks_usec() - b0) / 1000.0
			await get_tree().physics_frame
			var shapes := 0
			for node_variant in batch:
				shapes += _shapes(node_variant as Node)
			printerr("[curve] %3d buildings, collision=%s: %8.1f ms total, %6.2f ms each, %d shapes"
				% [n, "on " if want_collision else "off", ms, ms / float(n), shapes])
			for node_variant in batch:
				var node := node_variant as Node
				remove_child(node)
				node.free()
			await get_tree().physics_frame

	await get_tree().physics_frame
	var held: Array = []
	var p0 := Time.get_ticks_usec()
	for i in PORT_SCALE:
		var node := BuildingCache.instance(layout, true)
		node.position = Vector3(float(i) * 60.0, 0.0, 0.0)
		add_child(node)
		held.append(node)
	var port_ms := float(Time.get_ticks_usec() - p0) / 1000.0
	await get_tree().physics_frame
	var total_shapes := 0
	for node_variant in held:
		total_shapes += _shapes(node_variant as Node)
	printerr("[cost] PORT SCALE %d buildings: %.1f ms total, %.2f ms each, %d shapes in the space"
		% [PORT_SCALE, port_ms, port_ms / float(PORT_SCALE), total_shapes])

	## Distinct shape RIDs across every instance — the cache's whole point on the
	## collision side. Counted through PhysicsServer3D, not off the resources.
	var rids := {}
	for node_variant in held:
		var body := (node_variant as Node).get_node_or_null("Collision") as StaticBody3D
		if body == null:
			continue
		var rid := body.get_rid()
		for i in PhysicsServer3D.body_get_shape_count(rid):
			rids[str(PhysicsServer3D.body_get_shape(rid, i))] = true
	printerr("[cost] distinct shape RIDs across %d buildings holding %d shapes: %d"
		% [PORT_SCALE, total_shapes, rids.size()])

	## A physics query over the whole lot, so the cost of HAVING them is measured
	## and not only the cost of making them.
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	query.shape = capsule
	query.collide_with_bodies = true
	var q0 := Time.get_ticks_usec()
	var hits := 0
	for i in 2000:
		query.transform = Transform3D(Basis.IDENTITY,
			Vector3(fmod(float(i) * 7.3, float(PORT_SCALE) * 60.0), 0.9, fmod(float(i) * 3.1, 12.0) - 6.0))
		hits += space.intersect_shape(query, 4).size()
	var q_ms := float(Time.get_ticks_usec() - q0) / 1000.0
	printerr("[cost] 2000 capsule queries over the whole port: %.1f ms (%d hits)" % [q_ms, hits])

	for node_variant in held:
		var node := node_variant as Node
		remove_child(node)
		node.free()
	get_tree().quit(0)


func _meshes(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _meshes(child)
	return n


func _objects(node: Node) -> int:
	var n := 1 if node is CollisionObject3D else 0
	for child in node.get_children():
		n += _objects(child)
	return n


func _shapes(node: Node) -> int:
	var n := 0
	if node is PhysicsBody3D:
		n += PhysicsServer3D.body_get_shape_count((node as PhysicsBody3D).get_rid())
	for child in node.get_children():
		n += _shapes(child)
	return n
