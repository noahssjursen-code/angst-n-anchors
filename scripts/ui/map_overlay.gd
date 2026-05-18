class_name MapOverlay
extends Control

## Procedural sea chart drawn via _draw().
## Axis convention matches `NavigationAxes`: north-up ⇒ world −Z, east ⇒ +X.
## Supports scroll-wheel zoom, left-drag pan, and click-to-select ports.

const MARGIN    := 60.0
const CHART_PAD := 52.0

const ZOOM_IN  := 0.82
const ZOOM_OUT := 1.0 / 0.82
const SPAN_MIN := 300.0
const SPAN_MAX := 500000.0

const C_SEA          := Color(0.03, 0.04, 0.10, 0.97)
const C_BORDER       := Color(0.30, 0.44, 0.68, 0.80)
const C_GRID         := Color(0.18, 0.26, 0.44, 0.18)
const C_ISLAND       := Color(0.22, 0.30, 0.20, 0.90)
const C_ISLAND_SEL   := Color(0.34, 0.48, 0.28, 1.00)
const C_ISLAND_DEST  := Color(0.32, 0.28, 0.12, 0.90)
const C_EDGE         := Color(0.38, 0.52, 0.32, 0.70)
const C_EDGE_SEL     := Color(0.60, 0.80, 0.50, 1.00)
const C_EDGE_DEST    := Color(0.80, 0.60, 0.20, 0.85)
const C_PORT_LABEL   := Color(0.70, 0.84, 0.60, 0.90)
const C_PORT_LBL_SEL := Color(0.90, 1.00, 0.82, 1.00)
const C_SHIP         := Color(0.96, 0.86, 0.12, 1.00)
const C_TITLE        := Color(0.96, 0.86, 0.12, 0.92)
const C_HINT         := Color(0.40, 0.50, 0.66, 0.55)

var _cam_center:         Vector2 = Vector2.ZERO
var _cam_span:           float   = 10000.0
var _user_moved:         bool    = false
var _dragging:           bool    = false
var _drag_origin_mouse:  Vector2 = Vector2.ZERO
var _drag_origin_center: Vector2 = Vector2.ZERO
var _drag_dist:          float   = 0.0
var _was_visible:        bool    = false
var _selected_port:      String  = ""
var _poly_cache:         Dictionary = {}  ## port_id -> PackedVector2Array local XZ
var _show_weather:       bool       = true

## Set each frame in _draw; used by _try_select without re-computing.
var _cpx: float = 0.0
var _cpy: float = 0.0
var _cpw: float = 0.0
var _cph: float = 0.0
var _wx_min: float = 0.0
var _wx_max: float = 1.0
var _wz_min: float = 0.0
var _wz_max: float = 1.0

