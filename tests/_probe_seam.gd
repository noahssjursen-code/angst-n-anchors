extends SceneTree
## Scratch: does a plan carrying pieces[] reach the BAKER, or only the resolver?
const PATH := "res://resources/data/structures/probe_piece_trawler.json"

func _initialize() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var doc := raw as Dictionary

	var as_authored := StructurePlan.from_dict(doc)
	var resolved := PieceKit.resolve_document(doc)
	var as_resolved := StructurePlan.from_dict(resolved["doc"] as Dictionary)

	print("authored: items=%d pieces=%d   resolved: items=%d pieces=%d"
		% [as_authored.items.size(), as_authored.pieces.size(),
			as_resolved.items.size(), as_resolved.pieces.size()])

	for label in [["AS AUTHORED (pieces[])", as_authored], ["AS RESOLVED (items[])", as_resolved]]:
		var plan := label[1] as StructurePlan
		var node := StructureBaker.bake(plan)
		var surfaces := 0
		var tris := 0
		for child in node.find_children("*", "MeshInstance3D", true, false):
			var mesh := (child as MeshInstance3D).mesh
			if mesh == null:
				continue
			surfaces += mesh.get_surface_count()
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				if idx is PackedInt32Array:
					tris += (idx as PackedInt32Array).size() / 3
				else:
					tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var colliders := StructureBaker.collect_colliders(plan)
		print("  %-24s  surfaces=%d  triangles=%d  colliders=%d"
			% [str(label[0]), surfaces, tris, colliders.size()])
		node.queue_free()
	quit()
