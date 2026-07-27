class_name CompanySetupPanel
extends Control

signal confirmed(company_name: String, brand_color: Color, starter_vessel: String)
signal cancelled()

static var BRAND_COLORS: Array[Color] = [
	BrandTokens.color(&"HULL_TEAL"),
	BrandTokens.color(&"HULL_RED"),
	BrandTokens.color(&"HULL_YELLOW"),
	BrandTokens.color(&"HULL_BLUE"),
	BrandTokens.color(&"HULL_GREEN"),
	BrandTokens.color(&"HULL_NAVY"),
]

var _name_field: LineEdit
var _status: Label
var _confirm: Button
var _selected_color := BRAND_COLORS[0]
var _selected_starter := "general_cargo"
var _color_buttons: Array[Button] = []
var _starter_buttons: Dictionary = {}


func _ready() -> void:
	_fit_viewport()
	theme = BrandTheme.shared()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_fit_viewport):
		viewport.size_changed.connect(_fit_viewport)
	_build()


func _fit_viewport() -> void:
	if get_parent() is Control:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	var viewport := get_viewport()
	if viewport != null:
		size = viewport.get_visible_rect().size


func open_for_captain(captain_name: String) -> void:
	if not is_node_ready():
		await ready
	_name_field.text = "%s Maritime" % captain_name.strip_edges()
	_selected_color = BRAND_COLORS[0]
	_selected_starter = "general_cargo"
	_status.text = ""
	_refresh_choices()
	visible = true
	_name_field.grab_focus()
	_name_field.select_all()


func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = BrandTokens.alpha(BrandTokens.SCRIM, 0.90)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := BrandPanel.new(BrandPanel.Variant.RULED)
	panel.custom_minimum_size = Vector2(940, 620)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 38)
	margin.add_theme_constant_override("margin_right", 38)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var eyebrow := Label.new()
	eyebrow.text = "NEW COMPANY  /  02 OF 03"
	BrandTheme.apply_body_font(eyebrow, BrandTokens.LABEL_MONO, BrandTokens.INK_MUTED, true)
	root.add_child(eyebrow)
	var title := Label.new()
	title.text = "Put your name on the water"
	BrandTheme.apply_display_font(title, BrandTokens.DISPLAY_L, BrandTokens.INK)
	root.add_child(title)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.text = "Your company owns its vessels, money and stored goods. Your starter determines the first work available to you, not your permanent career."
	BrandTheme.apply_body_font(intro, BrandTokens.BODY, BrandTokens.INK_BODY)
	root.add_child(intro)

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 24)
	root.add_child(identity)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(name_col)
	var name_label := Label.new()
	name_label.text = "COMPANY NAME"
	BrandTheme.apply_body_font(name_label, BrandTokens.LABEL_MONO, BrandTokens.INK_MUTED, true)
	name_col.add_child(name_label)
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "North Coast Shipping"
	_name_field.max_length = 48
	_name_field.text_changed.connect(func(_value: String) -> void: _validate())
	_name_field.text_submitted.connect(func(_value: String) -> void: _submit())
	name_col.add_child(_name_field)

	var color_col := VBoxContainer.new()
	identity.add_child(color_col)
	var color_label := Label.new()
	color_label.text = "HOUSE COLOUR"
	BrandTheme.apply_body_font(color_label, BrandTokens.LABEL_MONO, BrandTokens.INK_MUTED, true)
	color_col.add_child(color_label)
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 7)
	color_col.add_child(swatches)
	for color in BRAND_COLORS:
		var swatch := BrandButton.new("", BrandButton.Variant.QUIET)
		swatch.custom_minimum_size = Vector2(BrandTokens.MIN_HIT_TARGET, BrandTokens.MIN_HIT_TARGET)
		swatch.tooltip_text = color.to_html(false)
		swatch.pressed.connect(func() -> void:
			_selected_color = color
			_refresh_choices()
		)
		swatches.add_child(swatch)
		_color_buttons.append(swatch)

	var vessel_label := Label.new()
	vessel_label.text = "CHOOSE YOUR FIRST VESSEL"
	BrandTheme.apply_body_font(vessel_label, BrandTokens.LABEL_MONO, BrandTokens.INK_MUTED, true)
	root.add_child(vessel_label)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cards)
	for option in CompanyContracts.starter_options():
		var starter_id := str(option.get("id", ""))
		var card := BrandButton.new("", BrandButton.Variant.SECONDARY)
		card.custom_minimum_size = Vector2(270, 210)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_ALL
		card.text = "%s\n\n%s\n\n%s" % [
			str(option.get("career", "")).to_upper(),
			str(option.get("label", "Vessel")),
			str(option.get("role", "")),
		]
		card.pressed.connect(func() -> void:
			_selected_starter = starter_id
			_refresh_choices()
		)
		cards.add_child(card)
		_starter_buttons[starter_id] = card

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BrandTheme.apply_body_font(_status, BrandTokens.LABEL_MONO, BrandTokens.ALERT)
	footer.add_child(_status)
	var back := BrandButton.new("BACK", BrandButton.Variant.QUIET)
	back.pressed.connect(func() -> void: cancelled.emit())
	footer.add_child(back)
	_confirm = BrandButton.new("", BrandButton.Variant.LOUD)
	_confirm.text = "Choose home port  >"
	_confirm.pressed.connect(_submit)
	footer.add_child(_confirm)
	_refresh_choices()


func _refresh_choices() -> void:
	for index in range(_color_buttons.size()):
		var button := _color_buttons[index] as Button
		var color: Color = BRAND_COLORS[index]
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.border_color = BrandTokens.BRASS if color == _selected_color else BrandTokens.INK
		style.set_border_width_all(3 if color == _selected_color else 1)
		style.set_content_margin_all(0)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
	for id in _starter_buttons:
		var button := _starter_buttons[id] as BrandButton
		var selected: bool = str(id) == _selected_starter
		button.variant = BrandButton.Variant.PRIMARY if selected else BrandButton.Variant.SECONDARY
		button.set_pressed_no_signal(selected)
	_validate()


func _validate() -> bool:
	if _name_field == null:
		return false
	var length := _name_field.text.strip_edges().length()
	var valid := length >= 2 and length <= 48 and CompanyContracts.STARTER_VESSELS.has(_selected_starter)
	if _confirm != null:
		_confirm.disabled = not valid
	if _status != null:
		_status.text = "Enter at least two characters." if length < 2 else ""
	return valid


func _submit() -> void:
	if not _validate():
		return
	confirmed.emit(_name_field.text.strip_edges(), _selected_color, _selected_starter)
