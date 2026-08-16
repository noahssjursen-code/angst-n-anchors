class_name ShipHud
extends Control

## Helm instruments rendered from the LocalPlayerView projection. The centre
## remains clear; trusted data sits on the top edge, corners, and waterline.

const COMPASS_RADIUS := 68.0
const TOAST_DURATION_S := 3.0

var _font: Font
var _instruments: Dictionary = {}
var _toast: BrandToast
var _marks_panel: BrandPanel
var _currency: BrandCurrency


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = BrandTheme.shared()
	_font = BrandTheme.font_data()
	_build_control_nodes()
	var view := get_node_or_null("/root/LocalPlayerView")
	if view != null:
		_instruments = view.get_helm_instruments()
		_currency.set_amount(view.get_marks())
		if not view.helm_instruments_changed.is_connected(_on_instruments_changed):
			view.helm_instruments_changed.connect(_on_instruments_changed)
		if not view.marks_changed.is_connected(_on_marks_changed):
			view.marks_changed.connect(_on_marks_changed)
		if not view.ship_notice_requested.is_connected(show_toast):
			view.ship_notice_requested.connect(show_toast)
	queue_redraw()


func _build_control_nodes() -> void:
	_marks_panel = BrandPanel.new(BrandPanel.Variant.DARK_RULED)
	_marks_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_marks_panel.offset_left = BrandTokens.SPACE_LG
	_marks_panel.offset_top = BrandTokens.SPACE_LG
	_marks_panel.offset_right = 190.0
	_marks_panel.offset_bottom = 76.0
	add_child(_marks_panel)
	_currency = BrandCurrency.new(0, true)
	_marks_panel.add_child(_currency)

	_toast = BrandToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -340.0
	_toast.offset_right = 340.0
	_toast.offset_top = 210.0
	_toast.custom_minimum_size.y = 64.0
	add_child(_toast)


## Retained for BoatController's construction API. Live instrument state is
## supplied by LocalPlayerView; passed scene nodes are deliberately not stored.
func setup(_boat: RigidBody3D, _controller: BoatController) -> void:
	pass


func show_toast(message: String, duration_seconds: float = TOAST_DURATION_S) -> void:
	if _toast != null:
		_toast.show_message(message, duration_seconds)


func _on_instruments_changed(snapshot: Dictionary) -> void:
	_instruments = snapshot.duplicate(true)
	queue_redraw()


func _on_marks_changed(balance: int) -> void:
	if _currency != null:
		_currency.set_amount(balance)


func _draw() -> void:
	if _instruments.is_empty():
		return
	var viewport := get_viewport_rect().size
	_draw_compass(Vector2(viewport.x * 0.5, 100.0))
	_draw_wind(Vector2(viewport.x - 92.0, 94.0))
	_draw_throttle(Vector2(BrandTokens.SPACE_LG, viewport.y - 92.0))
	_draw_status_band(viewport)


func _draw_compass(center: Vector2) -> void:
	var heading := float(_instruments.get("heading_deg", 0.0))
	var speed := float(_instruments.get("speed_knots", 0.0))
	var target_bearing := float(_instruments.get("target_bearing_deg", NAN))
	var radius := COMPASS_RADIUS
	var card_rotation := deg_to_rad(-heading)

	draw_circle(center, radius + 12.0, BrandTokens.SEA_DEEP)
	draw_arc(center, radius + 10.0, 0.0, TAU, 80, BrandTokens.SEA_LINE, 1.5, true)
	draw_arc(
		center,
		radius + 5.0,
		0.0,
		TAU,
		80,
		BrandTokens.alpha(BrandTokens.SEA_LINE, 0.38),
		1.0,
		true
	)

	for degrees in range(0, 360, 10):
		var angle := deg_to_rad(float(degrees)) + card_rotation - PI * 0.5
		var major := degrees % 90 == 0
		var medium := degrees % 45 == 0
		var tick_length := 13.0 if major else (8.0 if medium else 5.0)
		var tick_width := 1.8 if major else (1.2 if medium else 0.8)
		var tick_color := (
			BrandTokens.INK_INVERSE
			if major
			else BrandTokens.alpha(BrandTokens.INK_INVERSE_DIM, 0.55)
		)
		draw_line(
			center + Vector2(cos(angle), sin(angle)) * (radius - tick_length),
			center + Vector2(cos(angle), sin(angle)) * radius,
			tick_color,
			tick_width,
			true
		)

	for record in [
		{"degrees": 0, "label": "N", "color": BrandTokens.ALERT},
		{"degrees": 90, "label": "E", "color": BrandTokens.INK_INVERSE},
		{"degrees": 180, "label": "S", "color": BrandTokens.INK_INVERSE},
		{"degrees": 270, "label": "W", "color": BrandTokens.INK_INVERSE},
	]:
		var angle := deg_to_rad(float(record.degrees)) + card_rotation - PI * 0.5
		_draw_centered(
			str(record.label),
			center + Vector2(cos(angle), sin(angle)) * (radius - 22.0) + Vector2(0.0, 5.0),
			14,
			record.color as Color
		)

	if is_finite(target_bearing):
		var relative := deg_to_rad(target_bearing - heading) - PI * 0.5
		var direction := Vector2(cos(relative), sin(relative))
		draw_line(
			center + direction * 14.0,
			center + direction * (radius - 5.0),
			BrandTokens.BRASS,
			2.5,
			true
		)
		var tip := center + direction * (radius - 3.0)
		var back := center + direction * (radius - 18.0)
		var side := Vector2(-direction.y, direction.x) * 6.0
		draw_colored_polygon(
			PackedVector2Array([tip, back + side, back - side]),
			BrandTokens.BRASS
		)

	_draw_centered("%.1f" % speed, center + Vector2(0.0, -3.0), 20, BrandTokens.INK_INVERSE)
	_draw_centered("KN", center + Vector2(0.0, 15.0), 11, BrandTokens.INK_INVERSE_DIM)
	draw_colored_polygon(PackedVector2Array([
		Vector2(center.x, center.y - radius - 2.0),
		Vector2(center.x - 7.0, center.y - radius + 12.0),
		Vector2(center.x + 7.0, center.y - radius + 12.0),
	]), BrandTokens.BRASS)


