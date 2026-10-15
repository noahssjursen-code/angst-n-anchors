class_name CoastalPlotIndex
extends RefCounted

## Derived shoreline parcels, not ownership or purchase authority. The immutable
## world's actual contours (including small skerries) intersect a metre grid.
## Persistent ownership may reference these IDs later; it must live separately.
## A square can contain more than one shoreline section in narrow channels.
## Such parcels are flagged for boundary review before a future land sale system.
const VERSION := 1
const DEFAULT_CELL_SIZE_M := 200.0
const CACHE_LIMIT := 4
const JOIN_EPSILON_M := 0.02

static var _cache: Dictionary = {}
static var _cache_order: Array[String] = []

var cell_size_m: float:
	get: return _cell_size_m
var world_identity: Dictionary:
	get: return _world_identity.duplicate(true)
var world_bounds: Rect2:
	get: return _world_bounds
var build_usec: int:
	get: return _build_usec

var _cell_size_m := DEFAULT_CELL_SIZE_M
var _world_identity: Dictionary = {}
var _world_bounds := Rect2()
var _build_usec := 0

var _namespace := ""
var _plots_by_cell: Dictionary = {}
var _cells_by_id: Dictionary = {}
var _ordered_cells: Array[Vector2i] = []
var _neighbours: Dictionary = {}


static func for_layout(layout: WorldLayout, plot_size_m: float = DEFAULT_CELL_SIZE_M) -> CoastalPlotIndex:
	assert(layout != null)
	assert(is_finite(plot_size_m) and plot_size_m >= 10.0)
	var identity := {
		"seed": layout.seed,
		"generation_version": WorldLayoutGenerator.GENERATION_VERSION,
		"layout_checksum": layout.layout_checksum,
		"world_size_m": layout.world_size_m,
	}
	var key := _identity_key(identity, plot_size_m)
	if _cache.has(key):
		return _cache[key] as CoastalPlotIndex
	var index := CoastalPlotIndex.new()
	index._build(layout.coastline_contours, identity,
		Rect2(Vector2.ONE * -layout.half_extent_m, Vector2.ONE * layout.world_size_m), plot_size_m)
	_cache[key] = index
	_cache_order.append(key)
	while _cache_order.size() > CACHE_LIMIT:
		_cache.erase(_cache_order.pop_front())
	return index


static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


## Full context hashes prevent one world's parcel ID being restored in another.
static func _identity_key(identity: Dictionary, plot_size_m: float) -> String:
	return ("coastal-plots:%d:%d:%d:%s:%.6f:%.6f" % [VERSION,
		int(identity.get("generation_version", 0)), int(identity.get("seed", 0)),
		String(identity.get("layout_checksum", "")),
		float(identity.get("world_size_m", 0.0)), plot_size_m]).sha256_text()


func count() -> int:
	return _ordered_cells.size()


func cell_at(world_xz: Vector2) -> Vector2i:
	return Vector2i(floori(world_xz.x / cell_size_m), floori(world_xz.y / cell_size_m))


func plot_at(world_xz: Vector2) -> Dictionary:
	if not world_bounds.has_point(world_xz):
		return {}
	return _record_for_cell(cell_at(world_xz))


func get_plot(plot_id: String) -> Dictionary:
	if not _cells_by_id.has(plot_id):
		return {}
	return _record_for_cell(_cells_by_id[plot_id])


## O(number of visible grid cells), independent of the whole world's coast size.
## Returned records contain only JSON-compatible values and are safe to mutate.
func plots_in_rect(rect: Rect2, limit: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var clipped := rect.abs().intersection(world_bounds)
	if not clipped.has_area():
		return result
	var first := cell_at(clipped.position)
	var last := Vector2i(ceili(clipped.end.x / cell_size_m) - 1, ceili(clipped.end.y / cell_size_m) - 1)
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, z)
			if not _plots_by_cell.has(cell):
				continue
			result.append(_record_for_cell(cell))
			if limit > 0 and result.size() >= limit:
				return result
	return result


func plot_bounds(plot_id: String) -> Rect2:
	if not _cells_by_id.has(plot_id):
		return Rect2()
	return _bounds_for_cell(_cells_by_id[plot_id])


