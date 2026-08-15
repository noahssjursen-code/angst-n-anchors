extends Node

## Scratch probe (leading underscore — not a gate unit). Lane B.
## Which yaw puts a `railing`'s run along the PORT side rather than across the
## deck? The brick draws its run spanning local X on the local −Z face, so the
## answer is a rotation fact, and guessing it costs a render cycle. Measured.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var grid := HullRegistry.make_grid("hull_15x5")
	var cell := Vector3i(0, 0, 20)  ## a port-edge cell, well aft of the taper
	print("cell %v centre local %v  (cell spans x %.2f..%.2f, z %.2f..%.2f)" % [
		cell, grid.cell_center_local(cell),
		grid.cell_center_local(cell).x - 0.25, grid.cell_center_local(cell).x + 0.25,
		grid.cell_center_local(cell).z - 0.25, grid.cell_center_local(cell).z + 0.25,
	])
	for yaw in [0, 90, 180, 270]:
		var layout := BrickLayout.new()
		layout.hull_id = "hull_15x5"
		layout.set_brick(cell, "railing", yaw)
		var boat := VesselSpawn.instantiate("hull_15x5", layout.to_dict(), "general_vessel")
		add_child(boat)
		await get_tree().process_frame
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		_bounds(boat.get_node_or_null("DeckFitout"), boat, lo, hi)
		var b := _collect(boat.get_node_or_null("DeckFitout"), boat)
		print("  yaw %3d -> x %+.3f..%+.3f (%.2f m)   z %+.3f..%+.3f (%.2f m)" % [
			yaw, b[0].x, b[1].x, b[1].x - b[0].x, b[0].z, b[1].z, b[1].z - b[0].z,
		])
		boat.free()
		await get_tree().process_frame
	get_tree().quit(0)

func _bounds(_n: Node, _r: Node, _lo: Vector3, _hi: Vector3) -> void:
	pass

func _collect(node: Node, root: Node3D) -> Array:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	if node == null:
		return [lo, hi]
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var aabb := m.get_aabb()
		for i in range(8):
			var p: Vector3 = root.to_local(m.global_transform * aabb.get_endpoint(i))
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	return [lo, hi]
