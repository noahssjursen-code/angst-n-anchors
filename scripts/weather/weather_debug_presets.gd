class_name WeatherDebugPresetsPanel
extends BrandPanel

## Premade WeatherState presets for debug; parent toggles visibility with F4.


func _ready() -> void:
	variant = BrandPanel.Variant.DARK_RULED
	theme = BrandTheme.shared()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(BrandTokens.SPACE_MD, 56)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(304, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	add_child(vbox)

	var title := BrandLabel.new("WEATHER PRESETS", BrandLabel.Role.INVERSE_DATA)
	vbox.add_child(title)
	var hint := BrandLabel.new("F4 TO HIDE", BrandLabel.Role.MICRO_DATA)
	hint.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE_DIM)
	vbox.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	vbox.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	scroll.add_child(col)

	var authored := BrandLabel.new("AUTHORED COMPONENT MOODS", BrandLabel.Role.SECTION)
	authored.add_theme_color_override(&"font_color", BrandTokens.BRASS)
	col.add_child(authored)
	for raw_mood in WeatherProfileCatalog.moods():
		var mood := raw_mood as Dictionary
		var mood_button := BrandButton.new(
			str(mood.get("label", mood.get("id", "Weather"))),
			BrandButton.Variant.SECONDARY
		)
		var mood_id := str(mood.get("id", ""))
		mood_button.pressed.connect(func() -> void: _apply_mood(mood_id))
		col.add_child(mood_button)
	_add_component_picker(col)

	var legacy := BrandLabel.new("QUICK MOODS", BrandLabel.Role.SECTION)
	legacy.add_theme_color_override(&"font_color", BrandTokens.BRASS)
	col.add_child(legacy)
	for entry in _preset_entries():
		if entry.has("sep"):
			var sep := BrandLabel.new(str(entry.sep).to_upper(), BrandLabel.Role.MICRO_DATA)
			sep.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE_DIM)
			col.add_child(sep)
			continue
		var b := BrandButton.new(str(entry.label), BrandButton.Variant.SECONDARY)
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
		row.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
		var label := BrandLabel.new(dimension.to_upper(), BrandLabel.Role.MICRO_DATA)
		label.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE_DIM)
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
	var apply_button := BrandButton.new("APPLY COMPONENT MIX", BrandButton.Variant.PRIMARY)
	apply_button.pressed.connect(func() -> void: _apply_components(selectors))
	parent.add_child(apply_button)


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
