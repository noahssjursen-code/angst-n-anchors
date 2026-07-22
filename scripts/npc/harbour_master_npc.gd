class_name HarbourMasterNpc
extends NpcInteractable

## Harbour master — class-aware deploy, refuel, abandon.
## Harbour schematic lives on the marine chart (M → Harbour), not in dialogue.

const PEAKED_CAP_PATH := AssetPaths.HAT_PEAKED_CAP

@export var port_id: String = ""

var _dialogue: DialoguePanel

enum _Screen { MAIN, REQUEST_BERTH, SHIP_SELECT, VESSEL_INFO, REFUEL, LAND_CATCH, ABANDON_CONFIRM }

const FUEL_PRICE_PER_LITRE := 0.5
var _screen: _Screen = _Screen.MAIN


func _ready() -> void:
	clothing_color = Color(0.15, 0.22, 0.45)
	trousers_color = Color(0.12, 0.16, 0.32)
	prompt_text = "Press F — Harbour Master"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")
		call_deferred("_wire_session")
	else:
		call_deferred("_add_hat")


func _wire_session() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or not session.has_signal("vessels_synced"):
		return
	if not session.vessels_synced.is_connected(_on_vessels_synced):
		session.vessels_synced.connect(_on_vessels_synced)


func _on_vessels_synced() -> void:
	if _screen == _Screen.SHIP_SELECT:
		_show_ship_select()


func _add_hat() -> void:
	add_overlay("hat", PEAKED_CAP_PATH)


func _on_interact() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		_show_main()
		_dialogue.show_panel()
		open_ui()
		return
	var config := get_node_or_null("/root/ServerConfig")
	if config == null or not bool(config.get("is_multiplayer_mode")):
		_show_main()
		_dialogue.show_panel()
		open_ui()
		return
	VesselSync.refresh_for_ui(session, func() -> void:
		_show_main()
		_dialogue.show_panel()
		open_ui()
	)


func _on_ui_cancel() -> void:
	if _screen == _Screen.SHIP_SELECT:
		_show_request_berth()
	elif _screen == _Screen.MAIN:
		_dialogue.hide_panel()
		close_ui()
	else:
		_show_main()


func _close() -> void:
	_dialogue.hide_panel()
	close_ui()


func _show_main() -> void:
	_screen = _Screen.MAIN
	_dialogue.clear()
	_dialogue.add_quote(
		"Good day, Captain. What can I do for you?\n"
		+ "(Harbour board is on your chart — press M, then Harbour.)"
	)
	_dialogue.add_option("Request a berth / deploy my vessel.", _show_request_berth)
	if _can_offer_refuel():
		_dialogue.add_option("Refuel my ship.", _show_refuel)
	if _can_offer_catch_landing():
		_dialogue.add_option("Land and sell my catch.", _show_land_catch)
	_dialogue.add_option("What vessels can dock here?", _show_vessel_info)
	if LocalPlayerView.has_active_ship():
		_dialogue.add_option("Abandon my vessel.", _show_abandon_confirm)
	_dialogue.add_option("Nothing, thank you.", _close)


func _can_offer_refuel() -> bool:
	var data := _port_data()
	if data != null and not data.has_fuel_point:
		return false
	return LocalPlayerView.has_active_ship()


func _can_offer_catch_landing() -> bool:
	var data := _port_data()
	## Catch is physically landed at the generated RSW station. Do not offer
	## the old instant-sale shortcut at ports without that infrastructure.
	if data == null or not data.has_fish_landing:
		return false
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if ship == null or ship.get_harbour_port_id() != port_id or ship.get_moored_berth() == null:
		return false
	for hold in ship.get_catch_holds():
		if not hold.state.is_empty():
			return true
	return false


func _show_land_catch() -> void:
	_screen = _Screen.LAND_CATCH
	_dialogue.clear()
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if ship == null:
		_show_main()
		return
	var states: Array[CatchHoldState] = []
	for hold in ship.get_catch_holds():
		states.append(hold.get_state())
	var offer := FishingLandingService.quote(states)
	_dialogue.add_quote(
		("The fish market estimates %s for %.1f tonnes of fresh catch.\n"
		+ "Take the vessel alongside the fishing berth and speak to the fish landing operator. "
		+ "The RSW pump will weigh and transfer the catch before payment.")
		% [PlayerSession.format_money(int(offer.get("value_marks", 0))), float(offer.get("mass_kg", 0.0)) / 1000.0]
	)
	_dialogue.add_back_button(_show_main)


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
		"Your tank reads %d%% — fill her up for %s?\n(%d L of diesel)" % [
			pct, PlayerSession.format_money(price), int(round(needed)),
		]
	)
	_dialogue.add_option("Yes — top her off.", _commit_refuel.bind(needed, price))
	_dialogue.add_back_button(_show_main)


