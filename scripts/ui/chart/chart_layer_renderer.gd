class_name ChartLayerRenderer
extends RefCounted

const C_GRID := Color(0.18, 0.26, 0.44, 0.22)
const C_ISLAND := Color(0.22, 0.30, 0.20, 0.94)
const C_EDGE := Color(0.38, 0.52, 0.32, 0.78)
const C_MACRO_LAND := Color(0.16, 0.23, 0.16, 0.96)
const C_MACRO_COAST := Color(0.48, 0.66, 0.38, 0.92)
const C_PORT_MARKER := Color(0.82, 0.91, 0.56, 0.96)
const C_SHIP := Color(0.96, 0.86, 0.12, 1.0)
const C_TRAFFIC := Color(0.25, 0.88, 0.92, 0.92)
const MapWeatherViewClass = preload("res://scripts/ui/map/map_weather_view.gd")
const MapFishingViewClass = preload("res://scripts/ui/map/map_fishing_view.gd")
const WaterwayNavigationClass = preload("res://scripts/navigation/waterway_navigation.gd")
const ChartCoastlineCacheClass = preload("res://scripts/ui/chart/chart_coastline_cache.gd")

var weather_adapter := MapWeatherViewClass.new()
var fishing_adapter := MapFishingViewClass.new()
var polygon_cache: Dictionary = {}
var _active_layout: Variant
var _waterway_navigation := WaterwayNavigationClass.new()
var _coastline_cache := ChartCoastlineCacheClass.new()

var coastline_cache_revision: int:
	get: return _coastline_cache.revision


func render(
	canvas: Control,
	ctx: Dictionary,
	layers: RefCounted,
	nav: RefCounted,
	selected_port: String,
	route_waypoints: PackedVector3Array = PackedVector3Array(),
) -> void:
	var registry := canvas.get_node_or_null("/root/ContractRegistry")
	_active_layout = _resolve_world_layout(canvas)
	if _active_layout != null:
		prepare_layout(_active_layout)
	elif not _waterway_navigation.is_empty():
		_waterway_navigation.clear()
	if layers.is_visible("base"):
		_draw_base(canvas, ctx, registry, selected_port, _active_layout)
	if layers.is_visible("fishing"):
		fishing_adapter.render(canvas, ctx)
	if layers.is_visible("weather"):
		weather_adapter.render(canvas, ctx)
		_draw_fronts(canvas, ctx)
	if layers.is_visible("routes"):
		_draw_routes(canvas, ctx, nav, registry, route_waypoints)
	if layers.is_visible("approaches"):
		_draw_approaches(canvas, ctx, selected_port)
	if layers.is_visible("traffic"):
		_draw_traffic(canvas, ctx)
	if layers.is_visible("nav_vectors"):
		_draw_own_ship_and_vectors(canvas, ctx, nav)
	if layers.is_visible("annotations"):
		_draw_annotations(canvas, ctx, registry, nav, selected_port)


func screen_polygon(pid: String, world_pos: Vector3, info: Dictionary, ctx: Dictionary) -> PackedVector2Array:
	if not polygon_cache.has(pid):
		polygon_cache[pid] = IslandMeshBuilder.build_polygon(
			float(info.get("island_width", 80.0)),
			float(info.get("plot_depth", 140.0)),
			int(info.get("layout_seed", 0))
		)
	var local_poly := polygon_cache[pid] as PackedVector2Array
	var ry := float(info.get("rotation_y", 0.0))
	var cy := cos(ry)
	var sy := sin(ry)
	var out := PackedVector2Array()
	for p in local_poly:
		var rx := p.x * cy + p.y * sy
		var rz := -p.x * sy + p.y * cy
		out.append(_world_to_screen(Vector3(world_pos.x + rx, 0.0, world_pos.z + rz), ctx))
	return out


