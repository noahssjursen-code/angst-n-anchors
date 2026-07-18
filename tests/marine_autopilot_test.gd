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
	_check_close(plan.nearest_progress_m(Vector2(98.0, 30.0), 100.0, 80.0), 130.0, 0.1,
		"bounded nearest route progress")
	var restored := MarineRoutePlan.from_dict(plan.to_dict())
	_check(restored.route_id == plan.route_id, "route identity survives serialization")
	_check(restored.waypoints == plan.waypoints, "waypoints survive serialization")
	var compact := plan.to_dict(false)
	_check(not compact.has("waypoints"), "compact authority payload omits route geometry")
	_check(compact.get("start_point") == points[0], "compact authority payload keeps start")
	_check(compact.get("end_point") == points[-1], "compact authority payload keeps finish")
	var curve := MarineRoutePlanner._quadratic_corner(
		Vector2(0.0, 0.0), Vector2(10.0, 0.0), Vector2(10.0, 10.0))
	_check(curve.size() == 6, "rounded corner has deterministic sample count")
	_check(curve[0].is_equal_approx(Vector2.ZERO), "rounded corner preserves entry")
	_check(curve[-1].is_equal_approx(Vector2(10.0, 10.0)), "rounded corner preserves exit")
	_check(curve[3].x < 10.0 and curve[3].y > 0.0, "rounded corner forms an arc")
	plan.set_handoffs(Vector2(100.0, 0.0), Vector2(100.0, 70.0))
	_check(plan.has_berth_handoffs(), "berth route exposes both authority handoffs")
	_check_close(plan.departure_handoff_m, 100.0, 0.1, "departure handoff distance")
	_check_close(plan.arrival_handoff_m, 170.0, 0.1, "arrival handoff distance")
	var with_handoffs := MarineRoutePlan.from_dict(plan.to_dict())
	_check(with_handoffs.has_berth_handoffs(), "handoffs survive serialization")


func _test_steering_command() -> void:
	var north := Vector2(0.0, -1.0)
	_check(AutopilotMath.rudder_for_heading(north, Vector2(1.0, 0.0)) > 0.9, "east commands starboard")
	_check(AutopilotMath.rudder_for_heading(north, Vector2(-1.0, 0.0)) < -0.9, "west commands port")
	_check_close(AutopilotMath.rudder_for_heading(north, north), 0.0, 0.001, "on-course rudder neutral")
	var straight_lookahead := AutopilotMath.adaptive_lookahead_m(180.0, 0.0, 0.0)
	var corner_lookahead := AutopilotMath.adaptive_lookahead_m(180.0, 0.0, 90.0)
	var recovery_lookahead := AutopilotMath.adaptive_lookahead_m(180.0, 180.0, 0.0)
	_check_close(straight_lookahead, 180.0, 0.01, "straight course keeps long lookahead")
	_check(corner_lookahead < straight_lookahead, "sharp turn shortens lookahead")
	_check(corner_lookahead > 100.0, "sharp turn retains enough preview to turn early")
	_check(recovery_lookahead < 70.0, "cross-track recovery pulls target close")
	var cruise := AutopilotMath.throttle_for_course(1.0, 0.0, 0.0, 0.0)
	var turning := AutopilotMath.throttle_for_course(1.0, 55.0, 0.0, 75.0)
	_check_close(cruise, 1.0, 0.001, "straight course retains cruise throttle")
	_check(turning < 0.55, "large turn reduces throttle")
	var route_east := Vector2(1.0, 0.0)
	var from_left := AutopilotMath.centreline_guidance(
		Vector2(0.0, 20.0), Vector2.ZERO, route_east, route_east, 5.0)
	var from_right := AutopilotMath.centreline_guidance(
		Vector2(0.0, -20.0), Vector2.ZERO, route_east, route_east, 5.0)
	_check(from_left.y < 0.0, "centreline guidance steers right from left-side error")
	_check(from_right.y > 0.0, "centreline guidance steers left from right-side error")
	var anticipating := AutopilotMath.centreline_guidance(
		Vector2.ZERO, Vector2.ZERO, route_east, Vector2(0.0, 1.0), 5.0)
	_check(anticipating.y > 0.0 and anticipating.x > 0.0, "guidance anticipates upcoming curve")


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
