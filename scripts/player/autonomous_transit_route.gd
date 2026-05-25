class_name AutonomousTransitRoute
extends RefCounted

## Sea-lane waypoints: berth tentacle → open-water chord → destination tentacle.

enum SegmentMode { LANE, OPEN_WATER }

const OPEN_CONNECT_CLEARANCE_M := 28.0
const LAND_SAMPLE_COUNT := 32
const MAX_ARC_RAD := deg_to_rad(118.0)
const ARC_STEP_RAD := deg_to_rad(22.0)
const ROUTING_RADIUS_PADDING_M := 40.0
const TRAWL_OFFSHORE_M := 900.0

static var _graph_initialized: bool = false
static var _nodes: Array = []
static var _adj: Dictionary = {}


static func build_waypoints(
	from_port_id: String,
	to_port_id: String,
	loop_home: bool,
) -> Array:
	if loop_home:
		return _loop_home_waypoints(from_port_id)
	if from_port_id.is_empty() or to_port_id.is_empty():
		return []
	if from_port_id == to_port_id:
		return _loop_home_waypoints(from_port_id)
	return _port_to_port_waypoints(from_port_id, to_port_id)


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


static func _loop_home_waypoints(port_id: String) -> Array:
	var berth_pos := _berth_pos(port_id, 0)
	if not _vec3_is_valid(berth_pos):
		return []
	var offshore := _fishing_offshore(port_id, berth_pos)
	var pts: Array = []
	var depart_kind := BerthApproachLanes.best_departure_lane_kind(berth_pos, offshore, port_id)
	var approach_kind := BerthApproachLanes.best_approach_lane_kind(berth_pos, offshore, port_id)
	_append_lane_chain(pts, BerthApproachLanes.get_lane(port_id, 0, depart_kind))
	if _vec3_is_valid(offshore):
		_append_unique(pts, offshore)
	_append_lane_chain(pts, _reverse_lane(BerthApproachLanes.get_lane(port_id, 0, approach_kind)))
	_force_terminal(pts, berth_pos)
	return pts


static func _port_to_port_waypoints(from_port_id: String, to_port_id: String) -> Array:
	var from_berth := _berth_pos(from_port_id, 0)
	var to_berth := _berth_pos(to_port_id, 0)
	if not _vec3_is_valid(from_berth) or not _vec3_is_valid(to_berth):
		return []

	var path := _find_shortest_path(from_port_id, to_port_id)
	if path.is_empty():
		var pts: Array = []
		var depart_kind := BerthApproachLanes.best_departure_lane_kind(from_berth, to_berth, from_port_id)
		var approach_kind := BerthApproachLanes.best_approach_lane_kind(to_berth, from_berth, to_port_id)
		var depart_lane := BerthApproachLanes.get_lane(from_port_id, 0, depart_kind)
		var approach_lane := BerthApproachLanes.get_lane(to_port_id, 0, approach_kind)
		_append_lane_chain(pts, depart_lane)
		var open_start := BerthApproachLanes.lane_outer_point(from_port_id, 0, depart_kind)
		if pts.size() > 0:
			open_start = pts[pts.size() - 1] as Vector3
		var open_end := BerthApproachLanes.lane_outer_point(to_port_id, 0, approach_kind)
		if approach_lane.size() >= 2:
			open_end = approach_lane[approach_lane.size() - 1] as Vector3
		var ignore_centers: Array[Vector2] = []
		if not from_port_id.is_empty():
			ignore_centers.append(_port_island_center(from_port_id))
		if not to_port_id.is_empty():
			ignore_centers.append(_port_island_center(to_port_id))
		_append_open_water(pts, open_start, open_end, ignore_centers)
		_append_lane_chain(pts, _reverse_lane(approach_lane))
		_force_terminal(pts, to_berth)
		return pts

	var pts: Array = []
	
	# 1. Append departure lane
	var start_node: Dictionary = _nodes[path[0]]
	var start_idx: int = int(start_node.node_index)
	var depart_kind := int(BerthApproachLanes.LaneKind.SPINE)
	if start_idx == 3:
		depart_kind = int(BerthApproachLanes.LaneKind.FLANK_PORT)
	elif start_idx == 5:
		depart_kind = int(BerthApproachLanes.LaneKind.FLANK_STARBOARD)
		
	var depart_lane := BerthApproachLanes.get_lane(from_port_id, 0, depart_kind)
	_append_lane_chain(pts, depart_lane)
	
	# 2. Append intermediate open water nodes
	var open_start := BerthApproachLanes.lane_outer_point(from_port_id, 0, depart_kind)
	if pts.size() > 0:
		open_start = pts[pts.size() - 1] as Vector3
		
	var prev_pos := open_start
	for i in range(1, path.size() - 1):
		var node: Dictionary = _nodes[path[i]]
		var next_pos: Vector3 = node.position
		_append_unique(pts, next_pos)
		prev_pos = next_pos
		
	# 3. Append arrival lane (reversed)
	var end_node: Dictionary = _nodes[path[path.size() - 1]]
	var end_idx: int = int(end_node.node_index)
	var approach_kind := int(BerthApproachLanes.LaneKind.SPINE)
	if end_idx == 3:
		approach_kind = int(BerthApproachLanes.LaneKind.FLANK_PORT)
	elif end_idx == 5:
		approach_kind = int(BerthApproachLanes.LaneKind.FLANK_STARBOARD)
		
	var approach_lane := BerthApproachLanes.get_lane(to_port_id, 0, approach_kind)
	_append_lane_chain(pts, _reverse_lane(approach_lane))
	
	_force_terminal(pts, to_berth)
	return pts


