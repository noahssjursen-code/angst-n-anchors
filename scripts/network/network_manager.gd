extends Node

## Rebuild of the Multiplayer Client Orchestrator (v3).
## Coordinates the NetworkClient, stateless WireProtocol, and individual Replicators
## (Players, Ships, Cargos, Cranes). Autoloaded as NetworkManager.

const NetworkClientClass = preload("res://scripts/network/network_client.gd")
const WireProtocolClass = preload("res://scripts/network/wire_protocol.gd")
const PlayerReplicatorClass = preload("res://scripts/network/replicators/player_replicator.gd")
const ShipReplicatorClass = preload("res://scripts/network/replicators/ship_replicator.gd")
const CargoReplicatorClass = preload("res://scripts/network/replicators/cargo_replicator.gd")
const CraneReplicatorClass = preload("res://scripts/network/replicators/crane_replicator.gd")
const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")


var client: Node = null
var players: Node = null
var ships: Node = null
var cargos: Node = null
var cranes: Node = null

# Local player & out-seq state
var _local_player_node: CharacterBody3D = null
var _local_player_seq: int = 0
var _local_player_last_sent_pos: Vector3 = Vector3.ZERO
var _local_player_last_sent_yaw: float = 0.0

# Local ships managed by this client
var _local_ships: Dictionary = {}

# Local cargos managed by this client
var _local_cargos: Dictionary = {}

# Local cranes operated by this client
var _crane_outbound: Dictionary = {}

# Network settings and throttling
var send_interval_s: float = 0.05
var send_clock: float = 0.0
var force_move_threshold_m: float = 0.6
var force_yaw_threshold_rad: float = 0.16
var presence_refresh_interval_s: float = 30.0
var presence_clock: float = 0.0

# Pilot/avatar visibility set
var _current_piloting_player_ids: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Instantiate our modular network stack as children
	client = NetworkClientClass.new()
	client.name = "NetworkClient"
	add_child(client)
	client.connect("packet_received", _on_packet_received)
	
	players = PlayerReplicatorClass.new()
	players.name = "PlayerReplicator"
	add_child(players)
	
	ships = ShipReplicatorClass.new()
	ships.name = "ShipReplicator"
	add_child(ships)
	
	cargos = CargoReplicatorClass.new()
	cargos.name = "CargoReplicator"
	add_child(cargos)
	
	cranes = CraneReplicatorClass.new()
	cranes.name = "CraneReplicator"
	add_child(cranes)


func _process(delta: float) -> void:
	# Run client-side visual interpolation
	players.call("interpolate", delta)
	ships.call("interpolate", delta)
	cargos.call("interpolate", delta)
	cranes.call("interpolate", delta)
	
	# Tick our local outbound send queues
	_tick_local_player_outbound(delta)
	_tick_local_ship_outbound(delta)
	_tick_local_cargo_outbound(delta)
	cranes.call("tick_local_crane_outbound", delta)



func get_local_player_id() -> String:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return ""
	var pdata = session.get("data")
	if pdata != null:
		var pid := OS.get_process_id()
		return "%s_%d" % [pdata.display_name, pid]
	return ""


func is_local_ship(ship_id: String) -> bool:
	return _local_ships.has(ship_id)


func is_local_cargo(cargo_id: String) -> bool:
	return _local_cargos.has(cargo_id)


func find_any_ship_near(global_pos: Vector3, max_dist: float = 25.0) -> Node3D:
	var closest: Node3D = null
	var min_dist := max_dist
	
	# Check local ships
	for s_id in _local_ships.keys():
		var state: Dictionary = _local_ships[s_id]
		var node_val: Variant = state.get("node", null)
		if is_instance_valid(node_val):
			var node := node_val as Node3D
			var d := node.global_position.distance_to(global_pos)
			if d < min_dist:
				min_dist = d
				closest = node
				
	# Check remote ships
	if ships != null and ships.has_method("get_remote_ships"):
		var remote_dict: Dictionary = ships.call("get_remote_ships")
		for s_id in remote_dict.keys():
			var state: Dictionary = remote_dict[s_id]
			var node_val: Variant = state.get("node", null)
			if is_instance_valid(node_val):
				var node := node_val as Node3D
				var d := node.global_position.distance_to(global_pos)
				if d < min_dist:
					min_dist = d
					closest = node
					
	return closest


# ── Packet Router ─────────────────────────────────────────────────────────────

func _on_packet_received(msg_type: int, payload: PackedByteArray) -> void:
	if msg_type == WireProtocolClass.UDP_MSG_TYPE_SNAPSHOT:
		var snapshot := WireProtocolClass.decode_snapshot(payload)
		if snapshot.is_empty():
			return
			
		# Feed individual data segments to their specialized replicators
		players.call("apply_players", snapshot.get("players", []))
		ships.call("apply_ships", snapshot.get("ships", []))
		cargos.call("apply_cargos", snapshot.get("cargos", []))
		cranes.call("apply_cranes", snapshot.get("cranes", []))


