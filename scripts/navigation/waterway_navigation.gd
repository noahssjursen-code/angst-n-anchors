class_name WaterwayNavigation
extends RefCounted

## Deterministic routing over WorldLayout waterway polylines. Query points are
## attached to their nearest segment, so callers do not need port-placement APIs.

const UNREACHABLE_DISTANCE := INF
const EPSILON := 0.001

var layout_checksum := ""
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