## Port size → short class label for display
const SIZE_CLASS_LABEL: Array[String] = [
	"Coastal", "Coastal", "Short Sea", "Handysize", "Deep Sea"
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	if visible:
		if not _was_visible:
			if not _user_moved:
				_reset_view()
			_was_visible = true
		queue_redraw()
	else:
		_was_visible = false
		_dragging    = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_H:
				_user_moved = false
				_reset_view()
				get_viewport().set_input_as_handled()
				return
			if ke.keycode == KEY_F:
				_show_weather = not _show_weather
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_span   = maxf(_cam_span * ZOOM_IN, SPAN_MIN)
			_user_moved = true
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_span   = minf(_cam_span * ZOOM_OUT, SPAN_MAX)
			_user_moved = true
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging            = true
				_drag_dist           = 0.0
				_drag_origin_mouse   = mb.position
				_drag_origin_center  = _cam_center
			else:
				_dragging = false
				if _drag_dist < 5.0:
					_try_select(mb.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover_pos = mm.position
		_hover_inside = (
			mm.position.x >= _cpx and mm.position.x <= _cpx + _cpw
			and mm.position.y >= _cpy and mm.position.y <= _cpy + _cph
		)
		if _dragging:
			var ppu := _ppu()
			var dm  := mm.position - _drag_origin_mouse
			_drag_dist    += mm.relative.length()
			_cam_center.x  = _drag_origin_center.x - dm.x / ppu
			_cam_center.y  = _drag_origin_center.y - dm.y / ppu
			_user_moved    = true
			get_viewport().set_input_as_handled()


func _try_select(screen_pos: Vector2) -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	for pid in registry.get_port_ids():
		var info := registry.get_port_info(str(pid)) as Dictionary
		if info.is_empty():
			continue
		var wpos := info.get("position", Vector3(INF, INF, INF)) as Vector3
		if wpos.x == INF:
			continue
		var spoly := _to_screen_poly(str(pid), wpos, info)
		if spoly.size() >= 3 and Geometry2D.is_point_in_polygon(screen_pos, spoly):
			_selected_port = "" if _selected_port == str(pid) else str(pid)
			return
	_selected_port = ""


func _to_screen_poly(pid: String, wpos: Vector3, info: Dictionary) -> PackedVector2Array:
	if not _poly_cache.has(pid):
		var iw := float(info.get("island_width", 80.0))
		var pd := float(info.get("plot_depth",   140.0))
		var ls := int(info.get("layout_seed",    0))
		_poly_cache[pid] = IslandMeshBuilder.build_polygon(iw, pd, ls)
	var local_poly := _poly_cache[pid] as PackedVector2Array
	var ry := float(info.get("rotation_y", 0.0))
	var cy := cos(ry)
	var sy := sin(ry)
	var out := PackedVector2Array()
	for p in local_poly:
		var rx := p.x * cy + p.y * sy
		var rz := -p.x * sy + p.y * cy
		out.append(_w2s_f(wpos.x + rx, wpos.z + rz))
	return out


# ── Camera helpers ────────────────────────────────────────────────────────────

func _ppu() -> float:
	var vp  := get_viewport_rect().size
	var cpw := vp.x - MARGIN * 2.0 - CHART_PAD * 2.0
	var cph := vp.y - MARGIN * 2.0 - CHART_PAD * 2.0 - 10.0
	return minf(cpw, cph) / _cam_span


func _reset_view() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	var all_x: Array[float] = []
	var all_z: Array[float] = []

	if registry != null:
		for pid in registry.get_port_ids():
			var wpos: Vector3 = registry.get_port_position(str(pid))
			if wpos.x != INF:
				all_x.append(wpos.x)
				all_z.append(wpos.z)

	var ship_pos := Vector3(INF, INF, INF)
	for n in get_tree().get_nodes_in_group("player_boat"):
		var rb := n as RigidBody3D
		if rb != null:
			ship_pos = rb.global_position
			break

	if ship_pos.x != INF:
		_cam_center = Vector2(ship_pos.x, ship_pos.z)
		all_x.append(ship_pos.x)
		all_z.append(ship_pos.z)
	elif not all_x.is_empty():
		_cam_center = Vector2(
			(all_x.min() + all_x.max()) * 0.5,
			(all_z.min() + all_z.max()) * 0.5
		)

	if not all_x.is_empty():
		var dx := maxf(all_x.max() - all_x.min(), 200.0)
		var dz := maxf(all_z.max() - all_z.min(), 200.0)
		_cam_span = maxf(dx, dz) * 1.6
	else:
		_cam_span = 10000.0


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var vp   := get_viewport_rect().size
	var font := ThemeDB.fallback_font

	# Outer panel
	var px := MARGIN
	var py := MARGIN
	var pw := vp.x - MARGIN * 2.0
	var ph := vp.y - MARGIN * 2.0

	draw_rect(Rect2(px, py, pw, ph), C_SEA)
	draw_rect(Rect2(px, py, pw, ph), C_BORDER, false, 2.0)
	draw_rect(Rect2(px + 6, py + 6, pw - 12, ph - 12),
			  Color(0.20, 0.30, 0.52, 0.20), false, 1.0)

	# Title
	var title    := "SEA CHART"
	var title_fs := 20
	var ttw      := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs).x
	draw_string(font, Vector2(vp.x * 0.5 - ttw * 0.5, py + 38.0),
				title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs, C_TITLE)

	var hint    := "scroll  zoom    drag  pan    H  home    F  weather    M  close    click island  info"
	var hint_tw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(px + pw - hint_tw - 14, py + 32.0),
				hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_HINT)

	draw_line(Vector2(px + 16, py + 46), Vector2(px + pw - 16, py + 46),
			  Color(0.28, 0.40, 0.64, 0.35), 1.0)

	# Chart bounds (store for _try_select)
	_cpx = px + CHART_PAD
	_cpy = py + CHART_PAD + 10.0
	_cpw = pw - CHART_PAD * 2.0
	_cph = ph - CHART_PAD * 2.0 - 10.0

	# World extents from camera
	var ppu := _ppu()
	_wx_min = _cam_center.x - _cpw * 0.5 / ppu
	_wx_max = _cam_center.x + _cpw * 0.5 / ppu
	_wz_min = _cam_center.y - _cph * 0.5 / ppu
	_wz_max = _cam_center.y + _cph * 0.5 / ppu

	var registry := get_node_or_null("/root/ContractRegistry")
	var accepted: Array[Contract] = []
	var dest_ids: Dictionary      = {}

	if registry != null:
		accepted = registry.get_accepted_contracts()
		for c in accepted:
			dest_ids[c.destination_port_id] = true

	var ship_pos:    Vector3 = Vector3(INF, INF, INF)
	var ship_bow_hz := Vector2(0.0, -1.0)
	for n in get_tree().get_nodes_in_group("player_boat"):
		var rb := n as RigidBody3D
		if rb != null:
			ship_pos    = rb.global_position
			ship_bow_hz = NavigationAxes.vessel_bow_horizontal(rb)
			break

	# Grid interval
	var raw_interval := _cam_span / 6.0
	var nice_steps: Array[float] = [
		100.0, 200.0, 500.0, 1000.0,
		1852.0, 3704.0, 9260.0, 18520.0, 37040.0
	]
	var grid_interval := nice_steps[nice_steps.size() - 1]
	for s in nice_steps:
		if s >= raw_interval:
			grid_interval = s
			break

	# Grid
	var gx: float = floor(_wx_min / grid_interval) * grid_interval
	while gx <= _wx_max:
		var sx: float = _cpx + (gx - _wx_min) / (_wx_max - _wx_min) * _cpw
		if sx >= _cpx - 1.0 and sx <= _cpx + _cpw + 1.0:
			draw_line(Vector2(sx, _cpy), Vector2(sx, _cpy + _cph), C_GRID, 1.0)
		gx += grid_interval

	var gz: float = floor(_wz_min / grid_interval) * grid_interval
	while gz <= _wz_max:
		var sy: float = _cpy + (gz - _wz_min) / (_wz_max - _wz_min) * _cph
		if sy >= _cpy - 1.0 and sy <= _cpy + _cph + 1.0:
			draw_line(Vector2(_cpx, sy), Vector2(_cpx + _cpw, sy), C_GRID, 1.0)
		gz += grid_interval

	# Weather zones
	if _show_weather:
		_draw_weather_zones()

	# Contract routes
	if registry != null:
		for c in accepted:
			var op: Vector3 = registry.get_port_position(c.origin_port_id)
			var dp: Vector3 = registry.get_port_position(c.destination_port_id)
			if op.x == INF or dp.x == INF:
				continue
			var op2 := _w2s(op)
			var dp2 := _w2s(dp)
			_draw_dashed_line(op2, dp2, Color(1.0, 0.58, 0.06, 0.28), 1.5, 10.0)
			# Distance label at midpoint
			var mid      := (op2 + dp2) * 0.5
			var route_d  := op.distance_to(dp)
			var route_lbl := "%.0f m" % route_d if route_d < 1852.0 else "%.1f nm" % (route_d / 1852.0)
			var rtw      := font.get_string_size(route_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(font, mid + Vector2(-rtw * 0.5, -4.0),
						route_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 0.65, 0.15, 0.65))

	# Islands
	if registry != null:
		for pid in registry.get_port_ids():
			var info := registry.get_port_info(str(pid)) as Dictionary
			if info.is_empty():
				continue
			var wpos := info.get("position", Vector3(INF, INF, INF)) as Vector3
			if wpos.x == INF:
				continue

			var is_sel  := _selected_port == str(pid)
			var is_dest := dest_ids.has(str(pid))

			var spoly := _to_screen_poly(str(pid), wpos, info)
			if spoly.size() < 3:
				continue

			var fill_col: Color
			var edge_col: Color
			if is_sel:
				fill_col = C_ISLAND_SEL
				edge_col = C_EDGE_SEL
			elif is_dest:
				fill_col = C_ISLAND_DEST
				edge_col = C_EDGE_DEST
			else:
				fill_col = C_ISLAND
				edge_col = C_EDGE

			draw_colored_polygon(spoly, fill_col)
			var outline := PackedVector2Array(spoly)
			outline.append(spoly[0])
			draw_polyline(outline, edge_col, 1.5, true)

			# Only draw label when island is large enough on screen to read
			var poly_h := _poly_screen_height(spoly)
			if poly_h >= 10.0 or is_sel or is_dest:
				var sp       := _w2s(wpos)
				var pname    := str(info.get("display_name", ""))
				var lbl_size := 13 if is_sel else 11
				var ntw      := font.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_size).x
				var lbl_col  := C_PORT_LBL_SEL if is_sel else C_PORT_LABEL
				draw_string(font, sp + Vector2(-ntw * 0.5, -poly_h * 0.5 - 6.0),
							pname, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl_size, lbl_col)

	# Ship (bow projected to horizontal so chart agrees with helm after wave roll/pitch).
	if ship_pos.x != INF:
		var sp := _w2s(ship_pos)
		var fwd := ship_bow_hz
		if fwd.length_squared() < 1e-10:
			fwd = Vector2(0.0, -1.0)
		else:
			fwd = fwd.normalized()
		var perp := Vector2(-fwd.y, fwd.x)
		var sz   := 11.0
		draw_circle(sp, sz + 4.0, Color(C_SHIP.r, C_SHIP.g, C_SHIP.b, 0.20))
		draw_colored_polygon(PackedVector2Array([
			sp + fwd  * sz,
			sp - fwd  * sz * 0.5 + perp * sz * 0.5,
			sp - fwd  * sz * 0.5 - perp * sz * 0.5,
		]), C_SHIP)

	# Port info panel
	if not _selected_port.is_empty() and registry != null:
		_draw_port_panel(font, registry)

	# Compass rose — top-right inside chart
	_draw_compass_rose(Vector2(_cpx + _cpw - 48.0, _cpy + 50.0), 28.0)

	# Scale bar
	var scale_w_world := (_wx_max - _wx_min) * 0.2
	var scale_w_px    := scale_w_world / (_wx_max - _wx_min) * _cpw
	var bx := _cpx
	var by := _cpy + _cph + 18.0
	draw_line(Vector2(bx, by),                  Vector2(bx + scale_w_px, by),         Color(0.55, 0.68, 0.86, 0.70), 2.0)
	draw_line(Vector2(bx, by - 4),              Vector2(bx, by + 4),                  Color(0.55, 0.68, 0.86, 0.70), 1.5)
	draw_line(Vector2(bx + scale_w_px, by - 4), Vector2(bx + scale_w_px, by + 4),     Color(0.55, 0.68, 0.86, 0.70), 1.5)

	var scale_label := "%.0f m" % scale_w_world if scale_w_world < 1852.0 else "%.1f nm" % (scale_w_world / 1852.0)
	draw_string(font, Vector2(bx, by + 14), scale_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.58, 0.76, 0.60))

	var grid_label := "grid  %.0f m" % grid_interval if grid_interval < 1852.0 else "grid  %.0f nm" % (grid_interval / 1852.0)
	draw_string(font, Vector2(bx, by + 26), grid_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.48, 0.66, 0.45))