# ── Pilot Visibility Managers ──────────────────────────────────────────────────

func apply_pilot_visibilities(ship_pilots: Dictionary) -> void:
	# Combine ship pilots and crane operators to hide remote avatars
	_current_piloting_player_ids = ship_pilots.duplicate()
	_update_remote_avatar_visibilities()


func apply_crane_pilot_visibilities(crane_operators: Dictionary) -> void:
	for op_id in crane_operators:
		_current_piloting_player_ids[op_id] = true
	_update_remote_avatar_visibilities()


func _update_remote_avatar_visibilities() -> void:
	for c in players.get_children():
		var p_id := String(c.name).replace("RemotePlayer_", "")
		var is_visible := not _current_piloting_player_ids.has(p_id)
		c.visible = is_visible


# ── Local Player Outbound ──────────────────────────────────────────────────────

func _resolve_local_player() -> CharacterBody3D:
	if _local_player_node != null and is_instance_valid(_local_player_node):
		return _local_player_node
	var p := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if p != null and is_instance_valid(p):
		_local_player_node = p
		return p
	return null


func _tick_local_player_outbound(delta: float) -> void:
	var lp := _resolve_local_player()
	if lp == null:
		return
		
	send_clock += delta
	presence_clock += delta
	
	var pos := lp.global_position
	var yaw := float(lp.rotation.y)
	
	var pos_delta := pos.distance_to(_local_player_last_sent_pos)
	var yaw_delta := absf(wrapf(yaw - _local_player_last_sent_yaw, -PI, PI))
	
	var force_send := (pos_delta >= force_move_threshold_m or yaw_delta >= force_yaw_threshold_rad)
	var timed_send := (send_clock >= send_interval_s)
	var presence_send := (presence_clock >= presence_refresh_interval_s)
	
	if force_send or timed_send or presence_send:
		_local_player_seq += 1
		var pkt := WireProtocolClass.encode_player_position(_local_player_seq, get_local_player_id(), pos, yaw)
		client.call("send_packet", pkt)
		
		_local_player_last_sent_pos = pos
		_local_player_last_sent_yaw = yaw
		send_clock = 0.0
		if presence_send:
			presence_clock = 0.0


# ── Local Ship Outbound ────────────────────────────────────────────────────────

func register_ship_spawn(ship_id: String, hull_id: String, ship_node: Node3D) -> void:
	if ship_id.is_empty() or hull_id.is_empty() or ship_node == null:
		return
	if not is_instance_valid(ship_node):
		return
		
	var owner_id := get_local_player_id()
	if owner_id.is_empty():
		push_warning("NetworkManager: cannot register ship — local player id unknown")
		return
		
	var state: Dictionary = _local_ships.get(ship_id, {})
	state["node"] = ship_node
	state["hull_id"] = hull_id
	state["owner_id"] = owner_id
	state["boarded"] = bool(state.get("boarded", false))
	state["out_seq"] = int(state.get("out_seq", 0))
	state["spawn_seq"] = int(state.get("spawn_seq", 0))
	state["board_seq"] = int(state.get("board_seq", 0))
	state["has_last_sent_pose"] = false
	state["last_sent_position"] = ship_node.global_position
	state["last_sent_yaw"] = float(ship_node.rotation.y)
	state["last_sent_at_s"] = 0.0
	
	var already_wired := bool(state.get("board_signals_wired", false))
	state["board_signals_wired"] = true
	_local_ships[ship_id] = state
	
	# Send initial spawn & transform
	_send_ship_spawn_packet(ship_id, state)
	_send_ship_transform_packet(ship_id, state)
	
	if not already_wired:
		_wire_board_signals_recursive(ship_id, ship_node)


func unregister_ship(ship_id: String) -> void:
	_local_ships.erase(ship_id)


func notify_ship_board(ship_id: String, boarded: bool) -> void:
	var state: Dictionary = _local_ships.get(ship_id, {})
	if state.is_empty():
		return
	state["boarded"] = boarded
	_local_ships[ship_id] = state
	_send_ship_board_packet(ship_id, get_local_player_id() if boarded else "", state)


func _wire_board_signals_recursive(ship_id: String, n: Node) -> void:
	if (
		n.is_in_group(VehicleGroups.BOARDING_HIDES_OCCUPANT)
		and n.has_signal("player_boarded")
		and n.has_signal("player_exited")
	):
		n.connect("player_boarded", _on_local_ship_boarded.bind(ship_id))
		n.connect("player_exited", _on_local_ship_exited.bind(ship_id))
	for c in n.get_children():
		_wire_board_signals_recursive(ship_id, c)


