extends SceneTree

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")
const FOREST_STREAMER := preload("res://scripts/world/world_forest_streamer.gd")
const TREE_MESH := preload("res://scripts/world/forest_tree_mesh.gd")
const PROP_LOD := preload("res://scripts/world/world_prop_lod.gd")
const SEED := 90210

var _failures := PackedStringArray()


func _initialize() -> void:
	var layout: WorldLayout = GENERATOR.generate(SEED)
	ForestField.initialize(layout, SEED, [])
	_test_density(layout)
	_test_meshes()
	_test_transforms(layout)
	_test_requests(layout)
	ForestField.clear()
	_finish()


func _test_density(layout: WorldLayout) -> void:
	var water := ForestField.sample(Vector2(-18000.0, 0.0))
	_check(water <= 0.001, "open water has no forest")
	var a := ForestField.sample(Vector2(12000.0, 8000.0))
	var b := ForestField.sample(Vector2(12000.0, 8000.0))
	_check(is_equal_approx(a, b), "forest density is deterministic")
	var tex := ForestField.coverage_texture()
	_check(tex != null and tex.get_width() == ForestField.COVERAGE_MAP_SIZE, "coverage map bakes")
	var shore := layout.coastline_contours[0] if not layout.coastline_contours.is_empty() else PackedVector2Array()
	if shore.size() >= 2:
		var mid: Vector2 = shore[0].lerp(shore[1], 0.5)
		_check(ForestField.sample(mid) <= 0.05, "waterline itself stays bare")


func _test_meshes() -> void:
	var near := TREE_MESH.build_near_spruce()
	var mid := TREE_MESH.build_mid_card()
	_check(near.get_surface_count() >= 1, "near spruce ArrayMesh has a surface")
	_check(mid.get_surface_count() >= 1, "mid card ArrayMesh has a surface")
	_check(near.get_faces().size() > 12, "near spruce is faceted, not empty")


func _test_transforms(layout: WorldLayout) -> void:
	var found := false
	for z in range(4, 16):
		for x in range(8, 18):
			var transforms := FOREST_STREAMER.build_chunk_transforms(
				layout, Vector2i(x, z), 28.0, 120, []
			)
			if transforms.is_empty():
				continue
			found = true
			_check(transforms.size() <= 120, "chunk respects instance cap")
			for xf in transforms:
				_check(xf.origin.y > 0.5, "trees sit on land height")
			break
		if found:
			break
	_check(found, "at least one inland chunk places trees")


func _test_requests(layout: WorldLayout) -> void:
	var requests := FOREST_STREAMER.select_chunk_requests(
		Vector2(12000.0, 8000.0), layout.half_extent_m, PROP_LOD.CULL_M
	)
	_check(not requests.is_empty(), "forest streamer queues nearby chunks")
	_check(
		FOREST_STREAMER.stabilize_tier(
			PROP_LOD.Tier.PROXY, PROP_LOD.Tier.FULL, PROP_LOD.LOD_NEAR_M + 50.0
		) == PROP_LOD.Tier.FULL,
		"LOD hysteresis keeps FULL briefly when leaving near ring",
	)


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("ForestField / forest streamer tests: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("Forest test: " + failure)
	quit(1)