func _draw_port_panel(font: Font, registry: Node) -> void:
	var info := registry.get_port_info(_selected_port) as Dictionary
	if info.is_empty():
		return

	var pop         := int(info.get("population", 0))
	var exports     := str(info.get("commodity_export", ""))
	var imports     := info.get("commodity_imports", []) as Array
	var berths      := int(info.get("berth_count", 1))
	var port_size   := int(info.get("size", 1))
	var class_label := SIZE_CLASS_LABEL[clampi(port_size, 0, SIZE_CLASS_LABEL.size() - 1)]

	# Filter the feature pool to only things that are actually in-game.
	const IMPLEMENTED_FEATURES: Array[String] = [
		"Fuel Dock", "Lighthouse", "Fog Horn", "Harbour Master",
	]
	var raw_features := info.get("features", []) as Array
	var facilities: Array[String] = []
	for f in raw_features:
		if IMPLEMENTED_FEATURES.has(str(f)):
			facilities.append(str(f))

	var contracts := registry.get_contracts_from_port(_selected_port) as Array
	var avail     := 0
	for c in contracts:
		if (c as Contract).state == Contract.State.AVAILABLE:
			avail += 1

	var wpos     := info.get("position", Vector3.ZERO) as Vector3
	var ship_pos := Vector3(INF, INF, INF)
	for n in get_tree().get_nodes_in_group("player_boat"):
		var rb := n as RigidBody3D
		if rb != null:
			ship_pos = rb.global_position
			break

	var lh    := 18.0
	var lh_sm := 16.0
	var pad   := 12.0

	var panel_w := 264.0
	var panel_h := (pad
		+ 18.0    # port name
		+ 4.0
		+ lh      # pop + berths
		+ 8.0
		+ lh      # exports
		+ lh      # imports
		+ 8.0
		+ lh_sm   # facilities line (always shown)
		+ 8.0
		+ lh      # contracts + distance
		+ pad)

	var panel_x := _cpx + _cpw - panel_w - 8.0
	var panel_y := _cpy + _cph - panel_h - 8.0

	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.04, 0.07, 0.16, 0.95))
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), C_EDGE_SEL, false, 1.5)

	var tx := panel_x + pad
	var ty := panel_y + pad + 14.0

	# Port name + class badge
	draw_string(font, Vector2(tx, ty),
				str(info.get("display_name", "")).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_PORT_LBL_SEL)
	var nw := font.get_string_size(str(info.get("display_name", "")).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(tx + nw, ty),
				"  [%s]" % class_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.50, 0.65, 0.48, 0.70))
	ty += 4.0 + lh

	# Pop + berths
	draw_string(font, Vector2(tx, ty),
				"~%s  ·  %d berth%s" % [_format_population(pop), berths, "s" if berths != 1 else ""],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.75, 0.60, 0.75))
	ty += lh + 8.0

	draw_line(Vector2(panel_x + 8, ty - 4), Vector2(panel_x + panel_w - 8, ty - 4),
			  Color(0.38, 0.52, 0.32, 0.30), 1.0)

	# Exports
	draw_string(font, Vector2(tx, ty),
				"Exports   " + (exports.capitalize() if not exports.is_empty() else "—"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.62, 0.80, 0.55, 0.90))
	ty += lh

	# Imports
	var imp_parts: Array[String] = []
	for s in imports:
		imp_parts.append(str(s).capitalize())
	draw_string(font, Vector2(tx, ty),
				"Imports   " + (", ".join(imp_parts) if not imp_parts.is_empty() else "—"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.72, 0.50, 0.75))
	ty += lh + 8.0

	draw_line(Vector2(panel_x + 8, ty - 4), Vector2(panel_x + panel_w - 8, ty - 4),
			  Color(0.38, 0.52, 0.32, 0.30), 1.0)

	# Facilities — only implemented ones, joined on one line
	var fac_label := "  ·  ".join(facilities) if not facilities.is_empty() else "—"
	draw_string(font, Vector2(tx, ty),
				fac_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.58, 0.72, 0.52, 0.80))
	ty += lh_sm + 8.0

	draw_line(Vector2(panel_x + 8, ty - 4), Vector2(panel_x + panel_w - 8, ty - 4),
			  Color(0.38, 0.52, 0.32, 0.30), 1.0)

	# Contracts + distance
	draw_string(font, Vector2(tx, ty),
				"%d contract%s" % [avail, "s" if avail != 1 else ""],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.82, 0.58, 0.80))

	if ship_pos.x != INF:
		var dist     := Vector2(wpos.x, wpos.z).distance_to(Vector2(ship_pos.x, ship_pos.z))
		var dist_str := "%.0f m" % dist if dist < 1852.0 else "%.1f nm" % (dist / 1852.0)
		var dtw      := font.get_string_size(dist_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(panel_x + panel_w - pad - dtw, ty),
					dist_str,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.50, 0.65, 0.78, 0.80))


