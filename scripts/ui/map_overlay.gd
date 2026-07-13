class_name MapOverlay
extends Control

## Marine chart shell retained for GameMenu compatibility. Camera, navigation
## snapshot, declutter policy, and ordered layer drawing live under ui/chart.

const MARGIN := 48.0
const HEADER_H := 76.0
const STATUS_H := 34.0
const REDRAW_INTERVAL_S := 0.20
const C_SEA := Color(0.03, 0.04, 0.10, 0.97)
const C_BORDER := Color(0.30, 0.44, 0.68, 0.80)
const ChartCameraClass = preload("res://scripts/ui/chart/chart_camera.gd")
const ChartLayerManagerClass = preload("res://scripts/ui/chart/chart_layer_manager.gd")
const ChartLayerRendererClass = preload("res://scripts/ui/chart/chart_layer_renderer.gd")
const ChartNavSnapshotClass = preload("res://scripts/ui/chart/chart_nav_snapshot.gd")

var _camera := ChartCameraClass.new()
var _layers := ChartLayerManagerClass.new()
var _renderer := ChartLayerRendererClass.new()
var _nav := ChartNavSnapshotClass.new()
var _selected_port := ""
var _dragging := false
var _drag_origin_mouse := Vector2.ZERO
var _drag_origin_center := Vector2.ZERO
var _drag_distance := 0.0
var _hover_pos := Vector2(-1.0, -1.0)
var _redraw_elapsed := REDRAW_INTERVAL_S
var _was_visible := false
var _last_ctx: Dictionary = {}
var _preset_select: OptionButton
var _layer_buttons: Dictionary = {}
var _route_waypoints := PackedVector3Array()
var _last_draw_usec := 0
var _draw_count := 0


func _ready() -> void:
	add_to_group("marine_chart")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_controls()


func _process(delta: float) -> void:
	if not visible:
		_was_visible = false
		_dragging = false
		return
	if not _was_visible:
		_capture_nav()
		if not _camera.user_moved:
			_home()
		_was_visible = true
		_mark_dirty()
	_redraw_elapsed += delta
	if _redraw_elapsed >= REDRAW_INTERVAL_S:
		_redraw_elapsed = 0.0
		_capture_nav()
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_H:
				_home()
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_F:
				_set_layer("weather", _layers.toggle("weather"))
				get_viewport().set_input_as_handled()
			elif key.keycode == KEY_G:
				_set_layer("fishing", _layers.toggle("fishing"))
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not _chart_rect().has_point(mouse.position):
			return
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom(1)
			_mark_dirty()
			get_viewport().set_input_as_handled()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom(-1)
			_mark_dirty()
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_dragging = true
				_drag_distance = 0.0
				_drag_origin_mouse = mouse.position
				_drag_origin_center = _camera.center
			else:
				_dragging = false
				if _drag_distance < 5.0:
					_select_port(mouse.position)
			get_viewport().set_input_as_handled()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
			_route_waypoints.append(_screen_to_world(mouse.position))
			_capture_nav()
			_mark_dirty()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_hover_pos = motion.position
		if _dragging:
			_drag_distance += motion.relative.length()
			_camera.pan_pixels(
				motion.position - _drag_origin_mouse,
				_camera.pixels_per_world_unit(_chart_rect().size),
				_drag_origin_center
			)
			_mark_dirty()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var draw_started := Time.get_ticks_usec()
	var panel := Rect2(
		Vector2(MARGIN, MARGIN),
		get_viewport_rect().size - Vector2(MARGIN * 2.0, MARGIN * 2.0)
	)
	var chart := _chart_rect()
	draw_rect(panel, C_SEA)
	draw_rect(panel, C_BORDER, false, 2.0)
	draw_rect(chart, Color(0.025, 0.045, 0.095, 1.0))
	draw_rect(chart, Color(0.28, 0.40, 0.64, 0.45), false, 1.0)
	var bounds := _camera.world_bounds(chart.size)
	_last_ctx = {
		"chart_rect": chart,
		"world_bounds": bounds,
		"world_span": _camera.span,
		"cpx": chart.position.x,
		"cpy": chart.position.y,
		"cpw": chart.size.x,
		"cph": chart.size.y,
		"wx_min": bounds.position.x,
		"wx_max": bounds.end.x,
		"wz_min": bounds.position.y,
		"wz_max": bounds.end.y,
		"hover_pos": _hover_pos,
		"hover_inside": chart.has_point(_hover_pos),
	}
	_renderer.render(self, _last_ctx, _layers, _nav, _selected_port, _route_waypoints)
	_draw_compass(Vector2(chart.end.x - 38.0, chart.position.y + 38.0))
	_draw_status(panel)
	_last_draw_usec = Time.get_ticks_usec() - draw_started
	_draw_count += 1


func _build_controls() -> void:
	var bar := HBoxContainer.new()
	bar.name = "ChartControls"
	bar.position = Vector2(MARGIN + 14.0, MARGIN + 10.0)
	bar.size = Vector2(get_viewport_rect().size.x - MARGIN * 2.0 - 28.0, 32.0)
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)

	var title := Label.new()
	title.text = "MARINE CHART"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.12, 0.95))
	bar.add_child(title)

	_preset_select = OptionButton.new()
	for preset_name in ChartLayerManagerClass.PRESET_NAMES:
		_preset_select.add_item(preset_name)
	_preset_select.select(_layers.preset)
	_preset_select.item_selected.connect(_on_preset_selected)
	bar.add_child(_preset_select)

	var home := Button.new()
	home.text = "Home"
	home.pressed.connect(_home)
	bar.add_child(home)
	var clear_route := Button.new()
	clear_route.text = "Clear route"
	clear_route.tooltip_text = "Right-click chart to add waypoints"
	clear_route.pressed.connect(_clear_route)
	bar.add_child(clear_route)
	for spec in [
		["Weather", "weather"],
		["Fishing", "fishing"],
		["Traffic", "traffic"],
		["Routes", "routes"],
		["Approach", "approaches"],
		["Labels", "annotations"],
	]:
		var button := CheckButton.new()
		var layer_name := str(spec[1])
		button.text = str(spec[0])
		button.button_pressed = _layers.is_visible(layer_name)
		button.toggled.connect(_on_layer_toggled.bind(layer_name))
		_layer_buttons[layer_name] = button
		bar.add_child(button)


