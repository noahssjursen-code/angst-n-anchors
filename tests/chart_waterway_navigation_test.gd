extends SceneTree

const FIXED_SEED := 90210
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const NAVIGATION := preload("res://scripts/navigation/waterway_navigation.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	var first: WorldLayout = GENERATOR.generate(FIXED_SEED)
	var same: WorldLayout = GENERATOR.generate(FIXED_SEED)
	var different: WorldLayout = GENERATOR.generate(FIXED_SEED + 1)
	_test_graph_reachability(first)
	_test_route_distances(first)
	_test_layout_identity(first, same, different)
	_finish()


func _test_graph_reachability(layout: WorldLayout) -> void:
	var navigation := NAVIGATION.new(layout)
	var ids := navigation.waterway_ids()
	_check(ids.size() == layout.waterway_centerlines.size(), "graph includes every waterway")
	for waterway in layout.waterway_centerlines:
		var points: PackedVector2Array = waterway["points"]
		var endpoint := points[points.size() - 1]
		var nearest: Dictionary = navigation.nearest_waterway(endpoint)
		_check(not nearest.is_empty(), "%s has a nearest graph connection" % waterway["id"])
		_check(
			navigation.is_open_ocean_reachable(endpoint, 1.0),
			"%s reaches open ocean" % waterway["id"]
		)
	var waterways := layout.waterway_centerlines
	for i in range(waterways.size()):
		var a_points: PackedVector2Array = waterways[i]["points"]
		for j in range(i + 1, waterways.size()):
			var b_points: PackedVector2Array = waterways[j]["points"]
			_check(
				navigation.are_reachable(a_points[-1], b_points[-1], 1.0),
				"%s reaches %s" % [waterways[i]["id"], waterways[j]["id"]]
			)


func _test_route_distances(layout: WorldLayout) -> void:
	var first_navigation := NAVIGATION.new(layout)
	var second_navigation := NAVIGATION.new(layout)
	var trunk: Dictionary
	for waterway in layout.waterway_centerlines:
		if str(waterway["kind"]) == "trunk":
			trunk = waterway
			break
	var points: PackedVector2Array = trunk["points"]
	var a := points[0].lerp(points[1], 0.25)
	var b := points[0].lerp(points[1], 0.75)
	var expected := points[0].distance_to(points[1]) * 0.5
	var distance_a := first_navigation.route_distance(a, b, 0.01)
	var distance_b := second_navigation.route_distance(a, b, 0.01)
	_check_close(distance_a, expected, 0.01, "same-segment route follows polyline")
	_check_close(distance_a, distance_b, 0.0001, "route distance is deterministic")
	_check(
		not first_navigation.are_reachable(a + Vector2(0.0, 500.0), b, 10.0),
		"access threshold rejects remote endpoints"
	)


func _test_layout_identity(
	first: WorldLayout,
	same: WorldLayout,
	different: WorldLayout,
) -> void:
	_check(first.layout_checksum == same.layout_checksum, "same seed preserves layout checksum")
	_check(first.layout_checksum != different.layout_checksum, "different seed changes layout checksum")


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)


func _check_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(absf(actual - expected) <= tolerance, "%s (%f != %f)" % [label, actual, expected])


func _finish() -> void:
	if _failures.is_empty():
		print("Chart waterway navigation tests: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("Chart waterway navigation test: " + failure)
	quit(1)
