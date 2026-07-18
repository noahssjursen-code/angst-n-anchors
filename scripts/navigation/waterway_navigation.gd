class_name WaterwayNavigation
extends RefCounted

## Deterministic routing over WorldLayout waterway polylines. Query points are
## attached to their nearest segment, so callers do not need port-placement APIs.

const UNREACHABLE_DISTANCE := INF
const EPSILON := 0.001
const ROUTE_PROBE_STEP_M := 60.0
const ROUTE_SHORE_CLEARANCE_M := 12.0

var layout_checksum := ""
var _layout: Variant
var _sea_grid: AStarGrid2D
var _waterways: Array[Dictionary] = []
var _nodes: Array[Vector2] = []
var _adjacency: Array = []
var _indices_by_id: Dictionary = {}
var _trunk_mouth_nodes := PackedInt32Array()


func _init(layout: Variant = null) -> void:
	if layout != null:
		rebuild(layout)


func rebuild(layout: Variant) -> void:
	clear()
	if layout == null:
		return
	_layout = layout
	layout_checksum = str(layout.get("layout_checksum"))
	var source: Array = layout.get("waterway_centerlines")
	for raw in source:
		if not raw is Dictionary:
			continue
		var waterway := (raw as Dictionary).duplicate(true)
		var points := _points_from(waterway.get("points", PackedVector2Array()))
		if points.size() < 2:
			continue
		waterway["points"] = points
		_waterways.append(waterway)
		var indices := PackedInt32Array()
		for point in points:
			indices.append(_add_node(point))
		for i in range(indices.size() - 1):
			_connect(indices[i], indices[i + 1], points[i].distance_to(points[i + 1]))
		var id := str(waterway.get("id", "waterway_%d" % (_waterways.size() - 1)))
		_indices_by_id[id] = indices
		if str(waterway.get("kind", "")) == "trunk":
			_trunk_mouth_nodes.append(indices[0])
	_connect_declared_waterways()
	_connect_open_ocean()


func clear() -> void:
	layout_checksum = ""
	_layout = null
	_sea_grid = null
	_waterways.clear()
	_nodes.clear()
	_adjacency.clear()
	_indices_by_id.clear()
	_trunk_mouth_nodes.clear()


func is_empty() -> bool:
	return _waterways.is_empty()


func waterway_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for waterway in _waterways:
		result.append(str(waterway.get("id", "")))
	return result