func _format_population(pop: int) -> String:
	if pop >= 10000:
		return "%dk" % (pop / 1000)
	if pop >= 1000:
		return "%.1fk" % (float(pop) / 1000.0)
	return str(pop)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _w2s(world: Vector3) -> Vector2:
	return _w2s_f(world.x, world.z)


func _w2s_f(wx: float, wz: float) -> Vector2:
	var tx := (wx - _wx_min) / (_wx_max - _wx_min)
	var tz := (wz - _wz_min) / (_wz_max - _wz_min)
	return Vector2(_cpx + tx * _cpw, _cpy + tz * _cph)


func _poly_screen_height(poly: PackedVector2Array) -> float:
	if poly.is_empty():
		return 0.0
	var mn := poly[0].y
	var mx := poly[0].y
	for p in poly:
		mn = minf(mn, p.y)
		mx = maxf(mx, p.y)
	return mx - mn


func _draw_compass_rose(center: Vector2, r: float) -> void:
	var font := ThemeDB.fallback_font
	draw_circle(center, r + 5.0, Color(0.03, 0.05, 0.14, 0.88))
	draw_arc(center, r + 3.0, 0.0, TAU, 48, Color(0.28, 0.42, 0.66, 0.55), 1.5, true)

	# Intercardinal ticks
	for d in [45, 135, 225, 315]:
		var a := deg_to_rad(float(d)) - PI * 0.5
		draw_line(center + Vector2(cos(a), sin(a)) * r * 0.78,
				  center + Vector2(cos(a), sin(a)) * r,
				  Color(0.35, 0.46, 0.62, 0.38), 1.0, true)

	# Cardinals: N red, E/S/W pale blue
	var cdata: Array = [
		["N", 0,   Color(0.95, 0.28, 0.28, 1.00), true ],
		["E", 90,  Color(0.68, 0.80, 0.92, 0.80), false],
		["S", 180, Color(0.68, 0.80, 0.92, 0.80), false],
		["W", 270, Color(0.68, 0.80, 0.92, 0.80), false],
	]
	for entry in cdata:
		var e    := entry as Array
		var a    := deg_to_rad(float(int(e[1]))) - PI * 0.5
		var col  := e[2] as Color
		var bold := bool(e[3])
		var inner := r * (0.52 if bold else 0.68)
		draw_line(center + Vector2(cos(a), sin(a)) * inner,
				  center + Vector2(cos(a), sin(a)) * r,
				  col, 2.5 if bold else 1.5, true)
		var lp   := center + Vector2(cos(a), sin(a)) * (r - 17.0)
		var lstr := str(e[0])
		var tw   := font.get_string_size(lstr, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, lp + Vector2(-tw * 0.5, 5.0), lstr,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)

	# North pointer (gold up-triangle) and south pointer (dim down-triangle)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0,   -r * 0.53),
		center + Vector2(-r * 0.12, -r * 0.08),
		center + Vector2( r * 0.12, -r * 0.08),
	]), Color(0.96, 0.86, 0.12, 0.92))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0,    r * 0.53),
		center + Vector2(-r * 0.12,  r * 0.08),
		center + Vector2( r * 0.12,  r * 0.08),
	]), Color(0.42, 0.52, 0.68, 0.42))
	draw_circle(center, 3.5, Color(0.82, 0.88, 1.00, 0.72))


