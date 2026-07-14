class_name ChartLayerRenderer
extends RefCounted

## Retained naval-chart renderer. Expensive geography and field layers are
## textures; each frame only draws a small fixed number of symbols and labels.

const BaseRaster := preload("res://scripts/ui/chart/chart_base_raster.gd")
const RasterLayer := preload("res://scripts/ui/chart/chart_raster_layer.gd")
const CoastlineIndex := preload("res://scripts/ui/chart/chart_coastline_index.gd")

const C_GRID := Color(0.12, 0.18, 0.22, 0.26)
const C_GRID_TEXT := Color(0.25, 0.31, 0.32, 0.74)
const C_PORT := Color(0.10, 0.24, 0.28, 1.0)
const C_PORT_SELECTED := Color(0.95, 0.55, 0.10, 1.0)
const C_SHIP := Color(0.94, 0.28, 0.12, 1.0)
const C_ROUTE := Color(0.74, 0.22, 0.12, 0.90)

var snapshot
var base := BaseRaster.new()
var coastline := CoastlineIndex.new()
var weather := RasterLayer.new(RasterLayer.Kind.WEATHER)
var fishing := RasterLayer.new(RasterLayer.Kind.FISHING)
var last_draw_usec := 0
var draw_count := 0


func set_snapshot(next) -> void:
	snapshot = next
	weather.invalidate()
	fishing.invalidate()
	if snapshot != null and snapshot.layout != null:
		base.prepare(snapshot.layout)
		coastline.prepare(snapshot.layout)


func prepare_overlays(bounds: Rect2, layers: ChartLayerManager, game_hours: float) -> void:
	if snapshot == null:
		return
	if layers.is_visible("weather"):
		weather.prepare(snapshot, bounds, game_hours)
	if layers.is_visible("fishing"):
		fishing.prepare(snapshot, bounds, game_hours)


func render(
	canvas: CanvasItem,
	ctx: Dictionary,
	layers: ChartLayerManager,
	nav: ChartNavSnapshot,
	selected_port: String,
) -> void:
	var started := Time.get_ticks_usec()
	var chart: Rect2 = ctx["chart_rect"]
	var bounds: Rect2 = ctx["world_bounds"]
	base.draw(canvas, chart, bounds)
	if layers.is_visible("weather"):
		weather.draw(canvas, chart, bounds)
	if layers.is_visible("fishing"):
		fishing.draw(canvas, chart, bounds)
	if layers.is_visible("weather"):
		weather.draw_wind(canvas, chart, bounds)
		_draw_fronts(canvas, ctx)
	_draw_coastline(canvas, ctx)
	_draw_grid(canvas, ctx)
	if layers.is_visible("routes"):
		_draw_contract_routes(canvas, ctx, nav)
	_draw_ports(canvas, ctx, selected_port, layers.is_visible("annotations"))
	if layers.is_visible("nav_vectors"):
		_draw_ship(canvas, ctx, nav)
	if not selected_port.is_empty():
		_draw_port_card(canvas, ctx, selected_port, nav)
	last_draw_usec = Time.get_ticks_usec() - started
	draw_count += 1


func render_minimap(
	canvas: CanvasItem,
	ctx: Dictionary,
	layers: ChartLayerManager,
	nav: ChartNavSnapshot,
) -> void:
	var chart: Rect2 = ctx["chart_rect"]
	var bounds: Rect2 = ctx["world_bounds"]
	base.draw(canvas, chart, bounds)
	if layers.is_visible("weather"):
		weather.draw(canvas, chart, bounds)
	if layers.is_visible("fishing"):
		fishing.draw(canvas, chart, bounds)
	if layers.is_visible("weather"):
		weather.draw_wind(canvas, chart, bounds)
	_draw_coastline(canvas, ctx)
	if layers.is_visible("routes"):
		_draw_contract_routes(canvas, ctx, nav)
	_draw_ports(canvas, ctx, "", false)
	_draw_ship(canvas, ctx, nav)


