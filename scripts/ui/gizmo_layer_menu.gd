class_name GizmoLayerMenu
extends PanelContainer

signal layer_requested(layer_id: String, enabled: bool)
signal all_requested(enabled: bool)

var _buttons: Array[CheckButton] = []
var _ids := PackedStringArray()
var _selected := 0
var _syncing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(430.0, 0.0)
	offset_left = 18.0
	offset_top = 76.0
	theme = HudStyle.make_theme()
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)
	box.add_child(UiBuilder.title_label("WORLD GIZMO LAYERS", 20))
	var intro := UiBuilder.body_label(
		"Enable only the debug geometry you need. Layers remain selected when this menu closes.", 12)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	box.add_child(UiBuilder.separator())
	for definition in WorldGizmos.LAYERS:
		var layer_id := str(definition.get("id", ""))
		var button := CheckButton.new()
		button.text = str(definition.get("label", layer_id))
		button.tooltip_text = str(definition.get("hint", ""))
		button.focus_mode = Control.FOCUS_ALL
		button.toggled.connect(_on_button_toggled.bind(layer_id))
		box.add_child(button)
		var hint := UiBuilder.subtitle_label(str(definition.get("hint", "")), 10)
		hint.add_theme_constant_override("outline_size", 2)
		box.add_child(hint)
		_buttons.append(button)
		_ids.append(layer_id)
	box.add_child(UiBuilder.separator())
	var actions := HBoxContainer.new()
	var all_on := UiBuilder.compact_button("ENABLE ALL  [CTRL+A]", 165)
	all_on.pressed.connect(func() -> void: all_requested.emit(true))
	actions.add_child(all_on)
	var all_off := UiBuilder.compact_button("CLEAR ALL  [X]", 145)
	all_off.pressed.connect(func() -> void: all_requested.emit(false))
	actions.add_child(all_off)
	box.add_child(actions)
	box.add_child(UiBuilder.subtitle_label("↑↓ select  ·  Space toggle  ·  G close", 10))


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
	if _buttons.is_empty():
		return
	_buttons[_selected].button_pressed = not _buttons[_selected].button_pressed


func _on_button_toggled(enabled: bool, layer_id: String) -> void:
	if not _syncing:
		layer_requested.emit(layer_id, enabled)
