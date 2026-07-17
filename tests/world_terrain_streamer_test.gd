extends SceneTree

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")
const SEED := 90210

var _failures := PackedStringArray()


func _initialize() -> void:
	var layout: WorldLayout = GENERATOR.generate(SEED)
	_test_deterministic_mesh(layout)
	_test_shared_borders(layout)
	_test_water_and_shoreline(layout)
	_test_submerged_shelf_has_no_collision()
	_test_water_edge_skirts()
	_test_flatten_pads(layout)
	_test_chunk_zone_filtering()
	_test_collision_selection()
	_test_chunk_keys_and_refresh_gate()
	_test_request_and_queue_limits(layout)
	_test_runtime_queue(layout)
	_test_empty_water_retention(layout)
	_test_collision_cleanup_after_jump()
	_test_boot_ready_ring(layout)
	_finish()


func _test_deterministic_mesh(layout: WorldLayout) -> void:
	var a := STREAMER.build_chunk_mesh_data(layout, Vector2i(11, 12), 50.0)
	var b := STREAMER.build_chunk_mesh_data(layout, Vector2i(11, 12), 50.0)
	_check(a["vertices"] == b["vertices"], "mesh vertices are deterministic")
	_check(a["indices"] == b["indices"], "mesh topology is deterministic")
	_check(a["normals"] == b["normals"], "mesh normals are deterministic")
	_check(int(a["surface_side"]) == 21, "1 km chunk uses expected 50 m grid")
	var vertices: PackedVector3Array = a["vertices"]
	var indices: PackedInt32Array = a["indices"]
	if indices.size() >= 3:
		var v0 := vertices[indices[0]]
		var v1 := vertices[indices[1]]
		var v2 := vertices[indices[2]]
		var xz_winding := (v1.z - v0.z) * (v2.x - v0.x) \
			- (v1.x - v0.x) * (v2.z - v0.z)
		_check(xz_winding < 0.0, "terrain top triangles use Godot clockwise front faces")
		_check(
			(a["normals"] as PackedVector3Array)[indices[0]].y > 0.0,
			"terrain top shading normals point upward",
		)


func _test_shared_borders(layout: WorldLayout) -> void:
	var west_east := STREAMER.sample_chunk_border(layout, Vector2i(10, 12), 25.0, &"east")
	var east_west := STREAMER.sample_chunk_border(layout, Vector2i(11, 12), 25.0, &"west")
	_check(west_east == east_west, "same-LOD neighboring borders match exactly")

	var fine := STREAMER.sample_chunk_border(layout, Vector2i(10, 12), 25.0, &"east")
	var coarse := STREAMER.sample_chunk_border(layout, Vector2i(11, 12), 100.0, &"west")
	var subset_matches := coarse.size() * 4 - 3 == fine.size()
	if subset_matches:
		for i in range(coarse.size()):
			if coarse[i] != fine[i * 4]:
				subset_matches = false
				break
	_check(subset_matches, "neighboring-LOD borders share exact coarse samples")


func _test_water_and_shoreline(layout: WorldLayout) -> void:
	var open_water := STREAMER.build_chunk_mesh_data(layout, Vector2i(-16, 14), 50.0)
	_check((open_water["indices"] as PackedInt32Array).size() == 0, "fully submerged chunk excludes terrain")

	var shoreline_found := false
	for z in range(-16, 16):
		for x in range(-16, 16):
			var data := STREAMER.build_chunk_mesh_data(layout, Vector2i(x, z), 100.0, [], 0.0)
			var distances: PackedFloat32Array = data["signed_distances"]
			var has_land := false
			var has_water := false
			for distance in distances:
				has_land = has_land or distance < 0.0
				has_water = has_water or distance >= 0.0
			if not (has_land and has_water):
				continue
			shoreline_found = true
			var vertices: PackedVector3Array = data["vertices"]
			var side := int(data["surface_side"])
			for i in range(distances.size()):
				if distances[i] >= 0.0:
					_check(
						vertices[i].y < 0.0,
						"near-shore terrain shelf continues below sea level",
					)
			_check(not (data["indices"] as PackedInt32Array).is_empty(), "shoreline chunk retains coastal land")
			_check(
				vertices.size() > side * side,
				"shoreline chunk adds zero-crossing vertices instead of stair-step quads",
			)
			break
		if shoreline_found:
			break
	_check(shoreline_found, "test locates a generated shoreline chunk")


