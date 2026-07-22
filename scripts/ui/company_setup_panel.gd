class_name CompanySetupPanel
extends Control

signal confirmed(company_name: String, brand_color: Color, starter_vessel: String)
signal cancelled()

const BRAND_COLORS := [
	Color("2f7f83"), Color("b55f3d"), Color("c79a42"),
	Color("4d638c"), Color("657b51"), Color("7a526f"),
]

var _name_field: LineEdit
var _status: Label
var _confirm: Button
var _selected_color := BRAND_COLORS[0]
var _selected_starter := "general_cargo"
var _color_buttons: Array[Button] = []
var _starter_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


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
	shade.color = Color(0.015, 0.025, 0.03, 0.93)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(940, 620)
	panel.theme = HudStyle.make_theme()
	panel.add_theme_stylebox_override("panel", HudStyle.make_title_panel_style())
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
	eyebrow.text = "NEW COMPANY  ·  02 / 03"
	HudStyle.apply_body_font(eyebrow, 12, HudStyle.C_COPPER, true)
	root.add_child(eyebrow)
	var title := Label.new()
	title.text = "Put your name on the water"
	HudStyle.apply_display_font(title, 44, HudStyle.C_TEXT)
	root.add_child(title)
	var intro := Label.new()
	intro.text = "Your company owns the vessels, money and stored goods. The starter determines your first work—not your permanent career."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(intro, 14, HudStyle.C_LABEL)
	root.add_child(intro)

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 24)
	root.add_child(identity)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(name_col)
	var name_label := Label.new()
	name_label.text = "COMPANY NAME"
	HudStyle.apply_body_font(name_label, 11, HudStyle.C_COPPER, true)
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
	HudStyle.apply_body_font(color_label, 11, HudStyle.C_COPPER, true)
	color_col.add_child(color_label)
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 7)
	color_col.add_child(swatches)
	for color in BRAND_COLORS:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(42, 34)
		swatch.tooltip_text = color.to_html(false)
		swatch.pressed.connect(func() -> void:
			_selected_color = color
			_refresh_choices()
		)
		swatches.add_child(swatch)
		_color_buttons.append(swatch)

	var vessel_label := Label.new()
	vessel_label.text = "CHOOSE YOUR FIRST VESSEL"
	HudStyle.apply_body_font(vessel_label, 11, HudStyle.C_COPPER, true)
	root.add_child(vessel_label)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cards)
	for option in CompanyContracts.starter_options():
		var starter_id := str(option.get("id", ""))
		var card := Button.new()
		card.custom_minimum_size = Vector2(270, 210)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	HudStyle.apply_body_font(_status, 12, HudStyle.C_AMBER)
	footer.add_child(_status)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: cancelled.emit())
	footer.add_child(back)
	_confirm = MenuActionButton.new()
	_confirm.text = "Choose home port  →"
	_confirm.pressed.connect(_submit)
	footer.add_child(_confirm)
	_refresh_choices()


func _refresh_choices() -> void:
	for index in range(_color_buttons.size()):
		var button := _color_buttons[index] as Button
		var color: Color = BRAND_COLORS[index]
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.border_color = HudStyle.C_TEXT if color == _selected_color else color.darkened(0.35)
		style.set_border_width_all(3 if color == _selected_color else 1)
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
	for id in _starter_buttons:
		var button := _starter_buttons[id] as Button
		button.modulate = Color.WHITE if id == _selected_starter else Color(0.62, 0.66, 0.67)
		button.button_pressed = id == _selected_starter
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
