class_name WeatherDebugPresetsPanel
extends PanelContainer

## Premade WeatherState presets for debug — parent toggles visibility (F4 while DebugHud open).

const _BODY := Color(0.05, 0.075, 0.12, 0.94)
const _BTN_BG := Color(0.14, 0.2, 0.32, 0.92)
const _TITLE := Color(0.93, 0.88, 0.52, 0.95)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(14, 56)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(264, 0)

	var flat := StyleBoxFlat.new()
	flat.bg_color = _BODY
	flat.border_color = Color(0.36, 0.48, 0.72, 0.45)
	flat.set_border_width_all(1)
	flat.corner_radius_top_left = 5
	flat.corner_radius_top_right = 5
	flat.corner_radius_bottom_left = 5
	flat.corner_radius_bottom_right = 5
	flat.content_margin_top = 8
	flat.content_margin_bottom = 8
	flat.content_margin_left = 10
	flat.content_margin_right = 10
	add_theme_stylebox_override("panel", flat)

	var root := MarginContainer.new()
	root.add_theme_constant_override("margin_left", 2)
	root.add_theme_constant_override("margin_right", 2)
	root.add_theme_constant_override("margin_top", 2)
	root.add_theme_constant_override("margin_bottom", 2)
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "Weather presets — F4 to hide"
	title.add_theme_color_override("font_color", _TITLE)
	title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	vbox.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)

	for entry in _preset_entries():
		var b := Button.new()
		b.text = entry.label
		b.custom_minimum_size = Vector2(0, 26)
		b.add_theme_font_size_override("font_size", 11)
		var bs := StyleBoxFlat.new()
		bs.bg_color = _BTN_BG
		bs.corner_radius_top_left = 4
		bs.corner_radius_top_right = 4
		bs.corner_radius_bottom_left = 4
		bs.corner_radius_bottom_right = 4
		b.add_theme_stylebox_override("normal", bs)
		b.add_theme_stylebox_override("hover", _hover_style(bs))
		b.add_theme_stylebox_override("pressed", _pressed_style(bs))
		b.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96, 1.0))

		var p: float = entry.precip
		var w: float = entry.wind
		var v: float = entry.vis
		var c: float = entry.cloud
		b.pressed.connect(func() -> void: _apply(p, w, v, c))
		col.add_child(b)


func _hover_style(from: StyleBoxFlat) -> StyleBoxFlat:
	var h := StyleBoxFlat.new()
	h.bg_color = from.bg_color.lightened(0.12)
	h.corner_radius_top_left = from.corner_radius_top_left
	h.corner_radius_top_right = from.corner_radius_top_right
	h.corner_radius_bottom_left = from.corner_radius_bottom_left
	h.corner_radius_bottom_right = from.corner_radius_bottom_right
	return h


func _pressed_style(from: StyleBoxFlat) -> StyleBoxFlat:
	var h := StyleBoxFlat.new()
	h.bg_color = from.bg_color.darkened(0.08)
	h.corner_radius_top_left = from.corner_radius_top_left
	h.corner_radius_top_right = from.corner_radius_top_right
	h.corner_radius_bottom_left = from.corner_radius_bottom_left
	h.corner_radius_bottom_right = from.corner_radius_bottom_right
	return h


func _preset_entries() -> Array[Dictionary]:
	return [
		{"label": "Clear calm", "precip": 0.0, "wind": 0.0, "vis": 1.0, "cloud": 0.0},
		{"label": "Light breeze", "precip": 0.0, "wind": 0.22, "vis": 1.0, "cloud": 0.05},
		{"label": "Overcast (dry)", "precip": 0.0, "wind": 0.12, "vis": 0.92, "cloud": 0.92},
		{"label": "Dry squall", "precip": 0.0, "wind": 0.88, "vis": 0.94, "cloud": 0.08},
		{"label": "Grey drizzle", "precip": 0.55, "wind": 0.08, "vis": 0.68, "cloud": 0.38},
		{"label": "Heavy rain · calm seas", "precip": 0.92, "wind": 0.06, "vis": 0.48, "cloud": 0.52},
		{"label": "Full storm · gale", "precip": 0.88, "wind": 0.92, "vis": 0.52, "cloud": 0.58},
		{"label": "Sea fog · light swell", "precip": 0.06, "wind": 0.18, "vis": 0.28, "cloud": 0.65},
		{"label": "Pea soup fog + drizzle", "precip": 0.42, "wind": 0.05, "vis": 0.12, "cloud": 0.78},
	]


func _apply(precip: float, wind: float, vis: float, cloud: float) -> void:
	var wl := get_node_or_null("/root/WeatherLighting") as WeatherLightingState
	if wl == null:
		return
	var s := WeatherState.new()
	s.precipitation = precip
	s.wind_force = wind
	s.visibility = vis
	s.cloud_cover = cloud
	wl.apply_weather_state(s)
