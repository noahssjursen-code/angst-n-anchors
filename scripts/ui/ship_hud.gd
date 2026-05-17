class_name ShipHud
extends Control

## Full-screen ship helm HUD. Add to a CanvasLayer; call setup() after add_child.
## Draws a rotating compass (top-center) and a throttle telegraph (bottom-left).
## Everything is procedural — no image assets.

var _boat:       RigidBody3D    = null
var _controller: BoatController = null
var _font:       Font

const COMPASS_R := 68.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func setup(boat: RigidBody3D, controller: BoatController) -> void:
	_boat       = boat
	_controller = controller


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _boat == null or not is_instance_valid(_boat):
		return
	var vp := get_viewport_rect().size
	_draw_compass(Vector2(vp.x * 0.5, 92.0))
	_draw_throttle(Vector2(108.0, vp.y - 142.0))
	_draw_dashboard(Vector2(vp.x * 0.5, vp.y - 49.0))


# ── Compass ───────────────────────────────────────────────────────────────────

func _draw_compass(c: Vector2) -> void:
	var r        := COMPASS_R
	var bow_h    := NavigationAxes.vessel_bow_horizontal(_boat)
	var h_rad    := NavigationAxes.heading_rad_horizontal(bow_h)
	var card_rot := NavigationAxes.compass_card_rotation_rad(h_rad)
	var speed_kn := _boat.linear_velocity.length() * 1.943844
	var dest_rad := _dest_bearing_rad()

	# Background — dark hull circle, single brass ring
	draw_circle(c, r + 12.0, HudStyle.C_BG)
	draw_arc(c, r + 10.0, 0.0, TAU, 80, HudStyle.C_BRASS, 1.5, true)
	draw_arc(c, r +  5.0, 0.0, TAU, 80,
			Color(HudStyle.C_BRASS.r, HudStyle.C_BRASS.g, HudStyle.C_BRASS.b, 0.28), 0.8, true)

	# Tick marks
	for d in range(0, 360, 10):
		var a    := deg_to_rad(float(d)) + card_rot - PI * 0.5
		var tlen := 13.0 if d % 90 == 0 else (8.0 if d % 45 == 0 else 4.5)
		var tw   := 1.8  if d % 90 == 0 else (1.2 if d % 45 == 0 else 0.7)
		var col  := HudStyle.C_TEXT if d % 90 == 0 \
				else Color(HudStyle.C_LABEL.r, HudStyle.C_LABEL.g, HudStyle.C_LABEL.b, 0.40)
		draw_line(c + Vector2(cos(a), sin(a)) * (r - tlen),
				  c + Vector2(cos(a), sin(a)) * r, col, tw, true)

	# Cardinal letters — N in anti-fouling red, rest warm off-white
	var cardinals := {
		  0: ["N", HudStyle.C_RED ],
		 90: ["E", HudStyle.C_TEXT],
		180: ["S", HudStyle.C_TEXT],
		270: ["W", HudStyle.C_TEXT],
	}
	for deg in cardinals:
		var a    := deg_to_rad(float(deg)) + card_rot - PI * 0.5
		var lpos := c + Vector2(cos(a), sin(a)) * (r - 22.0)
		_draw_centered(cardinals[deg][0], lpos + Vector2(0.0, 5.0), 14, cardinals[deg][1])

	# Destination bearing arrow — amber
	if not is_nan(dest_rad):
		var da   := dest_rad + card_rot - PI * 0.5
		var dv   := Vector2(cos(da), sin(da))
		var ac   := Color(HudStyle.C_AMBER.r, HudStyle.C_AMBER.g, HudStyle.C_AMBER.b, 0.90)
		draw_line(c + dv * 14.0, c + dv * (r - 5.0), ac, 2.5, true)
		var tip  := c + dv * (r - 3.0)
		var back := c + dv * (r - 18.0)
		var perp := Vector2(-dv.y, dv.x) * 6.0
		draw_colored_polygon(PackedVector2Array([tip, back + perp, back - perp]),
				Color(HudStyle.C_AMBER.r, HudStyle.C_AMBER.g, HudStyle.C_AMBER.b, 0.96))
		draw_circle(c, 5.5, Color(HudStyle.C_AMBER.r, HudStyle.C_AMBER.g, HudStyle.C_AMBER.b, 0.20))

	# Speed readout centre
	_draw_centered("%.1f" % speed_kn, c + Vector2(0.0, -4.0), 18, HudStyle.C_TEXT)
	_draw_centered("kn",              c + Vector2(0.0, 12.0), 10, HudStyle.C_LABEL)
	draw_circle(c, 3.0, HudStyle.C_BRASS)

	# Lubber line — amber triangle at 12 o'clock
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x,       c.y - r - 2.0),
		Vector2(c.x - 7.0, c.y - r + 12.0),
		Vector2(c.x + 7.0, c.y - r + 12.0),
	]), HudStyle.C_AMBER)
	draw_line(Vector2(c.x, c.y + r + 2.0), Vector2(c.x, c.y + r - 7.0),
			Color(HudStyle.C_AMBER.r, HudStyle.C_AMBER.g, HudStyle.C_AMBER.b, 0.35), 2.0)


