class_name ShipHud
extends Control

## Full-screen ship helm HUD. Add to a CanvasLayer; call setup() after add_child.
## Draws a rotating compass (top-center) and a throttle telegraph (bottom-left).
## Everything is procedural — no image assets.

var _boat:       RigidBody3D    = null
var _controller: BoatController = null
var _font:       Font

const COMPASS_R := 68.0   # compass circle radius in px


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
	# Bow (+local Z) projected to X/Z; north = −world Z matches sea chart north-up.
	var bow_h := NavigationAxes.vessel_bow_horizontal(_boat)
	var h_rad := NavigationAxes.heading_rad_horizontal(bow_h)
	var card_rot := NavigationAxes.compass_card_rotation_rad(h_rad)
	var speed_kn := _boat.linear_velocity.length() * 1.943844
	var dest_rad := _dest_bearing_rad()

	# ── Background ────────────────────────────────────────────────────────────
	draw_circle(c, r + 13.0, Color(0.04, 0.06, 0.14, 0.90))
	draw_arc(c, r + 11.0, 0.0, TAU, 80, Color(0.32, 0.46, 0.70, 0.82), 2.5, true)
	draw_arc(c, r +  7.5, 0.0, TAU, 80, Color(0.16, 0.24, 0.42, 0.38), 1.0, true)
	draw_arc(c, r +  4.0, 0.0, TAU, 80, Color(0.10, 0.14, 0.26, 0.30), 0.8, true)

	# ── Tick marks ────────────────────────────────────────────────────────────
	for d in range(0, 360, 10):
		var a    := deg_to_rad(float(d)) + card_rot - PI * 0.5
		var tlen := 14.0 if d % 90 == 0 else (9.0 if d % 45 == 0 else 5.0)
		var tw   := 2.0  if d % 90 == 0 else (1.3 if d % 45 == 0 else 0.8)
		var col  := Color(1.0, 1.0, 1.0, 0.90) if d % 90 == 0 else Color(0.58, 0.70, 0.86, 0.52)
		draw_line(c + Vector2(cos(a), sin(a)) * (r - tlen),
		          c + Vector2(cos(a), sin(a)) * r, col, tw, true)

	# ── Cardinal letters ──────────────────────────────────────────────────────
	var cardinals := {
		  0: ["N", Color(1.00, 0.26, 0.26, 1.00)],
		 90: ["E", Color(0.86, 0.90, 1.00, 0.88)],
		180: ["S", Color(0.86, 0.90, 1.00, 0.88)],
		270: ["W", Color(0.86, 0.90, 1.00, 0.88)],
	}
	for deg in cardinals:
		var a    := deg_to_rad(float(deg)) + card_rot - PI * 0.5
		var lpos := c + Vector2(cos(a), sin(a)) * (r - 22.0)
		_draw_centered(cardinals[deg][0], lpos + Vector2(0.0, 5.0), 14, cardinals[deg][1])

	# ── Destination bearing arrow (orange) ────────────────────────────────────
	if not is_nan(dest_rad):
		var da   := dest_rad + card_rot - PI * 0.5
		var dv   := Vector2(cos(da), sin(da))
		draw_line(c + dv * 14.0, c + dv * (r - 5.0), Color(1.0, 0.58, 0.06, 0.90), 2.5, true)
		var tip  := c + dv * (r - 3.0)
		var back := c + dv * (r - 18.0)
		var perp := Vector2(-dv.y, dv.x) * 6.0
		draw_colored_polygon(PackedVector2Array([tip, back + perp, back - perp]),
		                     Color(1.0, 0.58, 0.06, 0.96))
		draw_circle(c, 5.5, Color(1.0, 0.58, 0.06, 0.35))

	# ── Speed readout (centre of compass) ────────────────────────────────────
	_draw_centered("%.1f" % speed_kn, c + Vector2(0.0, -4.0), 18, Color(0.92, 0.96, 1.00, 0.90))
	_draw_centered("kn",              c + Vector2(0.0, 12.0), 10, Color(0.50, 0.62, 0.78, 0.70))
	draw_circle(c, 3.2, Color(0.80, 0.88, 1.00, 0.88))

	# ── Lubber line — fixed gold triangle at 12 o'clock ──────────────────────
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x,        c.y - r - 2.0),
		Vector2(c.x - 7.5,  c.y - r + 13.0),
		Vector2(c.x + 7.5,  c.y - r + 13.0),
	]), Color(0.96, 0.86, 0.12, 1.00))
	draw_line(Vector2(c.x, c.y + r + 2.0), Vector2(c.x, c.y + r - 7.0),
	          Color(0.96, 0.86, 0.12, 0.40), 2.0)


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

	draw_rect(Rect2(px, py, pw, ph), Color(0.04, 0.06, 0.14, 0.90))
	draw_rect(Rect2(px, py, pw, ph), Color(0.30, 0.44, 0.68, 0.72), false, 1.5)

	# Segments — top = highest stage (FULL AHEAD), bottom = lowest (ASTERN)
	for i in range(n):
		var seg_idx := n - 1 - i
		var sx      := px + pad
		var sy      := py + pad + i * (seg_h + gap)
		var val: float = vals[clampi(seg_idx, 0, vals.size() - 1)]
		var active  := (seg_idx == stage_idx)

		var fill: Color
		var text_col: Color
		if val > 0.05:
			fill     = Color(0.20, 0.82, 0.36, 0.95) if active else Color(0.07, 0.28, 0.13, 0.60)
			text_col = Color(1.00, 1.00, 1.00, 0.95) if active else Color(0.28, 0.68, 0.40, 0.55)
		elif val < -0.05:
			fill     = Color(0.90, 0.22, 0.18, 0.95) if active else Color(0.32, 0.08, 0.08, 0.60)
			text_col = Color(1.00, 1.00, 1.00, 0.95) if active else Color(0.80, 0.30, 0.28, 0.55)
		else:
			fill     = Color(0.88, 0.88, 0.88, 0.92) if active else Color(0.28, 0.30, 0.36, 0.50)
			text_col = Color(0.06, 0.06, 0.08, 0.95) if active else Color(0.62, 0.64, 0.70, 0.55)

		draw_rect(Rect2(sx, sy, seg_w, seg_h), fill)
		if active:
			draw_line(Vector2(sx, sy), Vector2(sx, sy + seg_h), Color(1.0, 1.0, 1.0, 0.60), 2.0)
		_draw_centered(_stage_name(val), Vector2(sx + seg_w * 0.5, sy + seg_h - 5.0), 14, text_col)

	# Divider + thruster section
	var div_y := py + ph - dot_row + 8.0
	draw_line(Vector2(px + 10.0, div_y), Vector2(px + pw - 10.0, div_y),
	          Color(0.30, 0.44, 0.68, 0.30), 1.0)
	_draw_centered("BOW THRUSTER", Vector2(c.x, div_y + 16.0), 11, Color(0.40, 0.50, 0.66, 0.55))

	var modes := ["OFF", "BOW", "CRAB"]
	var dot_y := div_y + 36.0
	for i in range(3):
		var dot_c := Vector2(c.x + (i - 1) * 50.0, dot_y)
		var lit   := (i == thruster)
		draw_circle(dot_c, 9.0 if lit else 6.5,
		            Color(0.28, 0.72, 1.00, 0.95) if lit else Color(0.16, 0.22, 0.34, 0.70))
		_draw_centered(modes[i], dot_c + Vector2(0.0, 18.0), 12,
		               Color(0.28, 0.72, 1.00, 0.90) if lit else Color(0.38, 0.44, 0.56, 0.55))


