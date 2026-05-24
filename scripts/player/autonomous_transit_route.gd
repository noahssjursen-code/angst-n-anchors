class_name AutonomousTransitRoute
extends RefCounted

## Sea-lane waypoints for autonomous vessel transit — avoids cutting through islands.

enum SegmentMode { DOCK_LEG, OPEN_WATER, APPROACH }

const SEA_CLEARANCE_M := 180.0
const ROUTING_RADIUS_PADDING_M := 55.0
const TRAWL_OFFSHORE_M := 900.0
const DOCK_LEAD_M := 140.0
const LAND_SAMPLE_COUNT := 48
const MAX_DETOUR_PASSES := 4
const MAX_ARC_RAD := deg_to_rad(175.0)
const ARC_STEP_RAD := deg_to_rad(28.0)


static func build_waypoints(
	from_pos: Vector3,
	to_pos: Vector3,
	departure_offshore: Vector3,
	arrival_offshore: Vector3,
	loop_home: bool,
) -> Array:
	if loop_home:
		return _loop_home_waypoints(from_pos, departure_offshore)
	if not _vec3_is_valid(from_pos) or not _vec3_is_valid(to_pos):
		return [from_pos, to_pos] if _vec3_is_valid(from_pos) else []
	return _port_to_port_waypoints(from_pos, to_pos, departure_offshore, arrival_offshore)


static func polyline_length(points: Array) -> float:
	if points.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		total += Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	return maxf(total, 1.0)


