class_name FleetRouteMapPicker
extends MapOverlay

## Sea chart for picking a fleet route destination port.
## Home port is fixed by the company office — click another island to set destination.

signal destination_picked(port_id: String)
signal pick_cancelled()

var _home_port_id: String = ""


func _ready() -> void:
	super._ready()
	visible = false
	_show_weather = false
	_show_fishing = false


func open_picker(home_port_id: String, current_destination: String = "") -> void:
	_home_port_id = home_port_id
	_selected_port = current_destination
	_user_moved = false
	_center_on_home()
	visible = true
	queue_redraw()


func hide_picker() -> void:
	visible = false
	_home_port_id = ""
	_selected_port = ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		hide_picker()
		pick_cancelled.emit()
		get_viewport().set_input_as_handled()
		return
	super._input(event)


func _try_select(screen_pos: Vector2) -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	for pid in registry.get_port_ids():
		var port_id := str(pid)
		if port_id == _home_port_id:
			continue
		var info := registry.get_port_info(port_id) as Dictionary
		if info.is_empty():
			continue
		var wpos := info.get("position", Vector3(INF, INF, INF)) as Vector3
		if wpos.x == INF:
			continue
		var spoly := _to_screen_poly(port_id, wpos, info)
		if spoly.size() >= 3 and Geometry2D.is_point_in_polygon(screen_pos, spoly):
			_selected_port = port_id
			destination_picked.emit(port_id)
			hide_picker()
			return


func _draw() -> void:
	super._draw()
	if not visible or _home_port_id.is_empty():
		return
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(_cpx + 8.0, _cpy + 18.0),
		"Click a port on the chart to set destination",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		C_TITLE,
	)
	draw_string(
		font,
		Vector2(_cpx + 8.0, _cpy + 34.0),
		"Home port is fixed at this harbour",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		C_HINT,
	)
	_draw_home_marker(registry)
	_draw_route_preview(registry)


func _draw_home_marker(registry: Node) -> void:
	var info := registry.get_port_info(_home_port_id) as Dictionary
	if info.is_empty():
		return
	var wpos := info.get("position", Vector3(INF, INF, INF)) as Vector3
	if wpos.x == INF:
		return
	var spoly := _to_screen_poly(_home_port_id, wpos, info)
	if spoly.size() < 3:
		return
	var outline := PackedVector2Array(spoly)
	outline.append(spoly[0])
	draw_polyline(outline, Color(0.35, 0.85, 0.95, 0.95), 3.0, true)
	var sp := _w2s(wpos)
	draw_circle(sp, 6.0, Color(0.35, 0.85, 0.95, 0.85))


func _draw_route_preview(registry: Node) -> void:
	if _selected_port.is_empty() or _selected_port == _home_port_id:
		return
	var home_pos := registry.get_port_position(_home_port_id) as Vector3
	var dest_pos := registry.get_port_position(_selected_port) as Vector3
	if home_pos.x == INF or dest_pos.x == INF:
		return
	var a := _w2s(home_pos)
	var b := _w2s(dest_pos)
	draw_line(a, b, Color(0.96, 0.86, 0.12, 0.55), 2.0, true)


func _center_on_home() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null or _home_port_id.is_empty():
		return
	var wpos := registry.get_port_position(_home_port_id) as Vector3
	if wpos.x == INF:
		return
	_cam_center = Vector2(wpos.x, wpos.z)
	_cam_span = 14000.0
	_user_moved = true
