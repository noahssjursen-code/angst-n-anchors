extends Node

## Per-client view of the player and their world. Single source of truth
## that UIs consult to ask "what is *my* player doing?".

signal marks_changed(balance: int)
signal company_changed(summary: Dictionary)
signal helm_changed(boat: Node) # null when not helming
signal contracts_changed(contracts: Array) # kept empty until trade rewrite
signal voyage_changed(snapshot: Dictionary)
signal fishing_changed(snapshot: Dictionary)


var _session: Node = null
var _catalog: Node = null
var _state: Node = null
var _helmed: Node = null
var _presentation_tick := 0.0
var _view_rod: RodFishingStation


func _process(delta: float) -> void:
	if get_tree().get_first_node_in_group("player") == null: return
	_presentation_tick -= delta
	if _presentation_tick <= 0.0:
		_presentation_tick = 0.1
		voyage_changed.emit(get_voyage_snapshot())
	# A reaction-based instrument needs render-rate state. Reuse the rod resolved
	# by the slow ship snapshot; no contracts, habitat scans or tree searches here.
	if is_instance_valid(_view_rod) and _view_rod.working and not is_helming() and not WorldGateway.is_remote():
		fishing_changed.emit(_view_rod.snapshot())


func service_snapshot(npc: NpcInteractable) -> Dictionary:
	return PortServiceDesk.describe(npc)


func get_voyage_snapshot() -> Dictionary:
	var ship := get_active_ship() as BoatBody
	_view_rod = ship.get_node_or_null("RodFishingStation") as RodFishingStation if ship != null else null
	var result := {"helming": is_helming(), "ship": false, "name": "", "objective": "Speak to the shipwright to buy your first vessel."}
	if ship == null:
		if _session != null and not _session.data.owned_vessels.is_empty():
			result.objective = "Ask the harbourmaster to deploy your vessel at a suitable quay."
		return result
	var sounder := ship.get_node_or_null("ShipSounder")
	if sounder != null: result["sonar"] = sounder.snapshot()
	if _view_rod!=null and not WorldGateway.is_remote():result["fishing"]=_view_rod.snapshot()
	result.ship = true
	result.name = VesselSpawn.vessel_name_of(get_active_vessel_record())
	var local_velocity := ship.global_basis.inverse() * ship.linear_velocity
	result["speed_kn"] = Vector2(ship.linear_velocity.x,ship.linear_velocity.z).length()*1.943844
	result["ahead_kn"] = -local_velocity.z*1.943844
	result["side_kn"] = local_velocity.x*1.943844
	result["heading"] = fposmod(rad_to_deg(atan2(-ship.global_basis.z.x,-ship.global_basis.z.z)),360.0)
	result["fuel"] = ship.get_fuel_fraction()
	result["port"] = get_port_display_name(ship.get_harbour_port_id())
	var berth := ship.get_moored_berth() as QuayBerthSlot
	result["berth"] = PortServiceDesk.friendly_berth(berth) if berth != null else "Underway"
	var mooring := ship.get_node_or_null("MooringComponent") as MooringComponent
	result["bow"] = mooring.bow_line_tied if mooring != null else false
	result["stern"] = mooring.stern_line_tied if mooring != null else false
	result["mooring_reason"] = mooring.last_mooring_reject if mooring != null else ""
	var gangways := ship.find_children("*", "ShipGangway", true, false)
	result["gangway"] = str(gangways[0].status) if not gangways.is_empty() else "No gangway fitted"
	var controller := ship.get_node_or_null("BoatController") as BoatController
	var propulsion := ship.get_node_or_null("PropulsionComponent") as PropulsionComponent
	result["engine_running"] = propulsion != null and propulsion.engine_running
	if controller != null:
		var labels := ["ASTERN", "NEUTRAL", "DEAD SLOW", "HALF AHEAD", "FULL AHEAD"]
		result["order"] = labels[clampi(controller.get_throttle_stage_idx(),0,4)]
		result["thruster"] = ["Off","Bow","Crab"][clampi(controller.get_thruster_mode(),0,2)]
		var rudder := ship.get_node_or_null("RudderComponent") as RudderComponent
		result["rudder"] = rudder.rudder_input*rudder.max_rudder_angle_deg if rudder != null else 0.0
		result["autopilot"] = controller.get_autopilot() != null and controller.get_autopilot().is_engaged()
	var contracts := get_active_contracts()
	result.objective = "Speak to the cargo agent for compatible work, or prepare your fishing gear."
	for job in contracts:
		if str(job.get("vessel_uid","")) != str(get_active_vessel_record().get("uid","")): continue
		var quantity := float(job.get("quantity",0))
		var loaded := float(job.get("loaded_quantity",0))
		var delivered := float(job.get("delivered_quantity",0))
		var destination := get_port_display_name(str(job.get("destination_port_id","")))
		if loaded < quantity: result.objective = "Ask the quay operator to load your booked cargo."
		elif ship.get_harbour_port_id() == str(job.get("destination_port_id","")):
			result.objective = "Ask the receiving operator to unload. %.0f / %.0f delivered." % [delivered,quantity]
		else: result.objective = "Deliver cargo to %s. Open the chart to plan your passage." % destination
		break
	var passengers := get_passenger_voyage_snapshot()
	if not passengers.is_empty(): result.objective = passengers.objective
	return result