## Returns the closest point on any centerline and enough graph information for
## routing. The access distance lets callers enforce their own navigability limit.
func nearest_waterway(world_xz: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance_squared := INF
	for waterway in _waterways:
		var id := str(waterway.get("id", ""))
		var points: PackedVector2Array = waterway["points"]
		var indices: PackedInt32Array = _indices_by_id.get(id, PackedInt32Array())
		if indices.size() != points.size():
			continue
		for segment_index in range(points.size() - 1):
			var projection := _project_to_segment(world_xz, points[segment_index], points[segment_index + 1])
			var closest: Vector2 = projection["point"]
			var distance_squared := world_xz.distance_squared_to(closest)
			if distance_squared >= best_distance_squared:
				continue
			var segment_length := points[segment_index].distance_to(points[segment_index + 1])
			var t := float(projection["t"])
			best_distance_squared = distance_squared
			best = {
				"waterway_id": id,
				"kind": str(waterway.get("kind", "")),
				"segment_index": segment_index,
				"point": closest,
				"distance": sqrt(distance_squared),
				"node_a": indices[segment_index],
				"node_b": indices[segment_index + 1],
				"distance_to_a": segment_length * t,
				"distance_to_b": segment_length * (1.0 - t),
				"segment_length": segment_length,
				"segment_t": t,
			}
	return best


## Distance includes each endpoint's straight connection to its nearest
## centerline, travel along centerlines, and straight travel between ocean mouths.
func route_distance(from_xz: Vector2, to_xz: Vector2, max_access_distance: float = INF) -> float:
	var start := nearest_waterway(from_xz)
	var finish := nearest_waterway(to_xz)
	if start.is_empty() or finish.is_empty():
		return UNREACHABLE_DISTANCE
	if float(start["distance"]) > max_access_distance or float(finish["distance"]) > max_access_distance:
		return UNREACHABLE_DISTANCE
	var distances := _distances_from_projection(start)
	var result := _distance_to_projection(distances, finish)
	if str(start["waterway_id"]) == str(finish["waterway_id"]) \
			and int(start["segment_index"]) == int(finish["segment_index"]):
		var direct := absf(float(start["segment_t"]) - float(finish["segment_t"])) \
			* float(start["segment_length"])
		result = minf(result, direct)
	return float(start["distance"]) + result + float(finish["distance"])


## Returns the same shortest route as route_distance(), expressed as world-XZ
## waypoints for charting and autopilot consumers. The graph is intentionally
## coarse: solving it is cheap and the returned line follows generated water.
func route_points(from_xz: Vector2, to_xz: Vector2, max_access_distance: float = INF) -> PackedVector2Array:
	var start := nearest_waterway(from_xz)
	var finish := nearest_waterway(to_xz)
	if start.is_empty() or finish.is_empty():
		return PackedVector2Array()
	if float(start["distance"]) > max_access_distance or float(finish["distance"]) > max_access_distance:
		return PackedVector2Array()
	var sea_route := _sea_grid_route(from_xz, to_xz, start, finish)
	if sea_route.size() >= 2:
		return _smooth_water_route(sea_route)
	var route := PackedVector2Array([from_xz, start["point"]])
	if str(start["waterway_id"]) == str(finish["waterway_id"]) \
			and int(start["segment_index"]) == int(finish["segment_index"]):
		_append_distinct(route, finish["point"])
		_append_distinct(route, to_xz)
		return route
	var node_path := _shortest_node_path(start, finish)
	if node_path.is_empty():
		return PackedVector2Array()
	for node_index in node_path:
		_append_distinct(route, _nodes[node_index])
	_append_distinct(route, finish["point"])
	_append_distinct(route, to_xz)
	return _smooth_water_route(route)


## The centerline graph describes generated fjord topology, but its open-ocean
## mouths all meet at the map edge. A coarse grid over WorldLayout's existing
## 257x257 SDF finds the geographically shortest passage around headlands. It is
## built lazily once per layout; chart callers cache each resulting route.
func _sea_grid_route(
	from_xz: Vector2,
	to_xz: Vector2,
	start: Dictionary,
	finish: Dictionary,
) -> PackedVector2Array:
	_ensure_sea_grid()
	if _sea_grid == null:
		return PackedVector2Array()
	var start_id := _nearest_open_grid_id(_world_to_grid(from_xz))
	var finish_id := _nearest_open_grid_id(_world_to_grid(to_xz))
	if start_id.x < 0 or finish_id.x < 0:
		return PackedVector2Array()
	var ids: Array[Vector2i] = _sea_grid.get_id_path(start_id, finish_id)
	if ids.is_empty():
		return PackedVector2Array()
	var route := PackedVector2Array([from_xz])
	for id in ids:
		_append_distinct(route, _grid_to_world(id))
	_append_distinct(route, to_xz)
	return route


func _ensure_sea_grid() -> void:
	if _sea_grid != null or _layout == null:
		return
	var resolution := int(_layout.get("raster_resolution"))
	var cell_size := float(_layout.get("cell_size_m"))
	if resolution < 2 or cell_size <= 0.0:
		return
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, resolution, resolution)
	grid.cell_size = Vector2(cell_size, cell_size)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var signed_distances: PackedFloat32Array = _layout.call("get_signed_distance_raster")
	for z in range(resolution):
		for x in range(resolution):
			if signed_distances[z * resolution + x] < ROUTE_SHORE_CLEARANCE_M:
				grid.set_point_solid(Vector2i(x, z), true)
	_sea_grid = grid


func _world_to_grid(point: Vector2) -> Vector2i:
	var half := float(_layout.get("half_extent_m"))
	var cell := float(_layout.get("cell_size_m"))
	var last := int(_layout.get("raster_resolution")) - 1
	return Vector2i(
		clampi(roundi((point.x + half) / cell), 0, last),
		clampi(roundi((point.y + half) / cell), 0, last),
	)


func _grid_to_world(id: Vector2i) -> Vector2:
	var half := float(_layout.get("half_extent_m"))
	var cell := float(_layout.get("cell_size_m"))
	return Vector2(float(id.x) * cell - half, float(id.y) * cell - half)


func _nearest_open_grid_id(center: Vector2i) -> Vector2i:
	if not _sea_grid.is_point_solid(center):
		return center
	for radius in range(1, 9):
		for z in range(center.y - radius, center.y + radius + 1):
			for x in range(center.x - radius, center.x + radius + 1):
				if x != center.x - radius and x != center.x + radius \
						and z != center.y - radius and z != center.y + radius:
					continue
				var id := Vector2i(x, z)
				if _sea_grid.is_in_boundsv(id) and not _sea_grid.is_point_solid(id):
					return id
	return Vector2i(-1, -1)


