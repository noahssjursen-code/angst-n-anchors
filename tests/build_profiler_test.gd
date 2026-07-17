extends SceneTree


func _initialize() -> void:
	var root := Node3D.new()
	var sample := MeshBuilder.box(Vector3.ONE, Color(0.4, 0.5, 0.6))
	root.add_child(sample)
	var stats := BuildProfiler.analyze_node(root)
	assert(int(stats.get("mesh_instances", 0)) == 1, "BuildProfiler should count mesh instances")
	assert(int(stats.get("node_count", 0)) >= 2, "BuildProfiler should count nodes")
	var text := BuildProfiler.format_billboard("Test", stats, 500.0, "HIT")
	assert(text.contains("500"), "billboard should include distance")
	assert(BuildProfiler.tier_index(100.0) == 0)
	assert(BuildProfiler.tier_index(5000.0) == 3)
	assert(BuildProfiler.lod_label(100.0) == "T0 FULL")
	assert(BuildProfiler.lod_label(5000.0) == "T3 FAR")
	root.free()
	print("build_profiler_test: PASS")
	quit(0)
