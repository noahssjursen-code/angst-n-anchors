class_name ChartCamera
extends RefCounted

const ZOOM_IN := 0.70
const ZOOM_OUT := 1.0 / ZOOM_IN
const SPAN_MIN := 300.0
const SPAN_MAX := 500000.0

var center := Vector2.ZERO
var span := 10000.0
var user_moved := false


func zoom(steps: int) -> void:
	if steps == 0:
		return
	var factor := pow(ZOOM_IN if steps > 0 else ZOOM_OUT, abs(steps))
	span = clampf(span * factor, SPAN_MIN, SPAN_MAX)
	user_moved = true


func pan_pixels(delta_pixels: Vector2, pixels_per_world_unit: float, origin: Vector2) -> void:
	if pixels_per_world_unit <= 0.0:
		return
	# Chart is north-up: screen +Y is world +Z (south).
	center = origin - delta_pixels / pixels_per_world_unit
	user_moved = true


## Birdseye a harbour (or any coastal site) at a tight span.
func focus_harbour(world_xz: Vector2, span_m: float) -> void:
	center = world_xz
	span = clampf(span_m, SPAN_MIN, SPAN_MAX)
	user_moved = true


func home(ship_position: Vector3, points: Array[Vector3]) -> void:
	var all_points := points.duplicate()
	if ship_position.is_finite():
		center = Vector2(ship_position.x, ship_position.z)
		all_points.append(ship_position)
	elif not all_points.is_empty():
		var bounds := _bounds(all_points)
		center = (bounds.position + bounds.end) * 0.5

	if all_points.is_empty():
		span = 10000.0
	else:
		var bounds := _bounds(all_points)
		span = clampf(maxf(bounds.size.x, bounds.size.y) * 1.6, SPAN_MIN, SPAN_MAX)
	user_moved = false


func pixels_per_world_unit(chart_size: Vector2) -> float:
	return minf(chart_size.x, chart_size.y) / maxf(span, 1.0)


func world_bounds(chart_size: Vector2) -> Rect2:
	var ppu := pixels_per_world_unit(chart_size)
	var extent := chart_size * 0.5 / ppu
	return Rect2(center - extent, extent * 2.0)


static func _bounds(points: Array[Vector3]) -> Rect2:
	var first := points[0]
	var min_v := Vector2(first.x, first.z)
	var max_v := min_v
	for point in points:
		var p := Vector2(point.x, point.z)
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	return Rect2(min_v, max_v - min_v)
