extends Node

## Per-client view of the player and their world. Single source of truth
## that UIs consult to ask "what is *my* player doing?".

signal marks_changed(balance: int)
signal helm_changed(boat: Node) # null when not helming
signal contracts_changed(contracts: Array) # kept empty until trade rewrite


var _session: Node = null
var _catalog: Node = null
var _state: Node = null
var _helmed: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_session = get_node_or_null("/root/PlayerSession")
	_catalog = get_node_or_null("/root/PortCatalog")
	_state = get_node_or_null("/root/GameState")

	if _session != null:
		if _session.has_signal("marks_changed") and not _session.marks_changed.is_connected(_emit_marks):
			_session.marks_changed.connect(_emit_marks)
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
	var autopilot := ship.get_node_or_null("VesselAutopilot") as VesselAutopilot
	if autopilot == null:
		return {}
	var snapshot := autopilot.voyage_snapshot()
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