static func _departure_lane(
	port_id: String,
	berth_index: int,
	berth_pos: Vector3,
	target_pos: Vector3,
) -> Array:
	if not BerthApproachLanes.is_initialized():
		return [berth_pos]
	var kind := BerthApproachLanes.best_departure_lane_kind(berth_pos, target_pos, port_id)
	return BerthApproachLanes.get_lane(port_id, berth_index, kind)


static func _approach_lane(
	port_id: String,
	berth_index: int,
	berth_pos: Vector3,
	from_pos: Vector3,
) -> Array:
	if not BerthApproachLanes.is_initialized():
		return [berth_pos]
	var kind := BerthApproachLanes.best_approach_lane_kind(berth_pos, from_pos, port_id)
	return BerthApproachLanes.get_lane(port_id, berth_index, kind)


static func _fishing_offshore(port_id: String, berth_pos: Vector3) -> Vector3:
	if BerthApproachLanes.is_initialized():
		return BerthApproachLanes.lane_outer_point(port_id, 0, int(BerthApproachLanes.LaneKind.SPINE))
	var seaward := _registry_seaward(port_id)
	return berth_pos + seaward * TRAWL_OFFSHORE_M


static func _registry_seaward(port_id: String) -> Vector3:
	var reg: Node = Engine.get_main_loop().root.get_node_or_null("/root/ContractRegistry")
	if reg == null or not reg.has_method("get_port_info"):
		return Vector3(0.0, 0.0, -1.0)
	var info: Dictionary = reg.call("get_port_info", port_id) as Dictionary
	var ry := float(info.get("rotation_y", 0.0))
	var dir := Vector3(-sin(ry), 0.0, -cos(ry))
	if dir.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, -1.0)
	return dir.normalized()


static func _berth_pos(port_id: String, berth_index: int) -> Vector3:
	if BerthApproachLanes.is_initialized():
		var pos := BerthApproachLanes.berth_world_position(port_id, berth_index)
		if _vec3_is_valid(pos) and pos != Vector3.ZERO:
			return pos
	return _registry_pos(port_id)


static func _registry_pos(port_id: String) -> Vector3:
	var reg: Node = Engine.get_main_loop().root.get_node_or_null("/root/ContractRegistry")
	if reg == null:
		return Vector3.ZERO
	if reg.has_method("get_port_spawn_position"):
		var pos := reg.call("get_port_spawn_position", port_id) as Vector3
		if _vec3_is_valid(pos) and pos != Vector3(INF, INF, INF):
			return pos
	if reg.has_method("get_port_position"):
		return reg.call("get_port_position", port_id) as Vector3
	return Vector3.ZERO


static func _append_lane_chain(pts: Array, lane: Array) -> void:
	for p_raw in lane:
		if p_raw is Vector3:
			_append_unique(pts, p_raw as Vector3)


