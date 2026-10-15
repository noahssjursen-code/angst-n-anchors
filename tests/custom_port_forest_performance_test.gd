extends Node
## Native, bounded benchmark of the exact authored harbour footprint.
## --port-forest-performance-output <absolute path> writes machine-readable results.

const ORIGIN := Vector3(3200, .5, 1152)
const OWNER := "forest-performance-port"
const EARTHWORKS := preload("res://scripts/port/state/custom_port_earthworks.gd")
var checks := 0
var failures := 0
var result := {}
var forest: WorldForestStreamer
var distant: DistantForest
var points := PackedVector2Array()
var baseline := PackedFloat32Array()
var near_coords: Array[Vector2i] = []
var center := Vector2i.ZERO

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(1))
	var layout := WorldLayoutGenerator.generate(424242, WorldLayoutGenerator.DEFAULT_CONFIG_PATH, 10000)
	ForestField.initialize(layout, layout.seed)
	ForestTreeMesh.request_assets()
	while not ForestTreeMesh.assets_ready(): await get_tree().process_frame
	var catalog := CustomPortCatalog.definitions()
	var fixture := CustomPortExample.build(ORIGIN, [], {"seed": layout.seed, "layout_checksum": layout.layout_checksum})
	var projection := EARTHWORKS.project(fixture, catalog)
	var full := EARTHWORKS.forest_exclusions(projection)
	var hole_fixture := fixture.duplicate(true)
	var removed_id := "slab--2-30"
	for i in range(hole_fixture.placements.size() - 1, -1, -1):
		if hole_fixture.placements[i].id == removed_id:
			hole_fixture.placements.remove_at(i)
			hole_fixture.revision += 1
	var hole_projection := EARTHWORKS.project(hole_fixture, catalog)
	var hole := EARTHWORKS.forest_exclusions(hole_projection)
	check(full.size() == 568 and hole.size() == 567, "Fixture must use every actual example platform and remove exactly one interior tile")
	var bounds: Rect2 = projection.bounds
	var sample_bounds := bounds.grow(32)
	for y in 32:
		for x in 32:
			points.append(sample_bounds.position + Vector2((x + .37) / 32, (y + .61) / 32) * sample_bounds.size)
	for p in points: baseline.append(ForestField.sample(p))
	result = {"seed": layout.seed, "world_size_m": layout.world_size_m,
		"site": [ORIGIN.x, ORIGIN.z], "zones": full.size(), "hole_zones": hole.size(),
		"sample_points": points.size(), "removed_platform": removed_id,
		"renderer": RenderingServer.get_current_rendering_method(), "setters_ms": {}, "exclusion_slices": {}}
	_index_parity()
	result.sample_base = _sample_timing()
	result.near_generation_base = _near_timing(layout, [])
	forest = WorldForestStreamer.new()
	add_child(forest)
	forest.set_process(false)
	forest._layout = layout
	center = Vector2i(floori(ORIGIN.x / 256), floori(ORIGIN.z / 256))
	for z in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2): near_coords.append(Vector2i(x, z))
	_rebuild_near()
	var original_near := _near_count()
	result.near_roots = original_near
	result.near_chunks = forest._chunks.size()
	var outside := center + Vector2i(-1, -1)
	var outside_record: Dictionary = forest._chunks[outside].duplicate()
	var placement := WorldForestStreamer.create_placement_job(center, 6.5, 1521)
	WorldForestStreamer.advance_placement_job(layout, placement, [], 300)
	forest._jobs.assign([{"coord": center, "tier": 0, "placement": placement}])
	await _prepare_distant(layout, bounds)
	result.distant_roots = distant.trees
	result.distant_batches = distant.rendered_batches.size()
	result.initial_roots_inside = _distant_inside(full)
	result.setters_ms.initial = _time_set(full)
	result.affected_distant_batches = distant.exclusion_jobs.size()
	check(not forest._chunks.has(center), "Initial setter invalidates loaded affected near chunk")
	check(forest._chunks[outside] == outside_record, "Initial setter preserves unrelated loaded near chunk")
	check(not forest._jobs[0].has("placement"), "Initial setter resets partial affected near job")
	result.exclusion_slices.initial = _drain()
	result.sample_full = _sample_timing()
	result.near_generation_full = _near_timing(layout, full)
	_parity(full, "full")
	_rebuild_near()
	result.cleared_near_roots = _near_count()
	var same_near: Dictionary = forest._chunks[center].duplicate()
	result.setters_ms.identical_noop = _time_set(full.duplicate(true))
	check(forest._chunks[center] == same_near and distant.exclusion_jobs.is_empty(), "Identical geometry preserves loaded chunks and queues no distant work")
	var cargo_fixture := fixture.duplicate(true)
	cargo_fixture.revision += 1
	cargo_fixture.stores[0].lots[0].quantity += 1
	var cargo_projection := EARTHWORKS.project(cargo_fixture, catalog)
	var cargo_zones := EARTHWORKS.forest_exclusions(cargo_projection)
	check(cargo_projection.geometry_signature == projection.geometry_signature and cargo_zones == full, "Actual example cargo-only revision preserves all568 footprint polygons")
	var cargo_changed := forest.set_custom_port_exclusions(OWNER, cargo_zones)
	check(not cargo_changed and forest._chunks[center] == same_near and distant.exclusion_jobs.is_empty(), "Cargo-only revision is a full public-setter no-op")
	result.setters_ms.one_tile_removed = _time_set(hole)
	result.exclusion_slices.one_tile_removed = _drain()
	result.sample_hole = _sample_timing()
	result.near_generation_hole = _near_timing(layout, hole)
	_parity(hole, "one_tile_hole")
	var hole_center := Vector2(ORIGIN.x - 2, ORIGIN.z + 30)
	check(ForestField.inside_flatten_zones(hole_center, full) and not ForestField.inside_flatten_zones(hole_center, hole), "Removed interior tile leaves a real uncovered hole")
	check(ForestField.sample(hole_center) > .5, "Removed tile hole restores natural forest density")
	_rebuild_near()
	result.setters_ms.remove = _time_set([])
	result.exclusion_slices.remove = _drain()
	result.sample_restored = _sample_timing()
	_rebuild_near()
	check(_near_count() == original_near and distant.trees == result.distant_roots, "Removing the entire layer restores real near and distant root counts")
	check(forest._chunks[outside] == outside_record, "All edits preserve unrelated near node identity")
	# Empty cached patches must be invalidated too, even with no accepted roots.
	forest._unload_chunk(center)
	forest._chunks[center] = {"node": null, "tier": 0, "instances": 0, "transforms": []}
	forest.set_custom_port_exclusions(OWNER, full)
	check(not forest._chunks.has(center), "A custom edit invalidates affected empty cached near chunks")
	forest.set_custom_port_exclusions(OWNER, [])
	_drain()
	result.checks = checks
	result.failures = failures
	print("CUSTOM PORT FOREST PERFORMANCE ", JSON.stringify(result))
	_write_result()
	forest.free()
	ForestField.clear()
	get_tree().quit(0 if failures == 0 else 1)