func _on_local_ship_boarded(ship_id: String) -> void:
	notify_ship_board(ship_id, true)


func _on_local_ship_exited(ship_id: String) -> void:
	notify_ship_board(ship_id, false)


func _tick_local_ship_outbound(_delta: float) -> void:
	if _local_ships.is_empty():
		return
		
	var now_s := Time.get_ticks_msec() * 0.001
	for ship_id_variant in _local_ships.keys():
		var ship_id := String(ship_id_variant)
		var state: Dictionary = _local_ships.get(ship_id, {})
		
		# Only send transform ticks if boarded/moving
		if not bool(state.get("boarded", false)):
			continue
			
		var node := state.get("node", null) as Node3D
		if node == null or not is_instance_valid(node):
			continue
			
		var pos := node.global_position
		var yaw := float(node.rotation.y)
		
		var last_pos: Vector3 = state.get("last_sent_position", pos)
		var last_yaw: float = float(state.get("last_sent_yaw", yaw))
		var last_at: float = float(state.get("last_sent_at_s", 0.0))
		
		var move_delta := pos.distance_to(last_pos)
		var yaw_delta := absf(wrapf(yaw - last_yaw, -PI, PI))
		
		var force_send := (move_delta >= force_move_threshold_m or yaw_delta >= force_yaw_threshold_rad)
		var timed_send := (now_s - last_at >= send_interval_s)
		
		if force_send or timed_send:
			state["last_sent_position"] = pos
			state["last_sent_yaw"] = yaw
			state["last_sent_at_s"] = now_s
			_local_ships[ship_id] = state
			_send_ship_transform_packet(ship_id, state)


func _send_ship_spawn_packet(ship_id: String, state: Dictionary) -> void:
	var node := state.get("node", null) as Node3D
	if node == null or not is_instance_valid(node):
		return
	var seq := int(state.get("spawn_seq", 0)) + 1
	state["spawn_seq"] = seq
	_local_ships[ship_id] = state
	
	var pkt := WireProtocolClass.encode_ship_spawn(
		seq, ship_id, String(state.get("hull_id")), String(state.get("owner_id")),
		node.global_position, node.rotation.y
	)
	client.call("send_packet", pkt)


func _send_ship_board_packet(ship_id: String, pilot_id: String, state: Dictionary) -> void:
	var seq := int(state.get("board_seq", 0)) + 1
	state["board_seq"] = seq
	_local_ships[ship_id] = state
	
	var pkt := WireProtocolClass.encode_ship_board(seq, ship_id, pilot_id)
	client.call("send_packet", pkt)


func _send_ship_transform_packet(ship_id: String, state: Dictionary) -> void:
	var node := state.get("node", null) as Node3D
	if node == null or not is_instance_valid(node):
		return
	var seq := int(state.get("out_seq", 0)) + 1
	state["out_seq"] = seq
	_local_ships[ship_id] = state
	
	var pkt := WireProtocolClass.encode_ship_transform(seq, ship_id, node.global_position, node.rotation.y)
	client.call("send_packet", pkt)


# ── Local Cargo Outbound ──────────────────────────────────────────────────────

func register_cargo_spawn(cargo_id: String, pallet: Resource, node: Node3D) -> void:
	if cargo_id.is_empty() or pallet == null or node == null:
		return
	if not is_instance_valid(node):
		return
		
	var owner_id := get_local_player_id()
	if owner_id.is_empty():
		push_warning("NetworkManager: cannot register cargo — local player id unknown")
		return
		
	var state: Dictionary = _local_cargos.get(cargo_id, {})
	state["node"] = node
	state["pallet"] = pallet
	state["owner_id"] = owner_id
	state["spawn_seq"] = int(state.get("spawn_seq", 0))
	state["move_seq"] = int(state.get("move_seq", 0))
	state["last_sent_position"] = node.global_position
	state["last_sent_yaw"] = float(node.rotation.y)
	state["last_sent_at_s"] = 0.0
	_local_cargos[cargo_id] = state
	
	_send_cargo_spawn_packet(cargo_id, state)
	_send_cargo_move_packet(cargo_id, node.global_position, float(node.rotation.y), "", state)


func unregister_cargo(cargo_id: String, force_despawn: bool = false) -> void:
	var state: Dictionary = _local_cargos.get(cargo_id, {})
	if state.is_empty():
		return
	if not force_despawn:
		var node := state.get("node", null) as Node3D
		if node != null and is_instance_valid(node) and node.is_inside_tree():
			# Keep the local cargo if it is still inside the tree (e.g. reparented to scene root by crane)
			return
	_send_cargo_despawn_packet(cargo_id, state)
	_local_cargos.erase(cargo_id)


