@tool
class_name CompanyAgentNpc
extends NpcInteractable

## Company Agent NPC. Handles player shipping companies, fleet management, and crew routing.

@export var port_id: String = ""

var _dialogue: DialoguePanel

enum _Screen { MAIN, FLEET_LOGS, CLOSE }
var _screen: _Screen = _Screen.MAIN


func _ready() -> void:
	clothing_color = Color(0.15, 0.45, 0.22) # Green commerce jacket
	trousers_color = Color(0.12, 0.16, 0.24) # Professional slate trousers
	prompt_text    = "Press F — Company Agent"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")


# ── NpcInteractable hooks ──────────────────────────────────────────────────────

func _on_interact() -> void:
	_show_main()
	_dialogue.show_panel()
	open_ui()


func _on_ui_cancel() -> void:
	if _screen == _Screen.MAIN:
		_close()
	else:
		_show_main()


# ── Dialogue Screens ──────────────────────────────────────────────────────────

func _close() -> void:
	_dialogue.hide_panel()
	close_ui()


func _show_main() -> void:
	_screen = _Screen.MAIN
	_dialogue.clear()
	_dialogue.add_quote(
		"Good day, Captain. Welcome to the Shipping Company Office.\n"
		+ "We are currently setting up player commercial logistics and fleet routing ledger systems."
	)
	_dialogue.add_option("Inquire about fleet operations.", _show_fleet_logs)
	_dialogue.add_option("Nothing, thank you.", _close)


func _show_fleet_logs() -> void:
	_screen = _Screen.FLEET_LOGS
	_dialogue.clear()
	_dialogue.add_quote(
		"Once operational, you'll be able to:\n"
		+ " • Purchase cargo and fishing vessels for your private fleet.\n"
		+ " • Hire crew members to run them autonomously.\n"
		+ " • Map out trading routes between registered ports.\n"
		+ " • Fund the wages treasury to keep them sailing & earning passively!"
	)
	_dialogue.add_back_button(_show_main)


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_dialogue = DialoguePanel.new("COMPANY AGENT", Vector2(540.0, 280.0))
	add_child(_dialogue)
