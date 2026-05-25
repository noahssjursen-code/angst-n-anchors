class_name AutonomousVesselSim
extends RefCounted

## Deterministic time-based stages for autonomous fleet vessels.
## `sample()` is authoritative for reconnect — never replay physics.

enum Stage { DOCK, CRANE, TRANSIT }

const DOCK_SEC := 120.0
const CRANE_SEC := 90.0
const MIN_TRANSIT_SEC := 60.0
const TRAWL_START_T := 0.42
const TRAWL_END_T := 0.88
const TRAWL_OFFSHORE_M := 900.0
const NAUTICAL_MILE_M := 1852.0

const KNOTS_BY_CLASS: Dictionary = {
	ShipClass.Type.LAUNCH: 9.0,
	ShipClass.Type.COASTAL_TRADER: 11.0,
	ShipClass.Type.SHORT_SEA_COASTER: 13.0,
	ShipClass.Type.HANDYSIZE_FEEDER: 14.0,
	ShipClass.Type.DEEP_SEA_FREIGHTER: 15.0,
}


static func sample(record: Dictionary, now_unix: int = -1) -> Dictionary:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	av.hydrate_ports()
	if not av.active or av.active_at <= 0:
		return _sanitize_sample(_idle_sample(av))
	var now := float(now_unix) if now_unix >= 0 else AutonomousVesselSim.now_seconds()
	var elapsed := maxf(0.0, now - float(av.active_at))
	if now_unix < 0:
		elapsed = AutonomousSimDebug.scaled_elapsed(av.active_at)
	return sample_at_elapsed(record, elapsed)


static func cycle_duration_for_record(record: Dictionary) -> float:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	av.hydrate_ports()
	var legs := build_legs(av)
	return _cycle_duration(legs)


static func sample_at_elapsed(record: Dictionary, elapsed_sec: float) -> Dictionary:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	av.hydrate_ports()
	if not av.active or av.active_at <= 0:
		return _sanitize_sample(_idle_sample(av))
	var elapsed := maxf(0.0, elapsed_sec)
	var legs := build_legs(av)
	if legs.is_empty():
		return _sanitize_sample(_idle_sample(av))
	var cycle_sec := _cycle_duration(legs)
	if not is_finite(cycle_sec) or cycle_sec <= 0.0:
		return _sanitize_sample(_idle_sample(av))
	var t_cycle := fmod(elapsed, cycle_sec)
	var leg_info := _leg_at_time(legs, t_cycle)
	return _sanitize_sample(_sample_leg(av, leg_info, legs))


static func now_seconds() -> float:
	if _boot_unix < 0:
		_boot_unix = Time.get_unix_time_from_system()
		_boot_ticks_msec = Time.get_ticks_msec()
	return float(_boot_unix) + float(Time.get_ticks_msec() - _boot_ticks_msec) / 1000.0


static var _boot_unix: int = -1
static var _boot_ticks_msec: int = -1
static var _legs_cache: Dictionary = {}


static func invalidate_legs_cache() -> void:
	_legs_cache.clear()
	# Dynamically invalidate the global roundabout graph.
	# Graph rebuilding is now extremely cheap (<10ms) thanks to bounding sphere distance pruning.
	AutonomousTransitRoute.invalidate_graph()


static func build_legs(av: AutonomousVesselRecord) -> Array:
	var key := _legs_cache_key(av)
	if _legs_cache.has(key):
		return _legs_cache[key] as Array
	var legs := _build_legs_uncached(av)
	_legs_cache[key] = legs
	return legs


static func transit_waypoints_at_elapsed(record: Dictionary, elapsed_sec: float) -> Array:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	av.hydrate_ports()
	if not av.active or av.active_at <= 0:
		return []
	var legs := build_legs(av)
	if legs.is_empty():
		return []
	var cycle_sec := _cycle_duration(legs)
	if not is_finite(cycle_sec) or cycle_sec <= 0.0:
		return []
	var t_cycle := fmod(maxf(0.0, elapsed_sec), cycle_sec)
	var leg_info := _leg_at_time(legs, t_cycle)
	var leg := leg_info.get("leg", {}) as Dictionary
	if int(leg.get("stage", Stage.DOCK)) != Stage.TRANSIT:
		return []
	return leg.get("waypoints", [])


static func _legs_cache_key(av: AutonomousVesselRecord) -> String:
	var visit := av.visit_port_id
	var parts: PackedStringArray = PackedStringArray()
	parts.append(av.home_port_id)
	parts.append(visit)
	parts.append("1" if av.role_is_fishing() else "0")
	parts.append(av.hull_id)
	# Port ids only — never bake live dock transforms into the cache key.
	parts.append("route_v9")
	parts.append(str(BerthApproachLanes.is_initialized()))
	parts.append(str(LandField.get_island_count()) if LandField.is_initialized() else "0")
	return "|".join(parts)