func get_catch_library(hold_id: String) -> Dictionary:
	for hold in CatchHoldComponent.get_all_for_ship(get_active_ship()):
		if hold.hold_id!=hold_id:continue
		var items:Array=[]
		for lot in hold.state.lots:
			var item:=lot.to_dict();var species:=FishCatalog.species(lot.species_id)
			item.merge({"name":species.get("name",lot.species_id.capitalize()),"norwegian_name":species.get("norwegian_name",""),"rarity":species.get("rarity",""),"description":species.get("description","Bulk catch from this vessel."),"value_marks":roundi(FishingLandingService.lot_value(lot,lot.mass_kg))},true)
			items.append(item)
		var states:Array[CatchHoldState]=[hold.state]
		return {"items":items,"mass_kg":hold.state.total_mass_kg(),"capacity_kg":hold.state.capacity_kg,"value_marks":FishingLandingService.quote(states).value_marks}
	return {}

func get_interaction_hint() -> String:
	if is_helming(): return "F  Leave helm"
	var ship := get_active_ship()
	var rod := ship.get_node_or_null("RodFishingStation") as RodFishingStation if ship != null else null
	if rod != null:
		if rod.can_interact(): return rod.equipment_prompt()
	var pots: Node = ship.get_node_or_null("CrabPotStation") if ship != null else null
	if pots != null and pots.has_method("hint"):
		var pot_hint := str(pots.call("hint"))
		if not pot_hint.is_empty(): return pot_hint
	for hold in CatchHoldComponent.get_all_for_ship(ship):
		if hold.can_inspect(): return "F  Inspect catch crate"
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null: return ""
	for npc: Node in get_tree().get_nodes_in_group("port_service_npc"):
		if npc is NpcInteractable and npc._can_interact(): return npc.prompt_text.replace("Press ","")
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null: return ""
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3.0)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = true
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var node: Node = hit.get("collider")
	while is_instance_valid(node):
		if node is BridgeInteractable or node is CaptainsChair: return "F  Take the helm"
		node = node.get_parent()
	return ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_session = get_node_or_null("/root/PlayerSession")
	_catalog = get_node_or_null("/root/PortCatalog")
	_state = get_node_or_null("/root/GameState")

	if _session != null:
		if _session.has_signal("marks_changed") and not _session.marks_changed.is_connected(_emit_marks):
			_session.marks_changed.connect(_emit_marks)
		if _session.has_signal("company_changed") and not _session.company_changed.is_connected(_emit_company):
			_session.company_changed.connect(_emit_company)
	var freight := get_node_or_null("/root/FreightService")
	if freight != null and not freight.contracts_changed.is_connected(_emit_contracts):
		freight.contracts_changed.connect(_emit_contracts)

	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "BoatController", true, false):
		_wire_controller(n as BoatController)


func get_marks() -> int:
	if _session == null:
		return 0
	return int(_session.get_marks())


func get_display_name() -> String:
	if _session == null:
		return ""
	return str(_session.data.display_name)


func get_captain_id() -> String:
	if _session == null or _session.data == null:
		return ""
	return str(_session.data.captain_id)


func get_account_id() -> String:
	if _session == null or _session.data == null:
		return ""
	return str(_session.data.account_id)


## Stable identity used by transient multiplayer replication. A multiplayer
## session must have a server-issued captain id before UDP replication begins.
func get_network_player_id() -> String:
	var captain_id := get_captain_id().strip_edges()
	if not captain_id.is_empty():
		return captain_id
	return get_account_id().strip_edges()


func get_appearance() -> CharacterAppearance:
	if _session == null or _session.data == null:
		return CharacterAppearance.default_appearance()
	var appearance := _session.data.appearance as CharacterAppearance
	return appearance if appearance != null else CharacterAppearance.default_appearance()


func get_active_vessel_record() -> Dictionary:
	if _session == null or _session.data == null:
		return {}
	return _session.data.get_active_vessel_record()


func get_world_context() -> Dictionary:
	if _session == null or _session.data == null:
		return {}
	return (_session.data.world_context as Dictionary).duplicate(true)


func get_company_summary() -> Dictionary:
	if _session == null or not _session.has_method("get_company_summary"):
		return {}
	return _session.get_company_summary() as Dictionary


func is_helming() -> bool:
	return _helmed != null and is_instance_valid(_helmed)


func get_helmed_boat() -> Node:
	if _helmed == null or not is_instance_valid(_helmed):
		return null
	return _helmed