static func _reverse_lane(lane: Array) -> Array:
	var out: Array = []
	for i in range(lane.size() - 1, -1, -1):
		out.append(lane[i])
	return out


static func _append_open_water(pts: Array, start: Vector3, end: Vector3, ignore_centers: Array[Vector2] = []) -> void:
	if not _vec3_is_valid(start) or not _vec3_is_valid(end):
		return
	for p in _open_water_connector(start, end, ignore_centers):
		_append_unique(pts, p)


static func _open_water_connector(start: Vector3, end: Vector3, ignore_centers: Array[Vector2] = []) -> Array:
	if _horiz_dist(start, end) <= 1.0:
		return []
	if not _connector_blocked(start, end, ignore_centers):
		return [end]

	var blocker := _primary_blocker(start, end, ignore_centers)
	if blocker.is_empty():
		return [end]

	var arc := _single_arc_detour(blocker, start, end)
	if arc.is_empty():
		return [end]
	var out: Array = []
	for p in arc:
		out.append(p)
	if _horiz_dist(out[out.size() - 1], end) > 1.0:
		out.append(end)
	return out


static func _connector_blocked(a: Vector3, b: Vector3, ignore_centers: Array[Vector2] = []) -> bool:
	if not LandField.is_initialized():
		return false

	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var max_clearance := maxf(OPEN_CONNECT_CLEARANCE_M, 0.0)
	var active_indices := LandField.get_active_island_indices_for_segment(a2, b2, max_clearance)

	if active_indices.is_empty():
		return false  # Safe: no islands are near this segment at all

	# Build clearance-island list once so the sampling loop below can decide
	# pierce-vs-clearance in a single segment walk.
	var clearance_indices: Array[int] = []
	for idx in active_indices:
		if not LandField.is_island_ignored(idx, ignore_centers):
			clearance_indices.append(idx)

	var steps := _get_sample_count(a, b)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		if LandField.distance_to_land_filter(p, active_indices) < 0.0:
			return true
		if not clearance_indices.is_empty():
			if LandField.distance_to_land_filter(p, clearance_indices) < OPEN_CONNECT_CLEARANCE_M:
				return true
	return false


static func _get_sample_count(a: Vector3, b: Vector3) -> int:
	var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	return clampi(int(ceil(d / 12.0)), 32, 256)


static func _segment_pierces_land_filtered(a: Vector3, b: Vector3, active_indices: Array[int]) -> bool:
	var steps := _get_sample_count(a, b)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		if LandField.distance_to_land_filter(p, active_indices) < 0.0:
			return true
	return false


static func _segment_violates_clearance_filtered(a: Vector3, b: Vector3, clearance: float, clearance_indices: Array[int]) -> bool:
	var steps := _get_sample_count(a, b)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		if LandField.distance_to_land_filter(p, clearance_indices) < clearance:
			return true
	return false


static func _primary_blocker(a: Vector3, b: Vector3, ignore_centers: Array[Vector2] = []) -> Dictionary:
	if not LandField.is_initialized():
		return {}

	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var max_clearance := maxf(OPEN_CONNECT_CLEARANCE_M, 0.0)
	var active_indices := LandField.get_active_island_indices_for_segment(a2, b2, max_clearance)

	if active_indices.is_empty():
		return {}

	var worst := INF
	var worst_p := Vector2.ZERO
	var steps := _get_sample_count(a, b)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var d := LandField.distance_to_land_filter(p, active_indices)
		if d < worst:
			worst = d
			worst_p = Vector2(p.x, p.z)
	if worst >= OPEN_CONNECT_CLEARANCE_M:
		return {}

	for idx in active_indices:
		var disk := LandField.get_island_disk(idx)
		if disk.is_empty():
			continue
		var center: Vector2 = disk.get("center", Vector2.ZERO)
		var radius: float = float(disk.get("radius", 0.0))
		var is_ignored := false
		for ic in ignore_centers:
			if center.distance_to(ic) < 10.0:
				is_ignored = true
				break
		if is_ignored:
			if worst_p.distance_to(center) <= radius:
				return disk
			continue
		if worst_p.distance_to(center) <= radius + OPEN_CONNECT_CLEARANCE_M:
			return disk
	return {}