func are_reachable(from_xz: Vector2, to_xz: Vector2, max_access_distance: float = INF) -> bool:
	return is_finite(route_distance(from_xz, to_xz, max_access_distance))


func route_distance_to_open_ocean(world_xz: Vector2, max_access_distance: float = INF) -> float:
	var connection := nearest_waterway(world_xz)
	if connection.is_empty() or float(connection["distance"]) > max_access_distance:
		return UNREACHABLE_DISTANCE
	var distances := _distances_from_projection(connection)
	var best := INF
	for node_index in _trunk_mouth_nodes:
		best = minf(best, float(distances[node_index]))
	return float(connection["distance"]) + best


func is_open_ocean_reachable(world_xz: Vector2, max_access_distance: float = INF) -> bool:
	return is_finite(route_distance_to_open_ocean(world_xz, max_access_distance))


func _connect_declared_waterways() -> void:
	for waterway in _waterways:
		var id := str(waterway.get("id", ""))
		var own_indices: PackedInt32Array = _indices_by_id.get(id, PackedInt32Array())
		if own_indices.is_empty():
			continue
		var links := _string_array_from(waterway.get("connects_to", PackedStringArray()))
		for parent_id in links:
			if parent_id == "open_ocean" or not _indices_by_id.has(parent_id):
				continue
			var parent := _waterway_by_id(parent_id)
			if parent.is_empty():
				continue
			var nearest := _nearest_on_waterway(_nodes[own_indices[0]], parent)
			if nearest.is_empty():
				continue
			var gap := _nodes[own_indices[0]].distance_to(nearest["point"])
			_connect(own_indices[0], int(nearest["node_a"]), gap + float(nearest["distance_to_a"]))
			_connect(own_indices[0], int(nearest["node_b"]), gap + float(nearest["distance_to_b"]))


func _connect_open_ocean() -> void:
	# Open water is unobstructed at the western map edge. A complete mouth graph
	# preserves actual straight-line distance instead of using a zero-cost hub.
	for i in range(_trunk_mouth_nodes.size()):
		for j in range(i + 1, _trunk_mouth_nodes.size()):
			var a := _trunk_mouth_nodes[i]
			var b := _trunk_mouth_nodes[j]
			_connect(a, b, _nodes[a].distance_to(_nodes[b]))


func _nearest_on_waterway(point: Vector2, waterway: Dictionary) -> Dictionary:
	var id := str(waterway.get("id", ""))
	var points: PackedVector2Array = waterway["points"]
	var indices: PackedInt32Array = _indices_by_id.get(id, PackedInt32Array())
	var best: Dictionary = {}
	var best_distance_squared := INF
	for segment_index in range(points.size() - 1):
		var projection := _project_to_segment(point, points[segment_index], points[segment_index + 1])
		var closest: Vector2 = projection["point"]
		var distance_squared := point.distance_squared_to(closest)
		if distance_squared >= best_distance_squared:
			continue
		var length := points[segment_index].distance_to(points[segment_index + 1])
		var t := float(projection["t"])
		best_distance_squared = distance_squared
		best = {
			"point": closest,
			"node_a": indices[segment_index],
			"node_b": indices[segment_index + 1],
			"distance_to_a": length * t,
			"distance_to_b": length * (1.0 - t),
		}
	return best


func _distances_from_projection(connection: Dictionary) -> PackedFloat64Array:
	var distances := PackedFloat64Array()
	distances.resize(_nodes.size())
	distances.fill(INF)
	var pending: Array[int] = []
	var node_a := int(connection["node_a"])
	var node_b := int(connection["node_b"])
	distances[node_a] = float(connection["distance_to_a"])
	distances[node_b] = minf(distances[node_b], float(connection["distance_to_b"]))
	pending.append(node_a)
	if node_b != node_a:
		pending.append(node_b)
	while not pending.is_empty():
		var best_pending := 0
		for i in range(1, pending.size()):
			if distances[pending[i]] < distances[pending[best_pending]]:
				best_pending = i
		var current := pending[best_pending]
		pending.remove_at(best_pending)
		var current_distance := distances[current]
		for edge_raw in _adjacency[current]:
			var edge := edge_raw as Dictionary
			var target := int(edge["to"])
			var candidate := current_distance + float(edge["distance"])
			if candidate + EPSILON >= distances[target]:
				continue
			distances[target] = candidate
			if not pending.has(target):
				pending.append(target)
	return distances


func _distance_to_projection(distances: PackedFloat64Array, connection: Dictionary) -> float:
	return minf(
		distances[int(connection["node_a"])] + float(connection["distance_to_a"]),
		distances[int(connection["node_b"])] + float(connection["distance_to_b"])
	)