static func sample_polyline(points: Array, t: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if points.size() == 1:
		return points[0] as Vector3
	var clamped := clampf(t, 0.0, 1.0)
	var seg_lengths: Array[float] = []
	var total := 0.0
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var len := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		seg_lengths.append(len)
		total += len
	if total <= 0.001:
		return points[0] as Vector3
	var target := clamped * total
	var cursor := 0.0
	for i in range(seg_lengths.size()):
		var seg_len: float = seg_lengths[i]
		if cursor + seg_len >= target:
			var local := 0.0 if seg_len <= 0.001 else (target - cursor) / seg_len
			var a2: Vector3 = points[i]
			var b2: Vector3 = points[i + 1]
			var pos := a2.lerp(b2, local)
			pos.y = WaveSurface.WATER_LEVEL
			return pos
		cursor += seg_len
	var end: Vector3 = points[points.size() - 1]
	end.y = WaveSurface.WATER_LEVEL
	return end


static func velocity_along_polyline(points: Array, local_t: float, leg_duration: float) -> Vector3:
	if points.size() < 2 or leg_duration <= 0.0:
		return Vector3.ZERO
	var eps := 0.025
	var t1 := minf(local_t + eps, 1.0)
	var p0 := sample_polyline(points, local_t)
	var p1 := sample_polyline(points, t1)
	var dt := maxf((t1 - local_t) * leg_duration, 0.001)
	var vel := (p1 - p0) / dt
	vel.y = 0.0
	return vel


static func _loop_home_waypoints(from_pos: Vector3, offshore: Vector3) -> Array:
	if not _vec3_is_valid(from_pos):
		return []
	if not _vec3_is_valid(offshore):
		return [from_pos]
	var pts: Array = []
	_append_unique(pts, from_pos)
	var lead := _seaward_step(from_pos, offshore, DOCK_LEAD_M)
	_append_segment(pts, lead, SegmentMode.DOCK_LEG)
	_append_segment(pts, offshore, SegmentMode.OPEN_WATER)
	_append_segment(pts, from_pos, SegmentMode.APPROACH)
	_force_terminal(pts, from_pos)
	return pts


static func _port_to_port_waypoints(
	from_pos: Vector3,
	to_pos: Vector3,
	departure_offshore: Vector3,
	arrival_offshore: Vector3,
) -> Array:
	var pts: Array = []
	_append_unique(pts, from_pos)

	var dep_lead := _seaward_step(from_pos, departure_offshore, DOCK_LEAD_M)
	_append_segment(pts, dep_lead, SegmentMode.DOCK_LEG)

	var ocean_start: Vector3 = pts[pts.size() - 1]
	var entry_gate := _port_entry_gate(to_pos, ocean_start, arrival_offshore)
	_append_segment(pts, entry_gate, SegmentMode.OPEN_WATER)

	_append_segment(pts, to_pos, SegmentMode.APPROACH)
	_force_terminal(pts, to_pos)
	return pts


static func _append_segment(pts: Array, end: Vector3, mode: SegmentMode) -> void:
	if not _vec3_is_valid(end) or pts.is_empty():
		return
	var start: Vector3 = pts[pts.size() - 1]
	for p in _route_segment(start, end, mode):
		_append_unique(pts, p)


static func _route_segment(start: Vector3, end: Vector3, mode: SegmentMode) -> Array:
	var chain: Array = []
	var head := start
	for detour_i in range(MAX_DETOUR_PASSES):
		if not _segment_blocked(head, end, mode):
			if _horiz_dist(head, end) > 1.0:
				chain.append(end)
			return chain
		var blocker := _primary_blocker(head, end, mode)
		if blocker.is_empty():
			chain.append(end)
			return chain
		var arc := _arc_detour_points(blocker, head, end)
		if arc.is_empty():
			chain.append(end)
			return chain
		for p in arc:
			chain.append(p)
		head = arc[arc.size() - 1]
	chain.append(end)
	return chain


static func _seaward_step(port_pos: Vector3, seaward_hint: Vector3, lead_m: float) -> Vector3:
	var dir := seaward_hint - port_pos
	dir.y = 0.0
	if dir.length_squared() < 1.0:
		dir = Vector3(0.0, 0.0, -1.0)
	else:
		dir = dir.normalized()
	var out := port_pos + dir * lead_m
	out.y = WaveSurface.WATER_LEVEL
	return out


static func _port_entry_gate(
	port_pos: Vector3,
	approach_from: Vector3,
	seaward_hint: Vector3,
) -> Vector3:
	var disk := _nearest_island_disk(port_pos)
	if disk.is_empty():
		return _fallback_point(approach_from, port_pos, DOCK_LEAD_M * 2.5)
	var center: Vector2 = disk.get("center", Vector2.ZERO)
	var radius: float = float(disk.get("radius", 0.0))
	var ang_in: float = _bearing_from_center(center, approach_from)
	var ang_sea: float = _bearing_from_center(center, seaward_hint)
	var ang: float = ang_in
	if absf(_angle_diff(ang_in, ang_sea)) > PI * 0.45:
		ang = _lerp_angle(ang_in, ang_sea, 0.42)
	return _clearance_point(center, radius, ang)


static func _fallback_point(from_pos: Vector3, to_pos: Vector3, lead_m: float) -> Vector3:
	var dir := to_pos - from_pos
	dir.y = 0.0
	if dir.length_squared() < 1.0:
		dir = Vector3(0.0, 0.0, -1.0)
	else:
		dir = dir.normalized()
	var out := from_pos + dir * lead_m
	out.y = WaveSurface.WATER_LEVEL
	return out


static func _nearest_island_disk(pos: Vector3) -> Dictionary:
	if not LandField.is_initialized():
		return {}
	var pos2 := Vector2(pos.x, pos.z)
	var best := INF
	var best_disk: Dictionary = {}
	for disk in LandField.get_island_disks():
		var center: Vector2 = disk.get("center", Vector2.ZERO)
		var radius: float = float(disk.get("radius", 0.0))
		var d := pos2.distance_to(center) - radius
		if d < best:
			best = d
			best_disk = disk
	return best_disk


static func _routing_radius(island_radius: float) -> float:
	return island_radius + SEA_CLEARANCE_M + ROUTING_RADIUS_PADDING_M


static func _clearance_point(center: Vector2, island_radius: float, ang: float) -> Vector3:
	var r := _routing_radius(island_radius)
	return Vector3(
		center.x + cos(ang) * r,
		WaveSurface.WATER_LEVEL,
		center.y + sin(ang) * r,
	)


static func _bearing_from_center(center: Vector2, pos: Vector3) -> float:
	return atan2(pos.z - center.y, pos.x - center.x)


static func _angle_diff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))


static func _lerp_angle(a: float, b: float, t: float) -> float:
	var diff := _angle_diff(b, a)
	return a + diff * clampf(t, 0.0, 1.0)