func _on_preset_selected(index: int) -> void:
	_layers.apply_preset(index)
	for layer_name in _layer_buttons:
		(_layer_buttons[layer_name] as CheckButton).set_pressed_no_signal(
			_layers.is_visible(layer_name)
		)
	_mark_dirty()


func _on_layer_toggled(shown: bool, layer_name: String) -> void:
	_layers.set_visible(layer_name, shown)
	_mark_dirty()


func _set_layer(layer_name: String, shown: bool) -> void:
	if _layer_buttons.has(layer_name):
		(_layer_buttons[layer_name] as CheckButton).set_pressed_no_signal(shown)
	_mark_dirty()


func get_debug_stats() -> Dictionary:
	var weather_stats := _renderer.weather_adapter.get_debug_stats() as Dictionary
	return {
		"draw_usec": _last_draw_usec,
		"draw_count": _draw_count,
		"weather_cache_cells": weather_stats.get("cache_cells", 0),
		"weather_cache_rebuilds": weather_stats.get("cache_rebuilds", 0),
		"preset": ChartLayerManagerClass.PRESET_NAMES[_layers.preset],
	}


func _capture_nav() -> void:
	_nav = ChartNavSnapshotClass.capture(get_tree())
	if not _route_waypoints.is_empty():
		_nav.set_waypoint(_route_waypoints[0])


func _clear_route() -> void:
	_route_waypoints.clear()
	_capture_nav()
	_mark_dirty()


func _screen_to_world(screen: Vector2) -> Vector3:
	var chart := _chart_rect()
	var bounds := _camera.world_bounds(chart.size)
	var uv := (screen - chart.position) / chart.size
	return Vector3(
		lerpf(bounds.position.x, bounds.end.x, uv.x),
		0.0,
		lerpf(bounds.end.y, bounds.position.y, uv.y),
	)


func _home() -> void:
	var points: Array[Vector3] = []
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry != null:
		for pid in registry.call("get_port_ids"):
			var pos := registry.call("get_port_position", str(pid)) as Vector3
			if pos.is_finite():
				points.append(pos)
	_camera.home(_nav.ship_position, points)
	_mark_dirty()


func _select_port(screen_position: Vector2) -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null or _last_ctx.is_empty():
		return
	for pid_raw in registry.call("get_port_ids"):
		var pid := str(pid_raw)
		var info := registry.call("get_port_info", pid) as Dictionary
		var pos := info.get("position", Vector3(INF, INF, INF)) as Vector3
		if not pos.is_finite():
			continue
		var polygon := _renderer.screen_polygon(pid, pos, info, _last_ctx)
		if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(screen_position, polygon):
			_selected_port = "" if _selected_port == pid else pid
			_mark_dirty()
			return
	_selected_port = ""
	_mark_dirty()


func _draw_status(panel: Rect2) -> void:
	var status_y := panel.end.y - 13.0
	var values: Array[String] = [
		"HDG %s" % _degrees(_nav.heading_deg if _nav.has_ship() else NAN),
		"COG %s" % _degrees(_nav.course_deg),
		"SOG %.1f kt" % _nav.speed_knots,
		"BRG %s" % _degrees(_nav.bearing_deg),
		"LEE %s" % _signed_degrees(_nav.leeway_deg),
		"WIND %s %.1f kt" % [_degrees(_nav.wind_direction_deg), _nav.wind_speed_knots],
		"FUEL %s" % ("%.0f%%" % (_nav.fuel_fraction * 100.0) if is_finite(_nav.fuel_fraction) else "—"),
		"TIME %s" % _nav.time_label,
		"SCALE %s" % _distance(_camera.span),
	]
	draw_string(
		ThemeDB.fallback_font, Vector2(panel.position.x + 14.0, status_y),
		"    ".join(values), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.76, 0.86, 0.94, 0.92)
	)


func _draw_compass(center: Vector2) -> void:
	draw_circle(center, 25.0, Color(0.03, 0.05, 0.14, 0.88))
	draw_arc(center, 24.0, 0.0, TAU, 32, Color(0.48, 0.62, 0.82, 0.62), 1.0)
	draw_line(center, center + Vector2(0.0, -19.0), Color(0.96, 0.30, 0.25), 2.0)
	draw_string(
		ThemeDB.fallback_font, center + Vector2(-4.0, -7.0), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.96, 0.86, 0.12)
	)


func _chart_rect() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(
		Vector2(MARGIN + 14.0, MARGIN + HEADER_H),
		Vector2(
			maxf(size.x - (MARGIN + 14.0) * 2.0, 1.0),
			maxf(size.y - MARGIN * 2.0 - HEADER_H - STATUS_H, 1.0)
		)
	)


func _mark_dirty() -> void:
	_redraw_elapsed = REDRAW_INTERVAL_S
	queue_redraw()


static func _degrees(value: float) -> String:
	return "%03d°" % int(round(value)) if is_finite(value) else "—"


static func _signed_degrees(value: float) -> String:
	return "%+.1f°" % value if is_finite(value) else "—"


static func _distance(metres: float) -> String:
	return "%.0f m" % metres if metres < 1852.0 else "%.1f nm" % (metres / 1852.0)