func _test_submerged_shelf_has_no_collision() -> void:
	var cutoff := STREAMER.COLLISION_COAST_CUTOFF_Y
	var mixed := {
		"vertices": PackedVector3Array([
			Vector3(-1.0, cutoff + 2.0, 0.0),
			Vector3(1.0, cutoff - 2.0, -1.0),
			Vector3(1.0, cutoff - 2.0, 1.0),
		]),
		"indices": PackedInt32Array([0, 1, 2]),
		"surface_vertex_count": 3,
	}
	var clipped := STREAMER.collision_faces(mixed)
	_check(clipped.size() == 3, "shore collision clips a mixed triangle at water level")
	for point in clipped:
		_check(
			point.y >= cutoff - 0.0001,
			"terrain collision never extends below the waterline",
		)

	var submerged := {
		"vertices": PackedVector3Array([
			Vector3(-1.0, cutoff - 1.0, 0.0),
			Vector3(1.0, cutoff - 1.0, -1.0),
			Vector3(1.0, cutoff - 1.0, 1.0),
		]),
		"indices": PackedInt32Array([0, 1, 2]),
		"surface_vertex_count": 3,
	}
	_check(
		STREAMER.collision_faces(submerged).is_empty(),
		"fully submerged shelf remains visual-only",
	)


func _test_water_edge_skirts() -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for z in range(3):
		for x in range(3):
			vertices.append(Vector3(x, 0.0, z))
			colors.append(Color.WHITE)
	var distances := PackedFloat32Array()
	distances.resize(9)
	distances.fill(100.0)
	distances[4] = -10.0
	var indices := PackedInt32Array([0, 3, 1])
	STREAMER._append_skirts(vertices, colors, indices, distances, 3, 35.0)
	_check(indices.size() == 3, "all-water chunk borders do not emit visible skirts")

	vertices.resize(9)
	colors.resize(9)
	distances[0] = -10.0
	indices = PackedInt32Array([0, 3, 1])
	STREAMER._append_skirts(vertices, colors, indices, distances, 3, 35.0)
	_check(indices.size() == 3, "land→water border skirts are suppressed (no ocean forks)")

	vertices.resize(9)
	colors.resize(9)
	distances[1] = -10.0
	indices = PackedInt32Array([0, 3, 1])
	STREAMER._append_skirts(vertices, colors, indices, distances, 3, 35.0)
	_check(indices.size() > 3, "land→land chunk borders retain crack skirts")


func _test_flatten_pads(layout: WorldLayout) -> void:
	var center := Vector2(15000.0, 14500.0)
	var ports: Array = [{
		"world_position": Vector3(center.x, 99.0, center.y),
		"rotation_y": PI * 0.25,
		"size": 2,
		"flatten_shape": "rectangle",
		"pad_size_m": Vector2(300.0, 180.0),
		"flatten_falloff_m": 80.0,
	}]
	var zones := STREAMER.make_flatten_zones(ports, 0.0)
	_check(is_zero_approx(STREAMER.sample_terrain_height(layout, center, zones)), "port origin is flattened to sea-level pad height")
	var local_inside := Vector2(120.0, 0.0).rotated(PI * 0.25)
	_check(is_zero_approx(STREAMER.sample_terrain_height(layout, center + local_inside, zones)), "rotated rectangular pad has flat interior")
	var outside := center + Vector2(600.0, 0.0)
	_check(is_equal_approx(
		STREAMER.sample_terrain_height(layout, outside, zones),
		STREAMER.sample_terrain_height(layout, outside, []),
	), "flatten pad leaves terrain beyond smooth boundary unchanged")

	var water_center := Vector2(-15000.0, 14500.0)
	var water_zone := STREAMER.make_flatten_zones([{
		"world_position": Vector3(water_center.x, 0.0, water_center.y),
		"flatten_shape": "ellipse",
		"pad_size_m": Vector2(400.0, 300.0),
	}], 0.0)
	_check(is_zero_approx(STREAMER.sample_terrain_height(layout, water_center, water_zone)), "flattening does not create a water island")


