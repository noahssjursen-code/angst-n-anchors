extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const IMPOSTOR_CACHE := preload("res://scripts/core/impostor_cache.gd")


func _initialize() -> void:
	var t := TestReport.new("impostor_cache_test")
	IMPOSTOR_CACHE.clear()
	t.check("empty cache should miss", not IMPOSTOR_CACHE.has_key("missing"))
	var stage := Node3D.new()
	var box := MeshBuilder.box(Vector3(2.0, 4.0, 6.0), Color(0.5, 0.4, 0.3))
	box.position = Vector3(0.0, 2.0, 0.0)
	stage.add_child(box)
	var aabb := IMPOSTOR_CACHE.compute_local_aabb(stage)
	t.check("AABB should cover box", aabb.size.x > 1.5 and aabb.size.y > 3.5 and aabb.size.z > 5.5)
	var stamp := IMPOSTOR_CACHE.instance("missing")
	t.check("missing key stamps empty root", stamp.get_child_count() == 0)
	stamp.free()
	stage.free()
	t.finish(self)
