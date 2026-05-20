class_name HarbourMasterNpc
extends NpcInteractable

## Harbour master NPC. Handles berth booking and harbour dues enquiries.

const PEAKED_CAP_PATH := AssetPaths.HAT_PEAKED_CAP

@export var port_id: String = ""

var _dialogue: DialoguePanel

enum _Screen { MAIN, REQUEST_BERTH, VESSEL_INFO, SHIP_SELECT }
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
	if dock.reserve_berth(index, PortDock.local_player_owner_id()):
		_pending_berth_index = index
		_show_ship_select()
	else:
		_dialogue.clear()
		_dialogue.add_quote("I'm sorry — that berth was just taken.")
		_dialogue.add_back_button(_show_main)


func _show_ship_select() -> void:
	_screen = _Screen.SHIP_SELECT
	_dialogue.clear()

	var berth_n := _pending_berth_index + 1
	_dialogue.add_quote(
		"Berth #%d is held for you. One vessel per captain — what shall we bring alongside?"
		% berth_n
	)

	var session := get_node_or_null("/root/PlayerSession")
	var record: Dictionary = {}
	if session != null:
		record = session.data.get_active_vessel_record()

	var template_path := str(record.get("template_path", ""))
	var hull_id := str(record.get("hull_id", ""))
	var starter_only := _is_starter_vessel_record(template_path, hull_id)
	var has_ledger := not template_path.is_empty() and FileAccess.file_exists(template_path)
	var replace_note := (
		" (replaces your current vessel)"
		if LocalPlayerView.has_active_ship()
		else ""
	)

	if has_ledger and not starter_only:
		var display := str(record.get("display", "Your vessel"))
		var short := display.split("  •  ")[0] if "  •  " in display else display
		_dialogue.add_option(
			"Deploy %s%s" % [short, replace_note],
			_spawn_ledger_vessel.bind(template_path),
		)
	_dialogue.add_option(
		"Bring complimentary Coastal Trader (13 m)%s" % replace_note,
		_claim_starter_vessel,
	)

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


func _claim_starter_vessel() -> void:
	var path := StarterVessel.write_template_file()
	if path.is_empty():
		_dialogue.clear()
		_dialogue.add_quote("Couldn't prepare your yard loaner. Try again in a moment.")
		_dialogue.add_back_button(_show_main)
		return
	_spawn_chosen_ship(path, true)


func _spawn_ledger_vessel(template_path: String) -> void:
	_spawn_chosen_ship(template_path, false)


func _spawn_chosen_ship(scene_path: String, is_starter: bool) -> void:
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

	if is_starter:
		var session := get_node_or_null("/root/PlayerSession")
		if session != null:
			StarterVessel.set_active_vessel_record(session)

	_finish_berth_assignment(idx)


func _finish_berth_assignment(idx: int) -> void:
	var plot := get_parent() as PortPlot
	if plot != null:
		plot.respawn_staged_cargo()

	_dialogue.clear()
	_dialogue.add_quote("Berth #%d is yours, Captain. Mind the tides." % (idx + 1))
	_dialogue.add_option("Thank you.", _close)


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

func _is_starter_vessel_record(template_path: String, hull_id: String) -> bool:
	if template_path == StarterVessel.TEMPLATE_PATH:
		return true
	return hull_id == str(StarterVessel.ENTRY.get("id", "coastal_trader"))


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