func _test_chunk_zone_filtering() -> void:
	var near_zone := {
		"center": Vector2(950.0, 500.0),
		"half_size": Vector2(20.0, 20.0),
		"falloff": 40.0,
		"height": 0.0,
	}
	var far_zone := {
		"center": Vector2(5000.0, 5000.0),
		"half_size": Vector2(50.0, 50.0),
		"falloff": 20.0,
		"height": 0.0,
	}
	var selected := STREAMER.zones_intersecting_chunk([near_zone, far_zone], Vector2i.ZERO)
	_check(selected.size() == 1 and selected[0] == near_zone, "chunk filtering drops distant terrain zones")
	var adjacent := STREAMER.zones_intersecting_chunk([near_zone], Vector2i(1, 0))
	_check(adjacent.size() == 1, "chunk filtering retains zone falloff across a chunk edge")


func _test_collision_selection() -> void:
	_check(STREAMER.chunk_needs_collision(Vector2i(0, 0), Vector2(500.0, 500.0), 100.0), "near chunk receives collision")
	_check(not STREAMER.chunk_needs_collision(Vector2i(3, 3), Vector2.ZERO, 1800.0), "far chunk omits collision")
	_check(not STREAMER.chunk_needs_collision(Vector2i.ZERO, Vector2.ZERO, 0.0), "zero radius disables collision")


func _test_chunk_keys_and_refresh_gate() -> void:
	var coord := Vector2i(-17, 23)
	_check(STREAMER.chunk_key(coord) == coord, "chunk dictionaries use Vector2i keys")
	_check(STREAMER.parse_chunk_key(coord) == coord, "Vector2i chunk keys round-trip")
	var streamer := STREAMER.new()
	streamer.background_mesh_builds = false
	streamer._last_request_xz = Vector2.ZERO
	_check(not streamer._should_refresh_requests(Vector2(20.0, 10.0)), "small movement skips request rebuild")
	_check(streamer._should_refresh_requests(Vector2(60.0, 0.0)), "meaningful movement refreshes requests")
	streamer.free()


func _test_request_and_queue_limits(layout: WorldLayout) -> void:
	for step in STREAMER.DEFAULT_LOD_STEPS:
		_check(
			is_equal_approx(fmod(STREAMER.CHUNK_SIZE_M, float(step)), 0.0),
			"default LOD step %.1f divides a chunk exactly" % float(step),
		)
	var requests := STREAMER.select_chunk_requests(Vector2.ZERO, layout.half_extent_m, 9000.0)
	_check(not requests.is_empty(), "visual request set is populated")
	_check(requests.size() < 32 * 32, "visual radius does not load whole bounded world")
	var previous_distance := -1.0
	var all_in_bounds := true
	var min_coord := int(floor(-layout.half_extent_m / STREAMER.CHUNK_SIZE_M))
	var max_coord := int(ceil(layout.half_extent_m / STREAMER.CHUNK_SIZE_M)) - 1
	for request in requests:
		var coord: Vector2i = request["coord"]
		all_in_bounds = all_in_bounds and coord.x >= min_coord and coord.x <= max_coord \
			and coord.y >= min_coord and coord.y <= max_coord
		var distance := float(request["distance"])
		if distance < previous_distance:
			all_in_bounds = false
		previous_distance = distance
	_check(all_in_bounds, "requests are bounded and nearest-first")
	_check(STREAMER.job_count_for_frame(20, 1) == 1, "default queue limit builds one job per frame")
	_check(STREAMER.job_count_for_frame(2, 4) == 2, "queue limit never exceeds pending work")
	_check(STREAMER.DEFAULT_VISUAL_RADIUS_M >= 18000.0, "default visual radius keeps distant coasts loaded")


func _test_runtime_queue(layout: WorldLayout) -> void:
	var streamer := STREAMER.new()
	streamer.background_mesh_builds = false
	streamer.visual_radius_m = 1200.0
	streamer.collision_radius_m = 600.0
	streamer.max_jobs_per_frame = 1
	streamer.build_budget_ms = 3.0
	root.add_child(streamer)
	streamer.configure(layout)
	var mainland_position := Vector3(15000.0, 20.0, 14500.0)
	streamer._refresh_requests(mainland_position)
	var before := streamer.get_debug_stats()
	streamer._process_jobs(mainland_position)
	var after := streamer.get_debug_stats()
	_check(int(before["pending"]) > 1, "runtime streamer queues visual chunks incrementally")
	_check(int(after["loaded"]) == 1, "runtime frame obeys one-job queue limit")
	_check(int(after["pending"]) == int(before["pending"]) - 1, "runtime frame consumes exactly one queued job")
	_check(int(after["vertices"]) > 0 and int(after["triangles"]) > 0, "runtime job creates ArrayMesh data")
	_check((after["lod_counts"] as PackedInt32Array)[0] == 1, "runtime debug stats count loaded LOD")
	print("WorldTerrainStreamer runtime profile: %.3f ms first chunk" % float(after["last_build_ms"]))
	streamer.free()