# ── Bottom dashboard ─────────────────────────────────────────────────────────

func _draw_dashboard(c: Vector2) -> void:
	if _controller == null:
		return

	var bow_h := NavigationAxes.vessel_bow_horizontal(_boat)
	var heading_deg := NavigationAxes.heading_deg_horizontal(bow_h)
	var speed_kn     := _boat.linear_velocity.length() * 1.943844
	var stage_idx    := _controller.get_throttle_stage_idx()
	var vals         := _controller.throttle_stage_values
	var stage_val: float = vals[clampi(stage_idx, 0, vals.size() - 1)] if not vals.is_empty() else 0.0
	var thruster     := _controller.get_thruster_mode()
	var thruster_labels := ["OFF", "BOW ONLY", "CRAB"]
	var dest_info    := _nearest_dest_info()

	var marks_str := ""
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		marks_str = "ℳ %d" % session.get_marks()

	var cells: Array = [
		["MARKS",    marks_str,                             Color(0.96, 0.82, 0.28, 0.95)],
		["HDG",      "%03.0f°" % heading_deg,              Color(0.92, 0.96, 1.00, 0.95)],
		["KNOTS",    "%.1f"    % speed_kn,                 Color(0.92, 0.96, 1.00, 0.95)],
		["THROTTLE", _stage_name(stage_val),               _throttle_color(stage_val)   ],
		["THRUSTER", thruster_labels[clampi(thruster,0,2)],
		             Color(0.28, 0.72, 1.00, 0.90) if thruster > 0 else Color(0.65, 0.72, 0.82, 0.70)],
	]
	if dest_info[1] != "":
		cells.append([dest_info[0].to_upper(), dest_info[1], Color(1.0, 0.58, 0.06, 0.95)])

	var cell_w := 110.0
	var cell_h :=  58.0
	var h_pad  :=  10.0
	var v_pad  :=  10.0
	var pw     := cell_w * cells.size() + h_pad * 2.0
	var ph     := cell_h + v_pad * 2.0
	var px     := c.x - pw * 0.5
	var py     := c.y - ph * 0.5

	draw_rect(Rect2(px, py, pw, ph), Color(0.04, 0.06, 0.14, 0.90))
	draw_rect(Rect2(px, py, pw, ph), Color(0.30, 0.44, 0.68, 0.72), false, 1.5)

	for i in range(cells.size()):
		var lbl:     String = cells[i][0]
		var val:     String = cells[i][1]
		var val_col: Color  = cells[i][2]
		var cx := px + h_pad + cell_w * i + cell_w * 0.5
		if i > 0:
			draw_line(Vector2(px + h_pad + cell_w * i, py + 8.0),
			          Vector2(px + h_pad + cell_w * i, py + ph - 8.0),
			          Color(0.30, 0.44, 0.68, 0.35), 1.0)
		_draw_centered(lbl, Vector2(cx, py + v_pad + 13.0), 9,  Color(0.50, 0.62, 0.78, 0.70))
		_draw_centered(val, Vector2(cx, py + v_pad + 50.0), 15, val_col)


