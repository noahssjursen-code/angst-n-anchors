extends Control

## F6 component gallery for the complete branded UI vocabulary.
## Press 1–4 to inspect default, focus, disabled, and localisation stress states.

enum State { DEFAULT, FOCUS, DISABLED, LOCALISATION }

var _state := State.DEFAULT
var _state_label: BrandLabel
var _interactive: Array[Control] = []
var _stress_labels: Array[Label] = []
var _toast: BrandToast


func _ready() -> void:
	theme = BrandTheme.shared()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_apply_state()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_state = State.DEFAULT
		KEY_2:
			_state = State.FOCUS
		KEY_3:
			_state = State.DISABLED
		KEY_4:
			_state = State.LOCALISATION
		_:
			return
	_apply_state()


func _build() -> void:
	var background := ColorRect.new()
	background.color = BrandTokens.SCRIM
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override(&"separation", 0)
	add_child(root)

	root.add_child(_build_header())
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override(&"separation", 0)
	root.add_child(content)
	content.add_child(_build_paper_catalog())
	content.add_child(_build_dark_catalog())
	root.add_child(_build_status())

	_toast = BrandToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-220.0, 84.0)
	_toast.custom_minimum_size = Vector2(440.0, 0.0)
	add_child(_toast)


func _build_header() -> Control:
	var panel := BrandPanel.new(BrandPanel.Variant.BAND)
	panel.custom_minimum_size.y = 76.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XL)
	panel.add_child(row)
	var title := BrandLabel.new("UI SYSTEM", BrandLabel.Role.DISPLAY_MEDIUM)
	title.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE)
	row.add_child(title)
	var descriptor := BrandLabel.new(
		"COMPONENT GALLERY · 1 DEFAULT · 2 FOCUS · 3 DISABLED · 4 LOCALISATION",
		BrandLabel.Role.DATA_MUTED
	)
	descriptor.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE_DIM)
	descriptor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(descriptor)
	_state_label = BrandLabel.new("", BrandLabel.Role.INVERSE_DATA)
	row.add_child(_state_label)
	return panel


func _build_paper_catalog() -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := BrandComponents.screen_margin(BrandTokens.SPACE_XL)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", BrandTokens.SECTION_GAP)
	margin.add_child(column)

	var typography := VBoxContainer.new()
	typography.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	column.add_child(typography)
	typography.add_child(BrandComponents.section_header("Typography"))
	typography.add_child(BrandLabel.new("ØSTERVIK — BERTH 2 CLEARED", BrandLabel.Role.DISPLAY_LARGE))
	typography.add_child(BrandLabel.new("The harbour master is not in a hurry.", BrandLabel.Role.BODY))
	typography.add_child(BrandLabel.new("AIS · MMSI 257043210 · 10.4 KN · HDG 074°", BrandLabel.Role.DATA))

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	column.add_child(buttons)
	buttons.add_child(BrandComponents.section_header("Actions"))
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	buttons.add_child(button_row)
	for definition in [
		["REQUEST BERTH", BrandButton.Variant.PRIMARY],
		["SET COURSE", BrandButton.Variant.LOUD],
		["DETAILS", BrandButton.Variant.SECONDARY],
		["DELETE", BrandButton.Variant.DANGER],
	]:
		var button := BrandButton.new(str(definition[0]), int(definition[1]) as BrandButton.Variant)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _toast.show_message("%s accepted." % button.text))
		button_row.add_child(button)
		_interactive.append(button)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	buttons.add_child(chip_row)
	for chip_name in ["WEATHER", "FISHING", "TRAFFIC", "CENTRE"]:
		var chip := BrandButton.new(chip_name, BrandButton.Variant.CHIP)
		chip.toggle_mode = true
		chip_row.add_child(chip)
		_interactive.append(chip)

	var fields := BrandPanel.new(BrandPanel.Variant.RULED)
	column.add_child(fields)
	var fields_column := VBoxContainer.new()
	fields_column.add_theme_constant_override(&"separation", BrandTokens.GROUP_GAP)
	fields.add_child(fields_column)
	fields_column.add_child(BrandComponents.section_header("Fields and controls"))
	var name_field := LineEdit.new()
	name_field.placeholder_text = "Company name"
	name_field.custom_minimum_size.y = BrandTokens.MIN_HIT_TARGET
	fields_column.add_child(name_field)
	_interactive.append(name_field)
	var options := OptionButton.new()
	options.custom_minimum_size.y = BrandTokens.MIN_HIT_TARGET
	options.add_item("Windowed")
	options.add_item("Fullscreen")
	options.add_item("Borderless")
	fields_column.add_child(options)
	_interactive.append(options)
	var check := CheckBox.new()
	check.text = "Reduced motion"
	check.custom_minimum_size.y = BrandTokens.MIN_HIT_TARGET
	fields_column.add_child(check)
	_interactive.append(check)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(320.0, BrandTokens.MIN_HIT_TARGET)
	slider.value = 62.0
	fields_column.add_child(slider)
	_interactive.append(slider)
	var progress := ProgressBar.new()
	progress.value = 62.0
	progress.custom_minimum_size.y = 28.0
	fields_column.add_child(progress)

	var data_panel := BrandPanel.new(BrandPanel.Variant.RAISED)
	column.add_child(data_panel)
	var data_column := VBoxContainer.new()
	data_column.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	data_panel.add_child(data_column)
	data_column.add_child(BrandComponents.section_header("Port record"))
	for pair in [
		["Class", "COASTAL"],
		["Berths", "1 · FREE"],
		["Population", "234"],
		["Exports", "GENERAL CARGO"],
	]:
		var row := BrandDataRow.new(str(pair[0]), str(pair[1]))
		data_column.add_child(row)
		_stress_labels.append(row.key_label)
	_stress_labels.append(typography.get_child(1))
	return scroll