## Live weather chart: pressure heatmap + wind barbs + L/H markers + season.
## Driven by `WeatherField.sample()` — no extra state, sampled fresh each
## frame but on a coarse, world-anchored grid so the chart is cheap, readable
## at any zoom, and doesn't slide around as you pan.
##
## Grid model:
##   • cells are sized in WORLD metres, not screen pixels — minimum
##     `WX_MIN_CELL_M`, large enough that fine zoom doesn't sample the same
##     noise feature dozens of times
##   • cells snap to a world-space lattice so wind arrows stay anchored to
##     the world while you pan, instead of sliding under the cursor
##   • the visible grid is capped at `WX_MAX_CELLS` in either axis so
##     extreme zoom-out can't explode the sample count
##   • each cell averages 4 sub-samples so reported wind / pressure is the
##     "area average", not a single noisy point
const WX_MIN_CELL_M     : float = 2500.0  ## smallest cell side in world metres
const WX_MAX_CELLS_X    : int   = 32
const WX_MAX_CELLS_Y    : int   = 22
const WX_SUBSAMPLES     : int   = 1       ## NxN sub-samples averaged per cell — field is already smooth at this scale
const WX_PRESSURE_LO    : float = 990.0   ## hPa mapped to deep red
const WX_PRESSURE_HI    : float = 1030.0  ## hPa mapped to deep blue

## Throttle weather grid recomputation — pressure shifts over minutes of game
## time, no point re-rasterising 60×/s. We re-sample whenever the cached grid
## is stale by more than this many game-hours OR the view has scrolled/zoomed.
const WX_CACHE_MAX_AGE_GAME_H : float = 0.05    # ≈ 3s real-time at 1min/h

var _wx_cache_time_h : float = -1.0
var _wx_cache_wx0    : float = 0.0
var _wx_cache_wz0    : float = 0.0
var _wx_cache_cell_m : float = 0.0
var _wx_cache_cols   : int   = 0
var _wx_cache_rows   : int   = 0
var _wx_cache_pressure : PackedFloat32Array = PackedFloat32Array()
var _wx_cache_wind_x   : PackedFloat32Array = PackedFloat32Array()
var _wx_cache_wind_z   : PackedFloat32Array = PackedFloat32Array()

## Last cursor position over the chart (for the hover-inspect tooltip).
## Tracked in _input so we don't depend on get_local_mouse_position() during _draw.
var _hover_pos        : Vector2 = Vector2(-1.0, -1.0)
var _hover_inside     : bool    = false


func _draw_weather_zones() -> void:
	if not WorldWeather.is_initialized():
		return
	var time_h := WeatherField.current_game_time()
	var g := _weather_grid()
	_ensure_weather_cache(time_h, g)
	_draw_weather_pressure_field(g)
	_draw_weather_wind_field(g)
	_draw_weather_extrema(g)
	_draw_weather_legend()
	_draw_weather_season_banner(time_h)
	if _hover_inside:
		_draw_weather_hover(time_h, g)