## Builds stable world-space geometry once per deterministic layout. Camera
## movement only clips and projects visible cached geometry.
func prepare_layout(layout: Variant) -> void:
	if layout == null:
		return
	var previous_key: String = _coastline_cache.cache_key
	_coastline_cache.prepare(layout)
	if previous_key != _coastline_cache.cache_key \
			or _waterway_navigation.layout_checksum != _coastline_cache.cache_key:
		_waterway_navigation.rebuild(layout)


func coastline_segments_in_bounds(layout: Variant, bounds: Rect2) -> Array[PackedVector2Array]:
	return _coastline_cache.segments_in_bounds(layout, bounds)


func chart_land_at(layout: Variant, world_xz: Vector2) -> bool:
	return _coastline_cache.is_chart_land(layout, world_xz)


func _draw_macro_land(canvas: Control, ctx: Dictionary) -> void:
	var bounds: Rect2 = ctx["world_bounds"]
	for run in _coastline_cache.land_runs():
		if not run.intersects(bounds, true):
			continue
		var clipped := run.intersection(bounds)
		var a := _world_to_screen(Vector3(clipped.position.x, 0.0, clipped.position.y), ctx)
		var b := _world_to_screen(Vector3(clipped.end.x, 0.0, clipped.end.y), ctx)
		canvas.draw_rect(Rect2(a.min(b), (b - a).abs()), C_MACRO_LAND)
	for segment in coastline_segments_in_bounds(_active_layout, bounds):
		var a := _world_to_screen(Vector3(segment[0].x, 0.0, segment[0].y), ctx)
		var b := _world_to_screen(Vector3(segment[1].x, 0.0, segment[1].y), ctx)
		canvas.draw_line(a, b, C_MACRO_COAST, 1.6, true)


static func _resolve_world_layout(canvas: Control) -> Variant:
	var tree := canvas.get_tree()
	if tree == null:
		return null
	var world := tree.get_first_node_in_group("world")
	if world == null or not world.has_method("get_world_layout"):
		return null
	return world.call("get_world_layout")


func _draw_base(
	canvas: Control,
	ctx: Dictionary,
	registry: Node,
	selected_port: String,
	layout: Variant,
) -> void:
	if layout != null:
		_draw_macro_land(canvas, ctx)
	var interval := grid_interval(float(ctx["world_span"]))
	var bounds: Rect2 = ctx["world_bounds"]
	var chart: Rect2 = ctx["chart_rect"]
	var gx := floorf(bounds.position.x / interval) * interval
	while gx <= bounds.end.x:
		var sx := _world_to_screen(Vector3(gx, 0.0, 0.0), ctx).x
		canvas.draw_line(Vector2(sx, chart.position.y), Vector2(sx, chart.end.y), C_GRID, 1.0)
		gx += interval
	var gz := floorf(bounds.position.y / interval) * interval
	while gz <= bounds.end.y:
		var sy := _world_to_screen(Vector3(0.0, 0.0, gz), ctx).y
		canvas.draw_line(Vector2(chart.position.x, sy), Vector2(chart.end.x, sy), C_GRID, 1.0)
		gz += interval
	if registry == null:
		return
	for pid_raw in registry.call("get_port_ids"):
		var pid := str(pid_raw)
		var info := registry.call("get_port_info", pid) as Dictionary
		var world_pos := info.get("position", Vector3(INF, INF, INF)) as Vector3
		if not world_pos.is_finite():
			continue
		if layout != null:
			var marker := _world_to_screen(world_pos, ctx)
			var selected := pid == selected_port
			canvas.draw_circle(marker, 5.0 if selected else 3.5, Color(1.0, 0.88, 0.30) if selected else C_PORT_MARKER)
			canvas.draw_circle(marker, 7.0 if selected else 5.0, C_EDGE, false, 1.0, true)
			continue
		var poly := screen_polygon(pid, world_pos, info, ctx)
		if poly.size() < 3:
			continue
		var selected := pid == selected_port
		canvas.draw_colored_polygon(poly, Color(0.34, 0.48, 0.28) if selected else C_ISLAND)
		var outline := PackedVector2Array(poly)
		outline.append(poly[0])
		canvas.draw_polyline(outline, Color(0.60, 0.80, 0.50) if selected else C_EDGE, 1.5, true)


