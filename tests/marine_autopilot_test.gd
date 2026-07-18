extends SceneTree

const AutopilotMath := preload("res://scripts/ship/vessel_autopilot_math.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	_test_route_plan()
	_test_steering_command()
	_finish()


func _test_route_plan() -> void:
	var points := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(100.0, 0.0),
		Vector2(100.0, 100.0),
	])
	var plan := MarineRoutePlan.create(points, "layout-a", "port-a", "port-b")
	_check(plan.is_valid(), "route plan validates")
	_check_close(plan.total_distance_m(), 200.0, 0.01, "route distance")
	_check(plan.point_at_distance(150.0).is_equal_approx(Vector2(100.0, 50.0)), "distance interpolation")
	_check_close(plan.nearest_progress_m(Vector2(98.0, 30.0)), 130.0, 0.1, "nearest route progress")
	var restored := MarineRoutePlan.from_dict(plan.to_dict())
	_check(restored.route_id == plan.route_id, "route identity survives serialization")
	_check(restored.waypoints == plan.waypoints, "waypoints survive serialization")
	var compact := plan.to_dict(false)
	_check(not compact.has("waypoints"), "compact authority payload omits route geometry")
	_check(compact.get("start_point") == points[0], "compact authority payload keeps start")
	_check(compact.get("end_point") == points[-1], "compact authority payload keeps finish")


func _test_steering_command() -> void:
	var north := Vector2(0.0, -1.0)
	_check(AutopilotMath.rudder_for_heading(north, Vector2(1.0, 0.0)) > 0.9, "east commands starboard")
	_check(AutopilotMath.rudder_for_heading(north, Vector2(-1.0, 0.0)) < -0.9, "west commands port")
	_check_close(AutopilotMath.rudder_for_heading(north, north), 0.0, 0.001, "on-course rudder neutral")


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)


func _check_close(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(absf(actual - expected) <= tolerance, "%s (%f != %f)" % [label, actual, expected])


func _finish() -> void:
	if _failures.is_empty():
		print("Marine autopilot tests: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("Marine autopilot test: " + failure)
	quit(1)
