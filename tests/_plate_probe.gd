extends SceneTree

## Scratch probe — not a gate unit (leading underscore, like _chain_probe.gd).

func _initialize() -> void:
	var text := FileAccess.get_file_as_string(
		"res://resources/data/structures/probe_plate_deckhouse.json")
	var data: Dictionary = JSON.parse_string(text)
	var plan := StructurePlan.from_dict(data)
	print("items=%d walls=%d" % [plan.items.size(), plan.walls.size()])
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var props := StructurePlan.item_props(item)
		var problem := StructureBaker.plate_problem(props)
		var panels := StructureBaker.plate_panels(props)
		var frames := StructureBaker.plate_frames(props)
		var cols := StructureBaker.collect_colliders(_solo(item)).size()
		var root := StructureBaker.bake(_solo(item))
		var tris := _tris(root)
		root.free()
		print("id=%d problem=%s panels=%d frames=%d tris=%d (expect %d) colliders=%d  %s" % [
			int(item["id"]), "-" if problem.is_empty() else problem,
			panels.size(), frames.size(), tris, 12 * (panels.size() + frames.size()), cols,
			str(props.get("__is", ""))])
	var whole := StructureBaker.bake(plan)
	print("WHOLE: instances=%d tris=%d colliders=%d" % [
		whole.get_child_count(), _tris(whole), StructureBaker.collect_colliders(plan).size()])
	whole.free()
	print("degenerate cases:")
	for spec in [
		{"corners": [[0,0,0],[1,0,0],[1,0,1]]},
		{"corners": [[0,0,0],[1,0,0],[2,0,0],[3,0,0]]},
		{"corners": [[0,0,0],[1,0,0],[0,1,0],[1,1,0]]},
		{"corners": [[0,0,0],[1,0,0],[1,1,0],[0,1,0]], "thickness": 0.0},
		{"corners": [[0,0,0],[1,0,0],[1,1,0],[0,1,0]]},
		{"corners": [[0,0,0],[2,0,0],[0,1,0],[1,1,0]]},
		{"corners": [[0,0,0],[1,0,0],[1,0,0.00001],[0,1,0]]},
		{"corners": [[0,0,0],[1,0,0],[1,1,0],[0,1,NAN]]},
		{"corners": [[0,0,0],[3,0,0],[1,0,0],[2,0,0]]},
	]:
		print("  %s -> %s" % [str(spec.get("corners")), StructureBaker.plate_problem(spec)])
	quit(0)


func _solo(item: Dictionary) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.items = [item]
	return plan


func _tris(root: Node) -> int:
	var count := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh as ArrayMesh
			for surface in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return count
