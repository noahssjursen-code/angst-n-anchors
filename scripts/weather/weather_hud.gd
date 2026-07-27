class_name WeatherHUD
extends CanvasLayer

## Compact presentation debugger for the local weather projection.
## Toggle with Tab. This is intentionally an instrument, not a game HUD.

const _GRID_SIZE := 156.0
const _GRID_PAD := 16.0
const _FOG_H := 18.0
const _CORNER_PAD := 16.0

var _visible_hud := false
var _panel: BrandPanel
var _label: BrandLabel
var _compass_rect: Control
var _fog_bar: Control


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	layer = 10
	_build_hud()
	_refresh()
	var weather := _weather_lighting()
	if weather != null:
		weather.connect("state_changed", Callable(self, "_refresh"))


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_TAB:
			_visible_hud = not _visible_hud
			_panel.visible = _visible_hud
			if _visible_hud:
				BrandMotion.panel_in(_panel)
			get_viewport().set_input_as_handled()


func _build_hud() -> void:
	var total_w := _GRID_SIZE + _GRID_PAD * 2.0
	var label_h := 108.0
	var total_h := _GRID_SIZE + _GRID_PAD * 2.0 + _FOG_H + BrandTokens.SPACE_MD + label_h

	_panel = BrandPanel.new(BrandPanel.Variant.DARK_RULED)
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = _CORNER_PAD
	_panel.offset_bottom = -_CORNER_PAD
	_panel.offset_right = _CORNER_PAD + total_w
	_panel.offset_top = -_CORNER_PAD - total_h
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	_panel.add_child(root)

	var heading := BrandLabel.new("WEATHER PRESENTATION", BrandLabel.Role.INVERSE_DATA)
	root.add_child(heading)

	_compass_rect = Control.new()
	_compass_rect.custom_minimum_size = Vector2(_GRID_SIZE, _GRID_SIZE)
	_compass_rect.draw.connect(_draw_compass)
	root.add_child(_compass_rect)

	_fog_bar = Control.new()
	_fog_bar.custom_minimum_size = Vector2(_GRID_SIZE, _FOG_H)
	_fog_bar.draw.connect(_draw_fog_bar)
	root.add_child(_fog_bar)

	_label = BrandLabel.new("", BrandLabel.Role.INVERSE_DATA)
	_label.custom_minimum_size.y = label_h
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_label)


func _refresh() -> void:
	if _panel == null:
		return
	_compass_rect.queue_redraw()
	_fog_bar.queue_redraw()
	_update_label()


