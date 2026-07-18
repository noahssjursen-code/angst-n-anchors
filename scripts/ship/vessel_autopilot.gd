class_name VesselAutopilot
extends Node

## Vessel-agnostic route follower. It actuates ordinary propulsion and rudder
## components, so player and NPC captains share exactly the same sailing model.

signal engaged(plan: MarineRoutePlan)
signal disengaged(reason: String)
signal navigation_updated(progress_m: float, remaining_m: float)

const AutopilotMath := preload("res://scripts/ship/vessel_autopilot_math.gd")

const LOOKAHEAD_BASE_MIN_M := 60.0
const LOOKAHEAD_MIN_M := 32.0
const LOOKAHEAD_MAX_M := 220.0
const ARRIVAL_STOP_M := 70.0
const ARRIVAL_SLOW_M := 700.0
const MAX_ROUTE_ERROR_M := 650.0

@export_range(0.1, 1.0, 0.05) var cruise_throttle := 1.0
@export_range(5.0, 90.0, 1.0) var full_rudder_error_deg := 32.0

var route: MarineRoutePlan
var progress_m := 0.0
var active := false
var last_reason := ""
var target_point := Vector2(INF, INF)
var arrival_stop_m := ARRIVAL_STOP_M
var traffic_heading_offset_deg := 0.0
var traffic_speed_limit := 1.0
var traffic_instruction := ""
var cross_track_error_m := 0.0
var current_lookahead_m := 0.0
var upcoming_turn_deg := 0.0
var maneuver_mode := false
var desired_course := Vector2.ZERO

var _body: BoatBody
var _propulsion: PropulsionComponent
var _rudder: RudderComponent
var _distance_accum_m := 0.0
var _distance_flush_s := 0.0


func _ready() -> void:
	_body = get_parent() as BoatBody
	if _body == null:
		push_error("VesselAutopilot must be a child of BoatBody")
		return
	_propulsion = _body.get_node_or_null("PropulsionComponent") as PropulsionComponent
	_rudder = _body.get_node_or_null("RudderComponent") as RudderComponent


func engage(
	next_route: MarineRoutePlan,
	initial_progress_m: float = -1.0,
	stop_distance_m: float = ARRIVAL_STOP_M,
) -> bool:
	if _body == null or _propulsion == null or _rudder == null \
			or next_route == null or not next_route.is_valid():
		return false
	route = next_route
	arrival_stop_m = maxf(stop_distance_m, 1.0)
	var position := Vector2(_body.global_position.x, _body.global_position.z)
	progress_m = route.nearest_progress_m(position) if initial_progress_m < 0.0 \
		else clampf(initial_progress_m, 0.0, route.total_distance_m())
	active = true
	last_reason = ""
	if _body.is_in_group(PlayerVessel.GROUP):
		WaveSurface.set_local_visual_vessel(_body)
	engaged.emit(route)
	return true


func disengage(reason: String = "manual") -> void:
	if not active:
		return
	active = false
	last_reason = reason
	if _propulsion != null:
		_propulsion.throttle = 0.0
	if _rudder != null:
		_rudder.rudder_input = 0.0
	disengaged.emit(reason)


func is_engaged() -> bool:
	return active


func remaining_distance_m() -> float:
	return maxf(route.total_distance_m() - progress_m, 0.0) if route != null else 0.0


func voyage_snapshot() -> Dictionary:
	return {
		"active": active,
		"route": route.to_dict(false) if route != null else {},
		"route_progress_m": progress_m,
		"position": _body.global_position if _body != null else Vector3.ZERO,
		"heading_deg": NavigationAxes.heading_deg_horizontal(
			NavigationAxes.vessel_bow_horizontal(_body)
		) if _body != null else 0.0,
		"speed_ms": Vector2(_body.linear_velocity.x, _body.linear_velocity.z).length() \
			if _body != null else 0.0,
		"traffic_instruction": traffic_instruction,
		"traffic_speed_limit": traffic_speed_limit,
		"cross_track_error_m": cross_track_error_m,
		"lookahead_m": current_lookahead_m,
		"upcoming_turn_deg": upcoming_turn_deg,
		"desired_course": desired_course,
	}


func apply_traffic_instruction(instruction: Dictionary) -> void:
	traffic_instruction = str(instruction.get("action", ""))
	traffic_heading_offset_deg = clampf(float(instruction.get("heading_offset_deg", 0.0)), -45.0, 45.0)
	traffic_speed_limit = clampf(float(instruction.get("speed_limit", 1.0)), 0.0, 1.0)


func clear_traffic_instruction() -> void:
	traffic_instruction = ""
	traffic_heading_offset_deg = 0.0
	traffic_speed_limit = 1.0


