class_name ReplicatedFleetAuthority
extends Node

## Client-side fleet authority fed by server snapshots. A received timestamp is
## used once to establish each vessel's current route point; local deterministic
## progression continues from that point until the next server correction.

signal company_changed(snapshot: Dictionary)

const SCHEMA_VERSION := 1
const DEFAULT_CRUISE_SPEED_MS := 7.2
const MAX_REPLICATED_VESSELS := 512

var _fleet: Dictionary = {}
var _local_simulation: Dictionary = {}
var _snapshot_server_unix_msec := 0
var _snapshot_received_ticks_msec := 0
var _revision := -1


func _ready() -> void:
	add_to_group("vessel_fleet_authority")


func apply_server_snapshot(data: Dictionary, layout: WorldLayout = null) -> Dictionary:
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		return {"ok": false, "reason": "unsupported_schema", "accepted": 0}
	var incoming_revision := int(data.get("revision", 0))
	if incoming_revision < _revision:
		return {"ok": false, "reason": "stale_revision", "accepted": 0}
	var incoming := data.get("vessels", []) as Array
	if incoming.size() > MAX_REPLICATED_VESSELS:
		return {"ok": false, "reason": "fleet_limit_exceeded", "accepted": 0}
	var rebuilt: Dictionary = {}
	var rejected := 0
	for raw in incoming:
		var wire := raw as Dictionary
		if not VesselAuthoritySnapshot.is_valid(wire):
			rejected += 1
			continue
		var uid := str(wire.get("vessel_id", "")).strip_edges()
		if rebuilt.has(uid):
			rejected += 1
			continue
		var plan := _rebuild_route(wire, layout)
		var navigation := wire.get("navigation", {}) as Dictionary
		var expected_route_id := str(navigation.get("route_id", ""))
		var expected_layout := str(navigation.get("layout_checksum", ""))
		if layout != null and not expected_layout.is_empty() \
				and expected_layout != str(layout.layout_checksum):
			rejected += 1
			continue
		if layout != null and (plan == null or not plan.is_valid() \
				or (not expected_route_id.is_empty() and plan.route_id != expected_route_id)):
			rejected += 1
			continue
		rebuilt[uid] = {
			"uid": uid,
			"vessel": (wire.get("vessel", {}) as Dictionary).duplicate(true),
			"assignment": (wire.get("assignment", {}) as Dictionary).duplicate(true),
			"navigation": navigation.duplicate(true),
			"runtime": (wire.get("runtime", {}) as Dictionary).duplicate(true),
			"plan": plan,
		}
	if not incoming.is_empty() and rebuilt.is_empty():
		return {"ok": false, "reason": "all_vessels_rejected", "accepted": 0,
			"rejected": rejected}
	_fleet = rebuilt
	_revision = incoming_revision
	_snapshot_server_unix_msec = int(data.get(
		"server_unix_msec", Time.get_unix_time_from_system() * 1000.0))
	_snapshot_received_ticks_msec = Time.get_ticks_msec()
	company_changed.emit(snapshot())
	return {"ok": true, "reason": "", "accepted": rebuilt.size(), "rejected": rejected}


func snapshot() -> Dictionary:
	return {
		"replicated": true,
		"server_unix_msec": _snapshot_server_unix_msec,
		"revision": _revision,
		"fleet_count": _fleet.size(),
	}


func projection_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for uid_raw in _fleet.keys():
		var uid := str(uid_raw)
		var record := _fleet[uid] as Dictionary
		out.append({
			"uid": uid,
			"vessel": (record.get("vessel", {}) as Dictionary).duplicate(true),
			"assignment": (record.get("assignment", {}) as Dictionary).duplicate(true),
			"projection": _projection(record),
		})
	return out


func leg_route_plan(vessel_uid: String) -> MarineRoutePlan:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	var plan := record.get("plan") as MarineRoutePlan
	return plan if plan != null else MarineRoutePlan.new()


func set_local_voyage_simulation(vessel_uid: String, active: bool) -> void:
	if active:
		_local_simulation[vessel_uid] = true
	else:
		_local_simulation.erase(vessel_uid)


func suspend_local_voyage(vessel_uid: String, progress_m: float, _distance_m: float) -> void:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	if record.is_empty():
		return
	(record.get("navigation", {}) as Dictionary)["route_progress_m"] = progress_m
	_local_simulation.erase(vessel_uid)


func set_local_operations_active(_vessel_uid: String, _active: bool) -> void:
	pass


func _projection(record: Dictionary) -> Dictionary:
	var navigation := record.get("navigation", {}) as Dictionary
	var assignment := record.get("assignment", {}) as Dictionary
	var plan := record.get("plan") as MarineRoutePlan
	var progress_m := float(navigation.get("route_progress_m", 0.0))
	if str(assignment.get("status", "")) == "underway" and plan != null and plan.is_valid():
		var uid := str(record.get("uid", ""))
		if not _local_simulation.has(uid):
			var elapsed_s := maxf(
				float(Time.get_ticks_msec() - _snapshot_received_ticks_msec) * 0.001, 0.0)
			progress_m = minf(progress_m + elapsed_s * float(
				assignment.get("cruise_speed_ms", DEFAULT_CRUISE_SPEED_MS)),
				plan.total_distance_m())
		var point := plan.point_at_distance(progress_m)
		return {
			"position": Vector3(point.x, WaveSurface.WATER_LEVEL, point.y),
			"heading_xz": plan.direction_at_distance(progress_m, 30.0),
			"route_progress_m": progress_m,
			"route_distance_m": plan.total_distance_m(),
			"origin_port_id": navigation.get("origin_port_id", ""),
			"destination_port_id": navigation.get("destination_port_id", ""),
			"berthed": false,
		}
	var position := _vector2_value(navigation.get("position_xz", []))
	var heading := _vector2_value(navigation.get("heading_xz", []))
	return {
		"position": Vector3(position.x, WaveSurface.WATER_LEVEL, position.y),
		"heading_xz": heading,
		"route_progress_m": progress_m,
		"origin_port_id": navigation.get("origin_port_id", ""),
		"destination_port_id": navigation.get("destination_port_id", ""),
		"berthed": str(assignment.get("status", "")) != "underway",
	}


func _rebuild_route(wire: Dictionary, layout: WorldLayout) -> MarineRoutePlan:
	if layout == null:
		return null
	var navigation := wire.get("navigation", {}) as Dictionary
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null:
		return null
	var origin_id := str(navigation.get("origin_port_id", ""))
	var destination_id := str(navigation.get("destination_port_id", ""))
	var origin := catalog.get_port_position(origin_id) as Vector3
	var destination := catalog.get_port_position(destination_id) as Vector3
	return MarineRoutePlanner.new(layout).plan_berth_to_berth(
		Vector2(origin.x, origin.z),
		Vector2(destination.x, destination.z),
		origin_id,
		str(navigation.get("origin_berth_id", "")),
		destination_id,
		str(navigation.get("destination_berth_id", "")),
	)


func _vector2_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector3:
		return Vector2(value.x, value.z)
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