## Returns [port_name, distance_str] for the nearest accepted contract destination.
## Both strings are empty when nothing is active or the boat is invalid.
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


# ── Helpers ───────────────────────────────────────────────────────────────────

func _stage_name(val: float) -> String:
	if val >= 0.85:  return "FULL AHEAD"
	if val >= 0.40:  return "HALF AHEAD"
	if val >  0.05:  return "DEAD SLOW"
	if val > -0.05:  return "STOP"
	return "ASTERN"


func _throttle_color(val: float) -> Color:
	if val > 0.05:  return Color(0.20, 0.90, 0.40, 1.00)
	if val < -0.05: return Color(0.95, 0.30, 0.25, 1.00)
	return Color(0.88, 0.88, 0.88, 0.90)


func _dest_bearing_rad() -> float:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null or _boat == null:
		return NAN
	var contracts: Array[Contract] = registry.get_accepted_contracts()
	if contracts.is_empty():
		return NAN
	var ship_pos: Vector3 = _boat.global_position
	var best_pos          := Vector3(INF, INF, INF)
	var best_dist         := INF
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
	var to := best_pos - ship_pos
	return NavigationAxes.bearing_rad_world_delta(to)


func _draw_centered(text: String, pos: Vector2, font_size: int, color: Color) -> void:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, pos - Vector2(tw * 0.5, 0.0), text,
	            HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
