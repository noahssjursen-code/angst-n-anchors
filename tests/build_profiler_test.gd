extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	var t := TestReport.new("build_profiler_test")
	var root := Node3D.new()
	var sample := MeshBuilder.box(Vector3.ONE, Color(0.4, 0.5, 0.6))
	root.add_child(sample)
	var stats := BuildProfiler.analyze_node(root)
	t.check("BuildProfiler should count mesh instances", int(stats.get("mesh_instances", 0)) == 1)
	t.check("BuildProfiler should count nodes", int(stats.get("node_count", 0)) >= 2)
	var text := BuildProfiler.format_billboard("Test", stats, 500.0, "HIT")
	t.check("billboard should include distance", text.contains("500"))
	t.check("100 m is tier 0", BuildProfiler.tier_index(100.0) == 0)
	t.check("5000 m is tier 3", BuildProfiler.tier_index(5000.0) == 3)
	t.check("100 m labels T0 FULL", BuildProfiler.lod_label(100.0) == "T0 FULL")
	t.check("5000 m labels T3 FAR", BuildProfiler.lod_label(5000.0) == "T3 FAR")
	root.free()
	t.finish(self)
