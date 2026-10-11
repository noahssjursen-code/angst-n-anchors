class_name HarbourMasterNpc
extends NpcInteractable

## Harbour master — class-aware deploy, refuel, abandon.
## Harbour schematic lives on the marine chart (M → Harbour), not in dialogue.


@export var port_id: String = ""


const FUEL_PRICE_PER_LITRE := 0.5
signal deployment_finished(ok: bool, message: String)
var _pending_berth_claims: Dictionary = {} ## request id -> deployment context
var _pending_storage: Dictionary = {}

func request_storage(ship: BoatBody) -> void:
	if _passenger_storage_blocked(ship): return
	if not PortServiceDesk.storage_reason(self,ship).is_empty(): return
	if not _pending_storage.is_empty(): return
	var request_id := WorldGateway.next_request_id("store-vessel")
	_pending_storage[request_id] = weakref(ship)
	WorldGateway.send_command(WorldContracts.COMMAND_VESSEL_BERTH_RELEASE, {"vessel_id":HarbourDeploy.authority_vessel_id(LocalPlayerView.get_active_vessel_record()),"reason":"stored_at_port"},request_id)


func _ready() -> void:
	appearance = CharacterCatalog.appearance_preset("harbour_master")
	prompt_text = "Press F — Harbour Master"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_wire_session")


func _wire_session() -> void:
	if not WorldGateway.command_completed.is_connected(_on_world_command_completed):
		WorldGateway.command_completed.connect(_on_world_command_completed)


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


func _commit_refuel(litres: float, price: int) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if session == null or ship == null:
		return
	if not session.spend_marks(price, "fuel", "Bunkered marine fuel", ""):
		return
	ship.add_fuel(litres)


func _deploy_fleet_vessel(record: Dictionary) -> void:
	if _passenger_storage_blocked(PlayerVessel.find_active_ship(get_tree())): return
	var resolved := VesselSpawn.resolve_deployable_record(record)
	if resolved.is_empty():
		return
	var harbour := _harbour()
	var candidates := HarbourDeploy.compatible_slots_for(harbour, resolved, _max_ship_class())
	if candidates.is_empty():
		return
	var vessel_id := HarbourDeploy.authority_vessel_id(resolved)
	if vessel_id.is_empty():
		return
	if not WorldGateway.is_ready():
		return
	var berth_ids: Array = []
	for slot_variant in candidates:
		var slot := slot_variant as QuayBerthSlot
		if slot != null:
			berth_ids.append(slot.berth_id)
	var request_id := WorldGateway.next_request_id("vessel-berth-claim")
	var old_record := LocalPlayerView.get_active_vessel_record()
	var old_vessel_id := HarbourDeploy.authority_vessel_id(old_record)
	_pending_berth_claims[request_id] = {
		"record": resolved.duplicate(true),
		"vessel_id": vessel_id,
		"old_record": old_record,
	}
	WorldGateway.send_command(
		WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body(
			vessel_id,
			port_id,
			berth_ids,
			old_vessel_id,
		),
		request_id,
	)


func _on_world_command_completed(request_id: String, result: Dictionary) -> void:
	if _pending_storage.has(request_id):
		var ship := (_pending_storage[request_id] as WeakRef).get_ref() as BoatBody
		_pending_storage.erase(request_id)
		if not bool(result.get("ok",false)):
			deployment_finished.emit(false,str(result.get("message","Storage could not be confirmed.")))
			return
		if is_instance_valid(ship) and ship == LocalPlayerView.get_active_ship():
			_network_unregister_record(LocalPlayerView.get_active_vessel_record())
			PlayerVessel.despawn_all_ships(get_tree())
		deployment_finished.emit(true,"Vessel stored. Choose a vessel to bring alongside.")
		return
	if not _pending_berth_claims.has(request_id):
		return
	var context := _pending_berth_claims[request_id] as Dictionary
	_pending_berth_claims.erase(request_id)
	if not bool(result.get("ok", false)):
		deployment_finished.emit(false, str(result.get("message", "No suitable berth is currently available.")))
		return
	var data := result.get("data", {}) as Dictionary
	var assignment := data.get("assignment", {}) as Dictionary
	var berth_id := str(assignment.get("berth_id", "")).strip_edges()
	var resolved := context.get("record", {}) as Dictionary
	if berth_id.is_empty() or resolved.is_empty():
		return
	var old_record := context.get("old_record", {}) as Dictionary
	var old_vessel_id := HarbourDeploy.authority_vessel_id(old_record)
	var new_vessel_id := str(context.get("vessel_id", ""))
	if not old_vessel_id.is_empty() and old_vessel_id != new_vessel_id:
		_network_unregister_record(old_record)
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.data != null:
		session.data.set_active_vessel(resolved)
		if session.has_method("save_now"):
			session.call("save_now")
	_spawn_chosen_ship(resolved, berth_id)


func _spawn_chosen_ship(resolved: Dictionary, preferred_berth_id: String) -> void:
	var plot := _plot()
	if plot == null:
		return
	var ship := HarbourDeploy.deploy(plot, resolved, preferred_berth_id)
	if ship == null:
		WorldGateway.send_command(
			WorldContracts.COMMAND_VESSEL_BERTH_RELEASE,
			{
				"vessel_id": HarbourDeploy.authority_vessel_id(resolved),
				"reason": "local_spawn_failed",
			},
		)
		deployment_finished.emit(false, "The ship could not be launched. The berth reservation was released.")
		return

	var scene_path := str(resolved.get("scene_path", resolved.get("template_path", ""))).strip_edges()
	_network_register_ship(ship, scene_path, str(resolved.get("hull_id", "")))
	deployment_finished.emit(true, "%s is alongside at %s." % [VesselSpawn.vessel_name_of(resolved), PortServiceDesk.friendly_berth(ship.get_moored_berth())])


func _commit_abandon() -> void:
	var active_record: Dictionary = LocalPlayerView.get_active_vessel_record()
	var vessel_id := HarbourDeploy.authority_vessel_id(active_record)
	if not vessel_id.is_empty() and WorldGateway.is_ready():
		WorldGateway.send_command(
			WorldContracts.COMMAND_VESSEL_BERTH_RELEASE,
			{"vessel_id": vessel_id, "reason": "vessel_abandoned"},
		)
	_network_unregister_record(active_record)
	PlayerVessel.despawn_all_ships(get_tree())
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.data != null:
		session.data.ship_runtime_state = {}
		if session.has_method("save_now"):
			session.call("save_now")
	_teleport_player_to_home()


func _network_unregister_record(record: Dictionary) -> void:
	if record.is_empty():
		return
	var manager := get_node_or_null("/root/NetworkManager")
	if manager == null or not manager.has_method("unregister_ship"):
		return
	var uid := str(record.get("uid", "")).strip_edges()
	if not uid.is_empty():
		manager.call("unregister_ship", uid)


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


func _passenger_storage_blocked(ship: BoatBody) -> bool:
	var reason := PassengerOperations.storage_reason(ship)
	if reason.is_empty(): return false
	deployment_finished.emit(false, reason)
	return true