func hit_test_port(screen: Vector2, ctx: Dictionary, radius_px: float = 18.0) -> String:
	if snapshot == null:
		return ""
	var best := ""
	var best_distance := radius_px
	for port in snapshot.ports:
		var position := port.get("position", Vector3(INF, INF, INF)) as Vector3
		if not position.is_finite():
			continue
		var distance := screen.distance_to(_world_to_screen(position, ctx))
		if distance < best_distance:
			best_distance = distance
			best = str(port.get("id", ""))
	return best


func world_at(screen: Vector2, ctx: Dictionary) -> Vector2:
	var chart: Rect2 = ctx["chart_rect"]
	var bounds: Rect2 = ctx["world_bounds"]
	var uv := (screen - chart.position) / chart.size
	return bounds.position + uv * bounds.size


func overlay_readout(world: Vector2, layers: ChartLayerManager, game_hours: float) -> Array[String]:
	var rows: Array[String] = [
		"X %d m   Z %d m" % [roundi(world.x), roundi(world.y)],
	]
	if layers.is_visible("weather"):
		var data := weather.sample_at(world, game_hours)
		var wind := data.get("wind", Vector3.ZERO) as Vector3
		rows.append("Wind %s  %.0f kt" % [
			_compass_for_wind(wind),
			float(data.get("wind_speed_ms", 0.0)) * 1.943844,
		])
		rows.append("Pressure %.0f hPa   Cloud %d%%" % [
			float(data.get("pressure", 1013.0)),
			roundi(float(data.get("cloud_cover", 0.0)) * 100.0),
		])
		rows.append("Rain %d%%   Fog %d%%   Waves %.1f m" % [
			roundi(float(data.get("precipitation", 0.0)) * 100.0),
			roundi((1.0 - float(data.get("visibility", 1.0))) * 100.0),
			float(data.get("significant_wave_height_m", 0.25)),
		])
		var components: Dictionary = data.get("component_ids", {})
		if not components.is_empty():
			rows.append("%s · %s · %s" % [
				WeatherProfileCatalog.label_for_band("sky", str(components.get("sky", ""))),
				WeatherProfileCatalog.label_for_band("precipitation", str(components.get("precipitation", ""))),
				WeatherProfileCatalog.label_for_band("sea", str(components.get("sea", ""))),
			])
	if layers.is_visible("fishing"):
		var zone := fishing.sample_at(world, game_hours)
		rows.append(
			"Fishing %s" % str(zone.get("tier_label", "No trawling"))
			if bool(zone.get("open_water", false))
			else "No trawling"
		)
	return rows


func debug_stats() -> Dictionary:
	return {
		"draw_usec": last_draw_usec,
		"draw_count": draw_count,
		"base_build_usec": base.build_usec,
		"weather": weather.debug_stats(),
		"fishing": fishing.debug_stats(),
	}


func _draw_coastline(canvas: CanvasItem, ctx: Dictionary) -> void:
	var bounds: Rect2 = ctx["world_bounds"]
	for segment in coastline.segments_in(bounds):
		canvas.draw_line(
			_world_to_screen(Vector3(segment[0].x, 0.0, segment[0].y), ctx),
			_world_to_screen(Vector3(segment[1].x, 0.0, segment[1].y), ctx),
			Color(0.08, 0.14, 0.14, 0.96),
			1.35,
			true,
		)


