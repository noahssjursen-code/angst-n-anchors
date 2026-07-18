class_name VesselTrafficAgent
extends Node

## Thin per-vessel adapter between real BoatBody motion and the serializable
## maritime traffic authority. It is deliberately shared by player and NPC
## vessels; ownership/network replication belongs outside this component.

const UPDATE_INTERVAL_S := 0.5

var _body: BoatBody
var _elapsed_s := 0.0


func _ready() -> void:
	_body = get_parent() as BoatBody
	add_to_group("vessel_traffic_agent")


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	_elapsed_s += delta
	if _elapsed_s < UPDATE_INTERVAL_S:
		return
	_elapsed_s = 0.0
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	if traffic == null:
		return
	var autopilot := _body.get_node_or_null("VesselAutopilot") as VesselAutopilot
	var captain := _body.get_node_or_null("AutonomousVesselCaptain") as AutonomousVesselCaptain
	var route_id := ""
	var progress_m := 0.0
	if autopilot != null:
		route_id = autopilot.route.route_id if autopilot.route != null else ""
		progress_m = autopilot.progress_m
	traffic.publish_intent({
		"vessel_id": HarbourController.ship_id_of(_body),
		"owner_id": str(_body.get_meta("owner_id", _body.get_meta("company_id", ""))),
		"kind": "player" if _body.is_in_group(PlayerVessel.GROUP) else "npc",
		"position_xz": [_body.global_position.x, _body.global_position.z],
		"velocity_xz": [_body.linear_velocity.x, _body.linear_velocity.z],
		"heading_deg": NavigationAxes.heading_deg_horizontal(
			NavigationAxes.vessel_bow_horizontal(_body)),
		"length_m": _body.hull_size.z,
		"beam_m": _body.hull_size.x,
		"route_id": route_id,
		"route_progress_m": progress_m,
		"phase": AutonomousVesselCaptain.Phase.keys()[captain.phase].to_lower() \
			if captain != null else ("autopilot" if autopilot != null and autopilot.active else "manual"),
	})
	if autopilot == null:
		traffic.release_lane_window(HarbourController.ship_id_of(_body))
		return
	var vessel_id := HarbourController.ship_id_of(_body)
	var lane_result: Dictionary = {}
	if autopilot.route != null and autopilot.route.is_valid() \
			and captain != null and captain.phase == AutonomousVesselCaptain.Phase.PASSAGE:
		lane_result = traffic.request_lane_window(
			vessel_id,
			traffic.lane_window_for_route(autopilot.route, autopilot.progress_m),
			0,
		)
	else:
		traffic.release_lane_window(vessel_id)
	var agreement: Dictionary = traffic.agreement_for(HarbourController.ship_id_of(_body))
	if not lane_result.is_empty() and not bool(lane_result.get("granted", false)):
		autopilot.apply_traffic_instruction({
			"action": "waiting_for_lane_signal",
			"heading_offset_deg": 0.0,
			"speed_limit": 0.18,
		})
	elif agreement.is_empty():
		autopilot.clear_traffic_instruction()
	else:
		autopilot.apply_traffic_instruction(agreement.get("instruction", {}) as Dictionary)


func _exit_tree() -> void:
	if _body == null:
		return
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	if traffic != null:
		traffic.withdraw_vessel(HarbourController.ship_id_of(_body))
