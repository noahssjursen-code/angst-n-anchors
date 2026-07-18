class_name MarineRoutePlan
extends RefCounted

## Serializable deterministic voyage route. World identity + algorithm version
## let MP clients verify that reconstructing the route locally is safe.

const ALGORITHM_VERSION := 3

var route_id := ""
var layout_checksum := ""
var algorithm_version := ALGORITHM_VERSION
var origin_port_id := ""
var destination_port_id := ""
var waypoints := PackedVector2Array()
var cumulative_distance_m := PackedFloat32Array()
var departure_handoff_xz := Vector2(INF, INF)
var arrival_handoff_xz := Vector2(INF, INF)
var departure_handoff_m := -1.0
var arrival_handoff_m := -1.0


static func create(
	points: PackedVector2Array,
	checksum: String,
	origin_id: String = "",
	destination_id: String = "",
) -> MarineRoutePlan:
	var plan := MarineRoutePlan.new()
	plan.layout_checksum = checksum
	plan.origin_port_id = origin_id
	plan.destination_port_id = destination_id
	plan.waypoints = points.duplicate()
	plan._rebuild_distances()
	plan.route_id = plan._make_route_id()
	return plan


func is_valid() -> bool:
	return waypoints.size() >= 2 \
		and cumulative_distance_m.size() == waypoints.size() \
		and total_distance_m() > 1.0


func total_distance_m() -> float:
	return cumulative_distance_m[-1] if not cumulative_distance_m.is_empty() else 0.0


func set_handoffs(departure_xz: Vector2, arrival_xz: Vector2 = Vector2(INF, INF)) -> void:
	departure_handoff_xz = departure_xz
	arrival_handoff_xz = arrival_xz
	departure_handoff_m = nearest_progress_m(departure_xz) if departure_xz.is_finite() else -1.0
	arrival_handoff_m = nearest_progress_m(arrival_xz, departure_handoff_m) \
		if arrival_xz.is_finite() else -1.0
	route_id = _make_route_id()


func has_berth_handoffs() -> bool:
	return departure_handoff_xz.is_finite() and arrival_handoff_xz.is_finite() \
		and departure_handoff_m >= 0.0 and arrival_handoff_m >= departure_handoff_m


func point_at_distance(distance_m: float) -> Vector2:
	if waypoints.is_empty():
		return Vector2(INF, INF)
	var target := clampf(distance_m, 0.0, total_distance_m())
	var index := _segment_end_index(target)
	var span := float(cumulative_distance_m[index] - cumulative_distance_m[index - 1])
	var t := 0.0 if span <= 0.001 else (target - cumulative_distance_m[index - 1]) / span
	return waypoints[index - 1].lerp(waypoints[index], t)


func direction_at_distance(distance_m: float, sample_span_m: float = 20.0) -> Vector2:
	if not is_valid():
		return Vector2.ZERO
	var span := maxf(sample_span_m, 1.0)
	var before := point_at_distance(maxf(distance_m - span * 0.5, 0.0))
	var after := point_at_distance(minf(distance_m + span * 0.5, total_distance_m()))
	var direction := after - before
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector2.ZERO


func nearest_progress_m(
		position: Vector2,
		hint_progress_m: float = 0.0,
		local_search_radius_m: float = INF,
) -> float:
	if waypoints.size() < 2:
		return 0.0
	var best_progress := clampf(hint_progress_m, 0.0, total_distance_m())
	var best_distance_sq := INF
	var first_segment := 0
	var last_segment_exclusive := waypoints.size() - 1
	if is_finite(local_search_radius_m):
		var radius := maxf(local_search_radius_m, 50.0)
		first_segment = maxi(_segment_end_index(maxf(best_progress - radius, 0.0)) - 1, 0)
		last_segment_exclusive = mini(
			_segment_end_index(minf(best_progress + radius, total_distance_m())) + 1,
			waypoints.size() - 1,
		)
	for i in range(first_segment, last_segment_exclusive):
		var segment_start := float(cumulative_distance_m[i])
		var segment_end := float(cumulative_distance_m[i + 1])
		## Once underway, do not snap far backward onto a nearby parallel leg.
		if segment_end + 250.0 < hint_progress_m:
			continue
		var a := waypoints[i]
		var b := waypoints[i + 1]
		var delta := b - a
		var t := 0.0 if delta.length_squared() <= 0.001 \
			else clampf((position - a).dot(delta) / delta.length_squared(), 0.0, 1.0)
		var projected := a + delta * t
		var distance_sq := position.distance_squared_to(projected)
		if distance_sq >= best_distance_sq:
			continue
		best_distance_sq = distance_sq
		best_progress = lerpf(segment_start, segment_end, t)
	return best_progress


