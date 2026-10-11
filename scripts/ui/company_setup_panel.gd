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
var _world_size_row: HBoxContainer
var _world_size: OptionButton
var _intro: Label
var _work_heading: Label


func selected_world_preset() -> String:
	return str(_world_size.get_item_metadata(_world_size.selected))


func show_world_size_choice(enabled: bool) -> void:
	_world_size_row.visible = enabled


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_build_world_size_choice()


func open_for_captain(captain_name: String, walkup_purchase := false) -> void:
	if not is_node_ready():
		await ready
	_name_field.text = "%s Maritime" % captain_name.strip_edges()
	_selected_color = BRAND_COLORS[0]
	_selected_starter = "general_cargo"
	_world_size.select(0)
	_status.text = ""
	_intro.text = ("Opening capital: %s. Buy your first vessel at the shipwright. Choose the work you want nearby when selecting your home port." % PlayerData.format_money(CompanyContracts.WALKUP_STARTING_MARKS)) if walkup_purchase else "Your company owns its vessels, money and stored goods. The starter hull decides the first work, not the career."
	_work_heading.text = "Preferred first work" if walkup_purchase else "Choose your first vessel"
	_refresh_choices()
	visible = true
	_name_field.grab_focus()
	_name_field.select_all()


func _build() -> void:
	add_child(Ui.scrim())
	var modal := UiModal.new("Put your name on the water", "New company  ·  02 of 03",
		Vector2(980, 720), false, false)
	add_child(modal)
	_intro = Ui.paragraph("")
	modal.body.add_child(_intro)

	var identity := Ui.hbox(24)
	modal.body.add_child(identity)
	var name_col := Ui.vbox(4)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(name_col)
	name_col.add_child(Ui.field_label("Company name"))
	_name_field = Ui.line_edit("North Coast Shipping")
	_name_field.max_length = 48
	_name_field.text_changed.connect(func(_value: String) -> void: _validate())
	_name_field.text_submitted.connect(func(_value: String) -> void: _submit())
	name_col.add_child(_name_field)

	var color_col := Ui.vbox(4)
	identity.add_child(color_col)
	color_col.add_child(Ui.field_label("House colour"))
	var swatches := Ui.hbox(6)
	color_col.add_child(swatches)
	for color in BRAND_COLORS:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(44, 36)
		swatch.tooltip_text = color.to_html(false)
		swatch.pressed.connect(func() -> void:
			_selected_color = color
			_refresh_choices())
		swatches.add_child(swatch)
		_color_buttons.append(swatch)

	_work_heading = Ui.field_label("Choose your first vessel")
	modal.body.add_child(_work_heading)
	var cards := Ui.grid(2, 12, 12)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal.body.add_child(cards)
	for option in CompanyContracts.starter_options():
		var starter_id := str(option.get("id", ""))
		var card := Button.new()
		card.theme_type_variation = "SelectCard"
		card.custom_minimum_size = Vector2(0, 148)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.text = "%s\n\n%s\n\n%s" % [
			str(option.get("career", "")).to_upper(),
			str(option.get("label", "Vessel")),
			str(option.get("role", "")),
		]
		card.pressed.connect(func() -> void:
			_selected_starter = starter_id
			_refresh_choices())
		cards.add_child(card)
		_starter_buttons[starter_id] = card

	_status = Ui.caption("", "caution")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal.footer.add_child(_status)
	modal.footer.get_parent().visible = true
	modal.add_action("Back", "ghost", func() -> void: cancelled.emit())
	_confirm = modal.add_action("Choose home port", "primary", _submit)
	_refresh_choices()


func _build_world_size_choice() -> void:
	# Insert before company identity; inherit the existing panel's theme.
	var identity := _name_field.get_parent().get_parent()
	var body := identity.get_parent()
	_world_size_row = HBoxContainer.new()
	_world_size_row.add_theme_constant_override("separation", 12)
	body.add_child(_world_size_row)
	body.move_child(_world_size_row, identity.get_index())
	var label := Label.new()
	label.text = "Sailing area"
	_world_size_row.add_child(label)
	_world_size = OptionButton.new()
	_world_size.add_item("Standard  ·  40 × 40 km")
	_world_size.set_item_metadata(0, "standard")
	_world_size.add_item("Compact trial  ·  30 × 30 km (75%)")
	_world_size.set_item_metadata(1, "compact")
	_world_size.tooltip_text = "Generates terrain and ports in a smaller area. Ships and harbours stay full-sized. Applies only to this new captain."
	_world_size_row.add_child(_world_size)


func _refresh_choices() -> void:
	for index in range(_color_buttons.size()):
		var button := _color_buttons[index]
		var color: Color = BRAND_COLORS[index]
		var selected := color == _selected_color
		var style := UiThemeBuilder.box(color, UiPalette.PAINT if selected else color.darkened(0.35),
			3 if selected else 1, 0.0, 0.0)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
	for id in _starter_buttons:
		var button := _starter_buttons[id] as Button
		button.set_pressed_no_signal(str(id) == _selected_starter)
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