static func _build_legs_uncached(av: AutonomousVesselRecord) -> Array:
	var legs: Array = []
	if av.home_port_id.is_empty():
		return legs
	var fishing := av.role_is_fishing()
	var visit := av.visit_port_id

	_append_dock_crane(legs, av.home_port_id)

	if visit.is_empty():
		if fishing:
			_append_transit(legs, av, av.home_port_id, av.home_port_id, true, true)
		return legs

	_append_transit(legs, av, av.home_port_id, visit, fishing, false)
	_append_dock_crane(legs, visit)
	_append_transit(legs, av, visit, av.home_port_id, fishing, false)
	return legs


static func stage_name(stage: Stage) -> String:
	match stage:
		Stage.DOCK:
			return "Dock"
		Stage.CRANE:
			return "Crane"
		Stage.TRANSIT:
			return "Transit"
		_:
			return "Idle"


static func format_stage_remaining(sec: float) -> String:
	sec = maxf(0.0, sec)
	if sec >= 3600.0:
		var h := int(sec / 3600.0)
		var m := int(fmod(sec, 3600.0) / 60.0)
		return "%dh %dm" % [h, m]
	if sec >= 60.0:
		var m := int(sec / 60.0)
		var s := int(fmod(sec, 60.0))
		return "%dm %02ds" % [m, s]
	return "%ds" % int(ceil(sec))


static func _append_dock_crane(legs: Array, port_id: String) -> void:
	legs.append({
		"stage": Stage.DOCK,
		"port_id": port_id,
		"duration": DOCK_SEC,
	})
	legs.append({
		"stage": Stage.CRANE,
		"port_id": port_id,
		"duration": CRANE_SEC,
	})


static func _append_transit(
	legs: Array,
	av: AutonomousVesselRecord,
	from_id: String,
	to_id: String,
	trawl_mid: bool,
	loop_home: bool,
) -> void:
	var waypoints := AutonomousTransitRoute.build_waypoints(
		from_id,
		to_id,
		loop_home,
	)
	var distance_m := AutonomousTransitRoute.polyline_length(waypoints)
	var speed_knots := _speed_knots(av)
	var duration := maxf(MIN_TRANSIT_SEC, distance_m / maxf(speed_knots * NAUTICAL_MILE_M / 3600.0, 0.5))
	legs.append({
		"stage": Stage.TRANSIT,
		"from_id": from_id,
		"to_id": to_id,
		"duration": duration,
		"trawl_mid": trawl_mid,
		"loop_home": loop_home,
		"waypoints": waypoints,
	})


static func _cycle_duration(legs: Array) -> float:
	var total := 0.0
	for leg_raw in legs:
		if typeof(leg_raw) != TYPE_DICTIONARY:
			continue
		total += float((leg_raw as Dictionary).get("duration", 0.0))
	return maxf(total, 1.0)


static func _leg_at_time(legs: Array, t_cycle: float) -> Dictionary:
	var cursor := 0.0
	for i in range(legs.size()):
		var leg := legs[i] as Dictionary
		var dur := float(leg.get("duration", 0.0))
		if t_cycle < cursor + dur:
			var local_t := 0.0 if dur <= 0.0 else clampf((t_cycle - cursor) / dur, 0.0, 1.0)
			return {"index": i, "leg": leg, "local_t": local_t}
		cursor += dur
	var last: Dictionary = legs[legs.size() - 1] as Dictionary
	return {"index": legs.size() - 1, "leg": last, "local_t": 1.0}


