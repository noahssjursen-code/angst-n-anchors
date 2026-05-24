@tool
class_name CompanyAgentNpc
extends NpcInteractable

## Company Agent NPC — fleet roster and company operations.

@export var port_id: String = ""

var _panel: CompanyFleetPanel


func _ready() -> void:
	clothing_color = Color(0.15, 0.45, 0.22)
	trousers_color = Color(0.12, 0.16, 0.24)
	prompt_text    = "Press F — Company Agent"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")


func _on_interact() -> void:
	if _panel == null:
		return
	_panel.open_panel(port_id)
	open_ui()


func _on_ui_cancel() -> void:
	_close()


func _close() -> void:
	if _panel != null:
		_panel.hide_panel()
	close_ui()


func _build_ui() -> void:
	_panel = CompanyFleetPanel.new()
	_panel.closed.connect(_close)
	add_child(_panel)
