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
	_test_refresh_gate()
	_test_bounded_distribution()
	_test_incremental_placement()
	_test_cached_empty_chunks()
	ForestField.clear()
	_finish()


class FlatForestLayout extends RefCounted:
	var half_extent_m := 20000.0
	func sample_signed_distance(_p: Vector2) -> float: return -500.0
	func sample_height(_p: Vector2) -> float: return 30.0

class SeaLayout extends RefCounted:
	var half_extent_m := 20000.0
	func sample_signed_distance(_p: Vector2) -> float: return 500.0
	func sample_height(_p: Vector2) -> float: return -30.0

func _test_cached_empty_chunks() -> void:
	var sea := SeaLayout.new()
	ForestField.clear()
	ForestField.initialize(sea, SEED, [])
	var streamer := FOREST_STREAMER.new()
	streamer._layout = sea
	streamer._build_chunk(Vector2i.ZERO, PROP_LOD.Tier.FULL)
	var key := STREAMER.chunk_key(Vector2i.ZERO)
	_check(streamer._chunks.has(key), "empty sea chunks are remembered")
	_check(streamer._chunks[key].instances == 0, "empty chunks contain no scene instances")
	streamer._refresh_requests(Vector3(128, 0, 128))
	_check(not streamer._queued.has(key), "moving observer does not resample a completed empty chunk")
	streamer._build_chunk(Vector2i.ZERO, PROP_LOD.Tier.PROXY)
	_check(streamer._chunks[key].transforms.is_empty(), "empty result survives a detail change")
	streamer.free()

func _test_incremental_placement() -> void:
	var flat := FlatForestLayout.new()
	ForestField.clear()
	ForestField.initialize(flat, SEED, [])
	var expected := FOREST_STREAMER.build_chunk_transforms(flat, Vector2i.ZERO, 6.5, 1521)
	var job := FOREST_STREAMER.create_placement_job(Vector2i.ZERO, 6.5, 1521)
	var steps := 0
	while not job.done:
		var before: int = job.cursor
		FOREST_STREAMER.advance_placement_job(flat, job, [], 16, true)
		_check(job.cursor - before <= 16, "placement obeys per-step candidate budget")
		steps += 1
	_check(steps > 1, "dense placement is spread across multiple steps")
	_check(job.transforms == expected, "incremental placement preserves deterministic transforms")
	var grouped := 0
	for group in job.groups: grouped += group.size()
	_check(grouped == expected.size(), "incremental species grouping retains every tree")


func _test_bounded_distribution() -> void:
	var flat := FlatForestLayout.new()
	ForestField.initialize(flat,SEED,[])
	var full := FOREST_STREAMER.build_chunk_transforms(flat,Vector2i.ZERO,6.5,160,[])
	var reduced := FOREST_STREAMER.build_chunk_transforms(flat,Vector2i.ZERO,6.5,90,[])
	var quadrants := {}
	for xf in full:
		quadrants[Vector2i(int(xf.origin.x/128),int(xf.origin.z/128))] = true
	_check(quadrants.size()==4,"capped forest covers all four chunk quadrants")
	_check(full.size()==160 and reduced.size()==90,"dense chunk honors both budgets")
	for i in reduced.size():
		_check(reduced[i]==full[i],"mid trees retain near positions")
	for species in 4:
		for near in [true,false]:
			var mesh := TREE_MESH.species_mesh(species,near)
			_check(mesh.get_surface_count()<=2,"at most bark and foliage surfaces")
			_check(mesh.get_faces().size()/3<=2100,"vegetation geometry budget")
			if near:
				var textured_bark := false
				for surface in mesh.get_surface_count():
					var mat := mesh.surface_get_material(surface) as ShaderMaterial
					if mat != null:
						textured_bark = textured_bark or (mat.get_shader_parameter("bark_colour") != null and mat.get_shader_parameter("bark_normal") != null)
				_check(textured_bark, "near bark retains opaque colour and normal maps")
			if not near:
				_check(mesh.get_faces().size()/3 == 2, "distant tree is one cutout card")
				_check(mesh.custom_aabb.size.z >= mesh.get_aabb().size.x, "billboard bounds cover all camera angles")


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
	## Port town trapezoid must zero canopy (forest_clear_only polygon).
	var inland := Vector2(12000.0, 8000.0)
	var before := ForestField.sample(inland)
	ForestField.clear()
	var town := PackedVector2Array([
		inland + Vector2(-80.0, -80.0),
		inland + Vector2(80.0, -80.0),
		inland + Vector2(80.0, 80.0),
		inland + Vector2(-80.0, 80.0),
	])
	ForestField.initialize(layout, SEED, [{
		"forest_clear_only": true,
		"polygon": town,
		"facility_id": "test:town_forest_clear",
	}])
	_check(ForestField.sample(inland) <= 0.001, "town forest clear zeros canopy")
	_check(before >= 0.0, "baseline inland sample ran")
	ForestField.clear()
	ForestField.initialize(layout, SEED, [])


func _test_meshes() -> void:
	var near := TREE_MESH.build_near_spruce()
	var mid := TREE_MESH.build_mid_card()
	_check(near.get_surface_count() >= 1, "near spruce ArrayMesh has a surface")
	_check(mid.get_surface_count() >= 1, "mid card ArrayMesh has a surface")
	_check(near.get_faces().size() > 12, "near spruce is faceted, not empty")


func _test_transforms(layout: WorldLayout) -> void:
	var found := false
	for z in range(16, 64, 4):
		for x in range(32, 72, 4):
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


func _test_refresh_gate() -> void:
	var streamer := FOREST_STREAMER.new()
	streamer._last_request_xz = Vector2.ZERO
	_check(not streamer._should_refresh_requests(Vector2(20.0, 10.0)), "forest skips stationary request rebuilds")
	_check(streamer._should_refresh_requests(Vector2(60.0, 0.0)), "forest refreshes after meaningful movement")
	streamer.free()


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