func _shortest_node_path(start: Dictionary, finish: Dictionary) -> PackedInt32Array:
	var distances := PackedFloat64Array()
	distances.resize(_nodes.size())
	distances.fill(INF)
	var previous := PackedInt32Array()
	previous.resize(_nodes.size())
	previous.fill(-1)
	var pending: Array[int] = []
	for seed in [
		{"node": int(start["node_a"]), "distance": float(start["distance_to_a"])},
		{"node": int(start["node_b"]), "distance": float(start["distance_to_b"])},
	]:
		var node := int(seed["node"])
		if float(seed["distance"]) < distances[node]:
			distances[node] = float(seed["distance"])
		if not pending.has(node):
			pending.append(node)
	while not pending.is_empty():
		var best_pending := 0
		for i in range(1, pending.size()):
			if distances[pending[i]] < distances[pending[best_pending]]:
				best_pending = i
		var current := pending[best_pending]
		pending.remove_at(best_pending)
		for edge_raw in _adjacency[current]:
			var edge := edge_raw as Dictionary
			var target := int(edge["to"])
			var candidate := distances[current] + float(edge["distance"])
			if candidate + EPSILON >= distances[target]:
				continue
			distances[target] = candidate
			previous[target] = current
			if not pending.has(target):
				pending.append(target)
	var target_a := int(finish["node_a"])
	var target_b := int(finish["node_b"])
	var target := target_a
	if distances[target_b] + float(finish["distance_to_b"]) \
			< distances[target_a] + float(finish["distance_to_a"]):
		target = target_b
	if not is_finite(distances[target]):
		return PackedInt32Array()
	var reversed := PackedInt32Array()
	while target >= 0:
		reversed.append(target)
		target = previous[target]
	var result := PackedInt32Array()
	for i in range(reversed.size() - 1, -1, -1):
		result.append(reversed[i])
	return result


static func _append_distinct(points: PackedVector2Array, point: Vector2) -> void:
	if points.is_empty() or not points[-1].is_equal_approx(point):
		points.append(point)


## Greedy string-pulling removes graph-shape detours across open water while
## retaining A* waypoints wherever land actually blocks the direct passage.
## Port-to-centerline access legs are preserved because port anchors may sit on
## the quay rather than in the water raster.
func _smooth_water_route(route: PackedVector2Array) -> PackedVector2Array:
	if route.size() <= 4 or _layout == null or not _layout.has_method("sample_signed_distance"):
		return route
	var result := PackedVector2Array([route[0], route[1]])
	var current := 1
	var final_water_index := route.size() - 2
	while current < final_water_index:
		var furthest := current + 1
		for candidate in range(final_water_index, current, -1):
			if _has_water_line(route[current], route[candidate]):
				furthest = candidate
				break
		_append_distinct(result, route[furthest])
		current = furthest
	_append_distinct(result, route[-1])
	return result


func _has_water_line(a: Vector2, b: Vector2) -> bool:
	var distance := a.distance_to(b)
	var probes := maxi(1, ceili(distance / ROUTE_PROBE_STEP_M))
	## Graph nodes themselves can lie on a narrow channel's raster edge. They are
	## already known-safe; only judge the interior of the proposed shortcut.
	for i in range(1, probes):
		var point := a.lerp(b, float(i) / float(probes))
		if float(_layout.call("sample_signed_distance", point)) < ROUTE_SHORE_CLEARANCE_M:
			return false
	return true


func _add_node(point: Vector2) -> int:
	var index := _nodes.size()
	_nodes.append(point)
	_adjacency.append([])
	return index


func _connect(a: int, b: int, distance: float) -> void:
	if a < 0 or b < 0 or a >= _nodes.size() or b >= _nodes.size():
		return
	_adjacency[a].append({"to": b, "distance": maxf(distance, 0.0)})
	_adjacency[b].append({"to": a, "distance": maxf(distance, 0.0)})


func _waterway_by_id(id: String) -> Dictionary:
	for waterway in _waterways:
		if str(waterway.get("id", "")) == id:
			return waterway
	return {}


static func _project_to_segment(point: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var delta := b - a
	var length_squared := delta.length_squared()
	var t := 0.0 if length_squared <= EPSILON else clampf((point - a).dot(delta) / length_squared, 0.0, 1.0)
	return {"point": a + delta * t, "t": t}


static func _points_from(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return (value as PackedVector2Array).duplicate()
	var result := PackedVector2Array()
	if value is Array:
		for point in value:
			if point is Vector2:
				result.append(point)
	return result


static func _string_array_from(value: Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value
	var result := PackedStringArray()
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