static func _routing_radius(island_radius: float) -> float:
	return island_radius + OPEN_CONNECT_CLEARANCE_M + ROUTING_RADIUS_PADDING_M


static func _single_arc_detour(blocker: Dictionary, a: Vector3, b: Vector3) -> Array:
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
	var steps := clampi(int(ceil(absf(delta) / ARC_STEP_RAD)), 2, 6)
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


static func _port_island_center(port_id: String) -> Vector2:
	if BerthApproachLanes.is_initialized():
		var meta := BerthApproachLanes.get_island_meta(port_id)
		if not meta.is_empty():
			var center_v: Vector3 = meta.get("center", Vector3.ZERO)
			return Vector2(center_v.x, center_v.z)
	var pos := _berth_pos(port_id, 0)
	return Vector2(pos.x, pos.z)


static func invalidate_graph() -> void:
	_graph_initialized = false


static func _get_roundabout_local_node(idx: int, half_x: float, half_z: float) -> Vector3:
	var margin_x := 90.0
	match idx:
		0: return Vector3(0.0, WaveSurface.WATER_LEVEL, -half_z - 120.0)
		1: return Vector3(half_x + margin_x, WaveSurface.WATER_LEVEL, -half_z - 50.0)
		2: return Vector3(half_x + margin_x, WaveSurface.WATER_LEVEL, 70.0)
		3: return Vector3(half_x + margin_x, WaveSurface.WATER_LEVEL, half_z + 105.0)
		4: return Vector3(0.0, WaveSurface.WATER_LEVEL, half_z + 190.0)
		5: return Vector3(-half_x - margin_x, WaveSurface.WATER_LEVEL, half_z + 105.0)
		6: return Vector3(-half_x - margin_x, WaveSurface.WATER_LEVEL, 70.0)
		7: return Vector3(-half_x - margin_x, WaveSurface.WATER_LEVEL, -half_z - 50.0)
	return Vector3.ZERO


static func _roundabout_node_world(port_id: String, idx: int) -> Vector3:
	if not BerthApproachLanes.is_initialized():
		return Vector3.ZERO
	var meta := BerthApproachLanes.get_island_meta(port_id)
	if meta.is_empty():
		return Vector3.ZERO
	var half_x: float = meta.get("half_x", 0.0)
	var half_z: float = meta.get("half_z", 0.0)
	var local := _get_roundabout_local_node(idx, half_x, half_z)
	var center: Vector3 = meta.get("center", Vector3.ZERO)
	var ry: float = meta.get("rotation_y", 0.0)
	var basis := Basis.from_euler(Vector3(0.0, ry, 0.0))
	var world := center + basis * local
	world.y = WaveSurface.WATER_LEVEL
	return world


static func _get_node_index(port_id: String, node_index: int) -> int:
	for i in range(_nodes.size()):
		var n: Dictionary = _nodes[i]
		if n.port_id == port_id and int(n.node_index) == node_index:
			return i
	return -1


static func rebuild_navigation_graph() -> void:
	_nodes.clear()
	_adj.clear()
	
	if not BerthApproachLanes.is_initialized():
		return
		
	# 1. Collect all 8 nodes for every island
	var port_ids = BerthApproachLanes._lanes.keys()
	for port_id in port_ids:
		for idx in range(8):
			var pos := _roundabout_node_world(port_id, idx)
			if pos != Vector3.ZERO:
				_nodes.append({
					"port_id": port_id,
					"node_index": idx,
					"position": pos
				})
				
	var n := _nodes.size()
	for i in range(n):
		_adj[i] = []
		
	# 2. Add roundabout loop edges for each port
	for port_id in port_ids:
		for idx in range(8):
			var u := _get_node_index(port_id, idx)
			var v := _get_node_index(port_id, (idx + 1) % 8)
			if u != -1 and v != -1:
				_adj[u].append(v)
				_adj[v].append(u)
				
	# 3. Add open-water edges between different islands
	for i in range(n):
		var node_a: Dictionary = _nodes[i]
		var port_id_a: String = node_a.port_id
		for j in range(i + 1, n):
			var node_b: Dictionary = _nodes[j]
			var port_id_b: String = node_b.port_id
			if port_id_a == port_id_b:
				continue
				
			var d := _horiz_dist(node_a.position, node_b.position)
			if d >= 4000.0:
				continue
				
			if not _connector_blocked(node_a.position, node_b.position, []):
				_adj[i].append(j)
				_adj[j].append(i)
				
	_graph_initialized = true
	print("[AutonomousTransitRoute] Rebuilt global roundabout graph: %d nodes, %d edges" % [_nodes.size(), _total_edges()])