static func _segment_blocked(a: Vector3, b: Vector3, mode: SegmentMode) -> bool:
	if not LandField.is_initialized():
		return false
	if _segment_pierces_land(a, b):
		return true
	match mode:
		SegmentMode.DOCK_LEG:
			return false
		SegmentMode.OPEN_WATER:
			return _segment_violates_clearance(a, b, 0.0, 1.0)
		SegmentMode.APPROACH:
			return _segment_violates_clearance(a, b, 0.0, 0.88)
	return false


static func _segment_pierces_land(a: Vector3, b: Vector3) -> bool:
	for i in range(LAND_SAMPLE_COUNT + 1):
		var t := float(i) / float(LAND_SAMPLE_COUNT)
		var p := a.lerp(b, t)
		if LandField.distance_to_land(p) < 0.0:
			return true
	return false


static func _segment_violates_clearance(a: Vector3, b: Vector3, t_start: float, t_end: float) -> bool:
	for i in range(LAND_SAMPLE_COUNT + 1):
		var t := lerpf(t_start, t_end, float(i) / float(LAND_SAMPLE_COUNT))
		var p := a.lerp(b, t)
		if LandField.distance_to_land(p) < SEA_CLEARANCE_M:
			return true
	return false


static func _primary_blocker(a: Vector3, b: Vector3, mode: SegmentMode) -> Dictionary:
	if not LandField.is_initialized():
		return {}
	var worst := INF
	var worst_p := Vector2.ZERO
	for i in range(LAND_SAMPLE_COUNT + 1):
		var t := float(i) / float(LAND_SAMPLE_COUNT)
		if mode == SegmentMode.APPROACH and t > 0.88:
			continue
		var p := a.lerp(b, t)
		var d := LandField.distance_to_land(p)
		if d < worst:
			worst = d
			worst_p = Vector2(p.x, p.z)
	var limit := 0.0 if mode == SegmentMode.DOCK_LEG else SEA_CLEARANCE_M
	if worst >= limit:
		return {}
	for disk in LandField.get_island_disks():
		var center: Vector2 = disk.get("center", Vector2.ZERO)
		var radius: float = float(disk.get("radius", 0.0))
		if worst_p.distance_to(center) <= radius + SEA_CLEARANCE_M:
			return disk
	return {}


static func _arc_detour_points(blocker: Dictionary, a: Vector3, b: Vector3) -> Array:
	var center: Vector2 = blocker.get("center", Vector2.ZERO)
	var radius: float = _routing_radius(float(blocker.get("radius", 0.0)))
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ang_a: float = atan2(a2.y - center.y, a2.x - center.x)
	var ang_b: float = atan2(b2.y - center.y, b2.x - center.x)
	var delta_cw: float = posmod(ang_b - ang_a, TAU)
	var delta_ccw: float = delta_cw - TAU
	var delta: float = delta_ccw if absf(delta_ccw) <= absf(delta_cw) else delta_cw
	if absf(delta) < 0.04:
		return []
	if absf(delta) > MAX_ARC_RAD:
		delta = MAX_ARC_RAD if delta >= 0.0 else -MAX_ARC_RAD
	var steps := clampi(int(ceil(absf(delta) / ARC_STEP_RAD)), 2, 7)
	var pts: Array = []
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var ang: float = ang_a + delta * t
		pts.append(Vector3(
			center.x + cos(ang) * radius,
			WaveSurface.WATER_LEVEL,
			center.y + sin(ang) * radius,
		))
	return pts


static func _append_unique(points: Array, p: Vector3) -> void:
	if not _vec3_is_valid(p):
		return
	if points.is_empty():
		points.append(p)
		return
	var last: Vector3 = points[points.size() - 1]
	if _horiz_dist(last, p) > 6.0:
		points.append(p)


static func _force_terminal(points: Array, terminal: Vector3) -> void:
	if not _vec3_is_valid(terminal) or points.is_empty():
		return
	var last: Vector3 = points[points.size() - 1]
	if _horiz_dist(last, terminal) > 1.0:
		points.append(terminal)
	else:
		points[points.size() - 1] = terminal


static func _horiz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


static func _vec3_is_valid(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < 1.0e8 and absf(v.z) < 1.0e8
