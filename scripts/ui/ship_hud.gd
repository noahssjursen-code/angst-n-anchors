class_name ShipHud
extends Control

## Helm instruments rendered from the LocalPlayerView projection. The centre
## remains clear; trusted data sits on the top edge, corners, and waterline.

const COMPASS_RADIUS := 68.0
const TOAST_DURATION_S := 3.0

## Every dimension `_draw` positions anything by. They are constants rather than
## literals inside the draw methods because `hud_layout()` states the rect each
## instrument occupies and the draw methods paint into it: two copies of a
## number here is two derivations of one rect, and this project has fixed that
## same drift three times in geometry already (REALITY §3b).
const COMPASS_CENTER_Y := 100.0
const COMPASS_RING_PAD := 12.0
const WIND_INSET_X := 92.0
const WIND_CENTER_Y := 94.0
const WIND_RADIUS := 34.0
const WIND_RING_PAD := 7.0
const WIND_LABEL_DROP := 20.0
const WIND_LABEL_SIZE := 12
const THROTTLE_WIDTH := 184.0
const THROTTLE_SEGMENT_H := 30.0
const THROTTLE_HEADER_H := 42.0
const THROTTLE_BOTTOM_GAP := 92.0
const STATUS_BAND_H := 68.0
const STATUS_CELL_PITCH := 142.0
const STATUS_CELL_MIN_X := 224.0
const STATUS_LABEL_SIZE := 11
const STATUS_LABEL_BASELINE := 25.0
const STATUS_VALUE_SIZE := 14
const STATUS_VALUE_BASELINE := 51.0
const STATUS_CELL_TEXT_PAD := 8.0
const TOAST_HALF_WIDTH := 340.0
const TOAST_TOP := 210.0
const TOAST_HEIGHT := 64.0

var _font: Font
var _instruments: Dictionary = {}
var _toast: BrandToast
var _marks_panel: BrandPanel
var _currency: BrandCurrency


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	## …and take the size with it. `set_anchors_preset` sets ANCHORS; a Control
	## added to a viewport that never afterwards changes size is never laid out
	## against them, so measured under the real 1920 x 1080 window this HUD's own
	## rect was 0 x 0. `_draw` did not care — a CanvasItem is not clipped to its
	## rect and every instrument is positioned from `get_viewport_rect()` — but
	## `_toast` is anchored CENTER_TOP of THIS control, so it centred on x = 0
	## and spanned [-340, +340]: every ship notice in the game, the moored
	## warning, the autopilot toast and every trawl refusal, was drawn half off
	## the left edge of the screen.
	##
	## The anchors above are not what fixes it and are not load-bearing today:
	## deleting `set_anchors_preset` on its own changes no check, because this
	## line and `_on_viewport_resized` cover every parent the HUD currently has.
	## They start mattering the day something puts this Control in a container.
	size = get_viewport_rect().size
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)
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
	_toast.offset_left = -TOAST_HALF_WIDTH
	_toast.offset_right = TOAST_HALF_WIDTH
	_toast.offset_top = TOAST_TOP
	## This panel used to lay out **680 x 1357** at the real 1920 x 1080 window:
	## a dark slab from y=210 to past the bottom of the screen, its one line of
	## text stranded in the middle of it at y=874, drawn straight over HDG, COG,
	## SOG and FUEL in the status band. Every notice this HUD shows went through
	## it — the moored warning, the autopilot toast, every trawl refusal
	## `FishingSystem` sends.
	##
	## Setting a bottom offset here does NOT fix it, measured: removing that line
	## again changed no check. The height came from `BrandToast`'s label, which
	## autowraps and so reports a minimum height computed at its width, which at
	## first layout is zero — 47 one-word lines. The fix is a minimum wrap width
	## on the label, and it is in `brand_toast.gd` where the label is.
	_toast.custom_minimum_size.y = TOAST_HEIGHT
	add_child(_toast)


## Retained for BoatController's construction API. Live instrument state is
## supplied by LocalPlayerView; passed scene nodes are deliberately not stored.
func setup(_boat: RigidBody3D, _controller: BoatController) -> void:
	pass


func show_toast(message: String, duration_seconds: float = TOAST_DURATION_S) -> void:
	if _toast != null:
		_toast.show_message(message, duration_seconds)


func _on_viewport_resized() -> void:
	size = get_viewport_rect().size
	queue_redraw()


func _on_instruments_changed(snapshot: Dictionary) -> void:
	_instruments = snapshot.duplicate(true)
	queue_redraw()


func _on_marks_changed(balance: int) -> void:
	if _currency != null:
		_currency.set_amount(balance)


