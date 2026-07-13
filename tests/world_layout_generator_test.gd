extends SceneTree

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const FIXED_SEED := 90210

var _failures := PackedStringArray()


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var first: WorldLayout = GENERATOR.generate(FIXED_SEED)
	var generation_ms := Time.get_ticks_msec() - started
	var second: WorldLayout = GENERATOR.generate(FIXED_SEED)
	var different: WorldLayout = GENERATOR.generate(FIXED_SEED + 1)
	_test_seed_determinism(first, second, different)
	_test_archetype(first)
	_test_waterway_connectivity(first)
	_test_fixed_queries(first)
	_test_contours(first, second)
	_profile_queries(first)
	_finish(generation_ms, first)


func _test_seed_determinism(first: WorldLayout, second: WorldLayout, different: WorldLayout) -> void:
	_check(first.layout_checksum == second.layout_checksum, "same seed has identical checksum")
	_check(first.layout_checksum != different.layout_checksum, "different seed changes checksum")
	_check(first.layout_checksum.length() == 64, "checksum is SHA-256 hex")


func _test_archetype(layout: WorldLayout) -> void:
	_check(is_equal_approx(layout.world_size_m, 40000.0), "world is exactly 40 km square")
	_check(layout.raster_resolution == 257, "field uses documented 257 sample resolution")
	_check(is_equal_approx(layout.cell_size_m, 156.25), "field cells are 156.25 m")
	_check(layout.sample_signed_distance(Vector2(19000.0, 18000.0)) < 0.0, "eastern edge is mainland")
	_check(layout.sample_signed_distance(Vector2(-19000.0, 18000.0)) > 0.0, "western edge is open ocean")
	_check(layout.classify_region(Vector2(19000.0, 18000.0)) == WorldLayout.Region.MAINLAND, "east classifies mainland")
	_check(layout.classify_region(Vector2(-19000.0, 18000.0)) == WorldLayout.Region.OPEN_WATER, "west classifies open water")
	var trunks := 0
	for waterway in layout.waterway_centerlines:
		if String(waterway["kind"]) == "trunk":
			trunks += 1
	_check(trunks >= 3 and trunks <= 7, "layout has 3-7 branching fjord trees")
	var archipelago_land_cells := 0
	for z in range(-18000, 18001, 500):
		for x in range(-12000, 2001, 500):
			var point := Vector2(float(x), float(z))
			if layout.classify_region(point) == WorldLayout.Region.ARCHIPELAGO and layout.is_land(point):
				archipelago_land_cells += 1
	_check(archipelago_land_cells >= 12, "western archipelago contains a skerry belt")


func _test_waterway_connectivity(layout: WorldLayout) -> void:
	for waterway in layout.waterway_centerlines:
		var id := String(waterway["id"])
		var points: PackedVector2Array = waterway["points"]
		var width := float(waterway["width_m"])
		_check(points.size() >= 2, "%s has a usable centerline" % id)
		for point in points:
			_check(
				absf(point.x) <= layout.half_extent_m and absf(point.y) <= layout.half_extent_m,
				"%s remains inside bounded map" % id
			)
		for segment_idx in range(points.size() - 1):
			var a := points[segment_idx]
			var b := points[segment_idx + 1]
			var direction := (b - a).normalized()
			var normal := Vector2(-direction.y, direction.x)
			for step in range(9):
				var center := a.lerp(b, float(step) / 8.0)
				_check(layout.sample_signed_distance(center) > 0.0, "%s centerline remains water" % id)
				# Both sides remain water across at least 60% of configured width.
				_check(
					layout.sample_signed_distance(center + normal * width * 0.30) > 0.0
					and layout.sample_signed_distance(center - normal * width * 0.30) > 0.0,
					"%s preserves minimum corridor width" % id
				)
		if String(waterway["kind"]) == "trunk":
			_check(points[0].x <= -19900.0, "%s connects to western open ocean" % id)
			_check(layout.sample_signed_distance(points[0]) > 0.0, "%s ocean mouth is water" % id)
		else:
			_check((waterway["connects_to"] as PackedStringArray).size() == 1, "%s branch has a graph parent" % id)


func _test_fixed_queries(layout: WorldLayout) -> void:
	var points := PackedVector2Array([
		Vector2(-15000.0, 14500.0),
		Vector2(15000.0, 14500.0),
		Vector2(0.0, 0.0),
		Vector2(7200.0, -4100.0),
		Vector2(-6400.0, 8300.0),
	])
	var expected := PackedFloat32Array([5174.157, -2616.645, 1252.452, 590.345, 1030.766])
	for i in range(points.size()):
		var actual := layout.sample_signed_distance(points[i])
		_check(absf(actual - expected[i]) <= 0.06, "fixed signed-distance sample %d" % i)
	var height_a := layout.sample_height(Vector2(11250.0, 12750.0))
	var height_b := layout.sample_height(Vector2(11250.0, 12750.0))
	_check(is_equal_approx(height_a, height_b), "terrain height sampling is stateless")
	if not layout.coastline_contours.is_empty():
		var shore: PackedVector2Array = layout.coastline_contours[0]
		var mid := (shore[0] + shore[1]) * 0.5
		var tangent := (shore[1] - shore[0]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var inland_dir := normal if layout.sample_signed_distance(mid + normal * 80.0) < 0.0 else -normal
		var near_shore := layout.sample_height(mid + inland_dir * 12.0)
		var inland_h := layout.sample_height(mid + inland_dir * 420.0)
		_check(near_shore >= 0.0 and near_shore < 8.0, "svaberg shelf stays low near the waterline")
		_check(inland_h > near_shore + 40.0, "mainland rises into visible mountains inland of the shelf")


func _test_contours(first: WorldLayout, second: WorldLayout) -> void:
	var a := first.coastline_contours
	var b := second.coastline_contours
	_check(not a.is_empty(), "marching squares emits coastline contours")
	_check(a.size() == b.size(), "contour segment count is deterministic")
	if a.size() != b.size():
		return
	for i in range(a.size()):
		if a[i] != b[i]:
			_check(false, "contour segment ordering is deterministic")
			return


func _profile_queries(layout: WorldLayout) -> void:
	var started := Time.get_ticks_usec()
	var accumulator := 0.0
	for i in range(10000):
		var x := float((i * 7919) % 40000) - 20000.0
		var z := float((i * 3571) % 40000) - 20000.0
		accumulator += layout.sample_signed_distance(Vector2(x, z))
	var elapsed := Time.get_ticks_usec() - started
	print("WorldLayout query profile: %.3f µs/sample (%0.1f guard)" % [float(elapsed) / 10000.0, accumulator])


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)


func _finish(generation_ms: int, layout: WorldLayout) -> void:
	if _failures.is_empty():
		print(
			"WorldLayout tests: all checks passed; generation=%d ms contours=%d checksum=%s"
			% [generation_ms, layout.coastline_contours.size(), layout.layout_checksum]
		)
		quit()
		return
	for failure in _failures:
		push_error("WorldLayout test: " + failure)
	quit(1)
