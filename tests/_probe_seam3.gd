extends SceneTree
## Decisive: a wall_glazed resolves to FIVE plates. Does the baker draw five from
## a pieces[] entry, or one, or none?
func _initialize() -> void:
	for case in [
		["wall_panel  (resolves to 1 plate)", "wall_panel", {"span": 4, "height": 5}],
		["wall_glazed (resolves to 5 plates)", "wall_glazed",
			{"span": 4, "height": 5, "sill": 2, "band": 2, "lights": 3}],
		["trim_band   (resolves to 1 plate)", "trim_band", {"span": 4, "profile": "cap"}],
	]:
		var doc := {"format": "structure_plan_v1", "hull_id": "hull_28x10",
			"pieces": [{"id": 1, "piece": str(case[1]), "cell": [0, 0, 0], "facing": 0,
				"params": case[2]}]}
		var authored := StructurePlan.from_dict(doc)
		var resolved := StructurePlan.from_dict(
			PieceKit.resolve_document(doc.duplicate(true))["doc"] as Dictionary)
		var out := PackedStringArray()
		for pair in [["authored", authored], ["resolved", resolved]]:
			var plan := pair[1] as StructurePlan
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
			out.append("%s items=%d pieces=%d tris=%d colliders=%d"
				% [str(pair[0]), plan.items.size(), plan.pieces.size(), tris,
					StructureBaker.collect_colliders(plan).size()])
			node.queue_free()
		print("%s\n    %s\n    %s" % [str(case[0]), out[0], out[1]])
	quit()
