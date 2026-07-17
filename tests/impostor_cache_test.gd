extends SceneTree

const IMPOSTOR_CACHE := preload("res://scripts/core/impostor_cache.gd")


func _initialize() -> void:
	IMPOSTOR_CACHE.clear()
	assert(not IMPOSTOR_CACHE.has_key("missing"), "empty cache should miss")
	var root := Node3D.new()
	var box := MeshBuilder.box(Vector3(2.0, 4.0, 6.0), Color(0.5, 0.4, 0.3))
	box.position = Vector3(0.0, 2.0, 0.0)
	root.add_child(box)
	var aabb := IMPOSTOR_CACHE.compute_local_aabb(root)
	assert(aabb.size.x > 1.5 and aabb.size.y > 3.5 and aabb.size.z > 5.5, "AABB should cover box")
	var stamp := IMPOSTOR_CACHE.instance("missing")
	assert(stamp.get_child_count() == 0, "missing key stamps empty root")
	stamp.free()
	root.free()
	print("impostor_cache_test: PASS")
	quit(0)