func _draw_grid(canvas: CanvasItem, ctx: Dictionary) -> void:
	var chart: Rect2 = ctx["chart_rect"]
	var bounds: Rect2 = ctx["world_bounds"]
	var interval := grid_interval(float(ctx["world_span"]))
	var x := floorf(bounds.position.x / interval) * interval
	while x <= bounds.end.x:
		var screen_x := _world_to_screen(Vector3(x, 0.0, 0.0), ctx).x
		canvas.draw_line(
			Vector2(screen_x, chart.position.y),
			Vector2(screen_x, chart.end.y),
			C_GRID,
		)
		canvas.draw_string(
			ThemeDB.fallback_font,
			Vector2(screen_x + 3.0, chart.end.y - 5.0),
			_format_grid(x),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_GRID_TEXT,
		)
		x += interval
	var z := floorf(bounds.position.y / interval) * interval
	while z <= bounds.end.y:
		var screen_y := _world_to_screen(Vector3(0.0, 0.0, z), ctx).y
		canvas.draw_line(
			Vector2(chart.position.x, screen_y),
			Vector2(chart.end.x, screen_y),
			C_GRID,
		)
		canvas.draw_string(
			ThemeDB.fallback_font,
			Vector2(chart.position.x + 3.0, screen_y - 3.0),
			_format_grid(z),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_GRID_TEXT,
		)
		z += interval


func _draw_ports(
	canvas: CanvasItem,
	ctx: Dictionary,
	selected_port: String,
	show_labels: bool,
) -> void:
	if snapshot == null:
		return
	var chart: Rect2 = ctx["chart_rect"]
	for port in snapshot.ports:
		var position := port.get("position", Vector3(INF, INF, INF)) as Vector3
		if not position.is_finite():
			continue
		var screen := _world_to_screen(position, ctx)
		if not chart.grow(12.0).has_point(screen):
			continue
		var id := str(port.get("id", ""))
		var selected := id == selected_port
		var color := C_PORT_SELECTED if selected else C_PORT
		canvas.draw_circle(screen, 7.0 if selected else 5.0, Color(0.96, 0.94, 0.82, 0.98))
		canvas.draw_circle(screen, 4.5 if selected else 3.0, color)
		if show_labels or selected:
			canvas.draw_string(
				ThemeDB.fallback_font,
				screen + Vector2(8.0, -5.0),
				str(port.get("display_name", id)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.08, 0.13, 0.14, 0.96),
			)


func _draw_ship(canvas: CanvasItem, ctx: Dictionary, nav: ChartNavSnapshot) -> void:
	if nav == null or not nav.has_ship():
		return
	var screen := _world_to_screen(nav.ship_position, ctx)
	var forward := nav.bow_horizontal.normalized()
	var side := Vector2(-forward.y, forward.x)
	canvas.draw_colored_polygon(PackedVector2Array([
		screen + forward * 11.0,
		screen - forward * 6.0 + side * 5.0,
		screen - forward * 6.0 - side * 5.0,
	]), C_SHIP)
	canvas.draw_line(screen, screen + forward * 46.0, C_SHIP, 1.8, true)
	if nav.has_course():
		var course := nav.velocity_horizontal.normalized()
		_draw_dashed(canvas, screen, screen + course * 60.0, Color(0.08, 0.50, 0.62), 1.5)


func _draw_contract_routes(canvas: CanvasItem, ctx: Dictionary, nav: ChartNavSnapshot) -> void:
	if snapshot == null or nav == null:
		return
	for contract in nav.contracts:
		if contract == null:
			continue
		var origin: Vector3 = snapshot.port_position(str(contract.get("origin_port_id")))
		var destination: Vector3 = snapshot.port_position(str(contract.get("destination_port_id")))
		if origin.is_finite() and destination.is_finite():
			_draw_dashed(
				canvas,
				_world_to_screen(origin, ctx),
				_world_to_screen(destination, ctx),
				C_ROUTE,
				2.0,
			)