func _draw_routes(
	canvas: Control,
	ctx: Dictionary,
	nav: RefCounted,
	registry: Node,
	route_waypoints: PackedVector3Array,
) -> void:
	var font := ThemeDB.fallback_font
	if registry != null:
		for contract in nav.contracts:
			if contract == null:
				continue
			var origin := registry.call("get_port_position", str(contract.get("origin_port_id"))) as Vector3
			var destination := registry.call("get_port_position", str(contract.get("destination_port_id"))) as Vector3
			if not origin.is_finite() or not destination.is_finite():
				continue
			var a := _world_to_screen(origin, ctx)
			var b := _world_to_screen(destination, ctx)
			_dashed(canvas, a, b, Color(1.0, 0.58, 0.06, 0.52), 1.6, 9.0)
			var distance := Vector2(origin.x, origin.z).distance_to(Vector2(destination.x, destination.z))
			if not _waterway_navigation.is_empty():
				var navigable_distance := _waterway_navigation.route_distance(
					Vector2(origin.x, origin.z),
					Vector2(destination.x, destination.z)
				)
				if is_finite(navigable_distance):
					distance = navigable_distance
			canvas.draw_string(
				font, (a + b) * 0.5 + Vector2(4.0, -4.0), _distance(distance),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.70, 0.25, 0.78)
			)
	if route_waypoints.is_empty():
		return
	var route_points := PackedVector2Array()
	if nav.has_ship():
		route_points.append(_world_to_screen(nav.ship_position, ctx))
	for i in range(route_waypoints.size()):
		var screen := _world_to_screen(route_waypoints[i], ctx)
		route_points.append(screen)
		canvas.draw_circle(screen, 4.0, Color(0.98, 0.78, 0.20, 0.95))
		canvas.draw_string(
			font, screen + Vector2(6.0, -5.0), "WP%d" % (i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.98, 0.84, 0.42, 0.90)
		)
	if route_points.size() >= 2:
		canvas.draw_polyline(route_points, Color(0.98, 0.72, 0.16, 0.88), 2.0, true)


func _draw_approaches(canvas: Control, ctx: Dictionary, selected_port: String) -> void:
	if selected_port.is_empty() or not BerthApproachLanes.is_initialized():
		return
	var berth_count := BerthApproachLanes.berth_count_for_port(selected_port)
	for berth in range(berth_count):
		for kind in range(BerthApproachLanes.LANE_KIND_COUNT):
			var lane := BerthApproachLanes.get_lane(selected_port, berth, kind)
			if lane.size() < 2:
				continue
			var points := PackedVector2Array()
			for point in lane:
				points.append(_world_to_screen(point as Vector3, ctx))
			canvas.draw_polyline(points, Color(0.42, 0.92, 0.72, 0.58), 1.5, true)


func _draw_traffic(canvas: Control, ctx: Dictionary) -> void:
	var manager := canvas.get_node_or_null("/root/NetworkManager")
	if manager == null:
		return
	var service := manager.get("drawing_service") as Node
	if service == null or not service.has_method("get_visible_entities"):
		return
	var entities := service.call("get_visible_entities") as Dictionary
	for id_raw in entities.keys():
		var state := entities[id_raw] as Dictionary
		if not str(state.get("type", "")).begins_with("ship_"):
			continue
		var node := state.get("node", null) as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var pos := _world_to_screen(node.global_position, ctx)
		var bow := _world_horizontal_to_screen(
			NavigationAxes.vessel_bow_horizontal(node)
		).normalized()
		_draw_ship_symbol(canvas, pos, bow, C_TRAFFIC, 7.0)
		canvas.draw_string(
			ThemeDB.fallback_font, pos + Vector2(9.0, -7.0), str(id_raw),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(C_TRAFFIC, 0.72)
		)