static func _sample_leg(av: AutonomousVesselRecord, leg_info: Dictionary, legs: Array) -> Dictionary:
	var leg := leg_info.get("leg", {}) as Dictionary
	var local_t := float(leg_info.get("local_t", 0.0))
	var leg_duration := float(leg.get("duration", 0.0))
	var stage_remaining_sec := leg_duration * maxf(0.0, 1.0 - local_t)
	var stage: Stage = int(leg.get("stage", Stage.DOCK))
	var port_id := str(leg.get("port_id", leg.get("from_id", av.home_port_id)))
	var trawling := false

	var pos := Vector3.ZERO
	var yaw := 0.0
	var target := Vector3.ZERO
	var velocity := Vector3.ZERO

	match stage:
		Stage.DOCK, Stage.CRANE:
			var dock_pose := _sim_dock_pose(port_id)
			pos = dock_pose.get("position", Vector3.ZERO)
			target = pos
			yaw = float(dock_pose.get("yaw", 0.0))
		Stage.TRANSIT:
			pos = _transit_position(leg, local_t)
			velocity = _transit_velocity(leg, local_t, leg_duration)
			target = pos + velocity * 0.25
			yaw = _yaw_from_direction(velocity) if velocity.length_squared() > 0.01 else _port_yaw(str(leg.get("from_id", "")))
			if bool(leg.get("trawl_mid", false)):
				trawling = local_t >= TRAWL_START_T and local_t <= TRAWL_END_T

	pos.y = WaveSurface.WATER_LEVEL
	target.y = WaveSurface.WATER_LEVEL

	var transit_waypoints: Array = []
	if stage == Stage.TRANSIT:
		transit_waypoints = leg.get("waypoints", [])

	return {
		"stage": stage,
		"stage_name": stage_name(stage),
		"stage_remaining_sec": stage_remaining_sec,
		"leg_duration": leg_duration,
		"leg_index": int(leg_info.get("index", 0)),
		"leg_count": legs.size(),
		"leg_t": local_t,
		"port_id": port_id,
		"position": pos,
		"target_position": target,
		"velocity": velocity,
		"yaw": yaw,
		"trawling": trawling,
		"transit_waypoints": transit_waypoints,
		"active": true,
	}


static func _idle_sample(av: AutonomousVesselRecord) -> Dictionary:
	var pos := _berth_position(av.home_port_id) if not av.home_port_id.is_empty() else Vector3.ZERO
	pos.y = WaveSurface.WATER_LEVEL
	return {
		"stage": Stage.DOCK,
		"stage_name": "Idle",
		"stage_remaining_sec": 0.0,
		"leg_duration": 0.0,
		"leg_index": 0,
		"leg_count": 0,
		"leg_t": 0.0,
		"port_id": av.home_port_id,
		"position": pos,
		"target_position": pos,
		"velocity": Vector3.ZERO,
		"yaw": _port_yaw(av.home_port_id),
		"trawling": false,
		"active": false,
	}


static func _transit_position(leg: Dictionary, t: float) -> Vector3:
	var waypoints: Array = leg.get("waypoints", [])
	if waypoints.size() >= 2:
		return AutonomousTransitRoute.sample_polyline(waypoints, t)
	var from_id := str(leg.get("from_id", ""))
	var to_id := str(leg.get("to_id", ""))
	var from_pos := _port_sea_pos(from_id)
	var to_pos := _port_sea_pos(to_id)
	if bool(leg.get("loop_home", false)):
		var off := _offshore_point(from_id)
		if not _vec3_is_valid(from_pos) or not _vec3_is_valid(off):
			return from_pos if _vec3_is_valid(from_pos) else Vector3.ZERO
		if t <= 0.5:
			return from_pos.lerp(off, t * 2.0)
		return off.lerp(from_pos, (t - 0.5) * 2.0)
	if not _vec3_is_valid(from_pos) or not _vec3_is_valid(to_pos):
		return from_pos if _vec3_is_valid(from_pos) else to_pos
	return from_pos.lerp(to_pos, clampf(t, 0.0, 1.0))


static func _transit_velocity(leg: Dictionary, local_t: float, leg_duration: float) -> Vector3:
	var waypoints: Array = leg.get("waypoints", [])
	if waypoints.size() >= 2:
		return AutonomousTransitRoute.velocity_along_polyline(waypoints, local_t, leg_duration)
	if leg_duration <= 0.0:
		return Vector3.ZERO
	var from_id := str(leg.get("from_id", ""))
	var to_id := str(leg.get("to_id", ""))
	var from_pos := _port_sea_pos(from_id)
	var to_pos := _port_sea_pos(to_id)
	if bool(leg.get("loop_home", false)):
		var off := _offshore_point(from_id)
		if not _vec3_is_valid(from_pos) or not _vec3_is_valid(off):
			return Vector3.ZERO
		if local_t <= 0.5:
			return (off - from_pos) * (2.0 / leg_duration)
		return (from_pos - off) * (2.0 / leg_duration)
	if not _vec3_is_valid(from_pos) or not _vec3_is_valid(to_pos):
		return Vector3.ZERO
	return (to_pos - from_pos) / leg_duration


static func dock_berth_transform(
	port_id: String,
	berth_index: int = 0,
	half_beam_m: float = -1.0,
) -> Transform3D:
	var dock := _find_dock(port_id)
	if dock == null or not is_instance_valid(dock):
		return Transform3D.IDENTITY
	return dock.get_berth_spawn_transform(berth_index, half_beam_m)


