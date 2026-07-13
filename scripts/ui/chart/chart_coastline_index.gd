class_name ChartCoastlineIndex
extends RefCounted

## Spatially indexed vector coastline. Queries touch only visible grid buckets,
## so the chart gets a sharp coast at every zoom without scanning all segments.

const CELL_M := 2000.0

var cache_key := ""
var _segments: Array[PackedVector2Array] = []
var _cells: Dictionary = {}


func prepare(layout: WorldLayout) -> void:
	if layout == null:
		return
	var next_key := str(layout.layout_checksum)
	if next_key.is_empty():
		next_key = str(layout.get_instance_id())
	if next_key == cache_key:
		return
	cache_key = next_key
	_segments.clear()
	_cells.clear()
	for raw in layout.coastline_contours:
		if not raw is PackedVector2Array:
			continue
		var segment := raw as PackedVector2Array
		if segment.size() != 2:
			continue
		var index := _segments.size()
		_segments.append(segment)
		var minimum := segment[0].min(segment[1])
		var maximum := segment[0].max(segment[1])
		var cell_min := _cell_for(minimum)
		var cell_max := _cell_for(maximum)
		for y in range(cell_min.y, cell_max.y + 1):
			for x in range(cell_min.x, cell_max.x + 1):
				var key := Vector2i(x, y)
				var bucket: PackedInt32Array = _cells.get(key, PackedInt32Array())
				bucket.append(index)
				_cells[key] = bucket


func segments_in(bounds: Rect2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if _segments.is_empty():
		return result
	var seen: Dictionary = {}
	var cell_min := _cell_for(bounds.position)
	var cell_max := _cell_for(bounds.end)
	for y in range(cell_min.y, cell_max.y + 1):
		for x in range(cell_min.x, cell_max.x + 1):
			var bucket: PackedInt32Array = _cells.get(Vector2i(x, y), PackedInt32Array())
			for index in bucket:
				if seen.has(index):
					continue
				seen[index] = true
				var segment := _segments[index]
				var minimum := segment[0].min(segment[1])
				var segment_bounds := Rect2(minimum, (segment[1] - segment[0]).abs()).grow(0.01)
				if segment_bounds.intersects(bounds, true):
					result.append(segment)
	return result


static func _cell_for(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / CELL_M), floori(world.y / CELL_M))