func _draw() -> void:
	if _instruments.is_empty():
		return
	var layout := hud_layout(get_viewport_rect().size)
	_draw_compass(layout["compass_center"] as Vector2)
	_draw_wind(layout["wind_center"] as Vector2, str(layout["wind_label"]))
	if layout.has("throttle_origin"):
		_draw_throttle(layout["throttle_origin"] as Vector2)
	_draw_status_band(layout)


## WHERE THIS HUD PUTS INK, at a given viewport size, and what each status cell
## will actually draw after it has been trimmed to fit.
##
## `_draw` takes every coordinate from this dictionary and derives none of its
## own, so a region here is a claim about pixels: name a rect nothing paints, or
## paint outside the rect you named, and a frame disagrees with the seam. That
## is the whole reason it returns rects and not a cell list — a list of labels
## is one layer above the bug, and this HUD's live bug was a cell that computed
## the right STRING and drew it 44 px into its neighbour (REALITY §3).
##
## `regions` entries are `{"id", "rect"}` in paint order; `cells` entries are
## `{"label", "value", "text", "label_text", "status", "rect"}`, where `value`
## is what the instruments say and `text` is what fits. Absent regions are
## absent, not empty: no throttle stages means no throttle rect, because a rect
## with nothing in it would make "every region holds ink" unfalsifiable (§4).
##
## What it cannot see is stated in `tests/ship_hud_readout_test.gd`.
func hud_layout(viewport: Vector2) -> Dictionary:
	var compass_center := Vector2(viewport.x * 0.5, COMPASS_CENTER_Y)
	var wind_center := Vector2(viewport.x - WIND_INSET_X, WIND_CENTER_Y)
	var wind_label := "%d KT" % int(roundf(float(_instruments.get("wind_speed_ms", 0.0)) * 1.943844))
	var band := Rect2(0.0, viewport.y - STATUS_BAND_H, viewport.x, STATUS_BAND_H)
	var layout := {"viewport": Rect2(Vector2.ZERO, viewport)}
	var regions: Array[Dictionary] = []
	if _marks_panel != null and _marks_panel.visible:
		regions.append({"id": "marks", "rect": _control_ink_rect(_marks_panel)})
	if _toast != null and _toast.visible:
		regions.append({"id": "toast", "rect": _control_ink_rect(_toast)})
	## Nothing helmed, nothing published, no instruments painted — `_draw`
	## returns before any of them. The layout says the same thing rather than
	## naming rects that hold nothing, because a region with no ink in it is a
	## region no check can falsify (REALITY §4).
	if _instruments.is_empty():
		layout["regions"] = regions
		layout["cells"] = [] as Array[Dictionary]
		return layout
	layout["compass_center"] = compass_center
	layout["wind_center"] = wind_center
	layout["wind_label"] = wind_label
	layout["status_band"] = band
	var compass_reach := COMPASS_RADIUS + COMPASS_RING_PAD
	regions.append({
		"id": "compass",
		"rect": Rect2(
			compass_center - Vector2(compass_reach, compass_reach),
			Vector2(compass_reach, compass_reach) * 2.0
		),
	})
	regions.append({"id": "wind", "rect": _wind_rect(wind_center, wind_label)})
	var throttle_values := _instruments.get("throttle_values", []) as Array
	if not throttle_values.is_empty():
		var throttle_origin := Vector2(BrandTokens.SPACE_LG, viewport.y - THROTTLE_BOTTOM_GAP)
		var throttle_h := THROTTLE_HEADER_H + throttle_values.size() * THROTTLE_SEGMENT_H
		layout["throttle_origin"] = throttle_origin
		regions.append({
			"id": "throttle",
			"rect": Rect2(
				throttle_origin.x, throttle_origin.y - throttle_h, THROTTLE_WIDTH, throttle_h
			),
		})
	regions.append({"id": "status_band", "rect": band})
	layout["regions"] = regions

	var cells := status_cells()
	var start_x := maxf(
		STATUS_CELL_MIN_X, (viewport.x - float(cells.size()) * STATUS_CELL_PITCH) * 0.5
	)
	var available := maxf(viewport.x - start_x - BrandTokens.SPACE_LG, 1.0)
	var cell_width := available / float(cells.size())
	var text_width := cell_width - STATUS_CELL_TEXT_PAD * 2.0
	for index in range(cells.size()):
		var cell := cells[index]
		cell["rect"] = Rect2(start_x + cell_width * index, band.position.y, cell_width, band.size.y)
		cell["label_text"] = _fit_text(str(cell["label"]), STATUS_LABEL_SIZE, text_width)
		cell["text"] = _fit_text(str(cell["value"]), STATUS_VALUE_SIZE, text_width)
	layout["cells"] = cells
	return layout