func _draw_wind(center: Vector2) -> void:
	var wind_direction := _instruments.get("wind_direction", Vector3.ZERO) as Vector3
	var wind_speed_ms := float(_instruments.get("wind_speed_ms", 0.0))
	var bow := _instruments.get("bow", Vector2(0.0, -1.0)) as Vector2
	var radius := 34.0
	draw_circle(center, radius + 7.0, BrandTokens.SEA_DEEP)
	draw_arc(center, radius + 5.0, 0.0, TAU, 48, BrandTokens.SEA_LINE, 1.2, true)
	draw_line(
		center + Vector2(0.0, -radius - 2.0),
		center + Vector2(0.0, -radius + 6.0),
		BrandTokens.BRASS,
		1.5,
		true
	)
	if wind_direction.length_squared() > 0.0001 and bow.length_squared() > 0.0001:
		var from := -Vector2(wind_direction.x, wind_direction.z).normalized()
		var forward := bow.normalized()
		var starboard := Vector2(forward.y, -forward.x)
		var direction := Vector2(from.dot(starboard), -from.dot(forward)).normalized()
		var head := center + direction * (radius - 8.0)
		var tail := center - direction * (radius - 8.0)
		draw_line(tail, head, BrandTokens.CHART_ZONE_WEATHER, 2.0, true)
		var side := Vector2(-direction.y, direction.x) * 4.5
		var back := head - direction * 8.0
		draw_colored_polygon(
			PackedVector2Array([head, back + side, back - side]),
			BrandTokens.CHART_ZONE_WEATHER
		)
	_draw_centered(
		"%d KT" % int(roundf(wind_speed_ms * 1.943844)),
		center + Vector2(0.0, radius + 20.0),
		12,
		BrandTokens.INK_INVERSE
	)


func _draw_throttle(origin: Vector2) -> void:
	var values := _instruments.get("throttle_values", []) as Array
	if values.is_empty():
		return
	var active_index := int(_instruments.get("throttle_index", 0))
	var width := 184.0
	var segment_height := 30.0
	var height := 42.0 + values.size() * segment_height
	var rect := Rect2(origin.x, origin.y - height, width, height)
	draw_rect(rect, BrandTokens.SEA_DEEP)
	draw_rect(rect, BrandTokens.SEA_LINE, false, 1.0)
	draw_string(
		_font,
		rect.position + Vector2(BrandTokens.SPACE_MD, 25.0),
		tr("ENGINE TELEGRAPH"),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		BrandTokens.INK_INVERSE_DIM
	)
	for row in range(values.size()):
		var index := values.size() - 1 - row
		var value := float(values[index])
		var active := index == active_index
		var segment := Rect2(
			rect.position + Vector2(BrandTokens.SPACE_SM, 36.0 + row * segment_height),
			Vector2(rect.size.x - BrandTokens.SPACE_LG, segment_height - 3.0)
		)
		var fill := BrandTokens.SEA_DEEP
		if active:
			fill = (
				BrandTokens.OK
				if value > 0.05
				else (BrandTokens.ALERT if value < -0.05 else BrandTokens.BRASS_SHADE)
			)
		draw_rect(segment, fill)
		if active:
			draw_rect(
				Rect2(segment.position, Vector2(BrandTokens.RULE_WIDTH, segment.size.y)),
				BrandTokens.BRASS
			)
		_draw_centered(
			_stage_name(value),
			segment.get_center() + Vector2(0.0, 5.0),
			13,
			BrandTokens.INK_INVERSE if active else BrandTokens.INK_INVERSE_DIM
		)