func _commit_refuel(litres: float, price: int) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if session == null or ship == null:
		_show_main()
		return
	if not session.spend_marks(price, "fuel", "Bunkered marine fuel", ""):
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

	if not _captain_can_deploy_vessel():
		_dialogue.add_quote(
			"You've no vessel on the registry yet, Captain.\n"
			+ "Visit the Shipwright and commission a vessel first — then come back for a berth."
		)
		_dialogue.add_back_button(_show_main)
		return

	var harbour := _harbour()
	if harbour == null:
		_dialogue.add_quote("I'm afraid the harbour board is offline at the moment.")
		_dialogue.add_back_button(_show_main)
		return

	var free_count := harbour.free_berths().size()
	if free_count == 0:
		_dialogue.add_quote("I'm sorry, Captain — we have no berths free at present.")
		_dialogue.add_back_button(_show_main)
		return

	_dialogue.add_quote(
		(
			"We have %d free berth%s. I'll match your hull to the right quay family — "
			+ "bulk carriers go to bulk, deck cargo to the apron."
		)
		% [free_count, "s" if free_count != 1 else ""]
	)
	_dialogue.add_option("Assign me a berth for my vessel.", _show_ship_select)
	_dialogue.add_back_button(_show_main)


func _show_ship_select() -> void:
	_screen = _Screen.SHIP_SELECT
	_dialogue.clear()

	var session := get_node_or_null("/root/PlayerSession")
	var fleet: Array = []
	if session != null and session.data != null:
		fleet = session.data.get_harbour_vessel_records()

	if fleet.is_empty():
		_dialogue.add_quote(
			"No commissioned vessel on file, Captain.\n"
			+ "The Shipwright builds replacement vessels."
		)
		_dialogue.add_back_button(_show_request_berth)
		return

	var harbour := _harbour()
	var max_class := _max_ship_class()
	var replace_note := " (replaces current)" if LocalPlayerView.has_active_ship() else ""
	_dialogue.add_quote(
		"Which hull from your registry?\nPort accepts up to %s."
		% ShipClass.display_name(max_class)
	)

	for entry_raw in fleet:
		var record := entry_raw as Dictionary
		var req := HarbourDeploy.ship_requirements(record)
		var vessel_name := str(req.get("display", VesselSpawn.vessel_name_of(record)))
		var class_name_str := str(req.get("ship_class_name", "Vessel"))
		var loa := float(req.get("loa_display_m", ShipClass.display_metres(float(req.get("loa_m", 0.0)))))
		var fits_port := ShipClass.fits(req["ship_class"] as ShipClass.Type, max_class)
		var slots := HarbourDeploy.free_slots_for(harbour, record, max_class) if harbour != null \
				else []
		var families: PackedStringArray = req["terminal_families"]
		var family_note := ""
		if not families.is_empty():
			family_note = " · %s" % CommodityCatalog.terminal_family_display(families[0])
		if not fits_port or slots.is_empty():
			_dialogue.add_disabled_option(
				"%s — %.0f m %s%s (no free matching berth)" % [
					vessel_name, loa, class_name_str, family_note,
				]
			)
			continue
		var best := slots[0] as QuayBerthSlot
		var quay_note := ""
		if best != null:
			quay_note = " → %s" % CommodityCatalog.terminal_family_display(best.family)
		_dialogue.add_option(
			"Deploy %s — %.0f m %s%s%s%s" % [
				vessel_name, loa, class_name_str, family_note, quay_note, replace_note,
			],
			_deploy_fleet_vessel.bind(record),
		)

	_dialogue.add_option("Never mind.", _show_request_berth)
	_dialogue.add_back_button(_show_request_berth)


func _deploy_fleet_vessel(record: Dictionary) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.data != null:
		session.data.set_active_vessel(record)
		if session.has_method("save_now"):
			session.call("save_now")
	var resolved := VesselSpawn.resolve_deployable_record(record)
	if resolved.is_empty():
		_dialogue.clear()
		_dialogue.add_quote(
			"That vessel cannot sail until its registration checklist passes at the shipyard."
		)
		_dialogue.add_back_button(_show_main)
		return
	_spawn_chosen_ship(resolved)


