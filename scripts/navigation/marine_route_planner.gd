class_name MarineRoutePlanner
extends RefCounted

## Shared deterministic route-plan factory for player autopilot, NPC captains,
## server voyage simulation, and chart presentation.

var _layout: WorldLayout
var _navigation: WaterwayNavigation
var _cache: Dictionary = {}
static var _navigation_by_layout: Dictionary = {}


func _init(layout: WorldLayout = null) -> void:
	if layout != null:
		configure(layout)


func configure(layout: WorldLayout) -> void:
	_layout = layout
	_navigation = null
	if layout != null:
		var checksum := str(layout.layout_checksum)
		if _navigation_by_layout.has(checksum):
			_navigation = _navigation_by_layout[checksum] as WaterwayNavigation
		else:
			## Worlds do not coexist in normal play. Bound this process cache so
			## previewing many seeds cannot retain every 257x257 A* grid forever.
			if _navigation_by_layout.size() >= 2:
				_navigation_by_layout.clear()
			_navigation = WaterwayNavigation.new(layout)
			_navigation_by_layout[checksum] = _navigation
	_cache.clear()


func plan(
	from_xz: Vector2,
	to_xz: Vector2,
	origin_port_id: String = "",
	destination_port_id: String = "",
) -> MarineRoutePlan:
	if _layout == null or _navigation == null:
		return MarineRoutePlan.new()
	var key := "%d,%d>%d,%d|%s|%s" % [
		roundi(from_xz.x), roundi(from_xz.y),
		roundi(to_xz.x), roundi(to_xz.y),
		origin_port_id, destination_port_id,
	]
	if _cache.has(key):
		return _cache[key] as MarineRoutePlan
	var points := _navigation.route_points(from_xz, to_xz)
	## Port anchors can be on the quay. Autopilot stops at the final known-water
	## approach point and leaves berthing to the player.
	if points.size() >= 3:
		points.remove_at(points.size() - 1)
	var result := MarineRoutePlan.create(
		points,
		str(_layout.layout_checksum),
		origin_port_id,
		destination_port_id,
	)
	_cache[key] = result
	return result


func plan_departure(
	from_xz: Vector2,
	to_xz: Vector2,
	origin_port_id: String,
	origin_berth_id: String,
	destination_port_id: String = "",
) -> MarineRoutePlan:
	if origin_berth_id.is_empty():
		return plan(from_xz, to_xz, origin_port_id, destination_port_id)
	var berth := BerthApproachLanes.target_world_position(origin_port_id, origin_berth_id)
	if berth.length_squared() <= 0.01:
		return plan(from_xz, to_xz, origin_port_id, destination_port_id)
	var destination := Vector3(to_xz.x, WaveSurface.WATER_LEVEL, to_xz.y)
	var lane_kind := BerthApproachLanes.best_departure_lane_kind(
		berth, destination, origin_port_id
	)
	var lane := BerthApproachLanes.get_target_lane(origin_port_id, origin_berth_id, lane_kind)
	if lane.size() < 2:
		return plan(from_xz, to_xz, origin_port_id, destination_port_id)
	var points := PackedVector2Array()
	for raw_point in lane:
		var point := raw_point as Vector3
		points.append(Vector2(point.x, point.z))
	var passage := plan(points[-1], to_xz, origin_port_id, destination_port_id)
	for point in passage.waypoints:
		if not points[-1].is_equal_approx(point):
			points.append(point)
	return MarineRoutePlan.create(
		points,
		str(_layout.layout_checksum) if _layout != null else "",
		origin_port_id,
		destination_port_id,
	)


func plan_berth_to_berth(
	from_xz: Vector2,
	to_xz: Vector2,
	origin_port_id: String,
	origin_berth_id: String,
	destination_port_id: String,
	destination_berth_id: String,
) -> MarineRoutePlan:
	if _layout == null or _navigation == null or destination_berth_id.is_empty():
		return plan_departure(from_xz, to_xz, origin_port_id, origin_berth_id,
			destination_port_id)
	var departure := BerthApproachLanes.get_target_lane(
		origin_port_id, origin_berth_id, BerthApproachLanes.LaneKind.SPINE)
	var arrival := BerthApproachLanes.get_target_lane(
		destination_port_id, destination_berth_id, BerthApproachLanes.LaneKind.SPINE)
	if arrival.size() < 2:
		return plan_departure(from_xz, to_xz, origin_port_id, origin_berth_id,
			destination_port_id)
	var points := PackedVector2Array()
	for raw in departure:
		var point := raw as Vector3
		points.append(Vector2(point.x, point.z))
	if points.is_empty():
		points.append(from_xz)
	var arrival_outer := arrival[-1] as Vector3
	var water_end := Vector2(arrival_outer.x, arrival_outer.z)
	var water_points := _navigation.route_points(points[-1], water_end)
	for point in water_points:
		if not points[-1].is_equal_approx(point):
			points.append(point)
	## Stored berth lanes run quay -> sea. Reverse the destination lane so the
	## voyage becomes sea -> controlled approach -> berth.
	for index in range(arrival.size() - 2, -1, -1):
		var point3 := arrival[index] as Vector3
		var point2 := Vector2(point3.x, point3.z)
		if not points[-1].is_equal_approx(point2):
			points.append(point2)
	return MarineRoutePlan.create(points, str(_layout.layout_checksum),
		origin_port_id, destination_port_id)