static func _total_edges() -> int:
	var total: int = 0
	for u in _adj.keys():
		var neighbors: Array = _adj[u]
		total += neighbors.size()
	return total / 2


static func _find_shortest_path(from_port_id: String, to_port_id: String) -> Array:
	if not _graph_initialized:
		rebuild_navigation_graph()
	if _nodes.is_empty():
		return []
		
	var start_indices: Array[int] = []
	var end_indices: Array[int] = []
	
	# Start nodes are Node 0, Node 3, Node 5 of start port
	for node_idx in [0, 3, 5]:
		var idx := _get_node_index(from_port_id, node_idx)
		if idx != -1:
			start_indices.append(idx)
			
	# End nodes are Node 0, Node 3, Node 5 of end port
	for node_idx in [0, 3, 5]:
		var idx := _get_node_index(to_port_id, node_idx)
		if idx != -1:
			end_indices.append(idx)
			
	if start_indices.is_empty() or end_indices.is_empty():
		return []
		
	var dist: Dictionary = {}
	var parent: Dictionary = {}
	var visited: Dictionary = {}
	var pq: Array = []
	
	for idx in start_indices:
		var n: Dictionary = _nodes[idx]
		var kind := int(BerthApproachLanes.LaneKind.SPINE)
		if int(n.node_index) == 3:
			kind = int(BerthApproachLanes.LaneKind.FLANK_PORT)
		elif int(n.node_index) == 5:
			kind = int(BerthApproachLanes.LaneKind.FLANK_STARBOARD)
			
		var lane_len := polyline_length(BerthApproachLanes.get_lane(from_port_id, 0, kind))
		dist[idx] = lane_len
		parent[idx] = -1
		pq.append([lane_len, idx])
		
	while not pq.is_empty():
		# Linear-scan min instead of full sort-per-iteration. With ~64 nodes the
		# pq stays tiny; a sort_custom + lambda alloc per iteration was the bulk
		# of Dijkstra cost per ship.
		var best_i := 0
		var best_d: float = pq[0][0]
		for k in range(1, pq.size()):
			if pq[k][0] < best_d:
				best_d = pq[k][0]
				best_i = k
		var current = pq[best_i]
		pq.remove_at(best_i)
		var d: float = current[0]
		var u: int = current[1]

		if visited.has(u):
			continue
		visited[u] = true
		
		var neighbors: Array = _adj.get(u, [])
		for v in neighbors:
			var node_u: Dictionary = _nodes[u]
			var node_v: Dictionary = _nodes[v]
			var weight := _horiz_dist(node_u.position, node_v.position)
			var new_dist := d + weight
			if not dist.has(v) or new_dist < dist[v]:
				dist[v] = new_dist
				parent[v] = u
				pq.append([new_dist, v])
				
	var best_end_idx := -1
	var min_total_dist := INF
	
	for idx in end_indices:
		if dist.has(idx):
			var n: Dictionary = _nodes[idx]
			var kind := int(BerthApproachLanes.LaneKind.SPINE)
			if int(n.node_index) == 3:
				kind = int(BerthApproachLanes.LaneKind.FLANK_PORT)
			elif int(n.node_index) == 5:
				kind = int(BerthApproachLanes.LaneKind.FLANK_STARBOARD)
				
			var arr_len := polyline_length(BerthApproachLanes.get_lane(to_port_id, 0, kind))
			var total: float = float(dist[idx]) + arr_len
			if total < min_total_dist:
				min_total_dist = total
				best_end_idx = idx
				
	if best_end_idx == -1:
		return []
		
	var path: Array[int] = []
	var curr := best_end_idx
	while curr != -1:
		path.append(curr)
		curr = parent.get(curr, -1)
	path.reverse()
	
	return path
