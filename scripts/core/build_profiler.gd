class_name BuildProfiler
extends RefCounted

## Synchronous build timing + scene-tree stats for perf showcases and tests.


static func measure(build: Callable, clear_cache: Callable = Callable()) -> Dictionary:
	if clear_cache.is_valid():
		clear_cache.call()
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_process_frames()
	var built: Variant = build.call()
	var t1 := Time.get_ticks_usec()
	var f1 := Engine.get_process_frames()
	var node := built as Node
	var stats := analyze_node(node)
	stats["ms"] = float(t1 - t0) / 1000.0
	stats["frames"] = maxi(1, f1 - f0 + 1)
	stats["cache_cleared"] = clear_cache.is_valid()
	return stats


static func analyze_node(root: Node) -> Dictionary:
	if root == null:
		return _empty_stats()
	var acc := {
		"mesh_instances": 0,
		"collision_shapes": 0,
		"static_bodies": 0,
		"node_count": 0,
		"material_ids": {},
	}
	_count_recursive(root, acc)
	var material_ids: Dictionary = acc["material_ids"] as Dictionary
	return {
		"node": root,
		"mesh_instances": int(acc["mesh_instances"]),
		"collision_shapes": int(acc["collision_shapes"]),
		"static_bodies": int(acc["static_bodies"]),
		"node_count": int(acc["node_count"]),
		"materials": material_ids.size(),
		"draw_calls_est": int(acc["mesh_instances"]),
	}


static func format_billboard(
		title: String,
		stats: Dictionary,
		distance_m: float,
		cache_hit: String = "",
		extra: PackedStringArray = PackedStringArray(),
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(title)
	if not cache_hit.is_empty():
		lines.append("Cache: %s" % cache_hit)
	lines.append(
		"Parts: %d mi · %d coll · %d nodes"
		% [
			int(stats.get("mesh_instances", 0)),
			int(stats.get("collision_shapes", 0)),
			int(stats.get("node_count", 0)),
		]
	)
	lines.append(
		"Build: %.1f ms (%d frame%s)"
		% [
			float(stats.get("ms", 0.0)),
			int(stats.get("frames", 1)),
			"s" if int(stats.get("frames", 1)) != 1 else "",
		]
	)
	lines.append(
		"Draw est: %d · mats: %d"
		% [int(stats.get("draw_calls_est", 0)), int(stats.get("materials", 0))]
	)
	lines.append("Distance: %.0f m · %s" % [distance_m, lod_label(distance_m)])
	for line in extra:
		lines.append(line)
	return "\n".join(lines)


static func lod_label(distance_m: float) -> String:
	return tier_label(tier_index(distance_m))


static func tier_index(distance_m: float) -> int:
	if distance_m < 200.0:
		return 0
	if distance_m < 800.0:
		return 1
	if distance_m < 2200.0:
		return 2
	if distance_m < 6000.0:
		return 3
	if distance_m < 12000.0:
		return 4
	return 5


static func tier_label(tier: int) -> String:
	match clampi(tier, 0, 5):
		0:
			return "T0 FULL"
		1:
			return "T1 NEAR"
		2:
			return "T2 MID"
		3:
			return "T3 FAR"
		4:
			return "T4 HORIZON"
		_:
			return "T5 DORMANT"


static func _count_recursive(node: Node, acc: Dictionary) -> void:
	acc["node_count"] = int(acc["node_count"]) + 1
	if node is MeshInstance3D:
		acc["mesh_instances"] = int(acc["mesh_instances"]) + 1
		var mi := node as MeshInstance3D
		var mat := mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
		if mat != null:
			var material_ids: Dictionary = acc["material_ids"] as Dictionary
			material_ids[mat.get_instance_id()] = true
	elif node is CollisionShape3D:
		acc["collision_shapes"] = int(acc["collision_shapes"]) + 1
	elif node is StaticBody3D:
		acc["static_bodies"] = int(acc["static_bodies"]) + 1
	for child in node.get_children():
		_count_recursive(child, acc)


static func _empty_stats() -> Dictionary:
	return {
		"node": null,
		"mesh_instances": 0,
		"collision_shapes": 0,
		"static_bodies": 0,
		"node_count": 0,
		"materials": 0,
		"draw_calls_est": 0,
		"ms": 0.0,
		"frames": 0,
		"cache_cleared": false,
	}
