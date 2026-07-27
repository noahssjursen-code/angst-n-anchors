class_name SettingsPanel
extends Control

## Branded settings workspace. Preferences apply immediately; the footer saves
## them explicitly so every setting has one predictable persistence point.

signal close_requested

var _first_focus: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = BrandTheme.shared()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := BrandPanel.new(BrandPanel.Variant.RULED)
	panel.custom_minimum_size = Vector2(820.0, 720.0)
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", BrandTokens.SPACE_LG)
	panel.add_child(content)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	content.add_child(heading)
	var title := BrandLabel.new(tr("SETTINGS"), BrandLabel.Role.DISPLAY_MEDIUM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := BrandButton.new(tr("CLOSE"), BrandButton.Variant.QUIET)
	close.pressed.connect(close_requested.emit)
	heading.add_child(close)

	content.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", BrandTokens.SPACE_LG)
	grid.add_theme_constant_override(&"v_separation", BrandTokens.SPACE_LG)
	scroll.add_child(grid)

	grid.add_child(_audio_section())
	grid.add_child(_graphics_section())
	grid.add_child(_input_section())
	grid.add_child(_interface_section())

	content.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	content.add_child(actions)
	var reset := BrandButton.new(tr("RESTORE DEFAULTS"), BrandButton.Variant.QUIET)
	reset.pressed.connect(_restore_defaults)
	actions.add_child(reset)
	var save := BrandButton.new(tr("SAVE & CLOSE"), BrandButton.Variant.LOUD)
	save.pressed.connect(_save_and_close)
	actions.add_child(save)

	if _first_focus != null:
		_first_focus.call_deferred("grab_focus")


func _audio_section() -> BrandPanel:
	var section := _section(tr("AUDIO"), tr("Mix the bridge, machinery, and score."))
	var body := section.get_meta(&"body") as VBoxContainer
	body.add_child(_slider_row(
		tr("Master"),
		GameSettings.master_volume,
		func(value: float) -> void:
			GameSettings.master_volume = value
			GameSettings.apply_all()
	))
	body.add_child(_slider_row(
		tr("Effects"),
		GameSettings.sfx_volume,
		func(value: float) -> void:
			GameSettings.sfx_volume = value
			GameSettings.apply_all()
	))
	body.add_child(_slider_row(
		tr("Music"),
		GameSettings.music_volume,
		func(value: float) -> void:
			GameSettings.music_volume = value
			GameSettings.apply_all()
	))
	return section


func _graphics_section() -> BrandPanel:
	var section := _section(tr("DISPLAY"), tr("Window and rendering behaviour."))
	var body := section.get_meta(&"body") as VBoxContainer
	body.add_child(_option_row(tr("Window mode"), [
		{"label": tr("Windowed"), "value": int(GameSettings.WindowMode.WINDOWED)},
		{"label": tr("Fullscreen"), "value": int(GameSettings.WindowMode.FULLSCREEN)},
		{"label": tr("Borderless"), "value": int(GameSettings.WindowMode.BORDERLESS)},
	], int(GameSettings.window_mode), func(value: int) -> void:
		GameSettings.window_mode = value as GameSettings.WindowMode
		GameSettings.apply_all()
	))
	body.add_child(_check_row(tr("Vertical sync"), GameSettings.vsync_enabled, func(value: bool) -> void:
		GameSettings.vsync_enabled = value
		GameSettings.apply_all()
	))
	body.add_child(_option_row(tr("Frame limit"), [
		{"label": tr("60 FPS"), "value": 60},
		{"label": tr("120 FPS"), "value": 120},
		{"label": tr("144 FPS"), "value": 144},
		{"label": tr("240 FPS"), "value": 240},
		{"label": tr("Uncapped"), "value": 0},
	], GameSettings.max_fps, func(value: int) -> void:
		GameSettings.max_fps = value
		GameSettings.apply_all()
	))
	return section


func _input_section() -> BrandPanel:
	var section := _section(tr("CONTROLS"), tr("Mouse response while walking and at the helm."))
	var body := section.get_meta(&"body") as VBoxContainer
	body.add_child(_slider_row(
		tr("Mouse sensitivity"),
		GameSettings.mouse_sensitivity,
		func(value: float) -> void: GameSettings.mouse_sensitivity = value,
		0.25,
		3.0,
		func(value: float) -> String: return "%.2f×" % value
	))
	body.add_child(_check_row(tr("Invert vertical look"), GameSettings.invert_mouse_y, func(value: bool) -> void:
		GameSettings.invert_mouse_y = value
	))
	return section


func _interface_section() -> BrandPanel:
	var section := _section(tr("INTERFACE"), tr("Scale, language, and motion comfort."))
	var body := section.get_meta(&"body") as VBoxContainer
	body.add_child(_slider_row(
		tr("UI scale"),
		GameSettings.ui_scale,
		func(value: float) -> void:
			GameSettings.ui_scale = value
			GameSettings.apply_all(),
		0.8,
		1.4,
		func(value: float) -> String: return "%d%%" % int(roundf(value * 100.0))
	))
	body.add_child(_check_row(tr("Reduce interface motion"), GameSettings.reduced_motion, func(value: bool) -> void:
		GameSettings.reduced_motion = value
		GameSettings.apply_all()
	))
	body.add_child(_option_row(tr("Language"), [
		{"label": "English", "value": 0},
	], 0, func(_value: int) -> void:
		GameSettings.interface_locale = "en"
		GameSettings.apply_all()
	))
	return section


func _section(title_text: String, description: String) -> BrandPanel:
	var panel := BrandPanel.new(BrandPanel.Variant.RAISED)
	panel.custom_minimum_size = Vector2(372.0, 238.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	panel.add_child(body)
	body.add_child(BrandLabel.new(title_text, BrandLabel.Role.SECTION))
	var description_label := BrandLabel.new(description, BrandLabel.Role.BODY_MUTED)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(description_label)
	body.add_child(HSeparator.new())
	panel.set_meta(&"body", body)
	return panel


func _slider_row(
		label_text: String,
		value: float,
		on_change: Callable,
		min_value: float = 0.0,
		max_value: float = 1.0,
		formatter: Callable = Callable()
	) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	var header := HBoxContainer.new()
	row.add_child(header)
	var label := BrandLabel.new(label_text, BrandLabel.Role.BODY)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var readout := BrandLabel.new("", BrandLabel.Role.DATA)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(readout)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 0.01
	slider.value = clampf(value, min_value, max_value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var format_value := func(current: float) -> String:
		if formatter.is_valid():
			return str(formatter.call(current))
		return "%d%%" % int(roundf(current * 100.0))
	readout.text = format_value.call(slider.value)
	slider.value_changed.connect(func(current: float) -> void:
		readout.text = format_value.call(current)
		on_change.call(current)
	)
	if _first_focus == null:
		_first_focus = slider
	return row


func _check_row(label_text: String, value: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := BrandLabel.new(label_text, BrandLabel.Role.BODY)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var check := CheckBox.new()
	check.button_pressed = value
	check.toggled.connect(func(enabled: bool) -> void: on_change.call(enabled))
	row.add_child(check)
	return row


func _option_row(
		label_text: String,
		options: Array,
		current_value: int,
		on_change: Callable
	) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	row.add_child(BrandLabel.new(label_text, BrandLabel.Role.BODY))
	var option := OptionButton.new()
	var selected_index := 0
	for index in range(options.size()):
		var record := options[index] as Dictionary
		var record_value := int(record.get("value", 0))
		option.add_item(str(record.get("label", "")), record_value)
		if record_value == current_value:
			selected_index = index
	option.selected = selected_index
	option.item_selected.connect(func(index: int) -> void:
		on_change.call(option.get_item_id(index))
	)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return row


func _restore_defaults() -> void:
	GameSettings.master_volume = 1.0
	GameSettings.sfx_volume = 1.0
	GameSettings.music_volume = 0.7
	GameSettings.window_mode = GameSettings.WindowMode.WINDOWED
	GameSettings.vsync_enabled = true
	GameSettings.max_fps = 120
	GameSettings.mouse_sensitivity = 1.0
	GameSettings.invert_mouse_y = false
	GameSettings.ui_scale = 1.0
	GameSettings.reduced_motion = false
	GameSettings.interface_locale = "en"
	GameSettings.apply_all()
	for child in get_children():
		child.queue_free()
	_first_focus = null
	_build.call_deferred()


func _save_and_close() -> void:
	GameSettings.save_settings()
	close_requested.emit()