## Native geometry access for one prebatched map mesh; no JSON parsing needed.
func all_bounds() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for cell in _ordered_cells:
		result.append(_bounds_for_cell(cell))
	return result


func plot_ids() -> Array[String]:
	var result: Array[String] = []
	for cell in _ordered_cells:
		result.append(String(_plots_by_cell[cell]["id"]))
	return result


## Expansion follows connected shore crossings, not grid proximity alone.
func neighbour_ids(plot_id: String) -> Array[String]:
	var result: Array[String] = []
	if not _cells_by_id.has(plot_id):
		return result
	var cell: Vector2i = _cells_by_id[plot_id]
	for other in _neighbours.get(cell, {}):
		result.append(String(_plots_by_cell[other]["id"]))
	result.sort()
	return result


## Candidate neighbouring parcels only; does not claim they are for sale or free.
func expansion_frontier(owned_plot_ids: Array[String]) -> Array[String]:
	var owned := {}
	for plot_id in owned_plot_ids:
		if _cells_by_id.has(plot_id):
			owned[plot_id] = true
	var frontier := {}
	for plot_id in owned:
		for neighbour in neighbour_ids(plot_id):
			if not owned.has(neighbour):
				frontier[neighbour] = true
	var result: Array[String] = []
	for plot_id in frontier:
		result.append(String(plot_id))
	result.sort()
	return result


func _record_for_cell(cell: Vector2i) -> Dictionary:
	return (_plots_by_cell.get(cell, {}) as Dictionary).duplicate(true)


func _bounds_for_cell(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * cell_size_m, Vector2.ONE * cell_size_m)


func _build(contours: Array[PackedVector2Array], identity: Dictionary, bounds: Rect2, plot_size_m: float) -> void:
	var started := Time.get_ticks_usec()
	_cell_size_m = plot_size_m
	_world_identity = identity.duplicate(true)
	_world_bounds = bounds.abs()
	_namespace = _identity_key(identity, plot_size_m)
	_plots_by_cell.clear()
	_cells_by_id.clear()
	_ordered_cells.clear()
	_neighbours.clear()
	var fragments := {}
	var shore_totals := {}
	var endpoint_bins := {}
	for contour in contours:
		for segment in range(1, contour.size()):
			var a := contour[segment - 1]
			var b := contour[segment]
			if a.distance_squared_to(b) < 0.000001:
				continue
			var cuts := _segment_cuts(a, b)
			var previous: Variant = null
			var first: Variant = null
			for part in range(1, cuts.size()):
				if cuts[part] - cuts[part - 1] < 0.000000001:
					continue
				var start := a.lerp(b, cuts[part - 1])
				var end := a.lerp(b, cuts[part])
				var midpoint := (start + end) * 0.5
				var cell := cell_at(midpoint)
				if not fragments.has(cell):
					fragments[cell] = []
					shore_totals[cell] = {"length": 0.0, "centroid": Vector2.ZERO}
				fragments[cell].append([start, end])
				var length := start.distance_to(end)
				shore_totals[cell]["length"] += length
				shore_totals[cell]["centroid"] += midpoint * length
				if first == null:
					first = cell
				if previous != null:
					_connect(previous, cell)
				previous = cell
			if first != null:
				# Adjacent marching-squares segments can differ by float round-off.
				# Join their actual endpoints within 2 cm, not distant grid neighbours.
				if is_zero_approx(cuts[0]):
					_join_endpoint(a, first, endpoint_bins)
				if is_equal_approx(cuts[-1], 1.0):
					_join_endpoint(b, previous, endpoint_bins)
	for cell in fragments:
		_ordered_cells.append(cell)
	_ordered_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for cell in _ordered_cells:
		var shore: Dictionary = shore_totals[cell]
		var anchor: Vector2 = shore.centroid / maxf(float(shore.length), 0.001)
		var plot_id := "coast:%d:%s:%d:%d" % [VERSION, _namespace, cell.x, cell.y]
		var sections := _section_count(fragments[cell])
		_plots_by_cell[cell] = {
			"id": plot_id, "version": VERSION, "world": _world_identity.duplicate(true),
			"grid": [cell.x, cell.y],
			"bounds": {"x": cell.x * cell_size_m, "z": cell.y * cell_size_m, "size_m": cell_size_m},
			"shore_length_m": snappedf(float(shore.length), 0.001),
			"shore_anchor": [snappedf(anchor.x, 0.001), snappedf(anchor.y, 0.001)],
			"shore_section_count": sections,
			"boundary_review_required": sections > 1 or not world_bounds.encloses(_bounds_for_cell(cell)),
		}
		_cells_by_id[plot_id] = cell
	_build_usec = Time.get_ticks_usec() - started