# ── Throttle telegraph ────────────────────────────────────────────────────────

func _draw_throttle(c: Vector2) -> void:
	if _controller == null:
		return
	var stage_idx := _controller.get_throttle_stage_idx()
	var thruster  := _controller.get_thruster_mode()
	var vals      := _controller.throttle_stage_values
	var n         := vals.size()

	var seg_w   := 150.0
	var seg_h   :=  28.0
	var gap     :=   4.0
	var pad     :=  16.0
	var dot_row :=  76.0
	var pw      := seg_w + pad * 2.0
	var ph      := n * (seg_h + gap) - gap + pad * 2.0 + dot_row

	var px := c.x - pw * 0.5
	var py := c.y - ph * 0.5

	draw_rect(Rect2(px, py, pw, ph), HudStyle.C_BG)
	draw_rect(Rect2(px, py, pw, ph), HudStyle.C_BRASS, false, 1.2)

	for i in range(n):
		var seg_idx := n - 1 - i
		var sx      := px + pad
		var sy      := py + pad + i * (seg_h + gap)
		var val: float = vals[clampi(seg_idx, 0, vals.size() - 1)]
		var active  := (seg_idx == stage_idx)

		var fill: Color
		var text_col: Color
		if val > 0.05:
			fill     = HudStyle.C_GREEN if active else HudStyle.C_GREEN_DIM
			text_col = HudStyle.C_TEXT  if active \
					else Color(HudStyle.C_GREEN.r, HudStyle.C_GREEN.g, HudStyle.C_GREEN.b, 0.50)
		elif val < -0.05:
			fill     = HudStyle.C_RED   if active else HudStyle.C_RED_DIM
			text_col = HudStyle.C_TEXT  if active \
					else Color(HudStyle.C_RED.r, HudStyle.C_RED.g, HudStyle.C_RED.b, 0.50)
		else:
			fill     = Color(0.24, 0.21, 0.17, 0.90) if active else HudStyle.C_GREY_DIM
			text_col = HudStyle.C_TEXT if active else HudStyle.C_LABEL

		draw_rect(Rect2(sx, sy, seg_w, seg_h), fill)
		if active:
			draw_line(Vector2(sx, sy), Vector2(sx, sy + seg_h), HudStyle.C_AMBER, 2.5)
		_draw_centered(_stage_name(val), Vector2(sx + seg_w * 0.5, sy + seg_h - 5.0), 14, text_col)

	var div_y := py + ph - dot_row + 8.0
	draw_line(Vector2(px + 10.0, div_y), Vector2(px + pw - 10.0, div_y), HudStyle.C_SEP, 1.0)
	_draw_centered("BOW THRUSTER", Vector2(c.x, div_y + 16.0), 11, HudStyle.C_LABEL)

	var modes := ["OFF", "BOW", "CRAB"]
	var dot_y := div_y + 36.0
	for i in range(3):
		var dot_c := Vector2(c.x + (i - 1) * 50.0, dot_y)
		var lit   := (i == thruster)
		draw_circle(dot_c, 9.0 if lit else 6.5,
				HudStyle.C_AMBER if lit else Color(HudStyle.C_LABEL.r, HudStyle.C_LABEL.g, HudStyle.C_LABEL.b, 0.50))
		_draw_centered(modes[i], dot_c + Vector2(0.0, 18.0), 12,
				HudStyle.C_AMBER if lit else HudStyle.C_LABEL)


# ── Bottom dashboard ─────────────────────────────────────────────────────────

