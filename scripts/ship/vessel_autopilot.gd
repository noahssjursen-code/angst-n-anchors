class_name VesselAutopilot
extends Node

## Vessel-agnostic route follower. It actuates ordinary propulsion and rudder
## components, so player and NPC captains share exactly the same sailing model.

signal engaged(plan: MarineRoutePlan)
signal disengaged(reason: String)
signal navigation_updated(progress_m: float, remaining_m: float)

const AutopilotMath := preload("res://scripts/ship/vessel_autopilot_math.gd")

const LOOKAHEAD_MIN_M := 85.0
const LOOKAHEAD_MAX_M := 320.0
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
	}


func apply_traffic_instruction(instruction: Dictionary) -> void:
	traffic_instruction = str(instruction.get("action", ""))
	traffic_heading_offset_deg = clampf(float(instruction.get("heading_offset_deg", 0.0)), -45.0, 45.0)
	traffic_speed_limit = clampf(float(instruction.get("speed_limit", 1.0)), 0.0, 1.0)


func clear_traffic_instruction() -> void:
	traffic_instruction = ""
	traffic_heading_offset_deg = 0.0
	traffic_speed_limit = 1.0


func _physics_process(delta: float) -> void:
	if not active or route == null or _body == null:
		return
	var position := Vector2(_body.global_position.x, _body.global_position.z)
	var next_progress := route.nearest_progress_m(position, progress_m)
	if next_progress + 5.0 >= progress_m:
		progress_m = next_progress
	var route_error := position.distance_to(route.point_at_distance(progress_m))
	if route_error > MAX_ROUTE_ERROR_M:
		disengage("off_route")
		return
	var remaining := remaining_distance_m()
	if remaining <= arrival_stop_m:
		disengage("arrived")
		return
	var speed_ms := Vector2(_body.linear_velocity.x, _body.linear_velocity.z).length()
	var lookahead := clampf(speed_ms * 18.0, LOOKAHEAD_MIN_M, LOOKAHEAD_MAX_M)
	target_point = route.point_at_distance(minf(progress_m + lookahead, route.total_distance_m()))
	var desired := (target_point - position).normalized().rotated(
		deg_to_rad(traffic_heading_offset_deg))
	var bow := NavigationAxes.vessel_bow_horizontal(_body).normalized()
	var rudder_command := AutopilotMath.rudder_for_heading(bow, desired, full_rudder_error_deg)
	var throttle_command := cruise_throttle
	if remaining < ARRIVAL_SLOW_M:
		throttle_command = 0.28 if remaining < 260.0 else 0.56
	throttle_command = minf(throttle_command, traffic_speed_limit)
	## PropulsionComponent uses negative values for ahead.
	_propulsion.throttle = -throttle_command
	_rudder.rudder_input = rudder_command
	_accumulate_player_distance(delta, speed_ms)
	navigation_updated.emit(progress_m, remaining)


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
