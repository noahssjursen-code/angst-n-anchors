class_name VesselAuthoritySnapshot
extends RefCounted

## JSON-safe wire record shared by singleplayer authorities and future MP
## servers. Geometry and generated route waypoints are intentionally excluded:
## clients rebuild them from world identity + endpoints and verify route_id.

const SCHEMA_VERSION := 1


static func from_projection_record(
		record: Dictionary,
		plan: MarineRoutePlan,
		live_ship: Node3D = null,
		server_unix_msec: int = 0,
) -> Dictionary:
	var assignment := record.get("assignment", {}) as Dictionary
	var projection := record.get("projection", {}) as Dictionary
	var vessel := record.get("vessel", {}) as Dictionary
	var vessel_id := str(record.get("uid", vessel.get("uid", ""))).strip_edges()
	var navigation := {
		"route_id": plan.route_id if plan != null else "",
		"layout_checksum": plan.layout_checksum if plan != null else "",
		"algorithm_version": plan.algorithm_version if plan != null else 0,
		"route_progress_m": float(projection.get(
			"route_progress_m", assignment.get("route_progress_m", 0.0))),
		"route_distance_m": plan.total_distance_m() if plan != null else 0.0,
		"origin_port_id": str(assignment.get("leg_origin_port_id", "")),
		"origin_berth_id": str(assignment.get("leg_origin_berth_id", "")),
		"destination_port_id": str(assignment.get("leg_destination_port_id", "")),
		"destination_berth_id": str(assignment.get("leg_destination_berth_id", "")),
		"position_xz": _xz_of(projection.get("position", Vector3.ZERO)),
		"heading_xz": _xy_of(projection.get("heading_xz", Vector2.ZERO)),
	}
	var runtime := {}
	if live_ship != null and is_instance_valid(live_ship):
		navigation["position_xz"] = [live_ship.global_position.x, live_ship.global_position.z]
		var rigid := live_ship as RigidBody3D
		if rigid != null:
			navigation["velocity_xz"] = [rigid.linear_velocity.x, rigid.linear_velocity.z]
		navigation["heading_deg"] = NavigationAxes.heading_deg_horizontal(
			NavigationAxes.vessel_bow_horizontal(live_ship))
		var captain := live_ship.get_node_or_null("AutonomousVesselCaptain")
		var autopilot := live_ship.get_node_or_null("VesselAutopilot")
		if captain != null and captain.has_method("authority_snapshot"):
			runtime["captain"] = captain.call("authority_snapshot")
		if autopilot != null:
			navigation["route_progress_m"] = float(autopilot.get("progress_m"))
			runtime["traffic_instruction"] = str(autopilot.get("traffic_instruction"))
		if live_ship.has_method("get_physics_quality_name"):
			runtime["physics_quality"] = str(live_ship.call("get_physics_quality_name"))
	return _json_safe({
		"schema_version": SCHEMA_VERSION,
		"server_unix_msec": server_unix_msec if server_unix_msec > 0 \
			else int(Time.get_unix_time_from_system() * 1000.0),
		"vessel_id": vessel_id,
		"owner_id": str(vessel.get("owner_id", record.get("owner_id", ""))),
		"vessel": vessel.duplicate(true),
		"assignment": assignment.duplicate(true),
		"navigation": navigation,
		"runtime": runtime,
	})


static func is_valid(data: Dictionary) -> bool:
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	if str(data.get("vessel_id", "")).strip_edges().is_empty():
		return false
	var vessel := data.get("vessel", {}) as Dictionary
	var assignment := data.get("assignment", {}) as Dictionary
	var navigation := data.get("navigation", {}) as Dictionary
	return not vessel.is_empty() and not assignment.is_empty() \
		and str(navigation.get("origin_port_id", "")) != "" \
		and str(navigation.get("destination_port_id", "")) != ""


static func json_round_trip(data: Dictionary) -> Dictionary:
	var decoded: Variant = JSON.parse_string(JSON.stringify(_json_safe(data)))
	return decoded as Dictionary if decoded is Dictionary else {}


static func _json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in (value as Dictionary).keys():
			out[str(key)] = _json_safe((value as Dictionary)[key])
		return out
	if value is Array:
		var out := []
		for item in value as Array:
			out.append(_json_safe(item))
		return out
	if value is PackedStringArray or value is PackedFloat32Array \
			or value is PackedFloat64Array or value is PackedInt32Array \
			or value is PackedInt64Array or value is PackedVector2Array \
			or value is PackedVector3Array:
		return _json_safe(Array(value))
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector2i:
		return [value.x, value.y]
	if value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	return str(value)


static func _xz_of(value: Variant) -> Array:
	if value is Vector3:
		return [value.x, value.z]
	if value is Vector2:
		return [value.x, value.y]
	if value is Array and (value as Array).size() >= 2:
		return [float(value[0]), float(value[-1])]
	return [0.0, 0.0]


static func _xy_of(value: Variant) -> Array:
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.z]
	if value is Array and (value as Array).size() >= 2:
		return [float(value[0]), float(value[1])]
	return [0.0, 0.0]
