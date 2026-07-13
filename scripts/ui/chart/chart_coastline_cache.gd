class_name ChartCoastlineCache
extends RefCounted

## World-space chart geometry cache. Marching-squares output stays as independent
## two-point segments; visible queries perform bounds culling and line clipping.

var revision := 0
var cache_key := ""
var _segments: Array[PackedVector2Array] = []
var _segment_bounds: Array[Rect2] = []
var _land_runs: Array[Rect2] = []


func prepare(layout: Variant) -> void:
	if layout == null:
		return
	var next_key := _layout_cache_key(layout)
	if next_key == cache_key:
		return
	cache_key = next_key
	revision += 1
	_segments.clear()
	_segment_bounds.clear()
	_land_runs.clear()
	for raw_segment in layout.get("coastline_contours"):
		if not raw_segment is PackedVector2Array:
			continue
		var segment := raw_segment as PackedVector2Array
		if segment.size() != 2:
			continue
		var cached := segment.duplicate()
		_segments.append(cached)
		var minimum := Vector2(
			minf(cached[0].x, cached[1].x),
			minf(cached[0].y, cached[1].y)
		)
		_segment_bounds.append(Rect2(minimum, (cached[1] - cached[0]).abs()).grow(0.01))
	_build_land_runs(layout)


func segments_in_bounds(layout: Variant, bounds: Rect2) -> Array[PackedVector2Array]:
	prepare(layout)
	var visible: Array[PackedVector2Array] = []
	for i in range(_segments.size()):
		if not _segment_bounds[i].intersects(bounds, true):
			continue
		var clipped := _clip_segment_to_rect(_segments[i][0], _segments[i][1], bounds)
		if clipped.size() == 2:
			visible.append(clipped)
	return visible


func land_runs() -> Array[Rect2]:
	return _land_runs


func is_chart_land(layout: Variant, world_xz: Vector2) -> bool:
	prepare(layout)
	for run in _land_runs:
		if run.has_point(world_xz):
			return true
	return false


func _build_land_runs(layout: Variant) -> void:
	var resolution := int(layout.get("raster_resolution"))
	var cell_size := float(layout.get("cell_size_m"))
	var half_extent := float(layout.get("half_extent_m"))
	if resolution < 2 or cell_size <= 0.0:
		return
	for z in range(resolution - 1):
		var run_start := -1
		for x in range(resolution - 1):
			var center := Vector2(
				-half_extent + (float(x) + 0.5) * cell_size,
				-half_extent + (float(z) + 0.5) * cell_size
			)
			var land := bool(layout.call("is_land", center))
			if land and run_start < 0:
				run_start = x
			if run_start >= 0 and (not land or x == resolution - 2):
				var run_end := x + 1 if land else x
				_land_runs.append(Rect2(
					Vector2(
						-half_extent + float(run_start) * cell_size,
						-half_extent + float(z) * cell_size
					),
					Vector2(float(run_end - run_start) * cell_size, cell_size)
				))
				run_start = -1


static func _layout_cache_key(layout: Variant) -> String:
	var checksum := str(layout.get("layout_checksum"))
	if not checksum.is_empty():
		return checksum
	return "%d:%d:%f" % [
		layout.get_instance_id(),
		int(layout.get("raster_resolution")),
		float(layout.get("world_size_m")),
	]


static func _clip_segment_to_rect(a: Vector2, b: Vector2, bounds: Rect2) -> PackedVector2Array:
	var delta := b - a
	var t_min := 0.0
	var t_max := 1.0
	var p := PackedFloat32Array([-delta.x, delta.x, -delta.y, delta.y])
	var q := PackedFloat32Array([
		a.x - bounds.position.x,
		bounds.end.x - a.x,
		a.y - bounds.position.y,
		bounds.end.y - a.y,
	])
	for i in range(4):
		if is_zero_approx(p[i]):
			if q[i] < 0.0:
				return PackedVector2Array()
			continue
		var ratio := q[i] / p[i]
		if p[i] < 0.0:
			t_min = maxf(t_min, ratio)
		else:
			t_max = minf(t_max, ratio)
		if t_min > t_max:
			return PackedVector2Array()
	return PackedVector2Array([a + delta * t_min, a + delta * t_max])