func _draw_status_band(viewport: Vector2) -> void:
	var height := 68.0
	var rect := Rect2(0.0, viewport.y - height, viewport.x, height)
	draw_rect(rect, BrandTokens.INK)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, BrandTokens.RULE_WIDTH)), BrandTokens.BRASS)
	var velocity := _instruments.get("velocity", Vector3.ZERO) as Vector3
	var course := NAN
	if velocity.length_squared() > 0.01:
		course = NavigationAxes.heading_deg_horizontal(Vector2(velocity.x, velocity.z))
	var fuel := float(_instruments.get("fuel_fraction", 0.0))
	var throttle := float(_instruments.get("throttle_value", 0.0))
	var thruster_labels := [tr("OFF"), tr("BOW"), tr("CRAB")]
	var thruster := int(_instruments.get("thruster_mode", 0))
	var autopilot := bool(_instruments.get("autopilot_active", false))
	var destination := str(_instruments.get("destination_name", "")).to_upper()
	var remaining := float(_instruments.get("remaining_distance_m", 0.0))
	var cells: Array[Dictionary] = [
		{"label": tr("TIME"), "value": BrandFormat.time_24h(float(_instruments.get("time_hours", 0.0)))},
		{"label": tr("HDG"), "value": BrandFormat.heading(float(_instruments.get("heading_deg", 0.0)))},
		{"label": tr("COG"), "value": BrandFormat.heading(course) if is_finite(course) else "—"},
		{"label": tr("SOG"), "value": BrandFormat.speed_knots(float(_instruments.get("speed_knots", 0.0)))},
		{"label": tr("FUEL"), "value": "%d%%" % int(roundf(fuel * 100.0)), "status": _fuel_status(fuel)},
		{"label": tr("THROTTLE"), "value": _stage_name(throttle)},
		{"label": tr("THRUSTER"), "value": thruster_labels[clampi(thruster, 0, 2)]},
		{"label": tr("LIGHTS"), "value": str(_instruments.get("lights", "OFF"))},
	]
	if autopilot:
		cells.append({
			"label": tr("AUTOPILOT"),
			"value": (
				"%s · %s" % [destination, BrandFormat.distance_metres(remaining)]
				if not destination.is_empty()
				else tr("ENGAGED")
			),
			"status": BrandTokens.OK_LIGHT,
		})
	var fishing := _instruments.get("fishing", {}) as Dictionary
	if not fishing.is_empty():
		## `status` HAD NO CONSUMER UNTIL 2026-08-16. `GameState` has published
		## `FishingSystem.get_activity_status()` under this key all along and this
		## cell rendered tonnage only, so the one string that says WHY nothing is
		## being caught went into a dictionary nobody drew (REALITY §3d). It
		## matters now that the hatch gates every path that moves catch: a player
		## whose boards are down would otherwise learn it by losing a haul.
		## Blockers take the cell; with nothing blocking, the tonnage reads
		## exactly as it did before.
		var fishing_status := str(fishing.get("status", ""))
		var blocked := fishing_status in [
			FishingSystem.STATUS_HATCH_SHUT, FishingSystem.STATUS_HOLD_FULL
		]
		cells.append({
			"label": tr("FISH HOLD"),
			"value": (
				tr(fishing_status) if blocked
				else "%.1f / %.1f T" % [
					float(fishing.get("mass_t", 0.0)),
					float(fishing.get("capacity_t", 0.0)),
				]
			),
			"status": BrandTokens.WARN if blocked else BrandTokens.BRASS,
		})
	var start_x := maxf(224.0, (viewport.x - float(cells.size()) * 142.0) * 0.5)
	var available := maxf(viewport.x - start_x - BrandTokens.SPACE_LG, 1.0)
	var cell_width := available / float(cells.size())
	for index in range(cells.size()):
		var cell := cells[index]
		var x := start_x + cell_width * index
		if index > 0:
			draw_line(
				Vector2(x, rect.position.y + BrandTokens.SPACE_MD),
				Vector2(x, rect.end.y - BrandTokens.SPACE_MD),
				BrandTokens.alpha(BrandTokens.SEA_LINE, 0.7),
				1.0
			)
		var center_x := x + cell_width * 0.5
		_draw_centered(
			str(cell.label),
			Vector2(center_x, rect.position.y + 25.0),
			11,
			BrandTokens.INK_INVERSE_DIM
		)
		_draw_centered(
			str(cell.value),
			Vector2(center_x, rect.position.y + 51.0),
			14,
			cell.get("status", BrandTokens.BRASS) as Color
		)


func _fuel_status(fraction: float) -> Color:
	if fraction < 0.1:
		return BrandTokens.ALERT
	if fraction < 0.3:
		return BrandTokens.WARN
	return BrandTokens.BRASS


func _stage_name(value: float) -> String:
	if value >= 0.85:
		return tr("FULL AHEAD")
	if value >= 0.40:
		return tr("HALF AHEAD")
	if value > 0.05:
		return tr("DEAD SLOW")
	if value > -0.05:
		return tr("STOP")
	return tr("ASTERN")


func _draw_centered(text: String, position: Vector2, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size
	).x
	draw_string(
		_font,
		position - Vector2(width * 0.5, 0.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)
