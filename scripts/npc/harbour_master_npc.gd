@tool
class_name HarbourMasterNpc
extends NpcInteractable

## Harbour master NPC. Handles berth booking and harbour dues enquiries.

const PEAKED_CAP_PATH := "res://resources/data/meshes/characters/hat_peaked_cap.json"

## Ships offered when assigning a berth. Extend as you add ship JSON templates.
const PLAYER_VESSEL_CHOICES: Array[Dictionary] = [
	{"label": "Cargo Ship", "path": "res://resources/data/ships/test_boat.json"},
	{"label": "Fuel Tanker", "path": "res://resources/data/ships/fuel_tanker.json"},
]

@export var port_id: String = ""

var _dialogue: DialoguePanel

enum _Screen { MAIN, REQUEST_BERTH, PAY_DUES, VESSEL_INFO, SHIP_SELECT }
var _screen: _Screen = _Screen.MAIN
var _pending_berth_index: int = -1


func _ready() -> void:
	clothing_color = Color(0.15, 0.22, 0.45)
	trousers_color = Color(0.12, 0.16, 0.32)
	prompt_text    = "Press F — Harbour Master"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")
	else:
		call_deferred("_add_hat")


func _add_hat() -> void:
	add_overlay("hat", PEAKED_CAP_PATH)


# ── NpcInteractable hooks ──────────────────────────────────────────────────────

func _on_interact() -> void:
	_show_main()
	_dialogue.show_panel()
	open_ui()


func _on_ui_cancel() -> void:
	if _screen == _Screen.SHIP_SELECT:
		_release_pending_berth()
		_show_request_berth()
	elif _screen == _Screen.MAIN:
		_dialogue.hide_panel()
		close_ui()
	else:
		_show_main()


# ── Screens ───────────────────────────────────────────────────────────────────

func _close() -> void:
	_release_pending_berth()
	_dialogue.hide_panel()
	close_ui()


func _show_main() -> void:
	_screen = _Screen.MAIN
	_dialogue.clear()
	_dialogue.add_quote("Good day, Captain. What can I do for you?")
	_dialogue.add_option("I would like to request a berth.",  _show_request_berth)
	_dialogue.add_option("I am here to pay my harbour dues.", _show_pay_dues)
	_dialogue.add_option("What vessels can dock here?",        _show_vessel_info)
	_dialogue.add_option("Nothing, thank you.",                _close)


func _show_request_berth() -> void:
	_screen = _Screen.REQUEST_BERTH
	_dialogue.clear()

	var dock := _get_dock()
	if dock == null:
		_dialogue.add_quote("I'm afraid the dock is not operational at the moment.")
		_dialogue.add_back_button(_show_main)
		return

	var berths     := dock.get_berths()
	var free_count := 0
	for b in berths:
		if int((b as Dictionary)["status"]) == PortDock.BerthStatus.FREE:
			free_count += 1

	if free_count == 0:
		_dialogue.add_quote("I'm sorry, Captain — we have no berths free at present.")
		_dialogue.add_back_button(_show_main)
		return

	_dialogue.add_quote("We have %d berth%s available. Which would you like?" % [
		free_count, "s" if free_count != 1 else ""
	])

	for i in range(berths.size()):
		var b      := berths[i] as Dictionary
		var status := int(b["status"])
		if status == PortDock.BerthStatus.FREE:
			var idx := i
			_dialogue.add_option("Berth #%d — assign me here." % (i + 1),
				func() -> void: _on_berth_selected(idx))
		else:
			var by  : String = str(b["reserved_by"])
			var lbl : String = "Berth #%d — %s" % [
				i + 1,
				("reserved by %s" % by) if status == PortDock.BerthStatus.RESERVED else "occupied",
			]
			_dialogue.add_disabled_option(lbl)

	_dialogue.add_back_button(_show_main)


func _on_berth_selected(index: int) -> void:
	var dock := _get_dock()
	if dock == null:
		return
	if dock.reserve_berth(index, "Captain"):
		_pending_berth_index = index
		_show_ship_select()
	else:
		_dialogue.clear()
		_dialogue.add_quote("I'm sorry — that berth was just taken.")
		_dialogue.add_back_button(_show_main)


func _show_ship_select() -> void:
	_screen = _Screen.SHIP_SELECT
	_dialogue.clear()

	_dialogue.add_quote("Which vessel shall we bring alongside?")

	var listed := false
	for entry in PLAYER_VESSEL_CHOICES:
		var label      : String = str(entry.get("label", "Vessel"))
		var scene_path : String = str(entry.get("path", ""))
		if scene_path.is_empty() or (not ResourceLoader.exists(scene_path) and not FileAccess.file_exists(scene_path)):
			continue
		_dialogue.add_option(label, _spawn_chosen_ship.bind(scene_path))
		listed = true

	if not listed:
		_release_pending_berth()
		_dialogue.add_quote("No playable vessels configured for this harbour.")
		_dialogue.add_back_button(_show_main)
		return

	_dialogue.add_option("Never mind — release the berth.", _cancel_ship_select)
	_dialogue.add_back_button(_cancel_ship_select)


func _cancel_ship_select() -> void:
	_release_pending_berth()
	_show_request_berth()


func _release_pending_berth() -> void:
	if _pending_berth_index < 0:
		return
	var dock := _get_dock()
	if dock != null:
		dock.release_berth(_pending_berth_index)
	_pending_berth_index = -1


func _spawn_chosen_ship(scene_path: String) -> void:
	var dock := _get_dock()
	var idx  := _pending_berth_index
	if dock == null or idx < 0:
		return

	_pending_berth_index = -1

	var ship := dock.spawn_player_ship(idx, scene_path)
	if ship == null:
		dock.release_berth(idx)
		_dialogue.clear()
		_dialogue.add_quote("Couldn't ready that vessel. Your berth has been released.")
		_dialogue.add_back_button(_show_main)
		return

	var plot := get_parent() as PortPlot
	if plot != null:
		plot.respawn_staged_cargo()

	_dialogue.clear()
	_dialogue.add_quote("Berth #%d is yours, Captain. Mind the tides." % (idx + 1))
	_dialogue.add_option("Thank you.", _close)


func _show_pay_dues() -> void:
	_screen = _Screen.PAY_DUES
	_dialogue.clear()
	_dialogue.add_quote("No outstanding dues on record, Captain.")
	_dialogue.add_back_button(_show_main)


func _show_vessel_info() -> void:
	_screen = _Screen.VESSEL_INFO
	_dialogue.clear()
	var dock := _get_dock()
	if dock == null:
		_dialogue.add_quote("Dock information unavailable.")
		_dialogue.add_back_button(_show_main)
		return
	var class_name_str : String = ShipClass.display_name(dock.max_ship_class)
	var max_len        : float  = ShipClass.max_length(dock.max_ship_class)
	var slots          : int    = dock.berth_count()
	_dialogue.add_quote(
		"This port accepts vessels up to %s class (max %.0f m).\n%d berth%s available." % [
			class_name_str, max_len, slots, "s" if slots != 1 else ""
		]
	)
	_dialogue.add_back_button(_show_main)


# ── Dock lookup ───────────────────────────────────────────────────────────────

func _get_dock() -> PortDock:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("PortDock") as PortDock


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	add_overlay("hat", PEAKED_CAP_PATH)
	_dialogue = DialoguePanel.new("HARBOUR MASTER")
	add_child(_dialogue)