func notify_cargo_moved(cargo_id: String, position: Vector3, yaw: float, carried_by: String = "") -> void:
	var state: Dictionary = _local_cargos.get(cargo_id, {})
	if state.is_empty():
		return
		
	var now_s := Time.get_ticks_msec() * 0.001
	var last_pos: Vector3 = state.get("last_sent_position", position)
	var last_yaw: float = float(state.get("last_sent_yaw", yaw))
	var last_at: float = float(state.get("last_sent_at_s", 0.0))
	
	var move_delta := position.distance_to(last_pos)
	var yaw_delta := absf(wrapf(yaw - last_yaw, -PI, PI))
	
	var force_send := (move_delta >= 0.1 or yaw_delta >= 0.05 or not carried_by.is_empty())
	var timed_send := (now_s - last_at >= send_interval_s)
	
	if force_send or timed_send:
		state["last_sent_position"] = position
		state["last_sent_yaw"] = yaw
		state["last_sent_at_s"] = now_s
		_local_cargos[cargo_id] = state
		_send_cargo_move_packet(cargo_id, position, yaw, carried_by, state)


func _send_cargo_spawn_packet(cargo_id: String, state: Dictionary) -> void:
	var node := state.get("node", null) as Node3D
	if node == null or not is_instance_valid(node):
		return
	var pallet := state.get("pallet", null) as Resource
	if pallet == null:
		return
		
	var commodity := String(pallet.get("commodity"))
	var units := int(pallet.get("units"))
	var fp: Vector2i = pallet.get("footprint") as Vector2i
	
	var seq := int(state.get("spawn_seq", 0)) + 1
	state["spawn_seq"] = seq
	_local_cargos[cargo_id] = state
	
	var pkt := WireProtocolClass.encode_cargo_spawn(
		seq, cargo_id, String(state.get("owner_id")), commodity, units, fp.x, fp.y,
		node.global_position, node.rotation.y
	)
	client.call("send_packet", pkt)


func _send_cargo_move_packet(cargo_id: String, pos: Vector3, yaw: float, carried_by: String, state: Dictionary) -> void:
	var seq := int(state.get("move_seq", 0)) + 1
	state["move_seq"] = seq
	_local_cargos[cargo_id] = state
	
	var pkt := WireProtocolClass.encode_cargo_move(seq, cargo_id, pos, yaw, carried_by)
	client.call("send_packet", pkt)


func _send_cargo_despawn_packet(cargo_id: String, state: Dictionary) -> void:
	var seq := int(state.get("spawn_seq", 0)) + 1
	state["spawn_seq"] = seq
	_local_cargos[cargo_id] = state
	
	var pkt := WireProtocolClass.encode_cargo_despawn(seq, cargo_id)
	client.call("send_packet", pkt)


func _tick_local_cargo_outbound(_delta: float) -> void:
	if _local_cargos.is_empty():
		return
	for cargo_id_variant in _local_cargos.keys():
		var cargo_id := String(cargo_id_variant)
		var state: Dictionary = _local_cargos[cargo_id]
		var node := state.get("node", null) as Node3D
		if node != null and is_instance_valid(node):
			var carried_by := ""
			if node.has_meta("carried_by"):
				carried_by = String(node.get_meta("carried_by"))
			notify_cargo_moved(cargo_id, node.global_position, node.global_rotation.y, carried_by)


# ── Local Crane Outbound ──────────────────────────────────────────────────────

func register_crane(crane_id: String, crane_node: Node) -> void:
	cranes.call("register_crane", crane_id, crane_node)


func notify_crane_operated(crane_id: String, boarded: bool) -> void:
	if cranes != null and cranes.has_method("set_local_crane_boarded"):
		cranes.call("set_local_crane_boarded", crane_id, boarded)
		
	var state: Dictionary = _crane_outbound.get(crane_id, {})
	var seq := int(state.get("operate_seq", 0)) + 1
	state["operate_seq"] = seq
	_crane_outbound[crane_id] = state
	
	var pkt := WireProtocolClass.encode_crane_operate(seq, crane_id, get_local_player_id() if boarded else "")
	client.call("send_packet", pkt)


func send_crane_state(crane_id: String, joints: Dictionary) -> void:
	var state: Dictionary = _crane_outbound.get(crane_id, {})
	var seq := int(state.get("state_seq", 0)) + 1
	state["state_seq"] = seq
	_crane_outbound[crane_id] = state
	
	var pkt := WireProtocolClass.encode_crane_state(seq, crane_id, joints)
	client.call("send_packet", pkt)


# ── Connection API ────────────────────────────────────────────────────────────

func is_connected_to_host() -> bool:
	return bool(client.call("is_connected_to_host"))


func close_connection() -> void:
	client.call("close_connection")
	_local_ships.clear()
	_local_cargos.clear()
	_crane_outbound.clear()
	players.call("clear_all")
	ships.call("clear_all")
	cargos.call("clear_all")
	cranes.call("clear_all")
