extends SceneTree

func _initialize() -> void:
	var boxes: Array = [
		{"center": Vector3(0, -0.1, 0), "size": Vector3(8, 0.2, 8)},
		{"center": Vector3(0, 1.5, 2), "size": Vector3(6, 3, 0.3)},
		{"center": Vector3(2, 1.5, 0), "size": Vector3(0.3, 3, 6)},
	]
	var ao := StructureAO.from_boxes(boxes)
	print(ao.stats())
	var p := Vector3(1.8, 0.5, 1.85)
	var n := Vector3(0, 0, -1)
	var cand: PackedInt32Array = ao._candidates(p)
	print("candidates: ", cand)
	var probe := p + Vector3(0.7071, 0, -0.7071) * 0.27
	print("probe ", probe, " inside_any=", ao._inside_any(probe, cand))
	print("inside all: ", ao._inside_any(probe, PackedInt32Array([0, 1, 2])))
	print("occ=", ao.occlusion_at(p, n))
	quit(0)
