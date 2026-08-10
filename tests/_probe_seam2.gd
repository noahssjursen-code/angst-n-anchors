extends SceneTree
## Can the seam be pinned by a SMALL synthetic plan (fast enough for lane A)?
func _initialize() -> void:
	var pieces: Array = []
	var id := 1
	for entry in [
		["corner_45", [0, 0, 0], 0], ["corner_45", [8, 0, 0], 270],
		["corner_45", [8, 0, 8], 180], ["corner_45", [0, 0, 8], 90],
		["wall_panel", [1, 0, 0], 0], ["wall_panel", [8, 0, 1], 270],
		["wall_panel", [7, 0, 8], 180], ["wall_panel", [0, 0, 7], 90],
	]:
		pieces.append({"id": id, "piece": str(entry[0]), "cell": entry[1],
			"facing": int(entry[2]), "params": {"span": 6 if str(entry[0]) == "wall_panel" else 1,
			"height": 5}})
		id += 1
	var doc := {"format": "structure_plan_v1", "hull_id": "hull_28x10", "pieces": pieces}
	print("is_plan: ", StructurePlan.is_plan(doc))
	var authored := StructurePlan.from_dict(doc)
	var resolved := StructurePlan.from_dict(
		PieceKit.resolve_document(doc.duplicate(true))["doc"] as Dictionary)
	print("authored items=%d pieces=%d  resolved items=%d pieces=%d"
		% [authored.items.size(), authored.pieces.size(), resolved.items.size(), resolved.pieces.size()])
	for pair in [["authored", authored], ["resolved", resolved]]:
		var plan := pair[1] as StructurePlan
		var t := Time.get_ticks_msec()
		var node := StructureBaker.bake(plan)
		var tris := 0
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mesh := (child as MeshInstance3D).mesh
			if mesh == null: continue
			for s in mesh.get_surface_count():
				var a := mesh.surface_get_arrays(s)
				var idx: Variant = a[Mesh.ARRAY_INDEX]
				tris += ((idx as PackedInt32Array).size() / 3) if idx is PackedInt32Array \
					else ((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
		print("  %-9s triangles=%-6d colliders=%-4d  bake %d ms"
			% [str(pair[0]), tris, StructureBaker.collect_colliders(plan).size(), Time.get_ticks_msec() - t])
		node.queue_free()
	quit()