## Clip to the map, then split at every crossed world-aligned grid boundary.
## Using segment intersections includes tiny islands missed by corner samples.
func _segment_cuts(a: Vector2, b: Vector2) -> PackedFloat64Array:
	var delta := b - a
	var lo := 0.0
	var hi := 1.0
	for axis in 2:
		if absf(delta[axis]) < 0.000001:
			if a[axis] < world_bounds.position[axis] or a[axis] > world_bounds.end[axis]:
				return PackedFloat64Array()
			continue
		var enter := (world_bounds.position[axis] - a[axis]) / delta[axis]
		var leave := (world_bounds.end[axis] - a[axis]) / delta[axis]
		lo = maxf(lo, minf(enter, leave))
		hi = minf(hi, maxf(enter, leave))
		if hi <= lo:
			return PackedFloat64Array()
	var result := PackedFloat64Array([lo, hi])
	var start := a.lerp(b, lo)
	var end := a.lerp(b, hi)
	for axis in 2:
		if absf(delta[axis]) < 0.000001:
			continue
		var first := floori(minf(start[axis], end[axis]) / cell_size_m) + 1
		var last := ceili(maxf(start[axis], end[axis]) / cell_size_m) - 1
		for boundary in range(first, last + 1):
			var t := (float(boundary) * cell_size_m - a[axis]) / delta[axis]
			if t > lo and t < hi:
				result.append(t)
	result.sort()
	return result


func _connect(a: Vector2i, b: Vector2i) -> void:
	if a == b:
		return
	if not _neighbours.has(a):
		_neighbours[a] = {}
	if not _neighbours.has(b):
		_neighbours[b] = {}
	_neighbours[a][b] = true
	_neighbours[b][a] = true


func _join_endpoint(point: Vector2, cell: Vector2i, bins: Dictionary) -> void:
	var key := Vector2i(floori(point.x / JOIN_EPSILON_M), floori(point.y / JOIN_EPSILON_M))
	for z in range(key.y - 1, key.y + 2):
		for x in range(key.x - 1, key.x + 2):
			for endpoint in bins.get(Vector2i(x, z), []):
				if point.distance_squared_to(endpoint[0]) <= JOIN_EPSILON_M * JOIN_EPSILON_M:
					_connect(cell, endpoint[1])
	if not bins.has(key):
		bins[key] = []
	bins[key].append([point, cell])


## Count separately connected shore fragments inside one square. Neighbouring
## fjord shores or two small islands can share a parcel; future ownership rules
## must resolve those boundaries rather than sell them as one unquestioned lot.
static func _section_count(fragments: Array) -> int:
	var parents: Array[int] = []
	var bins := {}
	for i in fragments.size():
		parents.append(i)
	for i in fragments.size():
		for point: Vector2 in fragments[i]:
			var key := Vector2i(floori(point.x / JOIN_EPSILON_M), floori(point.y / JOIN_EPSILON_M))
			for z in range(key.y - 1, key.y + 2):
				for x in range(key.x - 1, key.x + 2):
					for endpoint in bins.get(Vector2i(x, z), []):
						if point.distance_squared_to(endpoint[0]) <= JOIN_EPSILON_M * JOIN_EPSILON_M:
							var left := _root(parents, i)
							var right := _root(parents, int(endpoint[1]))
							parents[right] = left
			if not bins.has(key):
				bins[key] = []
			bins[key].append([point, i])
	var sections := {}
	for i in fragments.size():
		sections[_root(parents, i)] = true
	return sections.size()


static func _root(parents: Array[int], index: int) -> int:
	while parents[index] != index:
		parents[index] = parents[parents[index]]
		index = parents[index]
	return index
