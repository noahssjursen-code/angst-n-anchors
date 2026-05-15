class_name MapOverlay
extends Control

## Procedural sea chart drawn via _draw().
## Supports scroll-wheel zoom and left-drag pan.
## Resets to ship position on open unless the user has already moved the view.

const MARGIN    := 60.0
const CHART_PAD := 52.0

const ZOOM_IN  := 0.82
const ZOOM_OUT := 1.0 / 0.82
const SPAN_MIN := 300.0
const SPAN_MAX := 500000.0

var _cam_center:  Vector2 = Vector2.ZERO
var _cam_span:    float   = 10000.0
var _user_moved:  bool    = false
var _dragging:    bool    = false
var _drag_origin_mouse:  Vector2 = Vector2.ZERO
var _drag_origin_center: Vector2 = Vector2.ZERO
var _was_visible: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


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
				_drag_origin_mouse   = mb.position
				_drag_origin_center  = _cam_center
			else:
				_dragging = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var mm  := event as InputEventMouseMotion
		var ppu := _ppu()
		var dm  := mm.position - _drag_origin_mouse
		_cam_center.x = _drag_origin_center.x - dm.x / ppu
		_cam_center.y = _drag_origin_center.y + dm.y / ppu
		_user_moved   = true
		get_viewport().set_input_as_handled()


# ── Camera helpers ────────────────────────────────────────────────────────────