## Single pass over the grid that fills the pressure / wind caches. Reused
## across all three draw passes — collapses ~3× redundant noise work into 1.
func _ensure_weather_cache(time_h: float, g: Dictionary) -> void:
	var cell_m : float = g["cell_m"]
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	var wx0    : float = g["wx0"]
	var wz0    : float = g["wz0"]
	# Reuse last frame's samples if view + time both barely moved.
	var view_unchanged := (
		_wx_cache_cell_m == cell_m
		and _wx_cache_cols == cols
		and _wx_cache_rows == rows
		and is_equal_approx(_wx_cache_wx0, wx0)
		and is_equal_approx(_wx_cache_wz0, wz0)
	)
	var time_fresh := view_unchanged and absf(time_h - _wx_cache_time_h) < WX_CACHE_MAX_AGE_GAME_H
	if time_fresh:
		return
	_wx_cache_time_h = time_h
	_wx_cache_wx0    = wx0
	_wx_cache_wz0    = wz0
	_wx_cache_cell_m = cell_m
	_wx_cache_cols   = cols
	_wx_cache_rows   = rows
	var n := cols * rows
	_wx_cache_pressure.resize(n)
	_wx_cache_wind_x.resize(n)
	_wx_cache_wind_z.resize(n)
	for j in range(rows):
		var wz : float = wz0 + (float(j) + 0.5) * cell_m
		for i in range(cols):
			var wx : float = wx0 + (float(i) + 0.5) * cell_m
			var s := _cell_avg_sample(time_h, wx0 + float(i) * cell_m, wz0 + float(j) * cell_m, cell_m)
			var idx := j * cols + i
			_wx_cache_pressure[idx] = float(s["pressure"])
			var w : Vector3 = s["wind"]
			_wx_cache_wind_x[idx] = w.x
			_wx_cache_wind_z[idx] = w.z


## Build the shared world-anchored grid description used by all three weather
## passes — single source of truth so pressure cells, wind arrows, and L/H
## markers all line up exactly.
##
## Returns a Dictionary:
##   cell_m   : float          world metres per cell side
##   cols/rows: int            number of cells in view (incl. partial)
##   wx0/wz0  : float          world coord of cell (0,0)'s south-west corner
##   ppu_x    : float          screen pixels per world metre, X
##   ppu_z    : float          screen pixels per world metre, Z (north-up flip)
func _weather_grid() -> Dictionary:
	var span_x := _wx_max - _wx_min
	var span_z := _wz_max - _wz_min
	# Pick cell size: at least WX_MIN_CELL_M, but grow it if the view is so
	# wide that we'd otherwise exceed WX_MAX_CELLS.
	var cell_m := maxf(WX_MIN_CELL_M,
						maxf(span_x / float(WX_MAX_CELLS_X),
							 span_z / float(WX_MAX_CELLS_Y)))
	# Snap origin to the world-space lattice. Cells stay anchored when panning.
	var wx0  : float = floorf(_wx_min / cell_m) * cell_m
	var wz0  : float = floorf(_wz_min / cell_m) * cell_m
	var cols : int   = int(ceilf((_wx_max - wx0) / cell_m))
	var rows : int   = int(ceilf((_wz_max - wz0) / cell_m))
	cols = clampi(cols, 1, WX_MAX_CELLS_X + 2)
	rows = clampi(rows, 1, WX_MAX_CELLS_Y + 2)
	return {
		"cell_m": cell_m,
		"cols":   cols,
		"rows":   rows,
		"wx0":    wx0,
		"wz0":    wz0,
		"ppu_x":  _cpw / span_x,
		"ppu_z":  _cph / span_z,
	}


## World → screen for the weather grid (matches _w2s_f but precomputed).
func _wx_to_sx(wx: float, g: Dictionary) -> float:
	return _cpx + (wx - _wx_min) * float(g["ppu_x"])

func _wz_to_sy(wz: float, g: Dictionary) -> float:
	return _cpy + (wz - _wz_min) * float(g["ppu_z"])


## Area-averaged WeatherSample at a cell origin. Sub-sampling smooths out the
## last bit of noise so two adjacent cells look continuous, not stippled.
func _cell_avg_sample(time_h: float, wx0: float, wz0: float, cell_m: float) -> Dictionary:
	var step := cell_m / float(WX_SUBSAMPLES)
	var p_sum := 0.0
	var w_sum := Vector3.ZERO
	for j in range(WX_SUBSAMPLES):
		var wz := wz0 + (float(j) + 0.5) * step
		for i in range(WX_SUBSAMPLES):
			var wx := wx0 + (float(i) + 0.5) * step
			p_sum += WeatherField.pressure_at(Vector3(wx, 0.0, wz), time_h)
			w_sum += WeatherField.sample_wind(Vector3(wx, 0.0, wz), time_h)
	var n := float(WX_SUBSAMPLES * WX_SUBSAMPLES)
	return {"pressure": p_sum / n, "wind": w_sum / n}


func _draw_weather_pressure_field(g: Dictionary) -> void:
	var cell_m : float = g["cell_m"]
	var cell_w : float = cell_m * float(g["ppu_x"])
	var cell_h : float = cell_m * float(g["ppu_z"])
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	for j in range(rows):
		var wz0 : float = g["wz0"] + float(j) * cell_m
		var sy  : float = _wz_to_sy(wz0, g)
		for i in range(cols):
			var wx0 : float = g["wx0"] + float(i) * cell_m
			var sx  : float = _wx_to_sx(wx0, g)
			draw_rect(Rect2(sx, sy, cell_w + 1.0, cell_h + 1.0),
					   _pressure_color(_wx_cache_pressure[j * cols + i]), true)


