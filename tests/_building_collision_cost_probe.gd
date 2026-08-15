extends Node

## SCRATCH PROBE (leading underscore — not a gate unit). Lane B.
##
## Answers three questions with numbers, none of them from a dictionary:
##  A. how many colliders does `BuildingFitout` emit for the warehouse, and of
##     what kinds;
##  B. does the vessel-side finding (Jolt rebuilds a body's compound on every
##     `body_add_shape`, but ONLY while the body is in a space) transfer to a
##     building? One input varied — body in the tree before its shapes are added,
##     or after — holding shapes, sizes, yaws and order identical;
##  C. what a stamp costs, and what a port full of them costs.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_building_collision_cost_probe.tscn

const REPEATS := 5


func _ready() -> void:
	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		printerr("[probe] warehouse did not load")
		get_tree().quit(1)
		return
	var bricks := layout.iter_primary_cells().size()
	printerr("[probe] warehouse: %d primary cells, %d cells total"
		% [bricks, layout.iter_cells().size()])

	# ── A. What BuildingFitout emits ─────────────────────────────────────────
	var fitout := BuildingFitout.build(layout, true)
	var body := fitout.get_node_or_null("Collision") as StaticBody3D
	var shapes: Array = []
	if body != null:
		for child in body.get_children():
			if child is CollisionShape3D:
				shapes.append(child)
	var kinds := {}
	for s_variant in shapes:
		var s := s_variant as CollisionShape3D
		var k := s.shape.get_class()
		kinds[k] = int(kinds.get(k, 0)) + 1
	printerr("[A] BuildingFitout emits %d CollisionShape3D on its Collision body; kinds %s"
		% [shapes.size(), str(kinds)])
	var doors: Array = []
	_find_doors(fitout, doors)
	printerr("[A] BrickDoor nodes in the fit-out: %d" % doors.size())
	printerr("[A] meshes in the fit-out: %d" % _count_meshes(fitout))
	## Distinct shape sizes — how much a shared-resource cache can win.
	var distinct := {}
	for s_variant in shapes:
		var s := s_variant as CollisionShape3D
		if s.shape is BoxShape3D:
			distinct[str((s.shape as BoxShape3D).size)] = true
	printerr("[A] distinct box sizes: %d" % distinct.size())
	fitout.free()

	# ── B. In a space vs out of one, one input varied ────────────────────────
	await get_tree().physics_frame
	for n in [128, 256, 512, 577, 1024, 2048]:
		var out_ms := await _time_adds(n, false)
		var in_ms := await _time_adds(n, true)
		printerr("[B] %5d boxes: detached %8.2f ms | in-space %8.2f ms | ratio %6.2fx"
			% [n, out_ms, in_ms, in_ms / maxf(out_ms, 0.0001)])

	get_tree().quit(0)


func _time_adds(count: int, in_space: bool) -> float:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)
	var holder := Node3D.new()
	var body := StaticBody3D.new()
	holder.add_child(body)
	if in_space:
		add_child(holder)
		await get_tree().physics_frame
	var t0 := Time.get_ticks_usec()
	for i in count:
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(float(i % 32), float(i / 1024), float((i / 32) % 32))
		body.add_child(col)
	var elapsed := float(Time.get_ticks_usec() - t0) / 1000.0
	var held := PhysicsServer3D.body_get_shape_count(body.get_rid())
	if held != count:
		printerr("    [!] body holds %d shapes for %d adds" % [held, count])
	if in_space:
		remove_child(holder)
	holder.free()
	await get_tree().physics_frame
	return elapsed


func _find_doors(node: Node, out: Array) -> void:
	if node is BrickDoor:
		out.append(node)
	for child in node.get_children():
		_find_doors(child, out)


func _count_meshes(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _count_meshes(child)
	return n