func _prepare_distant(layout: WorldLayout, bounds: Rect2) -> void:
	distant = DistantForest.new()
	distant.layout = layout
	distant.coverage = ForestField.coverage_texture().get_image()
	distant.prepare_density_pixels()
	distant.cell_m = layout.world_size_m / distant.coverage.get_width()
	distant.zones = ForestField.base_exclusions()
	for species in 4: distant.meshes.append(ForestTreeMesh.species_mesh(species, false))
	forest.add_child(distant)
	forest._distant = distant
	distant.set_process(false)
	var start := Vector2i(((bounds.position + Vector2.ONE * layout.half_extent_m) / (distant.cell_m * 4)).floor())
	var end := Vector2i(((bounds.end + Vector2.ONE * layout.half_extent_m) / (distant.cell_m * 4)).floor())
	for z in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			for cy in 4:
				for cx in 4: distant.jobs.append(Vector2i(x * 4 + cx, z * 4 + cy))
	distant.worker = Thread.new()
	distant.worker.start(distant.generate)
	while distant.worker.is_alive(): await get_tree().process_frame
	while distant.pending() > 0: distant._process(0)
	check(distant.trees > 256, "Actual overlapping worker batch must exercise more than one256-root slice")

func _time_set(zones: Array) -> float:
	var started := Time.get_ticks_usec()
	forest.set_custom_port_exclusions(OWNER, zones)
	return (Time.get_ticks_usec() - started) / 1000.0

func _near_timing(layout: WorldLayout, zones: Array) -> Dictionary:
	var coord := Vector2i(floori(ORIGIN.x / 256), floori(ORIGIN.z / 256))
	var started := Time.get_ticks_usec()
	var transforms := WorldForestStreamer.build_chunk_transforms(layout, coord, 6.5, 1521, zones)
	return {"ms": (Time.get_ticks_usec() - started) / 1000.0, "roots": transforms.size()}