func _draw_weather_wind_field(g: Dictionary) -> void:
	var cell_m : float = g["cell_m"]
	var cell_w : float = cell_m * float(g["ppu_x"])
	var cell_h : float = cell_m * float(g["ppu_z"])
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	var arrow_len := minf(cell_w, cell_h) * 0.78
	for j in range(rows):
		var wz0 : float = g["wz0"] + float(j) * cell_m
		for i in range(cols):
			var wx0 : float = g["wx0"] + float(i) * cell_m
			var idx := j * cols + i
			var wx_v : float = _wx_cache_wind_x[idx]
			var wz_v : float = _wx_cache_wind_z[idx]
			var mag := sqrt(wx_v * wx_v + wz_v * wz_v)
			if mag < 0.05:
				continue
			mag = minf(mag, 1.0)
			# Screen Y is flipped vs world Z (north-up): negate Z to match.
			var screen_dir := Vector2(wx_v, -wz_v) / maxf(sqrt(wx_v*wx_v + wz_v*wz_v), 1e-4)
			var cx := _wx_to_sx(wx0 + cell_m * 0.5, g)
			var cy := _wz_to_sy(wz0 + cell_m * 0.5, g)
			var tail := Vector2(cx, cy) - screen_dir * arrow_len * 0.5
			var head := Vector2(cx, cy) + screen_dir * arrow_len * 0.5
			var col  := Color(0.95, 0.95, 1.00, 0.35 + 0.55 * mag)
			draw_line(tail, head, col, 1.4, true)
			var perp := Vector2(-screen_dir.y, screen_dir.x)
			draw_line(head, head - screen_dir * 4.0 + perp * 2.6, col, 1.4, true)
			draw_line(head, head - screen_dir * 4.0 - perp * 2.6, col, 1.4, true)


## Walk the cached pressure grid and mark local minima as L (storm centres)
## and local maxima as H. Uses the SAME cached samples the heatmap drew, so
## labels always sit on cells that look the colour the label claims.
func _draw_weather_extrema(g: Dictionary) -> void:
	var cell_m : float = g["cell_m"]
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	if cols < 3 or rows < 3:
		return
	var font := ThemeDB.fallback_font
	for j in range(1, rows - 1):
		for i in range(1, cols - 1):
			var p := _wx_cache_pressure[j * cols + i]
			var is_low  := p < WX_PRESSURE_LO + 5.0
			var is_high := p > WX_PRESSURE_HI - 5.0
			if not (is_low or is_high):
				continue
			var min_ok := true
			var max_ok := true
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					if di == 0 and dj == 0:
						continue
					var nb := _wx_cache_pressure[(j + dj) * cols + (i + di)]
					if nb <= p: min_ok = false
					if nb >= p: max_ok = false
			if is_low and min_ok:
				var sx := _wx_to_sx(g["wx0"] + (float(i) + 0.5) * cell_m, g)
				var sy := _wz_to_sy(g["wz0"] + (float(j) + 0.5) * cell_m, g)
				draw_string(font, Vector2(sx - 5.0, sy + 5.0),
							"L", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
							Color(1.00, 0.45, 0.35, 0.95))
			elif is_high and max_ok:
				var sx2 := _wx_to_sx(g["wx0"] + (float(i) + 0.5) * cell_m, g)
				var sy2 := _wz_to_sy(g["wz0"] + (float(j) + 0.5) * cell_m, g)
				draw_string(font, Vector2(sx2 - 5.0, sy2 + 5.0),
							"H", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
							Color(0.55, 0.78, 1.00, 0.95))


func _draw_weather_season_banner(time_h: float) -> void:
	var season_name := Season.current_name(time_h)
	var progress    := Season.progress_within_current(time_h)
	var label := "%s  (%d%%)" % [season_name, int(progress * 100.0)]
	var font  := ThemeDB.fallback_font
	var tw    := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var pos   := Vector2(_cpx + _cpw - tw - 8.0, _cpy + 14.0)
	# Subtle drop-shadow plate so text reads over any pressure colour.
	draw_rect(Rect2(pos.x - 4.0, pos.y - 11.0, tw + 8.0, 14.0),
			   Color(0.0, 0.0, 0.0, 0.40), true)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.96, 0.92, 0.78, 0.92))


## hPa → tinted overlay. Low pressure = warm red, high = cool blue.
## Alpha is low so the underlying chart (grid, islands, routes) stays legible.
func _pressure_color(hpa: float) -> Color:
	var t := clampf(inverse_lerp(WX_PRESSURE_LO, WX_PRESSURE_HI, hpa), 0.0, 1.0)
	# t = 0 → low (red), t = 1 → high (blue), t = 0.5 → neutral grey.
	var r := lerpf(0.80, 0.18, t)
	var g := lerpf(0.18, 0.34, smoothstep(0.0, 1.0, t))
	var b := lerpf(0.08, 0.78, t)
	return Color(r, g, b, 0.13)


