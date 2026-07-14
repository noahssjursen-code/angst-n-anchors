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
	scroll.custom_minimum_size = Vector2(0, 420)
	vbox.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)

	var authored := Label.new()
	authored.text = "── Authored component moods"
	authored.add_theme_color_override("font_color", Color(0.55, 0.68, 0.88, 0.70))
	col.add_child(authored)
	for raw_mood in WeatherProfileCatalog.moods():
		var mood := raw_mood as Dictionary
		var mood_button := Button.new()
		mood_button.text = str(mood.get("label", mood.get("id", "Weather")))
		var mood_id := str(mood.get("id", ""))
		mood_button.pressed.connect(func() -> void: _apply_mood(mood_id))
		col.add_child(mood_button)
	_add_component_picker(col)

	var legacy := Label.new()
	legacy.text = "── Legacy quick moods"
	legacy.add_theme_color_override("font_color", Color(0.55, 0.68, 0.88, 0.70))
	col.add_child(legacy)
	for entry in _preset_entries():
		if entry.has("sep"):
			var sep := Label.new()
			sep.text = entry.sep
			sep.add_theme_color_override("font_color", Color(0.55, 0.68, 0.88, 0.70))
			sep.add_theme_font_size_override("font_size", 10)
			sep.add_theme_constant_override("margin_top", 4)
			col.add_child(sep)
			continue
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


func _add_component_picker(parent: VBoxContainer) -> void:
	var selectors := {}
	for dimension in ["sky", "precipitation", "fog", "wind", "sea", "convection"]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = dimension.capitalize()
		label.custom_minimum_size.x = 82.0
		row.add_child(label)
		var choices := OptionButton.new()
		choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for raw in WeatherProfileCatalog.bands(dimension):
			var entry := raw as Dictionary
			choices.add_item(str(entry.get("label", entry.get("id", ""))))
			choices.set_item_metadata(choices.item_count - 1, str(entry.get("id", "")))
		row.add_child(choices)
		parent.add_child(row)
		selectors[dimension] = choices
	var apply_button := Button.new()
	apply_button.text = "Apply component mix"
	apply_button.pressed.connect(func() -> void: _apply_components(selectors))
	parent.add_child(apply_button)


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
		# ── Fair weather ─────────────────────────────────────────
		{"sep": "── Fair weather"},
		{"label": "Calm",                   "precip": 0.00, "wind": 0.00, "vis": 1.00, "cloud": 0.00},
		{"label": "Light breeze",           "precip": 0.00, "wind": 0.22, "vis": 1.00, "cloud": 0.05},
		{"label": "Fresh breeze",           "precip": 0.00, "wind": 0.45, "vis": 0.98, "cloud": 0.10},
		{"label": "Strong breeze",          "precip": 0.00, "wind": 0.65, "vis": 0.95, "cloud": 0.18},
		{"label": "Near gale",              "precip": 0.00, "wind": 0.85, "vis": 0.90, "cloud": 0.22},
		{"label": "Dry squall",             "precip": 0.00, "wind": 0.92, "vis": 0.88, "cloud": 0.10},
		# ── Overcast ─────────────────────────────────────────────
		{"sep": "── Overcast"},
		{"label": "High cloud",             "precip": 0.00, "wind": 0.12, "vis": 0.88, "cloud": 0.60},
		{"label": "Overcast",               "precip": 0.00, "wind": 0.20, "vis": 0.82, "cloud": 0.95},
		{"label": "Overcast, fresh wind",   "precip": 0.00, "wind": 0.60, "vis": 0.80, "cloud": 0.92},
		{"label": "Haze",                   "precip": 0.00, "wind": 0.10, "vis": 0.65, "cloud": 0.35},
		{"label": "Frontal approach",       "precip": 0.18, "wind": 0.50, "vis": 0.65, "cloud": 0.80},
		# ── Fog ──────────────────────────────────────────────────
		{"sep": "── Fog"},
		{"label": "Shallow mist",           "precip": 0.00, "wind": 0.05, "vis": 0.55, "cloud": 0.40},
		{"label": "Patchy fog",             "precip": 0.00, "wind": 0.08, "vis": 0.40, "cloud": 0.55},
		{"label": "Dense fog",              "precip": 0.00, "wind": 0.05, "vis": 0.15, "cloud": 0.72},
		{"label": "Thick fog",              "precip": 0.08, "wind": 0.03, "vis": 0.05, "cloud": 0.85},
		{"label": "Fog, light wind",        "precip": 0.05, "wind": 0.28, "vis": 0.25, "cloud": 0.68},
		{"label": "Fog and drizzle",        "precip": 0.35, "wind": 0.08, "vis": 0.18, "cloud": 0.80},
		# ── Precipitation ────────────────────────────────────────
		{"sep": "── Precipitation"},
		{"label": "Light drizzle",          "precip": 0.30, "wind": 0.12, "vis": 0.72, "cloud": 0.55},
		{"label": "Steady drizzle",         "precip": 0.55, "wind": 0.10, "vis": 0.62, "cloud": 0.42},
		{"label": "Moderate rain",          "precip": 0.65, "wind": 0.30, "vis": 0.52, "cloud": 0.72},
		{"label": "Heavy persistent rain",  "precip": 0.85, "wind": 0.25, "vis": 0.38, "cloud": 0.82},
		{"label": "Heavy rain, calm sea",   "precip": 0.92, "wind": 0.08, "vis": 0.42, "cloud": 0.78},
		{"label": "Passing shower",         "precip": 0.45, "wind": 0.42, "vis": 0.65, "cloud": 0.58},
		# ── Storm ────────────────────────────────────────────────
		{"sep": "── Storm"},
		{"label": "Rain squall",            "precip": 0.55, "wind": 0.72, "vis": 0.55, "cloud": 0.75},
		{"label": "Gale, driving rain",     "precip": 0.88, "wind": 0.90, "vis": 0.48, "cloud": 0.88},
		{"label": "Severe storm",           "precip": 0.95, "wind": 0.98, "vis": 0.38, "cloud": 0.95},
		{"label": "Thunderstorm",           "precip": 0.95, "wind": 0.82, "vis": 0.40, "cloud": 0.92},
		{"label": "Post-storm clearing",    "precip": 0.12, "wind": 0.62, "vis": 0.78, "cloud": 0.48},
	]