func set_maneuver_mode(enabled: bool) -> void:
	maneuver_mode = enabled


func _physics_process(delta: float) -> void:
	if not active or route == null or _body == null:
		return
	var position := Vector2(_body.global_position.x, _body.global_position.z)
	var next_progress := route.nearest_progress_m(position, progress_m)
	if next_progress + 5.0 >= progress_m:
		progress_m = next_progress
	cross_track_error_m = position.distance_to(route.point_at_distance(progress_m))
	if cross_track_error_m > MAX_ROUTE_ERROR_M:
		disengage("off_route")
		return
	var remaining := remaining_distance_m()
	if remaining <= arrival_stop_m:
		disengage("arrived")
		return
	var speed_ms := Vector2(_body.linear_velocity.x, _body.linear_velocity.z).length()
	var base_lookahead := clampf(speed_ms * 14.0, LOOKAHEAD_BASE_MIN_M, LOOKAHEAD_MAX_M)
	var minimum_lookahead := LOOKAHEAD_MIN_M
	if maneuver_mode:
		var hull_preview := maxf(_body.hull_size.z * 1.35, 72.0)
		base_lookahead = clampf(maxf(speed_ms * 12.0, hull_preview), 72.0, 140.0)
		minimum_lookahead = 58.0
	upcoming_turn_deg = _upcoming_turn_angle_deg(base_lookahead)
	current_lookahead_m = AutopilotMath.adaptive_lookahead_m(
		base_lookahead, cross_track_error_m, upcoming_turn_deg, minimum_lookahead)
	target_point = route.point_at_distance(
		minf(progress_m + current_lookahead_m, route.total_distance_m()))
	var route_point := route.point_at_distance(progress_m)
	var current_tangent := route.direction_at_distance(progress_m, 24.0)
	var preview_tangent := route.direction_at_distance(
		minf(progress_m + current_lookahead_m, route.total_distance_m()), 32.0)
	desired_course = AutopilotMath.centreline_guidance(
		position,
		route_point,
		current_tangent,
		preview_tangent,
		speed_ms,
		0.72 if maneuver_mode else 0.58,
		0.15 if maneuver_mode else 0.10,
		70.0 if maneuver_mode else 58.0,
	).rotated(deg_to_rad(traffic_heading_offset_deg))
	var bow := NavigationAxes.vessel_bow_horizontal(_body).normalized()
	var rudder_command := AutopilotMath.rudder_for_heading(bow, desired_course, full_rudder_error_deg)
	var heading_error_deg := absf(rad_to_deg(bow.angle_to(desired_course)))
	var throttle_command := AutopilotMath.throttle_for_course(
		cruise_throttle, heading_error_deg, cross_track_error_m, upcoming_turn_deg)
	if maneuver_mode:
		throttle_command = minf(throttle_command, 0.32)
	if remaining < ARRIVAL_SLOW_M:
		throttle_command = 0.28 if remaining < 260.0 else 0.56
	throttle_command = minf(throttle_command, traffic_speed_limit)
	## PropulsionComponent uses negative values for ahead.
	_propulsion.throttle = -throttle_command
	_rudder.rudder_input = rudder_command
	_accumulate_player_distance(delta, speed_ms)
	navigation_updated.emit(progress_m, remaining)


func _upcoming_turn_angle_deg(sample_distance_m: float) -> float:
	var total := route.total_distance_m()
	var start := route.point_at_distance(progress_m)
	var middle := route.point_at_distance(minf(progress_m + sample_distance_m * 0.5, total))
	var finish := route.point_at_distance(minf(progress_m + sample_distance_m, total))
	var first_leg := middle - start
	var second_leg := finish - middle
	if first_leg.length_squared() <= 0.01 or second_leg.length_squared() <= 0.01:
		return 0.0
	return absf(rad_to_deg(first_leg.normalized().angle_to(second_leg.normalized())))


static func rudder_for_heading(
	bow: Vector2,
	desired: Vector2,
	full_error_deg: float = 32.0,
) -> float:
	return AutopilotMath.rudder_for_heading(bow, desired, full_error_deg)


func _accumulate_player_distance(delta: float, speed_ms: float) -> void:
	if not _body.is_in_group(PlayerVessel.GROUP):
		return
	_distance_accum_m += speed_ms * delta
	_distance_flush_s += delta
	if _distance_flush_s < 5.0:
		return
	_distance_flush_s = 0.0
	if _distance_accum_m < 0.1:
		return
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_method("add_distance_sailed"):
		session.add_distance_sailed(_distance_accum_m)
	_distance_accum_m = 0.0