## Authoritative sim anchor — berth lane origin when baked, else registry spawn.
static func _port_sea_pos(port_id: String) -> Vector3:
	if BerthApproachLanes.is_initialized():
		var berth := BerthApproachLanes.berth_world_position(port_id, 0)
		if _vec3_is_valid(berth) and berth != Vector3.ZERO:
			return berth
	return _registry_pos(port_id)


static func _sim_dock_pose(port_id: String) -> Dictionary:
	var pos := _port_sea_pos(port_id)
	if not _vec3_is_valid(pos) or pos == Vector3.ZERO:
		pos = Vector3.ZERO
	return {
		"position": pos,
		"yaw": _port_yaw(port_id),
	}


static func _berth_position(port_id: String) -> Vector3:
	return _port_sea_pos(port_id)


static func _offshore_point(port_id: String) -> Vector3:
	var base := _port_sea_pos(port_id)
	if not _vec3_is_valid(base) or base == Vector3.ZERO:
		return base
	var info := _port_info(port_id)
	var ry := float(info.get("rotation_y", 0.0))
	var seaward_reg := Vector3(-sin(ry), 0.0, -cos(ry))
	if seaward_reg.length_squared() < 0.0001:
		seaward_reg = Vector3(0.0, 0.0, -1.0)
	else:
		seaward_reg = seaward_reg.normalized()
	return base + seaward_reg * TRAWL_OFFSHORE_M


static func _port_yaw(port_id: String) -> float:
	var info := _port_info(port_id)
	return float(info.get("rotation_y", 0.0))


static func _yaw_from_basis(basis: Basis) -> float:
	var forward := -basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return 0.0
	forward = forward.normalized()
	return atan2(-forward.x, -forward.z)


static func _yaw_between(from_pos: Vector3, to_pos: Vector3) -> float:
	var dx := to_pos.x - from_pos.x
	var dz := to_pos.z - from_pos.z
	if dx * dx + dz * dz < 0.01:
		return 0.0
	return _yaw_from_direction(Vector3(dx, 0.0, dz))


static func _yaw_from_direction(v: Vector3) -> float:
	if v.length_squared() < 0.01:
		return 0.0
	# Body forward is −Z; align −basis.z with travel direction.
	return atan2(-v.x, -v.z)


static func _sanitize_sample(sample: Dictionary) -> Dictionary:
	var out := sample.duplicate(true)
	var pos: Vector3 = out.get("position", Vector3.ZERO)
	var target: Vector3 = out.get("target_position", pos)
	if not _vec3_is_valid(pos):
		pos = Vector3.ZERO
	if not _vec3_is_valid(target):
		target = pos
	pos.y = WaveSurface.WATER_LEVEL
	target.y = WaveSurface.WATER_LEVEL
	var yaw := float(out.get("yaw", 0.0))
	if not is_finite(yaw):
		yaw = 0.0
	var velocity: Vector3 = out.get("velocity", Vector3.ZERO)
	if not velocity.is_finite():
		velocity = Vector3.ZERO
	velocity.y = 0.0
	out["position"] = pos
	out["target_position"] = target
	out["velocity"] = velocity
	out["yaw"] = yaw
	out["valid"] = _vec3_is_valid(pos) and pos != Vector3.ZERO
	return out


static func _vec3_is_valid(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < 1.0e8 and absf(v.z) < 1.0e8


static func _speed_knots(av: AutonomousVesselRecord) -> float:
	var entry := HullRegistry.get_by_id(av.hull_id)
	var ship_class: int = int(entry.get("ship_class", ShipClass.Type.COASTAL_TRADER))
	return float(KNOTS_BY_CLASS.get(ship_class, 11.0))


static func _registry_pos(port_id: String) -> Vector3:
	if port_id.is_empty():
		return Vector3.ZERO
	var reg := _registry()
	if reg == null or not reg.has_method("get_port_spawn_position"):
		return Vector3.ZERO
	var pos := reg.call("get_port_spawn_position", port_id) as Vector3
	if not _vec3_is_valid(pos) or pos.x == INF:
		if reg.has_method("get_port_position"):
			pos = reg.call("get_port_position", port_id) as Vector3
	if not _vec3_is_valid(pos):
		return Vector3.ZERO
	return pos


static func _port_info(port_id: String) -> Dictionary:
	var reg := _registry()
	if reg == null or not reg.has_method("get_port_info"):
		return {}
	return reg.call("get_port_info", port_id) as Dictionary


static func find_dock(port_id: String) -> PortDock:
	return _find_dock(port_id)


static func _find_dock(port_id: String) -> PortDock:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("port_docks"):
		var dock := node as PortDock
		if dock != null and str(dock.port_id) == port_id:
			return dock
	return null


static func _registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("/root/ContractRegistry")
