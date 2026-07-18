class_name MarineRoutePlan
extends RefCounted

## Serializable deterministic voyage route. World identity + algorithm version
## let MP clients verify that reconstructing the route locally is safe.

const ALGORITHM_VERSION := 1

var route_id := ""
var layout_checksum := ""
var algorithm_version := ALGORITHM_VERSION
var origin_port_id := ""
var destination_port_id := ""
var waypoints := PackedVector2Array()
var cumulative_distance_m := PackedFloat32Array()


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


func point_at_distance(distance_m: float) -> Vector2:
	if waypoints.is_empty():
		return Vector2(INF, INF)
	var target := clampf(distance_m, 0.0, total_distance_m())
	for i in range(1, cumulative_distance_m.size()):
		if cumulative_distance_m[i] < target:
			continue
		var span := float(cumulative_distance_m[i] - cumulative_distance_m[i - 1])
		var t := 0.0 if span <= 0.001 else (target - cumulative_distance_m[i - 1]) / span
		return waypoints[i - 1].lerp(waypoints[i], t)
	return waypoints[-1]


func nearest_progress_m(position: Vector2, hint_progress_m: float = 0.0) -> float:
	if waypoints.size() < 2:
		return 0.0
	var best_progress := clampf(hint_progress_m, 0.0, total_distance_m())
	var best_distance_sq := INF
	for i in range(waypoints.size() - 1):
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
	return "%08x" % (identity.hash() & 0xffffffff)