func _draw_fronts(canvas: CanvasItem, ctx: Dictionary) -> void:
	var bounds: Rect2 = ctx["world_bounds"]
	var chart: Rect2 = ctx["chart_rect"]
	for front in WeatherFrontField.fronts_in_bounds(bounds, WeatherField.current_game_time()):
		var center_xz := front.get("center", Vector2.ZERO) as Vector2
		var center := _world_to_screen(Vector3(center_xz.x, 0.0, center_xz.y), ctx)
		var radius := float(front.get("radius_m", 0.0)) / bounds.size.x * chart.size.x
		var color := Color(0.75, 0.12, 0.12, 0.68)
		if int(front.get("kind", 0)) == WeatherFront.Kind.COLD_FRONT:
			color = Color(0.12, 0.34, 0.78, 0.72)
		canvas.draw_arc(center, radius, 0.0, TAU, 48, color, 1.8, true)
		if chart.size.x > 80.0 and chart.size.y > 80.0 and chart.grow(-40.0).has_point(center):
			canvas.draw_string(
				ThemeDB.fallback_font,
				center + Vector2(6.0, -6.0),
				str(front.get("label", "Front")),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color,
			)


func _draw_port_card(
	canvas: CanvasItem,
	ctx: Dictionary,
	port_id: String,
	nav: ChartNavSnapshot,
) -> void:
	if snapshot == null:
		return
	var info: Dictionary = snapshot.port_info(port_id)
	if info.is_empty():
		return
	var chart: Rect2 = ctx["chart_rect"]
	var panel := Rect2(chart.end.x - 252.0, chart.end.y - 108.0, 240.0, 96.0)
	canvas.draw_rect(panel, Color(0.92, 0.91, 0.82, 0.97))
	canvas.draw_rect(panel, Color(0.12, 0.20, 0.20, 0.88), false, 1.0)
	var range := "—"
	var position := info.get("position", Vector3.ZERO) as Vector3
	if nav != null and nav.has_ship():
		range = _distance(position.distance_to(nav.ship_position))
	var rows: Array[String] = [
		str(info.get("display_name", port_id)).to_upper(),
		"Berths %d   Population %d" % [
			int(info.get("berth_count", 1)),
			int(info.get("population", 0)),
		],
		"Export %s" % str(info.get("commodity_export", "—")).capitalize(),
		"Range %s" % range,
	]
	for index in range(rows.size()):
		canvas.draw_string(
			ThemeDB.fallback_font,
			panel.position + Vector2(10.0, 19.0 + index * 20.0),
			rows[index],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.08, 0.14, 0.14),
		)


static func grid_interval(world_span: float) -> float:
	var raw := world_span / 7.0
	for step in [100.0, 200.0, 500.0, 1000.0, 1852.0, 3704.0, 9260.0, 18520.0, 37040.0, 92600.0]:
		if step >= raw:
			return step
	return 92600.0


static func _world_to_screen(world: Vector3, ctx: Dictionary) -> Vector2:
	var bounds: Rect2 = ctx["world_bounds"]
	var chart: Rect2 = ctx["chart_rect"]
	return chart.position + Vector2(
		(world.x - bounds.position.x) / bounds.size.x * chart.size.x,
		(world.z - bounds.position.y) / bounds.size.y * chart.size.y,
	)


static func _draw_dashed(
	canvas: CanvasItem,
	a: Vector2,
	b: Vector2,
	color: Color,
	width: float,
) -> void:
	var distance := a.distance_to(b)
	if distance < 1.0:
		return
	var direction := (b - a) / distance
	var cursor := 0.0
	while cursor < distance:
		var length := minf(8.0, distance - cursor)
		canvas.draw_line(a + direction * cursor, a + direction * (cursor + length), color, width, true)
		cursor += 16.0


static func _format_grid(metres: float) -> String:
	return "%+.0f km" % (metres / 1000.0)


static func _distance(metres: float) -> String:
	return "%.0f m" % metres if metres < 1852.0 else "%.1f nm" % (metres / 1852.0)


static func _compass_for_wind(wind: Vector3) -> String:
	if wind.length_squared() < 0.001:
		return "calm"
	var bearing := fposmod(rad_to_deg(NavigationAxes.bearing_rad_world_delta(-wind)), 360.0)
	var labels := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return labels[int(round(bearing / 45.0)) % 8]
