extends SceneTree

const ChartNavSnapshotClass = preload("res://scripts/ui/chart/chart_nav_snapshot.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	var eastbound: RefCounted = ChartNavSnapshotClass.from_kinematics(
		Vector2(0.0, 1.0),
		Vector2(5.0, 0.0),
		Vector3.ZERO,
		Vector3(0.0, 0.0, -100.0)
	)
	_check_close(eastbound.heading_deg, 0.0, "north heading")
	_check_close(eastbound.course_deg, 90.0, "east course")
	_check_close(eastbound.speed_knots, 5.0 * ChartNavSnapshotClass.MPS_TO_KNOTS, "horizontal SOG")
	_check_close(eastbound.bearing_deg, 180.0, "south waypoint bearing")
	_check_close(eastbound.leeway_deg, 90.0, "signed HDG-to-COG leeway")

	var stationary: RefCounted = ChartNavSnapshotClass.from_kinematics(
		Vector2(1.0, 0.0), Vector2.ZERO, Vector3.ZERO, Vector3(INF, INF, INF)
	)
	_check_close(stationary.heading_deg, 90.0, "east heading")
	_check(not stationary.has_course(), "stationary vessel has no COG")
	_check(not is_finite(stationary.leeway_deg), "stationary vessel has no leeway")
	_check(not is_finite(stationary.bearing_deg), "missing waypoint has no bearing")
	eastbound.set_waypoint(Vector3(100.0, 0.0, 0.0))
	_check_close(eastbound.bearing_deg, 90.0, "planned route waypoint bearing")
	_check_close(
		ChartNavSnapshotClass.signed_angle_difference_deg(350.0, 10.0),
		20.0,
		"leeway wraps clockwise"
	)
	_check_close(
		ChartNavSnapshotClass.signed_angle_difference_deg(10.0, 350.0),
		-20.0,
		"leeway wraps counter-clockwise"
	)

	# Vessel convention: Bow = −Z. Identity basis faces +Z (stern ahead of origin
	# along +Z), so bow horizontal is −Z → heading 180° (south).
	var vessel := Node3D.new()
	root.add_child(vessel)
	var stern_facing := NavigationAxes.vessel_bow_horizontal(vessel)
	_check_close(stern_facing.x, 0.0, "identity bow x")
	_check_close(stern_facing.y, -1.0, "identity bow is −Z")
	_check_close(
		NavigationAxes.heading_deg_horizontal(stern_facing),
		180.0,
		"identity vessel heads south"
	)
	# Yaw 180°: local −Z aligns with world +Z (north).
	vessel.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	vessel.force_update_transform()
	var north_bow := NavigationAxes.vessel_bow_horizontal(vessel)
	_check_close(north_bow.x, 0.0, "yaw-180 bow x")
	_check_close(north_bow.y, 1.0, "yaw-180 bow is +Z north")
	_check_close(
		NavigationAxes.heading_deg_horizontal(north_bow),
		0.0,
		"yaw-180 vessel heads north"
	)
	vessel.queue_free()
	_finish()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _check_close(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) < 0.001, "%s (%f != %f)" % [label, actual, expected])


func _finish() -> void:
	if _failures.is_empty():
		print("ChartNavSnapshot tests: all deterministic checks passed")
		quit()
		return
	for failure in _failures:
		push_error("ChartNavSnapshot test: " + failure)
	quit(1)