func _segment_end_index(distance_m: float) -> int:
	if cumulative_distance_m.size() < 2:
		return 0
	var target := clampf(distance_m, 0.0, total_distance_m())
	var low := 1
	var high := cumulative_distance_m.size() - 1
	while low < high:
		var middle := (low + high) >> 1
		if float(cumulative_distance_m[middle]) < target:
			low = middle + 1
		else:
			high = middle
	return low


func to_dict(include_waypoints: bool = true) -> Dictionary:
	var out := {
		"route_id": route_id,
		"layout_checksum": layout_checksum,
		"algorithm_version": algorithm_version,
		"origin_port_id": origin_port_id,
		"destination_port_id": destination_port_id,
		"total_distance_m": total_distance_m(),
		## Endpoints are always included in the compact authority payload. A
		## client can rebuild the same route locally without receiving every
		## waypoint, then verify the resulting route_id before displaying it.
		"start_point": waypoints[0] if not waypoints.is_empty() else Vector2.ZERO,
		"end_point": waypoints[-1] if not waypoints.is_empty() else Vector2.ZERO,
		"departure_handoff_xz": departure_handoff_xz,
		"arrival_handoff_xz": arrival_handoff_xz,
	}
	if include_waypoints:
		out["waypoints"] = Array(waypoints)
	return out


static func from_dict(data: Dictionary) -> MarineRoutePlan:
	var points := PackedVector2Array()
	for raw in data.get("waypoints", []) as Array:
		if raw is Vector2:
			points.append(raw)
	var plan := create(
		points,
		str(data.get("layout_checksum", "")),
		str(data.get("origin_port_id", "")),
		str(data.get("destination_port_id", "")),
	)
	plan.algorithm_version = int(data.get("algorithm_version", ALGORITHM_VERSION))
	var departure := data.get("departure_handoff_xz", Vector2(INF, INF)) as Vector2
	var arrival := data.get("arrival_handoff_xz", Vector2(INF, INF)) as Vector2
	if departure.is_finite() or arrival.is_finite():
		plan.set_handoffs(departure, arrival)
	var supplied_id := str(data.get("route_id", ""))
	if not supplied_id.is_empty():
		plan.route_id = supplied_id
	return plan


func _rebuild_distances() -> void:
	cumulative_distance_m.clear()
	if waypoints.is_empty():
		return
	cumulative_distance_m.append(0.0)
	var distance := 0.0
	for i in range(1, waypoints.size()):
		distance += waypoints[i - 1].distance_to(waypoints[i])
		cumulative_distance_m.append(distance)


func _make_route_id() -> String:
	var identity := "%s|%d|%s|%s" % [
		layout_checksum,
		algorithm_version,
		origin_port_id,
		destination_port_id,
	]
	for point in waypoints:
		identity += "|%d,%d" % [roundi(point.x), roundi(point.y)]
	if departure_handoff_xz.is_finite():
		identity += "|D%d,%d" % [roundi(departure_handoff_xz.x), roundi(departure_handoff_xz.y)]
	if arrival_handoff_xz.is_finite():
		identity += "|A%d,%d" % [roundi(arrival_handoff_xz.x), roundi(arrival_handoff_xz.y)]
	return "%08x" % (identity.hash() & 0xffffffff)