func _build_dark_catalog() -> Control:
	var panel := BrandPanel.new(BrandPanel.Variant.DARK_RULED)
	panel.custom_minimum_size.x = 560.0
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", BrandTokens.SECTION_GAP)
	panel.add_child(column)

	var title := BrandLabel.new("NAVIGATION SYSTEMS", BrandLabel.Role.DISPLAY_MEDIUM)
	title.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE)
	column.add_child(title)
	column.add_child(BrandLabel.new(
		"Dark surfaces are instruments and viewports. Information remains paper.",
		BrandLabel.Role.INVERSE_BODY
	))

	var status := VBoxContainer.new()
	status.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	column.add_child(status)
	status.add_child(BrandComponents.section_header("Status"))
	for definition in [
		["MOORING SECURE", BrandLabel.Role.STATUS_OK],
		["VISIBILITY 0.8 NM", BrandLabel.Role.STATUS_WARN],
		["COLLISION RISK", BrandLabel.Role.STATUS_ALERT],
	]:
		var label := BrandLabel.new(str(definition[0]), int(definition[1]) as BrandLabel.Role)
		status.add_child(label)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	column.add_child(menu)
	menu.add_child(BrandComponents.section_header("Edge menu"))
	for text_value in ["Resume passage", "Navigation chart", "Company", "Settings"]:
		var menu_button := BrandMenuButton.new(text_value)
		menu.add_child(menu_button)
		_interactive.append(menu_button)

	var dialogue := BrandPanel.new(BrandPanel.Variant.PAPER)
	dialogue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(dialogue)
	var dialogue_column := VBoxContainer.new()
	dialogue_column.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	dialogue.add_child(dialogue_column)
	dialogue_column.add_child(BrandLabel.new("HARBOUR MASTER", BrandLabel.Role.DISPLAY_SMALL))
	dialogue_column.add_child(BrandLabel.new("ØYANGEN · QUAY OFFICE", BrandLabel.Role.DATA_MUTED))
	var speech := BrandLabel.new(
		"Good day, Captain. Berth two is clear until the ferry turns up. It usually turns up.",
		BrandLabel.Role.BODY
	)
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_column.add_child(speech)
	_stress_labels.append(speech)
	return panel


func _build_status() -> Control:
	var strip := BrandStatusStrip.new()
	strip.add_metric("HDG", "074°")
	strip.add_metric("COG", "071°")
	strip.add_metric("SOG", "10.4 KN")
	strip.add_metric("WIND", "295°/27")
	strip.add_metric("FUEL", "62%")
	strip.add_metric("TIME", "14:42")
	strip.add_flexible_spacer()
	strip.add_trailing("COMPONENTS 24 · TOKENS 146")
	return strip


func _apply_state() -> void:
	for control in _interactive:
		if control is BaseButton:
			(control as BaseButton).disabled = _state == State.DISABLED
		elif control is LineEdit:
			(control as LineEdit).editable = _state != State.DISABLED
		elif control is Slider:
			(control as Slider).editable = _state != State.DISABLED
	for label in _stress_labels:
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if _state == State.FOCUS:
		for control in _interactive:
			if control.focus_mode != Control.FOCUS_NONE:
				control.grab_focus()
				break
	if _state == State.LOCALISATION:
		for label in _stress_labels:
			label.text = "LIEGEPLATZ ANFORDERN · ОБСЛУЖИВАНИЕ ПОРТА"
	_state_label.text = State.keys()[_state]