func _drain() -> Dictionary:
	var durations := PackedFloat64Array()
	while not distant.exclusion_jobs.is_empty():
		var started := Time.get_ticks_usec()
		distant._process_exclusions()
		durations.append((Time.get_ticks_usec() - started) / 1000.0)
	var total := 0.0
	var maximum := 0.0
	for duration in durations:
		total += duration
		maximum = maxf(maximum, duration)
	return {"calls": durations.size(), "total_ms": total, "mean_ms": total / maxi(1, durations.size()), "max_ms": maximum, "each_ms": Array(durations)}

func _sample_timing() -> Dictionary:
	# Warm the actual field's spatial cache before recording steady-state cost.
	for p in points: ForestField.sample(p)
	var durations := PackedFloat64Array()
	var sum := 0.0
	for repeat in 3:
		var started := Time.get_ticks_usec()
		for p in points: sum += ForestField.sample(p)
		durations.append((Time.get_ticks_usec() - started) / 1000.0)
	var total := 0.0
	for duration in durations: total += duration
	return {"mean_ms": total / 3, "each_ms": Array(durations), "density_sum": sum / 3}

func _parity(zones: Array, stage: String) -> void:
	var probes := points.duplicate()
	for zone in zones:
		var polygon: PackedVector2Array = zone.polygon
		if polygon.size() != 3: continue
		var centroid := (polygon[0] + polygon[1] + polygon[2]) / 3
		probes.append(centroid)
		for corner in polygon:
			probes.append(corner)
			probes.append(corner.lerp(centroid, .01))
			probes.append(corner + (corner - centroid).normalized() * .02)
	probes.append(Vector2(ORIGIN.x - 2, ORIGIN.z + 30))
	probes.append(Vector2(ORIGIN.x - 2 + 1.9, ORIGIN.z + 30 + 1.9))
	var mismatches := 0
	for p in probes:
		var expected := 0.0 if ForestField.inside_flatten_zones(p, zones) else ForestField.sample(p, false)
		if not is_equal_approx(ForestField.sample(p), expected): mismatches += 1
	result["parity_" + stage] = {"points": probes.size(), "mismatches": mismatches}
	check(mismatches == 0, "Exact polygon parity at sample grid, triangle boundaries and hole: " + stage)

func _index_parity() -> void:
	var cases: Array = [
		[{"center": Vector2(-16, -32), "half_size": Vector2(9, 5), "yaw": .73, "falloff": 16.0}],
		[{"polygon": PackedVector2Array([Vector2(-10000, -10000), Vector2(10000, -10000), Vector2(10000, 10000), Vector2(-10000, 10000)])}],
		[{"polygon": PackedVector2Array([Vector2(-32, -16), Vector2(-16, -16), Vector2(-32, 0)])}]]
	var probes := PackedVector2Array()
	for y in range(-80, 17, 4):
		for x in range(-64, 33, 4): probes.append(Vector2(x, y))
	for value in [-10000.001, -10000.0, -9999.999, -32.001, -32.0, -31.999, -16.001, -16.0, -15.999, -.001, 0.0, .001, 9999.999, 10000.0, 10000.001]:
		probes.append(Vector2(value, -16))
		probes.append(Vector2(-32, value))
	var mismatches := 0
	for i in cases.size():
		var zones: Array = cases[i]
		var index := ForestField.exclusion_index(zones)
		if i < 2: check(index.large.size() == 1, "Rotated rectangle or oversized polygon uses exact bounded fallback")
		for p in probes:
			if ForestField.inside_exclusion_index(p, index) != ForestField.inside_flatten_zones(p, zones): mismatches += 1
			if WorldForestStreamer._in_flatten_indexed(p, index) != WorldForestStreamer._in_flatten(p, zones): mismatches += 1
	result.index_fallback_parity = {"cases": cases.size(), "points_per_case": probes.size(), "predicate_comparisons": cases.size() * probes.size() * 2, "mismatches": mismatches}
	check(mismatches == 0, "Index preserves full/half falloff, huge polygon fallback and negative grid boundaries")

func _rebuild_near() -> void:
	for coord in near_coords:
		if not forest._chunks.has(coord): forest._build_chunk(coord, 0)

func _near_count() -> int:
	var count := 0
	for record: Dictionary in forest._chunks.values(): count += int(record.instances)
	return count

func _distant_inside(zones: Array) -> int:
	var count := 0
	for child in distant.get_children():
		if not child is MultiMeshInstance3D: continue
		for i in child.multimesh.instance_count:
			var p: Vector3 = child.multimesh.get_instance_transform(i).origin
			if ForestField.inside_flatten_zones(Vector2(p.x, p.z), zones): count += 1
	return count

func _write_result() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] != "--port-forest-performance-output" or i + 1 >= args.size(): continue
		var path := args[i + 1]
		assert(path.is_absolute_path())
		var file := FileAccess.open(path, FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify(result, "\t") + "\n")
		file.close()