func _spawn_chosen_ship(resolved: Dictionary) -> void:
	var plot := _plot()
	if plot == null:
		_dialogue.clear()
		_dialogue.add_quote("Harbour plot missing — cannot deploy.")
		_dialogue.add_back_button(_show_main)
		return
	var ship := HarbourDeploy.deploy(plot, resolved)
	if ship == null:
		_dialogue.clear()
		_dialogue.add_quote(
			"Couldn't ready that vessel alongside. No free berth matches her class and quay type.\n"
			+ "Check the chart harbour board (M → Harbour) for free bulk / cargo faces."
		)
		_dialogue.add_back_button(_show_main)
		return

	var scene_path := str(resolved.get("scene_path", resolved.get("template_path", ""))).strip_edges()
	_network_register_ship(ship, scene_path, str(resolved.get("hull_id", "")))
	var berth_id := str(ship.get_meta("harbour_berth_id", ""))
	var slot := _harbour().berth(berth_id) if _harbour() != null else null
	var family := slot.family if slot != null else ""
	_dialogue.clear()
	_dialogue.add_quote(
		"She's alongside at %s%s, Captain. Mind the tides."
		% [
			berth_id.get_file() if not berth_id.is_empty() else "her berth",
			(" (%s)" % CommodityCatalog.terminal_family_display(family)) if not family.is_empty() else "",
		]
	)
	_dialogue.add_option("Thank you.", _close)
	var tut := get_node_or_null("/root/Tutorial")
	if tut != null:
		tut.call_deferred("show", "first_berth")


func _show_abandon_confirm() -> void:
	_screen = _Screen.ABANDON_CONFIRM
	_dialogue.clear()
	if not LocalPlayerView.has_active_ship():
		_dialogue.add_quote("You have no vessel to abandon, Captain.")
		_dialogue.add_back_button(_show_main)
		return
	_dialogue.add_quote(
		"Abandon your vessel? She'll be towed away and any cargo aboard "
		+ "will be forfeit. Your hull stays on the registry — request a berth to deploy her again."
	)
	_dialogue.add_option("Yes — scrap her.", _commit_abandon)
	_dialogue.add_back_button(_show_main)


func _commit_abandon() -> void:
	PlayerVessel.despawn_all_ships(get_tree())
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.data != null:
		session.data.ship_runtime_state = {}
		if session.has_method("save_now"):
			session.call("save_now")
	_teleport_player_to_home()
	_dialogue.clear()
	_dialogue.add_quote("She's gone, Captain. Come back when you'd like her alongside again.")
	_dialogue.add_option("Thank you.", _close)


func _teleport_player_to_home() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var home := tree.root.find_child("HomePort", true, false) as PortPlot
	if home == null:
		home = _plot()
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
	var harbour := _harbour()
	var max_class := _max_ship_class()
	var slots := harbour.berths().size() if harbour != null else 0
	var free_n := harbour.free_berths().size() if harbour != null else 0
	var data := _port_data()
	var export_line := "—"
	if data != null and not data.commodity_export.is_empty():
		export_line = CommodityCatalog.commodity_display(data.commodity_export)
	_dialogue.add_quote(
		(
			"This port accepts vessels up to %s class (max %.0f m).\n"
			+ "%d berth%s (%d free).\nPrimary export: %s.\n"
			+ "Open the chart (M) and switch to Harbour for the live board."
		)
		% [
			ShipClass.display_name(max_class),
			ShipClass.max_length(max_class),
			slots,
			"s" if slots != 1 else "",
			free_n,
			export_line,
		]
	)
	_dialogue.add_back_button(_show_main)


func _captain_can_deploy_vessel() -> bool:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.data == null:
		return false
	return session.data.can_deploy_at_harbour()


func _plot() -> PortPlot:
	return get_parent() as PortPlot


func _harbour() -> HarbourController:
	var plot := _plot()
	return plot.harbour_controller() if plot != null else null


func _port_data() -> PortData:
	var plot := _plot()
	return plot.port_data() if plot != null else null


func _max_ship_class() -> ShipClass.Type:
	var data := _port_data()
	if data != null:
		return data.max_ship_class
	return ShipClass.Type.COASTAL_TRADER


func _build_ui() -> void:
	add_overlay("hat", PEAKED_CAP_PATH)
	_dialogue = DialoguePanel.new("HARBOUR MASTER", Vector2(640.0, 480.0))
	add_child(_dialogue)


func _network_register_ship(
		ship_node: Node3D,
		template_path: String,
		preferred_hull_id: String = "",
) -> void:
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
		preferred_hull_id if not preferred_hull_id.is_empty() else record_hull_id,
	)
	if hull_id.is_empty():
		hull_id = "fishing_trawler_small"
	var ship_id := "player_ship"
	if session != null and session.get("data") != null:
		var record2: Dictionary = session.data.get_active_vessel_record()
		if not record2.is_empty():
			ship_id = String(record2.get("uid", "player_ship"))
	manager.call("register_ship_spawn", ship_id, hull_id, ship_node)
