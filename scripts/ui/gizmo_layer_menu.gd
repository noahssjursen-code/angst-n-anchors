class_name GizmoLayerMenu
extends BrandPanel

signal layer_requested(layer_id: String, enabled: bool)
signal all_requested(enabled: bool)

var _buttons: Array[CheckButton] = []
var _ids := PackedStringArray()
var _selected := 0
var _syncing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	variant = BrandPanel.Variant.RULED
	custom_minimum_size = Vector2(470.0, 0.0)
	offset_left = 18.0
	offset_top = 76.0
	theme = BrandTheme.shared()
	_build()


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	add_child(box)
	box.add_child(BrandComponents.title_label("WORLD GIZMO LAYERS", 20))
	var intro := BrandComponents.body_label(
		"Select only the infrastructure you need. Choices remain active when this menu closes.", 12)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	box.add_child(BrandComponents.separator())
	for definition in WorldGizmos.LAYERS:
		var layer_id := str(definition.get("id", ""))
		var button := CheckButton.new()
		button.text = str(definition.get("label", layer_id))
		button.tooltip_text = str(definition.get("hint", ""))
		button.focus_mode = Control.FOCUS_ALL
		button.toggled.connect(_on_button_toggled.bind(layer_id))
		box.add_child(button)
		var hint := BrandComponents.subtitle_label(str(definition.get("hint", "")), 10)
		hint.add_theme_constant_override("outline_size", 2)
		box.add_child(hint)
		_buttons.append(button)
		_ids.append(layer_id)
	box.add_child(BrandComponents.separator())
	var actions := HBoxContainer.new()
	var all_on := BrandButton.new("ENABLE ALL  [CTRL+A]", BrandButton.Variant.PRIMARY)
	all_on.pressed.connect(func() -> void: all_requested.emit(true))
	actions.add_child(all_on)
	var all_off := BrandButton.new("CLEAR ALL  [X]", BrandButton.Variant.QUIET)
	all_off.pressed.connect(func() -> void: all_requested.emit(false))
	actions.add_child(all_off)
	box.add_child(actions)
	box.add_child(BrandComponents.subtitle_label("↑↓ select  ·  Space toggle  ·  G close", 10))


func sync_states(states: Dictionary) -> void:
	_syncing = true
	for index in range(_buttons.size()):
		_buttons[index].button_pressed = bool(states.get(_ids[index], false))
	_syncing = false


func focus_selected() -> void:
	if _buttons.is_empty():
		return
	_selected = clampi(_selected, 0, _buttons.size() - 1)
	_buttons[_selected].grab_focus()


func move_selection(delta: int) -> void:
	if _buttons.is_empty():
		return
	_selected = wrapi(_selected + delta, 0, _buttons.size())
	focus_selected()


func toggle_selected() -> void:
	if not _buttons.is_empty():
		_buttons[_selected].button_pressed = not _buttons[_selected].button_pressed


func _on_button_toggled(enabled: bool, layer_id: String) -> void:
	if not _syncing:
		layer_requested.emit(layer_id, enabled)