func _draw_compass() -> void:
	var weather := _weather_lighting()
	var wind_speed_norm := 0.0
	var sea_state := 0.0
	if weather != null:
		var wind_speed := float(weather.get("wind_speed_ms"))
		var maximum := 30.0
		if "WIND_SPEED_MAX" in weather:
			maximum = float(weather.get("WIND_SPEED_MAX"))
		wind_speed_norm = clampf(wind_speed / maxf(maximum, 0.001), 0.0, 1.0)
		sea_state = float(weather.get("sea_state"))

	var size := _compass_rect.size
	var midpoint := size * 0.5
	_compass_rect.draw_rect(Rect2(Vector2.ZERO, size), BrandTokens.INK)
	_compass_rect.draw_rect(
		Rect2(Vector2.ZERO, midpoint),
		BrandTokens.alpha(BrandTokens.WATER_SHALLOW, 0.18)
	)
	_compass_rect.draw_rect(
		Rect2(Vector2(midpoint.x, 0), midpoint),
		BrandTokens.alpha(BrandTokens.OK, 0.12)
	)
	_compass_rect.draw_rect(
		Rect2(Vector2(0, midpoint.y), midpoint),
		BrandTokens.alpha(BrandTokens.SEA_LIGHT, 0.16)
	)
	_compass_rect.draw_rect(
		Rect2(midpoint, midpoint),
		BrandTokens.alpha(BrandTokens.ALERT, 0.16)
	)
	_compass_rect.draw_line(
		Vector2(midpoint.x, 0), Vector2(midpoint.x, size.y), BrandTokens.SEA_LINE, 1.0
	)
	_compass_rect.draw_line(
		Vector2(0, midpoint.y), Vector2(size.x, midpoint.y), BrandTokens.SEA_LINE, 1.0
	)
	_compass_rect.draw_rect(Rect2(Vector2.ZERO, size), BrandTokens.SEA_LINE, false, 1.0)

	var font := BrandTheme.font_data()
	var labels := BrandTokens.INK_INVERSE_DIM
	_compass_rect.draw_string(font, Vector2(4, 14), "DEAD CALM", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, labels)
	_compass_rect.draw_string(font, Vector2(4, size.y - 6), "OLD SWELL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, labels)
	_compass_rect.draw_string(font, Vector2(midpoint.x + 4, 14), "FRESH BREEZE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, labels)
	_compass_rect.draw_string(font, Vector2(midpoint.x + 4, size.y - 6), "FULL GALE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, labels)

	var dot := Vector2(wind_speed_norm * size.x, sea_state * size.y)
	_compass_rect.draw_circle(dot, 7.0, BrandTokens.BRASS)
	_compass_rect.draw_arc(dot, 7.0, 0.0, TAU, 24, BrandTokens.INK, 2.0)


func _draw_fog_bar() -> void:
	var weather := _weather_lighting()
	var visibility := 1.0
	if weather != null:
		visibility = float(weather.get("visibility"))

	var size := _fog_bar.size
	var fill_x := visibility * size.x
	_fog_bar.draw_rect(Rect2(Vector2.ZERO, size), BrandTokens.INK)
	_fog_bar.draw_rect(
		Rect2(Vector2.ZERO, Vector2(fill_x, size.y)),
		BrandTokens.WATER_SHALLOW
	)
	_fog_bar.draw_rect(
		Rect2(Vector2(fill_x, 0), Vector2(size.x - fill_x, size.y)),
		BrandTokens.FOG
	)
	_fog_bar.draw_rect(Rect2(Vector2.ZERO, size), BrandTokens.SEA_LINE, false, 1.0)

	var font := BrandTheme.font_data()
	_fog_bar.draw_string(
		font, Vector2(4, size.y - 4), "CLEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BrandTokens.INK
	)
	_fog_bar.draw_string(
		font, Vector2(size.x - 30, size.y - 4), "FOG", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BrandTokens.INK
	)


func _update_label() -> void:
	if _label == null:
		return
	var weather := _weather_lighting()
	if weather == null:
		_label.text = "WEATHER LIGHTING OFFLINE"
		return
	var precipitation := float(weather.get("precipitation"))
	var sea_state := float(weather.get("sea_state"))
	var wind_speed := float(weather.get("wind_speed_ms"))
	var visibility := float(weather.get("visibility"))
	var time_of_day := float(weather.get("time_of_day"))
	var cloud_dial := float(weather.get("cloud_cover"))
	var cloud_sky := float(weather.get("cloud_coverage"))
	var wave_height := float(weather.get("significant_wave_height_m"))
	var zone := str(weather.get("zone_label")).to_upper()
	_label.text = (
		"%s\nWIND  %.1f m/s / %.0f kn   SEA  %.1f m HS / %d%%\n"
		+ "RAIN  %d%%   CLOUD  %d%% / %d%%   FOG  %d%%   TIME  %.2f"
	) % [
		zone,
		wind_speed,
		wind_speed * 1.94384,
		wave_height,
		int(sea_state * 100),
		int(precipitation * 100),
		int(cloud_sky * 100),
		int(cloud_dial * 100),
		int((1.0 - visibility) * 100),
		time_of_day,
	]


func _weather_lighting() -> Node:
	return get_node_or_null("/root/WeatherLighting")