func _draw_dashboard(c: Vector2) -> void:
	if _controller == null:
		return

	var bow_h       := NavigationAxes.vessel_bow_horizontal(_boat)
	var heading_deg := NavigationAxes.heading_deg_horizontal(bow_h)
	var speed_kn    := _boat.linear_velocity.length() * 1.943844
	var stage_idx   := _controller.get_throttle_stage_idx()
	var vals        := _controller.throttle_stage_values
	var stage_val: float = vals[clampi(stage_idx, 0, vals.size() - 1)] if not vals.is_empty() else 0.0
	var thruster    := _controller.get_thruster_mode()
	var thruster_labels := ["OFF", "BOW ONLY", "CRAB"]
	var dest_info   := _nearest_dest_info()

	var marks_str := ""
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		marks_str = "ℳ %d" % session.get_marks()

	var cells: Array = [
		["TIME",     _time_string(),                         HudStyle.C_AMBER                                             ],
		["MARKS",    marks_str,                              HudStyle.C_AMBER                                             ],
		["HDG",      "%03.0f°" % heading_deg,               HudStyle.C_TEXT                                              ],
		["KNOTS",    "%.1f"    % speed_kn,                  HudStyle.C_TEXT                                              ],
		["THROTTLE", _stage_name(stage_val),                 _throttle_color(stage_val)                                  ],
		["THRUSTER", thruster_labels[clampi(thruster, 0, 2)],
				HudStyle.C_AMBER if thruster > 0 else HudStyle.C_LABEL],
	]
	if dest_info[1] != "":
		cells.append([dest_info[0].to_upper(), dest_info[1], HudStyle.C_AMBER])

	var cell_w := 110.0
	var cell_h :=  58.0
	var h_pad  :=  10.0
	var v_pad  :=  10.0
	var pw     := cell_w * cells.size() + h_pad * 2.0
	var ph     := cell_h + v_pad * 2.0
	var px     := c.x - pw * 0.5
	var py     := c.y - ph * 0.5

	draw_rect(Rect2(px, py, pw, ph), HudStyle.C_BG)
	draw_rect(Rect2(px, py, pw, ph), HudStyle.C_BRASS, false, 1.2)

	for i in range(cells.size()):
		var lbl:     String = cells[i][0]
		var val:     String = cells[i][1]
		var val_col: Color  = cells[i][2]
		var cx := px + h_pad + cell_w * i + cell_w * 0.5
		if i > 0:
			draw_line(Vector2(px + h_pad + cell_w * i, py + 8.0),
					  Vector2(px + h_pad + cell_w * i, py + ph - 8.0),
					  Color(HudStyle.C_SEP.r, HudStyle.C_SEP.g, HudStyle.C_SEP.b, 0.65), 1.0)
		_draw_centered(lbl, Vector2(cx, py + v_pad + 13.0), 9,  HudStyle.C_LABEL)
		_draw_centered(val, Vector2(cx, py + v_pad + 50.0), 15, val_col)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _time_string() -> String:
	var clock := get_node_or_null("/root/WorldClock")
	if clock == null:
		return "--:--"
	var tod: float = clock.get_time_of_day()
	var total_min  := int(tod * 1440.0)
	return "%02d:%02d" % [total_min / 60, total_min % 60]


func _nearest_dest_info() -> Array:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null or _boat == null:
		return ["", ""]
	var contracts: Array[Contract] = registry.get_accepted_contracts()
	if contracts.is_empty():
		return ["", ""]
	var best_dist := INF
	var best_name := ""
	for contract in contracts:
		var dest_pos: Vector3 = registry.get_port_position(contract.destination_port_id)
		if dest_pos.x == INF:
			continue
		var d := _boat.global_position.distance_to(dest_pos)
		if d < best_dist:
			best_dist = d
			best_name = registry.get_port_display_name(contract.destination_port_id)
	if best_dist == INF:
		return ["", ""]
	var dist_str := "%.1f nm" % (best_dist / 1852.0) if best_dist >= 1852.0 else "%.0f m" % best_dist
	return [best_name, dist_str]


func _stage_name(val: float) -> String:
	if val >= 0.85:  return "FULL AHEAD"
	if val >= 0.40:  return "HALF AHEAD"
	if val >  0.05:  return "DEAD SLOW"
	if val > -0.05:  return "STOP"
	return "ASTERN"


func _throttle_color(val: float) -> Color:
	if val > 0.05:  return HudStyle.C_GREEN
	if val < -0.05: return HudStyle.C_RED
	return HudStyle.C_TEXT


func _dest_bearing_rad() -> float:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null or _boat == null:
		return NAN
	var contracts: Array[Contract] = registry.get_accepted_contracts()
	if contracts.is_empty():
		return NAN
	var ship_pos  := _boat.global_position
	var best_pos  := Vector3(INF, INF, INF)
	var best_dist := INF
	for contract in contracts:
		var dest_pos: Vector3 = registry.get_port_position(contract.destination_port_id)
		if dest_pos.x == INF:
			continue
		var d := ship_pos.distance_to(dest_pos)
		if d < best_dist:
			best_dist = d
			best_pos  = dest_pos
	if best_pos.x == INF:
		return NAN
	return NavigationAxes.bearing_rad_world_delta(best_pos - ship_pos)


func _draw_centered(text: String, pos: Vector2, font_size: int, color: Color) -> void:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, pos - Vector2(tw * 0.5, 0.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
