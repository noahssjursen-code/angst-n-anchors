class_name ChartCoastlineIndex
extends RefCounted

## Spatially indexed vector coastline. Queries touch only visible grid buckets,
## so the chart gets a sharp coast at every zoom without scanning all segments.

const CELL_M := 2000.0
const CACHE_LIMIT := 4
static var _cache: Dictionary = {}
static var _cache_order := PackedStringArray()

var cache_key := ""
var _segments: Array[PackedVector2Array] = []
var _cells: Dictionary = {}
var _segment_bounds: Array[Rect2] = []
var _query_bounds := Rect2()
var _query_result: Array[PackedVector2Array] = []
var build_usec := 0
var query_count := 0
var query_hits := 0


func prepare(layout: WorldLayout) -> void:
	if layout == null:
		return
	var next_key := ChartRasterCache.world_key(layout)
	if next_key == cache_key:
		return
	cache_key = next_key
	_query_bounds = Rect2()
	_query_result = []
	if _cache.has(cache_key):
		var cached: Dictionary = _cache[cache_key]
		_segments = cached.segments
		_cells = cached.cells
		_segment_bounds = cached.bounds
		build_usec = 0
		return
	var started := Time.get_ticks_usec()
	# New containers, never mutate a previous world's shared index.
	_segments = []
	_cells = {}
	_segment_bounds = []
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
		_segment_bounds.append(Rect2(minimum, maximum - minimum).grow(0.01))
		var cell_min := _cell_for(minimum)
		var cell_max := _cell_for(maximum)
		for y in range(cell_min.y, cell_max.y + 1):
			for x in range(cell_min.x, cell_max.x + 1):
				var key := Vector2i(x, y)
				var bucket: PackedInt32Array = _cells.get(key, PackedInt32Array())
				bucket.append(index)
				_cells[key] = bucket
	_cache[cache_key] = {"segments": _segments, "cells": _cells, "bounds": _segment_bounds}
	_cache_order.append(cache_key)
	while _cache_order.size() > CACHE_LIMIT:
		_cache.erase(_cache_order[0])
		_cache_order.remove_at(0)
	build_usec = Time.get_ticks_usec() - started


func segments_in(bounds: Rect2) -> Array[PackedVector2Array]:
	query_count += 1
	if bounds == _query_bounds:
		query_hits += 1
		return _query_result
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
				if _segment_bounds[index].intersects(bounds, true):
					result.append(segment)
	_query_bounds = bounds
	_query_result = result
	return result


func debug_stats() -> Dictionary:
	return {"key": cache_key, "segments": _segments.size(), "build_usec": build_usec,
		"queries": query_count, "query_hits": query_hits}


static func _cell_for(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / CELL_M), floori(world.y / CELL_M))