func _draw_fronts(canvas: Control, ctx: Dictionary) -> void:
	var world_weather := canvas.get_node_or_null("/root/WorldWeather")
	if world_weather == null or not bool(world_weather.call("is_initialized")):
		return
	var bounds: Rect2 = ctx["world_bounds"]
	var chart: Rect2 = ctx["chart_rect"]
	var fronts := world_weather.call("active_fronts", bounds, WeatherField.current_game_time()) as Array
	for front in fronts:
		var center_xz := front.get("center", Vector2.ZERO) as Vector2
		var screen := _world_to_screen(Vector3(center_xz.x, 0.0, center_xz.y), ctx)
		var radius_px := float(front.get("radius_m", 0.0)) / bounds.size.x * float(ctx["cpw"])
		var intensity := float(front.get("intensity", 0.0))
		var kind := int(front.get("kind", 0))
		var color := Color(0.95, 0.40, 0.28, 0.42 + intensity * 0.38)
		if kind == WeatherFront.Kind.COLD_FRONT:
			color = Color(0.28, 0.68, 1.0, 0.42 + intensity * 0.38)
		elif kind == WeatherFront.Kind.SQUALL_LINE:
			color = Color(1.0, 0.72, 0.18, 0.48 + intensity * 0.38)
		var previous := screen + Vector2(radius_px, 0.0)
		for segment in range(1, 65):
			var angle := TAU * float(segment) / 64.0
			var next := screen + Vector2(cos(angle), sin(angle)) * radius_px
			if chart.has_point(previous) and chart.has_point(next):
				canvas.draw_line(previous, next, color, 2.0, true)
			previous = next
		var velocity := front.get("velocity", Vector2.ZERO) as Vector2
		if velocity.length_squared() > 0.01 and chart.grow(-24.0).has_point(screen):
			var direction := _world_horizontal_to_screen(velocity).normalized()
			canvas.draw_line(screen, screen + direction * 22.0, color, 1.5, true)
		if chart.grow(-80.0).has_point(screen):
			canvas.draw_string(
				ThemeDB.fallback_font,
				screen + Vector2(7.0, -7.0),
				"%s  %d%%" % [str(front.get("label", "Front")), int(intensity * 100.0)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color
			)


func _draw_own_ship_and_vectors(canvas: Control, ctx: Dictionary, nav: RefCounted) -> void:
	if not nav.has_ship():
		return
	var pos := _world_to_screen(nav.ship_position, ctx)
	var heading_dir := _world_horizontal_to_screen(nav.bow_horizontal).normalized()
	_draw_ship_symbol(canvas, pos, heading_dir, C_SHIP, 10.0)
	canvas.draw_line(pos, pos + heading_dir * 48.0, Color(1.0, 0.86, 0.18, 0.95), 2.0, true)
	if nav.has_course():
		var course_dir := _world_horizontal_to_screen(nav.velocity_horizontal).normalized()
		_dashed(canvas, pos, pos + course_dir * 64.0, Color(0.25, 0.92, 0.96, 0.95), 2.0, 7.0)


func _draw_annotations(
	canvas: Control,
	ctx: Dictionary,
	registry: Node,
	nav: RefCounted,
	selected_port: String,
) -> void:
	if registry == null:
		return
	var font := ThemeDB.fallback_font
	for pid_raw in registry.call("get_port_ids"):
		var pid := str(pid_raw)
		var info := registry.call("get_port_info", pid) as Dictionary
		var pos := info.get("position", Vector3(INF, INF, INF)) as Vector3
		if not pos.is_finite():
			continue
		var screen := _world_to_screen(pos, ctx)
		canvas.draw_string(
			font, screen + Vector2(6.0, -7.0), str(info.get("display_name", pid)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.90, 1.0, 0.82) if pid == selected_port else Color(0.70, 0.84, 0.60, 0.90)
		)
	if not selected_port.is_empty():
		_draw_port_inspector(canvas, ctx, registry, nav, selected_port)


func _draw_port_inspector(
	canvas: Control,
	ctx: Dictionary,
	registry: Node,
	nav: RefCounted,
	port_id: String,
) -> void:
	var info := registry.call("get_port_info", port_id) as Dictionary
	if info.is_empty():
		return
	var chart: Rect2 = ctx["chart_rect"]
	var panel := Rect2(chart.end.x - 238.0, chart.end.y - 112.0, 228.0, 102.0)
	canvas.draw_rect(panel, Color(0.04, 0.07, 0.16, 0.96))
	canvas.draw_rect(panel, Color(0.60, 0.80, 0.50, 0.85), false, 1.0)
	var world_pos := info.get("position", Vector3.ZERO) as Vector3
	var distance := NAN
	if nav.has_ship():
		distance = Vector2(world_pos.x, world_pos.z).distance_to(
			Vector2(nav.ship_position.x, nav.ship_position.z)
		)
	var lines: Array[String] = [
		str(info.get("display_name", port_id)).to_upper(),
		"Berths  %d    Population  %d" % [
			int(info.get("berth_count", 1)), int(info.get("population", 0))
		],
		"Export  %s" % str(info.get("commodity_export", "—")).capitalize(),
		"Range   %s" % (_distance(distance) if is_finite(distance) else "—"),
	]
	for i in range(lines.size()):
		canvas.draw_string(
			ThemeDB.fallback_font, panel.position + Vector2(10.0, 19.0 + i * 20.0),
			lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.90, 1.0, 0.82) if i == 0 else Color(0.68, 0.80, 0.72, 0.88)
		)