func _ppu() -> float:
	var vp := get_viewport_rect().size
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

	# ── Outer panel ───────────────────────────────────────────────────────────
	var px := MARGIN
	var py := MARGIN
	var pw := vp.x - MARGIN * 2.0
	var ph := vp.y - MARGIN * 2.0

	draw_rect(Rect2(px, py, pw, ph), Color(0.03, 0.04, 0.10, 0.97))
	draw_rect(Rect2(px, py, pw, ph), Color(0.30, 0.44, 0.68, 0.80), false, 2.0)
	draw_rect(Rect2(px + 6, py + 6, pw - 12, ph - 12),
			  Color(0.20, 0.30, 0.52, 0.20), false, 1.0)

	# ── Title ─────────────────────────────────────────────────────────────────
	var title    := "SEA CHART"
	var title_fs := 20
	var ttw      := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs).x
	draw_string(font, Vector2(vp.x * 0.5 - ttw * 0.5, py + 38.0),
				title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs,
				Color(0.96, 0.86, 0.12, 0.92))

	var hint    := "scroll  zoom    drag  pan    M  close"
	var hint_tw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(px + pw - hint_tw - 14, py + 32.0),
				hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.40, 0.50, 0.66, 0.55))

	draw_line(Vector2(px + 16, py + 46), Vector2(px + pw - 16, py + 46),
			  Color(0.28, 0.40, 0.64, 0.35), 1.0)

	# ── Chart bounds ──────────────────────────────────────────────────────────
	var cpx := px + CHART_PAD
	var cpy := py + CHART_PAD + 10.0
	var cpw := pw - CHART_PAD * 2.0
	var cph := ph - CHART_PAD * 2.0 - 10.0

	# ── World extents from camera ──────────────────────────────────────────────
	var ppu    := minf(cpw, cph) / _cam_span
	var wx_min := _cam_center.x - cpw * 0.5 / ppu
	var wx_max := _cam_center.x + cpw * 0.5 / ppu
	var wz_min := _cam_center.y - cph * 0.5 / ppu
	var wz_max := _cam_center.y + cph * 0.5 / ppu

	# ── Gather world data ──────────────────────────────────────────────────────
	var registry := get_node_or_null("/root/ContractRegistry")

	var ports:    Dictionary      = {}
	var accepted: Array[Contract] = []
	var dest_ids: Dictionary      = {}

	if registry != null:
		for pid in registry.get_port_ids():
			var wpos: Vector3 = registry.get_port_position(str(pid))
			if wpos.x == INF:
				continue
			ports[str(pid)] = {
				"pos":  wpos,
				"name": registry.get_port_display_name(str(pid)),
			}
		accepted = registry.get_accepted_contracts()
		for c in accepted:
			dest_ids[c.destination_port_id] = true

	var ship_pos:   Vector3 = Vector3(INF, INF, INF)
	var ship_rot_y: float   = 0.0
	for n in get_tree().get_nodes_in_group("player_boat"):
		var rb := n as RigidBody3D
		if rb != null:
			ship_pos   = rb.global_position
			ship_rot_y = rb.rotation.y
			break

	# ── Grid interval ─────────────────────────────────────────────────────────
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

	# ── Grid ──────────────────────────────────────────────────────────────────
	var grid_col := Color(0.18, 0.26, 0.44, 0.18)

	var gx: float = floor(wx_min / grid_interval) * grid_interval
	while gx <= wx_max:
		var sx: float = cpx + (gx - wx_min) / (wx_max - wx_min) * cpw
		if sx >= cpx - 1.0 and sx <= cpx + cpw + 1.0:
			draw_line(Vector2(sx, cpy), Vector2(sx, cpy + cph), grid_col, 1.0)
		gx += grid_interval

	var gz: float = floor(wz_min / grid_interval) * grid_interval
	while gz <= wz_max:
		var sy: float = cpy + (1.0 - (gz - wz_min) / (wz_max - wz_min)) * cph
		if sy >= cpy - 1.0 and sy <= cpy + cph + 1.0:
			draw_line(Vector2(cpx, sy), Vector2(cpx + cpw, sy), grid_col, 1.0)
		gz += grid_interval

	# ── Contract routes ────────────────────────────────────────────────────────
	for c in accepted:
		var op: Vector3 = registry.get_port_position(c.origin_port_id)
		var dp: Vector3 = registry.get_port_position(c.destination_port_id)
		if op.x == INF or dp.x == INF:
			continue
		var sa := _w2s(op, wx_min, wz_min, wx_max, wz_max, cpx, cpy, cpw, cph)
		var da := _w2s(dp, wx_min, wz_min, wx_max, wz_max, cpx, cpy, cpw, cph)
		_draw_dashed_line(sa, da, Color(1.0, 0.58, 0.06, 0.28), 1.5, 10.0)

	# ── Ports ─────────────────────────────────────────────────────────────────
	for pid in ports:
		var info: Dictionary = ports[pid] as Dictionary
		var wpos: Vector3    = info.get("pos") as Vector3
		var sp   := _w2s(wpos, wx_min, wz_min, wx_max, wz_max, cpx, cpy, cpw, cph)
		var is_d := dest_ids.has(str(pid))

		var dot_r   := 7.0 if is_d else 5.0
		var dot_col := Color(1.0, 0.58, 0.06, 0.95) if is_d else Color(0.58, 0.76, 1.00, 0.80)

		draw_circle(sp, dot_r + 5.0, Color(dot_col.r, dot_col.g, dot_col.b, 0.18))
		draw_circle(sp, dot_r, dot_col)

		var pname: String = info.get("name") as String
		var ntw := font.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, sp + Vector2(-ntw * 0.5, -dot_r - 7.0),
					pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dot_col)

	# ── Ship ──────────────────────────────────────────────────────────────────
	if ship_pos.x != INF:
		var sp   := _w2s(ship_pos, wx_min, wz_min, wx_max, wz_max, cpx, cpy, cpw, cph)
		var fwd  := Vector2(sin(ship_rot_y), -cos(ship_rot_y))
		var perp := Vector2(-fwd.y, fwd.x)
		var sz   := 11.0
		var col  := Color(0.96, 0.86, 0.12, 1.00)
		draw_circle(sp, sz + 4.0, Color(col.r, col.g, col.b, 0.20))
		draw_colored_polygon(PackedVector2Array([
			sp + fwd  * sz,
			sp - fwd  * sz * 0.5 + perp * sz * 0.5,
			sp - fwd  * sz * 0.5 - perp * sz * 0.5,
		]), col)

	# ── Scale bar ─────────────────────────────────────────────────────────────
	var scale_w_world := (wx_max - wx_min) * 0.2
	var scale_w_px    := scale_w_world / (wx_max - wx_min) * cpw
	var bx := cpx
	var by := cpy + cph + 18.0
	draw_line(Vector2(bx, by),                   Vector2(bx + scale_w_px, by),         Color(0.55, 0.68, 0.86, 0.70), 2.0)
	draw_line(Vector2(bx, by - 4),               Vector2(bx, by + 4),                  Color(0.55, 0.68, 0.86, 0.70), 1.5)
	draw_line(Vector2(bx + scale_w_px, by - 4),  Vector2(bx + scale_w_px, by + 4),     Color(0.55, 0.68, 0.86, 0.70), 1.5)

	var scale_label := "%.0f m" % scale_w_world if scale_w_world < 1852.0 else "%.1f nm" % (scale_w_world / 1852.0)
	draw_string(font, Vector2(bx, by + 14), scale_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.58, 0.76, 0.60))

	var grid_label := "grid  %.0f m" % grid_interval if grid_interval < 1852.0 else "grid  %.0f nm" % (grid_interval / 1852.0)
	draw_string(font, Vector2(bx, by + 26), grid_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.35, 0.48, 0.66, 0.45))

	# ── Legend ────────────────────────────────────────────────────────────────
	var lx := bx + scale_w_px + 24.0
	draw_circle(Vector2(lx, by), 4.0, Color(0.58, 0.76, 1.00, 0.80))
	draw_string(font, Vector2(lx + 10, by + 4), "Port",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.58, 0.76, 0.60))
	draw_circle(Vector2(lx + 68, by), 4.0, Color(1.0, 0.58, 0.06, 0.95))
	draw_string(font, Vector2(lx + 78, by + 4), "Destination",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.58, 0.76, 0.60))
	draw_colored_polygon(PackedVector2Array([
		Vector2(lx + 168, by - 5),
		Vector2(lx + 164, by + 4),
		Vector2(lx + 172, by + 4),
	]), Color(0.96, 0.86, 0.12, 1.00))
	draw_string(font, Vector2(lx + 178, by + 4), "Your ship",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.58, 0.76, 0.60))


# ── Helpers ───────────────────────────────────────────────────────────────────

func _w2s(world: Vector3,
		wx_min: float, wz_min: float, wx_max: float, wz_max: float,
		sx: float, sy: float, sw: float, sh: float) -> Vector2:
	var tx := (world.x - wx_min) / (wx_max - wx_min)
	var tz := (world.z - wz_min) / (wz_max - wz_min)
	return Vector2(sx + tx * sw, sy + (1.0 - tz) * sh)


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