## The status-band cell list, in order, before layout. Split out so the cells a
## reader can name are one function and not eleven lines inside a `_draw`.
func status_cells() -> Array[Dictionary]:
	if _instruments.is_empty():
		return [] as Array[Dictionary]
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
		## exactly as it did before. Four of the six strings
		## `get_activity_status()` can return still reach no pixel — see the
		## survey in `tests/ship_hud_readout_test.gd`.
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
	return cells


## A cell wider than the cell it owns is drawn ON TOP of its neighbour, not
## clipped: measured at the project's 1920 px viewport, an autopilot destination
## came to 253 px of text in a 165 px cell and wrote through the FISH HOLD
## tonnage next to it, leaving both unreadable. Trimming states the property
## "one cell, one cell's worth of ink"; the width measured here is the width
## `_draw_centered` then centres on, so the seam cannot claim a fit the draw
## does not honour.
func _fit_text(text: String, font_size: int, max_width: float) -> String:
	if text.is_empty() or max_width <= 0.0:
		return ""
	if _text_width(text, font_size) <= max_width:
		return text
	var trimmed := text
	while trimmed.length() > 0:
		trimmed = trimmed.substr(0, trimmed.length() - 1).rstrip(" ")
		if _text_width(trimmed + "…", font_size) <= max_width:
			return trimmed + "…"
	return ""


func _text_width(text: String, font_size: int) -> float:
	return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## A child control's ink is not clipped to its parent, so this looked like it
## needed to merge the descendants' rects. MEASURED, it does not: the marks
## panel lays out at (16, 16) 174 x 72 — twelve px taller than its own offsets
## ask for, because `BrandPanel`'s minimum size grows it — and its currency row
## sits at (40, 40) 126 x 24, wholly inside. The merge was written first and
## deleting it changed no check, which is the signal that it was covering
## nothing (REALITY §4e). If a child ever does overrun its parent, the frame
## check in `ship_hud_readout_test` that counts ink outside every declared
## region is what will say so.
func _control_ink_rect(control: Control) -> Rect2:
	return control.get_global_rect()


func _wind_rect(center: Vector2, label: String) -> Rect2:
	var reach := WIND_RADIUS + WIND_RING_PAD
	var rect := Rect2(center - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	var half_width := _text_width(label, WIND_LABEL_SIZE) * 0.5
	var baseline := center.y + WIND_RADIUS + WIND_LABEL_DROP
	return rect.merge(Rect2(
		center.x - half_width,
		baseline - _font.get_ascent(WIND_LABEL_SIZE),
		half_width * 2.0,
		_font.get_ascent(WIND_LABEL_SIZE) + _font.get_descent(WIND_LABEL_SIZE)
	))


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


func _draw_wind(center: Vector2, label: String) -> void:
	var wind_direction := _instruments.get("wind_direction", Vector3.ZERO) as Vector3
	var bow := _instruments.get("bow", Vector2(0.0, -1.0)) as Vector2
	var radius := WIND_RADIUS
	draw_circle(center, radius + WIND_RING_PAD, BrandTokens.SEA_DEEP)
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
		label,
		center + Vector2(0.0, radius + WIND_LABEL_DROP),
		WIND_LABEL_SIZE,
		BrandTokens.INK_INVERSE
	)


func _draw_throttle(origin: Vector2) -> void:
	var values := _instruments.get("throttle_values", []) as Array
	if values.is_empty():
		return
	var active_index := int(_instruments.get("throttle_index", 0))
	var width := THROTTLE_WIDTH
	var segment_height := THROTTLE_SEGMENT_H
	var height := THROTTLE_HEADER_H + values.size() * segment_height
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


func _draw_status_band(layout: Dictionary) -> void:
	var rect := layout["status_band"] as Rect2
	draw_rect(rect, BrandTokens.INK)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, BrandTokens.RULE_WIDTH)), BrandTokens.BRASS)
	var cells := layout["cells"] as Array[Dictionary]
	for index in range(cells.size()):
		var cell := cells[index]
		var cell_rect := cell["rect"] as Rect2
		if index > 0:
			draw_line(
				Vector2(cell_rect.position.x, rect.position.y + BrandTokens.SPACE_MD),
				Vector2(cell_rect.position.x, rect.end.y - BrandTokens.SPACE_MD),
				BrandTokens.alpha(BrandTokens.SEA_LINE, 0.7),
				1.0
			)
		var center_x := cell_rect.position.x + cell_rect.size.x * 0.5
		_draw_centered(
			str(cell["label_text"]),
			Vector2(center_x, rect.position.y + STATUS_LABEL_BASELINE),
			STATUS_LABEL_SIZE,
			BrandTokens.INK_INVERSE_DIM
		)
		_draw_centered(
			str(cell["text"]),
			Vector2(center_x, rect.position.y + STATUS_VALUE_BASELINE),
			STATUS_VALUE_SIZE,
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