## Small pressure-colour key in the bottom-left so the heatmap is readable.
## Same gradient _pressure_color produces, with hPa labels at both ends.
func _draw_weather_legend() -> void:
	var w := 130.0
	var h := 9.0
	var x := _cpx + 10.0
	var y := _cpy + _cph - 26.0
	var font := ThemeDB.fallback_font
	# Title
	draw_string(font, Vector2(x, y - 4.0),
				"Pressure (hPa)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.82, 0.86, 0.92, 0.80))
	# Gradient bar — 18 stops, opaque so the legend reads against the chart.
	var stops := 18
	var stop_w := w / float(stops)
	for i in range(stops):
		var hpa := lerpf(WX_PRESSURE_LO, WX_PRESSURE_HI, float(i) / float(stops - 1))
		var col := _pressure_color(hpa)
		col.a = 0.85
		draw_rect(Rect2(x + float(i) * stop_w, y + 4.0, stop_w + 0.5, h), col, true)
	# End labels
	draw_string(font, Vector2(x - 2.0, y + 4.0 + h + 9.0),
				"%d  Low" % int(WX_PRESSURE_LO), HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(1.0, 0.65, 0.55, 0.88))
	draw_string(font, Vector2(x + w - 36.0, y + 4.0 + h + 9.0),
				"High  %d" % int(WX_PRESSURE_HI), HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(0.65, 0.82, 1.0, 0.88))


## Hover-inspect tooltip — picks the cell under the cursor, samples
## WeatherField for the full WeatherSample, formats the numbers, and draws
## a small box near the cursor. Single sample per frame — cheap.
func _draw_weather_hover(time_h: float, g: Dictionary) -> void:
	var cell_m : float = g["cell_m"]
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	# Mouse → world XZ → cell index.
	var wx : float = _wx_min + (_hover_pos.x - _cpx) / float(g["ppu_x"])
	var wz : float = _wz_min + (_hover_pos.y - _cpy) / float(g["ppu_z"])
	var i := int(floorf((wx - float(g["wx0"])) / cell_m))
	var j := int(floorf((wz - float(g["wz0"])) / cell_m))
	if i < 0 or j < 0 or i >= cols or j >= rows:
		return
	# Sample at the centre of the hovered cell so the readout matches the cell.
	var cell_wx : float = float(g["wx0"]) + (float(i) + 0.5) * cell_m
	var cell_wz : float = float(g["wz0"]) + (float(j) + 0.5) * cell_m
	var s := WeatherField.sample(Vector3(cell_wx, 0.0, cell_wz), time_h)

	# Format readout lines
	var pressure_label := "Normal"
	if s.pressure < 1000.0:
		pressure_label = "Low (stormy)"
	elif s.pressure > 1020.0:
		pressure_label = "High (clear)"
	var wind_kts := s.wind_force * 50.0  ## tuned: wind_force=1.0 ≈ gale (~50 kts)
	var wind_dir_label := _compass_label_for(s.wind)
	var precip_pct := int(s.precipitation * 100.0)
	var cloud_pct  := int(s.cloud_cover * 100.0)
	var vis_pct    := int(s.visibility * 100.0)

	var lines : Array[String] = [
		"Position:  %d, %d  m"      % [int(cell_wx), int(cell_wz)],
		"Pressure:  %.1f hPa  (%s)" % [s.pressure, pressure_label],
		"Wind:      %s  %.0f kts"   % [wind_dir_label, wind_kts],
		"Cloud:     %d %%"          % cloud_pct,
		"Precip:    %d %%"          % precip_pct,
		"Visibility:%d %%"          % vis_pct,
		"Temp:      %.1f °C"        % s.temperature,
	]
	# Box geometry
	var font := ThemeDB.fallback_font
	var line_h := 13
	var pad := 6.0
	var w := 0.0
	for ln in lines:
		w = maxf(w, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	w += pad * 2.0
	var h := float(lines.size()) * float(line_h) + pad * 2.0
	# Offset from cursor; flip sides if it'd run off the chart.
	var bx := _hover_pos.x + 14.0
	var by := _hover_pos.y + 14.0
	if bx + w > _cpx + _cpw: bx = _hover_pos.x - 14.0 - w
	if by + h > _cpy + _cph: by = _hover_pos.y - 14.0 - h
	# Background plate
	draw_rect(Rect2(bx, by, w, h), Color(0.05, 0.07, 0.11, 0.92), true)
	draw_rect(Rect2(bx, by, w, h), Color(0.38, 0.50, 0.72, 0.72), false)
	# Lines
	for k in range(lines.size()):
		draw_string(font, Vector2(bx + pad, by + pad + float(k + 1) * float(line_h) - 3.0),
					lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(0.92, 0.94, 0.98, 0.96))


## XZ wind vector → 8-point compass label ("blowing FROM" convention,
## matching how navigators speak — "N wind" means blowing from the north).
func _compass_label_for(wind: Vector3) -> String:
	if wind.length() < 0.04:
		return "calm"
	# Wind FROM direction: opposite of where wind blows TO. Atan in world XZ:
	# +X = east, +Z = south. "From" angle: atan2(-wx, -wz), normalised to 0–360.
	var ang := rad_to_deg(atan2(-wind.x, -wind.z))
	if ang < 0.0: ang += 360.0
	var dirs := ["N","NE","E","SE","S","SW","W","NW"]
	var idx := int(round(ang / 45.0)) % 8
	return dirs[idx]


func _draw_dashed_line(a: Vector2, b: Vector2, col: Color, width: float, dash: float) -> void:
	var total := a.distance_to(b)
	if total < 1.0:
		return
	var dir := (b - a) / total
	var t   := 0.0
	var on  := true
	while t < total:
		var seg := minf(dash, total - t)
		if on:
			draw_line(a + dir * t, a + dir * (t + seg), col, width, true)
		t  += seg
		on  = not on
