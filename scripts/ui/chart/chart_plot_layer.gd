class_name ChartPlotLayer
extends RefCounted

## Coastline squares batched once into one retained mesh and one border call.
## The chart's clipping canvas and GPU transform handle camera pan/zoom.
## Ownership/purchase authority will be an overlay on this immutable geography.
const FILL := Color(0.13, 0.85, 0.36, 0.24)
const EDGE := Color(0.08, 0.60, 0.25, 0.73)
const OWNED_FILL := Color(0.13, 0.56, 0.95, 0.38)
const OTHER_FILL := Color(0.38, 0.43, 0.44, 0.13)
var index: CoastalPlotIndex
var mesh: ArrayMesh
var borders := PackedVector2Array()
var _bounds := Rect2()
var _visible := Rect2()
var build_count := 0
var visible_count := 0
var build_usec := 0
var _plot_filter: Dictionary = {}
var _ownership_active := false
var _owned: Dictionary = {}
var _available: Dictionary = {}
var _status_colours: Dictionary = {}

## Optional geographical scope for isolated property / island previews.
func set_plot_filter(ids: Array[String]) -> void:
	_plot_filter.clear()
	for id in ids:
		_plot_filter[id] = true
	if index != null:
		_build(index.world_bounds)

func allows_plot(id: String) -> bool:
	return _plot_filter.is_empty() or _plot_filter.has(id)

## Optional presentation only; the host's authority still approves purchases.
## Rebuild the retained mesh on ownership changes, never while panning/zooming.
func set_ownership_status(owned_ids: Array[String], available_ids: Array[String]) -> void:
	_owned.clear()
	_available.clear()
	for id in owned_ids: _owned[id] = true
	for id in available_ids: _available[id] = true
	_ownership_active = true
	if index != null: _build(index.world_bounds)


func plot_status(id: String) -> String:
	if not _ownership_active: return "unassigned"
	if _owned.has(id): return "owned"
	return "available" if _available.has(id) else "unavailable"

func prepare(layout: WorldLayout) -> void:
	var next := CoastalPlotIndex.for_layout(layout)
	if index == next and mesh != null:
		return
	index = next
	_build(index.world_bounds)

func draw(canvas: CanvasItem, ctx: Dictionary) -> void:
	if index == null:
		return
	var bounds: Rect2 = ctx.world_bounds
	var chart: Rect2 = ctx.chart_rect
	_visible = bounds
	if mesh == null:
		return
	var scale := chart.size / bounds.size
	canvas.draw_set_transform(chart.position + (_bounds.position-bounds.position)*scale, 0.0, scale)
	canvas.draw_mesh(mesh, null)
	if index.cell_size_m * scale.x >= 4.0 and not borders.is_empty():
		# Transform the retained line buffer; negative width stays one screen pixel.
		canvas.draw_multiline(borders, Color(0.32,0.39,0.41,0.4) if _ownership_active else EDGE, -1.0)
	canvas.draw_set_transform(Vector2.ZERO)

func draw_selection(canvas: CanvasItem, ctx: Dictionary, selected: String, hovered: String) -> void:
	if index == null:
		return
	if _ownership_active:
		for id in _owned: _outline(canvas, ctx, index.get_plot(id), Color(0.12,0.49,0.89), 2.5)
		for id in _available: _outline(canvas, ctx, index.get_plot(id), Color(0.08,0.65,0.25), 2.0)
	if not selected.is_empty() and not _ownership_active:
		for neighbour in index.neighbour_ids(selected):
			if allows_plot(neighbour):
				_outline(canvas, ctx, index.get_plot(neighbour), Color(0.30, 0.98, 0.54, 0.90), 2.0)
	if not selected.is_empty():
		_outline(canvas, ctx, index.get_plot(selected), Color(0.96, 1.0, 0.93), 3.0)
	if not hovered.is_empty() and hovered != selected:
		_outline(canvas, ctx, index.get_plot(hovered), Color(0.91, 1.0, 0.65), 2.0)

func _build(bounds: Rect2) -> void:
	var started := Time.get_ticks_usec()
	_bounds = bounds
	borders.clear()
	_status_colours.clear()
	if _ownership_active:
		for id in _owned: _status_colours[index.plot_bounds(id).position] = OWNED_FILL
		for id in _available: _status_colours[index.plot_bounds(id).position] = FILL
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var squares := index.all_bounds()
	if not _plot_filter.is_empty():
		squares.clear()
		for id in _plot_filter:
			squares.append(index.plot_bounds(id))
	for square in squares:
		var r := square.intersection(bounds)
		if not r.has_area():
			continue
		var a := r.position - bounds.position
		var b := r.end - bounds.position
		var start := vertices.size()
		vertices.append_array(PackedVector2Array([
			a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]))
		var fill: Color = _status_colours.get(square.position, OTHER_FILL) if _ownership_active else FILL
		for _i in 4:
			colors.append(fill)
		indices.append_array(PackedInt32Array([start, start+1, start+2, start, start+2, start+3]))
		borders.append_array(PackedVector2Array([a, Vector2(b.x,a.y),
			Vector2(b.x,a.y), b, b, Vector2(a.x,b.y), Vector2(a.x,b.y), a]))
	mesh = ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	build_count += 1
	build_usec = Time.get_ticks_usec() - started

static func plot_rect(row: Dictionary) -> Rect2:
	var bounds: Dictionary = row.get("bounds", {})
	return Rect2(float(bounds.get("x", 0.0)), float(bounds.get("z", 0.0)),
		float(bounds.get("size_m", 0.0)), float(bounds.get("size_m", 0.0)))

func _outline(canvas: CanvasItem, ctx: Dictionary, row: Dictionary, colour: Color, width: float) -> void:
	if row.is_empty():
		return
	var bounds: Rect2 = ctx.world_bounds
	var r := plot_rect(row)
	if not r.intersects(bounds):
		return
	var chart: Rect2 = ctx.chart_rect
	canvas.draw_rect(Rect2(chart.position + (r.position-bounds.position)/bounds.size*chart.size,
		r.size/bounds.size*chart.size), colour, false, width)

func debug_stats() -> Dictionary:
	visible_count = index.plots_in_rect(_visible).size() if index != null else 0
	return {"total_plots": index.count() if index != null else 0,
		"visible_plots": visible_count, "mesh_builds": build_count, "mesh_build_usec": build_usec}