static func grid_interval(world_span: float) -> float:
	var raw := world_span / 6.0
	var steps: Array[float] = [
		100.0, 200.0, 500.0, 1000.0, 1852.0, 3704.0,
		9260.0, 18520.0, 37040.0, 92600.0,
	]
	for step in steps:
		if step >= raw:
			return step
	return steps[steps.size() - 1]


static func _world_to_screen(world: Vector3, ctx: Dictionary) -> Vector2:
	var bounds: Rect2 = ctx["world_bounds"]
	var chart: Rect2 = ctx["chart_rect"]
	return chart.position + Vector2(
		(world.x - bounds.position.x) / bounds.size.x * chart.size.x,
		(bounds.end.y - world.z) / bounds.size.y * chart.size.y
	)


static func _world_horizontal_to_screen(direction: Vector2) -> Vector2:
	return Vector2(direction.x, -direction.y)


static func _draw_ship_symbol(
	canvas: Control,
	pos: Vector2,
	bow: Vector2,
	color: Color,
	size: float,
) -> void:
	var fwd := bow.normalized() if bow.length_squared() > 1.0e-8 else Vector2(0.0, -1.0)
	var side := Vector2(-fwd.y, fwd.x)
	canvas.draw_colored_polygon(PackedVector2Array([
		pos + fwd * size,
		pos - fwd * size * 0.55 + side * size * 0.5,
		pos - fwd * size * 0.55 - side * size * 0.5,
	]), color)


static func _dashed(
	canvas: Control,
	a: Vector2,
	b: Vector2,
	color: Color,
	width: float,
	dash: float,
) -> void:
	var total := a.distance_to(b)
	if total < 1.0:
		return
	var direction := (b - a) / total
	var cursor := 0.0
	var draw_segment := true
	while cursor < total:
		var length := minf(dash, total - cursor)
		if draw_segment:
			canvas.draw_line(
				a + direction * cursor, a + direction * (cursor + length),
				color, width, true
			)
		cursor += length
		draw_segment = not draw_segment


static func _distance(metres: float) -> String:
	return "%.0f m" % metres if metres < 1852.0 else "%.1f nm" % (metres / 1852.0)
