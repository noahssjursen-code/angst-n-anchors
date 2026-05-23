class_name HarbourMasterNpc
extends NpcInteractable

## Harbour master NPC. Handles berth booking and harbour dues enquiries.

const PEAKED_CAP_PATH := AssetPaths.HAT_PEAKED_CAP

@export var port_id: String = ""

var _dialogue: DialoguePanel

enum _Screen { MAIN, REQUEST_BERTH, VESSEL_INFO, SHIP_SELECT, REFUEL, ABANDON_CONFIRM }

## Price per litre of diesel. Tuned so a full 400 L tank costs ~200 marks —
## a starter player earns enough from one delivery to cover the return trip.
const FUEL_PRICE_PER_LITRE : float = 0.5
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
	if _can_offer_refuel():
		_dialogue.add_option("Refuel my ship.",                _show_refuel)
	_dialogue.add_option("What vessels can dock here?",        _show_vessel_info)
	if LocalPlayerView.has_active_ship():
		_dialogue.add_option("Abandon my vessel.",             _show_abandon_confirm)
	_dialogue.add_option("Nothing, thank you.",                _close)


# ── Refuel ────────────────────────────────────────────────────────────────────

func _can_offer_refuel() -> bool:
	var dock := _get_dock()
	if dock == null or not dock.has_fuel_point:
		return false
	return LocalPlayerView.has_active_ship()


func _show_refuel() -> void:
	_screen = _Screen.REFUEL
	_dialogue.clear()
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if ship == null:
		_dialogue.add_quote("You have no vessel to refuel, Captain.")
		_dialogue.add_back_button(_show_main)
		return
	var needed := maxf(ship.fuel_capacity_l - ship.fuel_l, 0.0)
	if needed <= 0.5:
		_dialogue.add_quote("Tank is already full, Captain. No fuel needed.")
		_dialogue.add_back_button(_show_main)
		return
	var price := int(ceil(needed * FUEL_PRICE_PER_LITRE))
	var pct := int(round(ship.get_fuel_fraction() * 100.0))
	_dialogue.add_quote(
		"Your tank reads %d%% — fill her up for %s?\n(%d L of diesel)" %
		[pct, PlayerSession.format_money(price), int(round(needed))]
	)
	_dialogue.add_option("Yes — top her off.", _commit_refuel.bind(needed, price))
	_dialogue.add_back_button(_show_main)


func _commit_refuel(litres: float, price: int) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if session == null or ship == null:
		_show_main()
		return
	if not session.spend_marks(price):
		_dialogue.clear()
		_dialogue.add_quote(
			"Your balance won't cover that, Captain.\nNeed %s more."
			% PlayerSession.format_money(price - session.get_marks())
		)
		_dialogue.add_back_button(_show_main)
		return
	ship.add_fuel(litres)
	_dialogue.clear()
	_dialogue.add_quote("Tank's full, Captain. Safe sailing.")
	_dialogue.add_option("Thank you.", _close)


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

	_network_register_ship(ship, scene_path)

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

	var tut := get_node_or_null("/root/Tutorial")
	if tut != null:
		tut.call_deferred("show", "first_berth")


# ── Abandon ship ──────────────────────────────────────────────────────────────

func _show_abandon_confirm() -> void:
	_screen = _Screen.ABANDON_CONFIRM
	_dialogue.clear()
	if not LocalPlayerView.has_active_ship():
		_dialogue.add_quote("You have no vessel to abandon, Captain.")
		_dialogue.add_back_button(_show_main)
		return
	_dialogue.add_quote(
		"Abandon your vessel? She'll be towed away and any cargo aboard "
		+ "will be forfeit. You can claim a fresh loaner afterwards."
	)
	_dialogue.add_option("Yes — scrap her.",   _commit_abandon)
	_dialogue.add_back_button(_show_main)


func _commit_abandon() -> void:
	# Despawn the ship — PlayerVessel handles cargo forfeit, dock unregister,
	# and mooring release as part of _prepare_despawn.
	PlayerVessel.despawn_all_ships(get_tree())

	# Clear active-vessel record so the harbour master offers the starter
	# loaner again on the next berth request. Drop saved ship pose too so
	# we don't try to restore a vessel that no longer exists.
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.data != null:
		session.data.set_active_vessel({})
		session.data.ship_runtime_state = {}
		if session.has_method("save_now"):
			session.call("save_now")

	# Move the player back to the home port spawn anchor so they're not
	# left floating where their ship used to be.
	_teleport_player_to_home()

	_dialogue.clear()
	_dialogue.add_quote("She's gone, Captain. Come back when you'd like another berth.")
	_dialogue.add_option("Thank you.", _close)


func _teleport_player_to_home() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var home := tree.root.find_child("HomePort", true, false) as PortPlot
	if home == null:
		return
	var spawn_pos := home.get_spawn_position()
	for node in tree.get_nodes_in_group("player"):
		var player := node as Node3D
		if player != null and is_instance_valid(player):
			player.global_position = spawn_pos


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
	return hull_id == str(StarterVessel.ENTRY.get("id", "cargo_ship"))


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


func _network_register_ship(ship_node: Node3D, template_path: String, preferred_hull_id: String = "") -> void:
	var manager := get_node_or_null("/root/NetworkManager")
	if manager == null:
		return

	var session := get_node_or_null("/root/PlayerSession")
	var record_hull_id := ""
	if session != null and session.get("data") != null:
		var record: Dictionary = session.data.get_active_vessel_record()
		if not record.is_empty():
			record_hull_id = str(record.get("hull_id", ""))

	var hull_id := HullRegistry.resolve_id_from_template(
		template_path,
		preferred_hull_id if not preferred_hull_id.is_empty() else record_hull_id
	)
	if hull_id.is_empty():
		hull_id = "cargo_ship_medium"

	var ship_id := "player_ship"
	if session != null and session.get("data") != null:
		var record: Dictionary = session.data.get_active_vessel_record()
		if not record.is_empty():
			ship_id = String(record.get("uid", "player_ship"))

	manager.call("register_ship_spawn", ship_id, hull_id, ship_node)