func _test_empty_water_retention(layout: WorldLayout) -> void:
	var streamer := STREAMER.new()
	streamer.background_mesh_builds = false
	root.add_child(streamer)
	streamer.configure(layout)
	var coord := Vector2i(-16, 14)
	streamer._build_chunk(coord, 1, Vector3.ZERO)
	var record := streamer._chunks[coord] as Dictionary
	_check(record.get("node", null) == null, "open-water chunk creates no scene node")
	_check((record.get("surface_data", {}) as Dictionary).is_empty(), "open-water chunk drops CPU mesh arrays")
	streamer.free()


func _test_collision_cleanup_after_jump() -> void:
	var streamer := STREAMER.new()
	streamer.background_mesh_builds = false
	streamer.collision_radius_m = 1800.0
	root.add_child(streamer)
	var chunk_root := Node3D.new()
	streamer.add_child(chunk_root)
	var body := StaticBody3D.new()
	chunk_root.add_child(body)
	var coord := Vector2i.ZERO
	streamer._chunks[coord] = {
		"node": chunk_root,
		"coord": coord,
		"lod": 0,
		"collision": body,
		"surface_data": {},
	}
	streamer._sync_collisions(Vector3(10000.0, 0.0, 0.0))
	var record := streamer._chunks[coord] as Dictionary
	_check(record.get("collision", null) == null, "teleport retires collision outside physics ring")
	streamer.free()


func _test_boot_ready_ring(layout: WorldLayout) -> void:
	var streamer := STREAMER.new()
	streamer.background_mesh_builds = false
	streamer.visual_radius_m = 8000.0
	streamer.collision_radius_m = 1800.0
	streamer.max_jobs_per_frame = 1
	streamer.build_budget_ms = 4.5
	root.add_child(streamer)
	streamer.configure(layout)
	var focus := Vector3(15000.0, 20.0, 14500.0)
	streamer.begin_boot_priority(focus)
	_check(streamer.is_boot_priority(), "boot priority flag engages")
	_check(not streamer.is_ready_around(focus), "boot ring starts incomplete")
	var guard := 0
	while not streamer.is_ready_around(focus) and guard < 256:
		streamer._refresh_requests(focus)
		streamer._process_jobs(focus)
		streamer._sync_collisions(focus)
		guard += 1
	_check(streamer.is_ready_around(focus), "boot priority drains spawn/collision ring")
	_check(guard > 1, "boot ring needs more than one frame of work")
	# Far visual jobs may still be pending after the near ring is ready.
	_check(int(streamer.get_debug_stats()["loaded"]) > 0, "boot leaves loaded near chunks")
	streamer.end_boot_priority()
	_check(not streamer.is_boot_priority(), "boot priority flag clears")
	streamer.free()

	# Open-water chunks have verts but no walkable collision faces; boot must
	# still complete instead of waiting forever on null collision.
	var ocean := STREAMER.new()
	ocean.background_mesh_builds = false
	ocean.visual_radius_m = 4000.0
	ocean.collision_radius_m = 1800.0
	root.add_child(ocean)
	ocean.configure(layout)
	var ocean_focus := Vector3.ZERO
	ocean.begin_boot_priority(ocean_focus)
	guard = 0
	while not ocean.is_ready_around(ocean_focus) and guard < 256:
		ocean._refresh_requests(ocean_focus)
		ocean._process_jobs(ocean_focus)
		ocean._sync_collisions(ocean_focus)
		guard += 1
	_check(ocean.is_ready_around(ocean_focus), "open-water boot ring resolves without collision faces")
	ocean.end_boot_priority()
	ocean.free()


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("WorldTerrainStreamer tests: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("WorldTerrainStreamer test: " + failure)
	quit(1)
