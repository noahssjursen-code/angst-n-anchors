class_name SettingsPanel
extends Control

## Modal settings screen — graphics, audio, input. Lives on the menu layer
## alongside Pause and Map. GameMenu owns the lifecycle.

signal close_requested

const ROW_LABEL_WIDTH : int = 160


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = HudStyle.make_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var panel := UiBuilder.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -260.0
	panel.offset_right  =  260.0
	panel.offset_top    = -240.0
	panel.offset_bottom =  240.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	vbox.add_child(UiBuilder.title_label("SETTINGS"))
	vbox.add_child(UiBuilder.separator())

	# ── Audio section ──────────────────────────────────────────────────────────
	vbox.add_child(UiBuilder.section_header("AUDIO"))
	vbox.add_child(_slider_row("Master", GameSettings.master_volume, func(v: float) -> void:
		GameSettings.master_volume = v
		GameSettings.apply_all()
	))
	vbox.add_child(_slider_row("SFX", GameSettings.sfx_volume, func(v: float) -> void:
		GameSettings.sfx_volume = v
		GameSettings.apply_all()
	))
	vbox.add_child(_slider_row("Music", GameSettings.music_volume, func(v: float) -> void:
		GameSettings.music_volume = v
		GameSettings.apply_all()
	))

	vbox.add_child(UiBuilder.separator())

	# ── Graphics section ───────────────────────────────────────────────────────
	vbox.add_child(UiBuilder.section_header("GRAPHICS"))
	vbox.add_child(_window_mode_row())
	vbox.add_child(_checkbox_row("V-Sync", GameSettings.vsync_enabled, func(b: bool) -> void:
		GameSettings.vsync_enabled = b
		GameSettings.apply_all()
	))
	vbox.add_child(_fps_cap_row())

	vbox.add_child(UiBuilder.separator())

	# ── Input section ──────────────────────────────────────────────────────────
	vbox.add_child(UiBuilder.section_header("INPUT"))
	var on_sens := func(v: float) -> void:
		GameSettings.mouse_sensitivity = v
	vbox.add_child(_slider_row("Mouse sensitivity", GameSettings.mouse_sensitivity, on_sens, 0.25, 3.0))
	vbox.add_child(_checkbox_row("Invert Y", GameSettings.invert_mouse_y, func(b: bool) -> void:
		GameSettings.invert_mouse_y = b
	))

	vbox.add_child(UiBuilder.separator())

	# ── Actions ────────────────────────────────────────────────────────────────
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	vbox.add_child(actions)

	var save_btn := UiBuilder.button("SAVE & CLOSE", Vector2(200, 36))
	save_btn.pressed.connect(_on_save_pressed)
	actions.add_child(save_btn)

	var close_btn := UiBuilder.button("CLOSE", Vector2(120, 36))
	close_btn.pressed.connect(func() -> void: close_requested.emit())
	actions.add_child(close_btn)


# ── Row builders ──────────────────────────────────────────────────────────────

func _slider_row(label_text: String, value: float, on_change: Callable,
		minv: float = 0.0, maxv: float = 1.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = ROW_LABEL_WIDTH
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = 0.01
	slider.value = clampf(value, minv, maxv)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 240
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = "%d%%" % int(slider.value * 100.0)
	val_lbl.custom_minimum_size.x = 56
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val_lbl)

	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%d%%" % int(v * 100.0)
		on_change.call(v)
	)
	return row


func _checkbox_row(label_text: String, value: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = ROW_LABEL_WIDTH
	row.add_child(lbl)

	var cb := CheckBox.new()
	cb.button_pressed = value
	cb.toggled.connect(func(b: bool) -> void: on_change.call(b))
	row.add_child(cb)
	return row


func _window_mode_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = "Window mode"
	lbl.custom_minimum_size.x = ROW_LABEL_WIDTH
	row.add_child(lbl)

	var opt := OptionButton.new()
	opt.add_item("Windowed",   int(GameSettings.WindowMode.WINDOWED))
	opt.add_item("Fullscreen", int(GameSettings.WindowMode.FULLSCREEN))
	opt.add_item("Borderless", int(GameSettings.WindowMode.BORDERLESS))
	opt.selected = int(GameSettings.window_mode)
	opt.item_selected.connect(func(idx: int) -> void:
		GameSettings.window_mode = idx as GameSettings.WindowMode
		GameSettings.apply_all()
	)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(opt)
	return row


func _fps_cap_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = "FPS limit"
	lbl.custom_minimum_size.x = ROW_LABEL_WIDTH
	row.add_child(lbl)

	var opt := OptionButton.new()
	var presets := [
		{"label": "Uncapped", "value": 0},
		{"label": "60 fps",   "value": 60},
		{"label": "120 fps",  "value": 120},
		{"label": "144 fps",  "value": 144},
		{"label": "240 fps",  "value": 240},
	]
	for i in range(presets.size()):
		opt.add_item(str(presets[i]["label"]), int(presets[i]["value"]))
	# Select the entry whose id matches current setting; fall back to uncapped.
	var match_idx := 0
	for i in range(presets.size()):
		if int(presets[i]["value"]) == GameSettings.max_fps:
			match_idx = i
			break
	opt.selected = match_idx
	opt.item_selected.connect(func(idx: int) -> void:
		GameSettings.max_fps = int(presets[idx]["value"])
		GameSettings.apply_all()
	)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(opt)
	return row


func _on_save_pressed() -> void:
	GameSettings.save_settings()
	close_requested.emit()