func _apply(precip: float, wind: float, vis: float, cloud: float) -> void:
	var wl := get_node_or_null("/root/WeatherLighting") as WeatherLightingState
	if wl == null:
		return
	var s := WeatherState.new()
	s.precipitation = precip
	s.wind_force = wind
	s.wind_speed_ms = wind * 22.0
	s.visibility = vis
	s.cloud_cover = cloud
	s.sea_state = wind
	s.significant_wave_height_m = lerpf(0.25, 10.0, pow(s.sea_state, 1.65))
	s.convection_index = 0.0
	WorldWeather.set_blend_to_lighting_paused(true)
	wl.apply_weather_state(s)


func _apply_mood(mood_id: String) -> void:
	var mood := WeatherProfileCatalog.mood(mood_id)
	if mood.is_empty():
		return
	_apply_component_ids(mood)


func _apply_components(selectors: Dictionary) -> void:
	var ids := {}
	for dimension in selectors.keys():
		var choices := selectors[dimension] as OptionButton
		ids[dimension] = str(choices.get_item_metadata(choices.selected))
	_apply_component_ids(ids)


func _apply_component_ids(ids: Dictionary) -> void:
	var wl := get_node_or_null("/root/WeatherLighting") as WeatherLightingState
	if wl == null:
		return
	var s := WeatherState.new()
	s.component_ids = ids.duplicate()
	s.cloud_cover = WeatherProfileCatalog.value_for_band("sky", str(ids.get("sky", "clear")), 0.5)
	s.precipitation = WeatherProfileCatalog.value_for_band("precipitation", str(ids.get("precipitation", "none")), 0.5)
	var fog := WeatherProfileCatalog.value_for_band("fog", str(ids.get("fog", "none")), 0.5)
	s.visibility = 1.0 - fog
	s.wind_force = WeatherProfileCatalog.value_for_band("wind", str(ids.get("wind", "calm")), 0.5)
	s.wind_speed_ms = s.wind_force * 22.0
	s.sea_state = WeatherProfileCatalog.value_for_band("sea", str(ids.get("sea", "calm")), 0.5)
	s.significant_wave_height_m = lerpf(0.25, 10.0, pow(s.sea_state, 1.65))
	s.convection_index = WeatherProfileCatalog.value_for_band(
		"convection",
		str(ids.get("convection", "none")),
		0.5,
	)
	s.weather_cell_id = "debug:%s" % str(ids.values())
	WorldWeather.set_blend_to_lighting_paused(true)
	wl.apply_weather_state(s)
