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
	custom_minimum_size = Vector2(470.0, 0.0)
	offset_left = 18.0
	offset_top = 76.0
	theme_type_variation = "Sheet"
	_build()


func _build() -> void:
	var box := Ui.vbox(8)
	add_child(box)
	box.add_child(Ui.header("World", "Gizmo layers",
		"Select only the infrastructure you need. Choices stay on when this menu closes."))
	box.add_child(Ui.rule())
	for definition in WorldGizmos.LAYERS:
		var layer_id := str(definition.get("id", ""))
		var button := Ui.toggle(str(definition.get("label", layer_id)))
		button.tooltip_text = str(definition.get("hint", ""))
		button.focus_mode = Control.FOCUS_ALL
		button.toggled.connect(_on_button_toggled.bind(layer_id))
		box.add_child(button)
		box.add_child(Ui.caption(str(definition.get("hint", ""))))
		_buttons.append(button)
		_ids.append(layer_id)
	box.add_child(Ui.rule())
	var actions := Ui.hbox(8)
	actions.add_child(Ui.button("Enable all", "secondary", func() -> void: all_requested.emit(true)))
	actions.add_child(Ui.button("Clear all", "ghost", func() -> void: all_requested.emit(false)))
	box.add_child(actions)
	box.add_child(Ui.key_hint("G", "Close  ·  arrows select  ·  space toggles"))


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