func get_active_ship() -> Node:
	return PlayerVessel.find_active_ship(get_tree())


func has_active_ship() -> bool:
	return get_active_ship() != null


func get_active_ship_berth_context() -> Dictionary:
	var ship := get_active_ship()
	if ship == null:
		return {}
	return {
		"port_id": str(ship.call("get_harbour_port_id")) \
			if ship.has_method("get_harbour_port_id") else "",
		"berth_id": str(ship.call("get_moored_berth_id")) \
			if ship.has_method("get_moored_berth_id") else "",
	}


func get_autopilot_snapshot() -> Dictionary:
	var ship := get_active_ship()
	if ship == null:
		return {}
	var snapshot := {}
	if ship.has_method("get_fuel_fraction"):
		snapshot["fuel_fraction"] = float(ship.call("get_fuel_fraction"))
	var autopilot := ship.get_node_or_null("VesselAutopilot") as VesselAutopilot
	if autopilot == null:
		return snapshot
	snapshot = autopilot.voyage_snapshot()
	if ship.has_method("get_fuel_fraction"):
		snapshot["fuel_fraction"] = float(ship.call("get_fuel_fraction"))
	snapshot["remaining_distance_m"] = autopilot.remaining_distance_m()
	if autopilot.route != null:
		snapshot["destination_port_id"] = autopilot.route.destination_port_id
	var watch := ship.get_node_or_null("BridgeWatchAlarm") as BridgeWatchAlarm
	if watch != null:
		snapshot["bridge_watch"] = watch.snapshot()
	return snapshot


func get_active_contracts() -> Array:
	var freight := get_node_or_null("/root/FreightService")
	return freight.active_contracts() if freight != null else []


func get_contract_cancellation(contract_id: String) -> Dictionary:
	return FreightService.cancellation_status(contract_id)


func get_port_display_name(port_id: String) -> String:
	if _catalog == null or port_id.is_empty():
		return ""
	return str(_catalog.get_port_display_name(port_id))


func get_port_position(port_id: String) -> Vector3:
	if _catalog == null or port_id.is_empty():
		return Vector3(INF, INF, INF)
	return _catalog.get_port_position(port_id)


func _on_node_added(node: Node) -> void:
	if node is BoatController:
		_wire_controller(node as BoatController)


func _wire_controller(bc: BoatController) -> void:
	if bc == null:
		return
	if not bc.helm_activated.is_connected(_on_helm_on.bind(bc)):
		bc.helm_activated.connect(_on_helm_on.bind(bc))
	if not bc.helm_deactivated.is_connected(_on_helm_off):
		bc.helm_deactivated.connect(_on_helm_off)


func _on_helm_on(bc: BoatController) -> void:
	_helmed = bc.get_parent()
	helm_changed.emit(_helmed)


func _on_helm_off() -> void:
	_helmed = null
	helm_changed.emit(null)


func _emit_marks(balance: int) -> void:
	marks_changed.emit(balance)


func _emit_company(summary: Dictionary) -> void:
	company_changed.emit(summary)


func _snapshot_into_player_data() -> void:
	if _session == null:
		return
	var data: PlayerData = _session.data
	if data == null:
		return

	data.accepted_contracts = get_active_contracts()
	data.port_operations_state = {}
	data.ship_runtime_state = {}

	var clock := get_node_or_null("/root/WorldClock")
	if clock != null and clock.has_method("get_game_hours_elapsed"):
		data.world_clock_hours = float(clock.call("get_game_hours_elapsed"))
	var live_context := _current_world_context()
	if not live_context.is_empty() and int(live_context.get("seed", 0)) > 0:
		data.world_context = live_context


func save_player_state() -> void:
	if _session != null and _session.has_method("save_now"):
		_session.save_now()


func restore_player_state() -> void:
	if _session == null:
		return
	var data: PlayerData = _session.data
	if data == null:
		return

	if data.world_clock_hours >= 0.0:
		var clock := get_node_or_null("/root/WorldClock")
		if clock != null and clock.has_method("set_game_hours_elapsed"):
			clock.call("set_game_hours_elapsed", data.world_clock_hours)
	var freight := get_node_or_null("/root/FreightService")
	if freight != null:
		freight.restore_contracts(data.accepted_contracts)
	else:
		contracts_changed.emit([])


func _emit_contracts(contracts: Array) -> void:
	contracts_changed.emit(contracts)


func _current_world_context() -> Dictionary:
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("get_world_context"):
		return world.call("get_world_context") as Dictionary
	return {}


func passenger_terminal_snapshot(agent: PassengerAgentNpc) -> Dictionary:
	return agent.snapshot()


func get_passenger_voyage_snapshot() -> Dictionary:
	var operations := PassengerOperations.current(get_tree())
	return operations.voyage_snapshot(get_active_ship() as BoatBody) if operations != null else {}
