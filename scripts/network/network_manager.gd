extends Node

## Rebuilt, modular, and 100% generic Multiplayer Client Replication Service (v4).
## Coordinates the NetworkClient backend, stateless WireProtocol, local registered senders,
## and delegates visual rendering / interpolation to the ReplicationDrawingService.
## Autoloaded as NetworkManager.

const NetworkClientClass = preload("res://scripts/network/network_client.gd")
const WireProtocolClass = preload("res://scripts/network/wire_protocol.gd")
const ReplicationDrawingServiceClass = preload("res://scripts/network/replication_drawing_service.gd")
const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

var client: Node = null
var drawing_service: Node3D = null

# Outbound generic senders: id -> { "node": Node, "type": String, "format": int, "state_callable": Callable, "meta_callable": Callable }
var _local_senders: Dictionary = {}

# Static pre-placed level nodes registered by ID: id -> Node
var _scene_nodes: Dictionary = {}

# Local ship boarding tracker: ship_id -> bool
var _local_ships_board_states: Dictionary = {}

# Sequence counter for outbound packets
var _outbound_seq: int = 0

# Network settings and throttling
@export var send_interval_s: float = 0.05
var send_clock: float = 0.0
@export var force_move_threshold_m: float = 0.15
@export var force_yaw_threshold_rad: float = 0.05
@export var entity_timeout_ms: int = 3000

# Interpolation speeds passed to drawing service
@export var position_smoothness: float = 14.0
@export var payload_smoothness: float = 12.0

var _session_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Instantiate raw socket network backend
	client = NetworkClientClass.new()
	client.name = "NetworkClient"
	add_child(client)
	client.connect("packet_received", _on_packet_received)
	
	# Instantiate clean, modular drawing service
	drawing_service = ReplicationDrawingServiceClass.new()
	drawing_service.name = "ReplicationDrawingService"
	drawing_service.visible = false
	add_child(drawing_service)


func _process(delta: float) -> void:
	if not _session_active:
		return
	# 1. Delegate dynamic remote entities interpolation to the drawing service
	drawing_service.interpolate_entities(delta, position_smoothness, payload_smoothness)
	
	# 2. Tick local outbound send queue
	_tick_outbound(delta)


# ── Generic Sender Registration API ──────────────────────────────────────────

## Registers a node for dynamic replication to the server.
## - `state_callable` must return an Array of float payload values.
## - `meta_callable` must return a String of metadata.
func register_sender(node: Node, id: String, type: String, format: int, state_callable: Callable, meta_callable: Callable) -> void:
	if id.is_empty() or node == null or not is_instance_valid(node):
		return
	
	_local_senders[id] = {
		"node": node,
		"type": type,
		"format": format,
		"state_callable": state_callable,
		"meta_callable": meta_callable,
		"last_sent_pos": Vector3(INF, INF, INF), # Trigger initial force send
		"last_sent_payload": [],
		"last_sent_meta": "",
		"last_sent_time_ms": 0
	}
	if drawing_service != null:
		drawing_service.clear_entity_remote_state(id)


## Unregisters a node from replication.
func unregister_sender(id: String) -> void:
	_local_senders.erase(id)


## Registers a static/pre-placed scene node by its ID (e.g. static cranes).
func register_scene_node(id: String, node: Node) -> void:
	if not id.is_empty() and node != null:
		_scene_nodes[id] = node


# ── Outbound Serialization Loop ──────────────────────────────────────────────

func _tick_outbound(delta: float) -> void:
	send_clock += delta
	if send_clock < send_interval_s:
		return
	
	var local_id := get_local_player_id()
	if local_id.is_empty():
		return

	_ensure_local_ship_registered()
		
	# Resolve our main observer camera position
	var observer_pos := Vector3.ZERO
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null:
			observer_pos = cam.global_position

	# Auto-register local player avatar as Vector4 (XYZ + Yaw)
	var lp := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if lp != null and is_instance_valid(lp) and not _local_senders.has(local_id):
		register_sender(
			lp,
			local_id,
			"player",
			4,
			func():
				var yaw := lp.rotation.y
				var cam_ctrl := lp.get_node_or_null("PlayerCamera")
				if cam_ctrl != null and cam_ctrl.has_method("get_replication_yaw"):
					yaw = float(cam_ctrl.call("get_replication_yaw"))
				return [lp.global_position.x, lp.global_position.y, lp.global_position.z, yaw],
			func():
				var session := get_node_or_null("/root/PlayerSession")
				if session != null and session.data != null and session.data.appearance != null:
					return session.data.appearance.to_meta_string(
						str(session.data.display_name),
						str(session.data.captain_id)
					)
				return ""
		)

	# Collect states from all active registered senders with delta compression / standstill filtering
	var entities_payload: Array = []
	var now_ms := Time.get_ticks_msec()
	
	for id in _local_senders.keys():
		var sender: Dictionary = _local_senders[id]
		var node = sender["node"]
		if not is_instance_valid(node):
			_local_senders.erase(id)
			continue
			
		var pos: Vector3 = node.global_position if node is Node3D else Vector3.ZERO
		var payload: Array = sender["state_callable"].call()
		var meta: String = sender["meta_callable"].call()
		
		# Change detection
		var last_pos: Vector3 = sender["last_sent_pos"]
		var last_pay: Array = sender["last_sent_payload"]
		var last_meta: String = sender["last_sent_meta"]
		var last_time: int = sender["last_sent_time_ms"]
		
		var pos_changed := pos.distance_to(last_pos) >= force_move_threshold_m
		var pay_changed := false
		if payload.size() != last_pay.size():
			pay_changed = true
		else:
			for k in payload.size():
				if absf(payload[k] - last_pay[k]) >= force_yaw_threshold_rad:
					pay_changed = true
					break
					
		var meta_changed := (meta != last_meta)
		var heartbeat_elapsed := (now_ms - last_time) >= 3000 # 3-second heartbeat to prevent server pruning
		
		# Send if there is an active change, or as a slow heartbeat
		if pos_changed or pay_changed or meta_changed or heartbeat_elapsed:
			entities_payload.append({
				"id": id,
				"type": sender["type"],
				"format": sender["format"],
				"payload": payload,
				"meta": meta
			})
			
			sender["last_sent_pos"] = pos
			sender["last_sent_payload"] = payload.duplicate()
			sender["last_sent_meta"] = meta
			sender["last_sent_time_ms"] = now_ms

	# Blast the consolidated update packet to the server if we have any entity updates
	if entities_payload.size() > 0 or send_clock >= send_interval_s:
		_outbound_seq += 1
		var pkt := WireProtocolClass.encode_client_update(_outbound_seq, local_id, observer_pos, entities_payload)
		client.call("send_packet", pkt)
		send_clock = 0.0


# ── Snapshot Packet Router ───────────────────────────────────────────────────

func _on_packet_received(msg_type: int, payload: PackedByteArray) -> void:
	if not _session_active:
		return
	if msg_type == WireProtocolClass.UDP_MSG_TYPE_SNAPSHOT:
		var snapshot := WireProtocolClass.decode_snapshot(payload)
		if snapshot.is_empty():
			return
			
		# Forward snapshots directly to drawing service
		drawing_service.apply_entities(
			snapshot.get("entities", []),
			get_local_player_id(),
			_scene_nodes,
			_local_senders.keys(),
			Time.get_ticks_msec(),
			entity_timeout_ms
		)


# ── Backwards Compatible Gameplay Hooks ─────────────────────────────────────

func register_crane(crane_id: String, crane_node: Node) -> void:
	register_scene_node(crane_id, crane_node)
	if drawing_service != null and drawing_service.has_method("adopt_scene_node"):
		drawing_service.call("adopt_scene_node", crane_id, crane_node, _scene_nodes)


func notify_crane_operated(crane_id: String, boarded: bool) -> void:
	if boarded:
		var crane_node: Node = _scene_nodes.get(crane_id, null)
		if crane_node != null and is_instance_valid(crane_node):
			register_sender(
				crane_node,
				crane_id,
				"crane",
				6, # Vector6: [base_x, base_y, base_z, gantry_x, trolley_z, hoist_drop]
				func():
					var crane3d := crane_node as Node3D
					var base_pos := crane3d.global_position
					var gantry_x_val := float(crane_node.get("_gantry_x_offset"))
					var trolley_z_val := float(crane_node.get("_trolley_z"))
					var hoist_drop_val := float(crane_node.get("_hoist_drop"))
					return [base_pos.x, base_pos.y, base_pos.z, gantry_x_val, trolley_z_val, hoist_drop_val],
				func():
					var hook_node := crane_node.get("_hook") as Node3D
					var hook_yaw := 0.0
					if hook_node != null and is_instance_valid(hook_node):
						hook_yaw = hook_node.rotation.y
					return "op=%s;hy=%.3f" % [get_local_player_id(), hook_yaw]
			)
	else:
		_flush_crane_vacated(crane_id)
		unregister_sender(crane_id)
		if drawing_service != null and drawing_service.has_method("clear_scene_node_remote_state"):
			drawing_service.call("clear_scene_node_remote_state", crane_id)


func _flush_crane_vacated(crane_id: String) -> void:
	var sender: Variant = _local_senders.get(crane_id, null)
	if sender == null or client == null:
		return
	var crane_node: Node = sender["node"]
	if crane_node == null or not is_instance_valid(crane_node):
		return
	var payload: Array = sender["state_callable"].call()
	var hook_node := crane_node.get("_hook") as Node3D
	var hook_yaw := 0.0
	if hook_node != null and is_instance_valid(hook_node):
		hook_yaw = hook_node.rotation.y
	var local_id := get_local_player_id()
	if local_id.is_empty():
		return
	var observer_pos := Vector3.ZERO
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null:
			observer_pos = cam.global_position
	_outbound_seq += 1
	var pkt := WireProtocolClass.encode_client_update(
		_outbound_seq,
		local_id,
		observer_pos,
		[{
			"id": crane_id,
			"type": "crane",
			"format": 6,
			"payload": payload,
			"meta": "op=;hy=%.3f" % hook_yaw,
		}]
	)
	client.call("send_packet", pkt)


func register_cargo_spawn(cargo_id: String, pallet: Resource, node: Node3D) -> void:
	if cargo_id.is_empty() or node == null or not is_instance_valid(node):
		return
	register_sender(
		node,
		cargo_id,
		"cargo",
		4, # Vector4: [x, y, z, yaw]
		func():
			return _cargo_replication_state(node),
		func():
			return _cargo_replication_meta(pallet, node)
	)


func entity_id_for_node(target: Node) -> String:
	if target == null:
		return ""
	for sender_id in _local_senders.keys():
		var sender: Dictionary = _local_senders[sender_id]
		var n: Node = sender.get("node") as Node
		if n == null or not is_instance_valid(n):
			continue
		if n == target or n.is_ancestor_of(target):
			return str(sender_id)
	return ""


func _cargo_replication_state(node: Node3D) -> Array:
	var ship := _boat_body_ancestor(node)
	var ship_id := entity_id_for_node(ship)
	if ship != null and not ship_id.is_empty():
		var local_xform := ship.global_transform.affine_inverse() * node.global_transform
		var origin := local_xform.origin
		return [origin.x, origin.y, origin.z, local_xform.basis.get_euler().y]
	return [node.global_position.x, node.global_position.y, node.global_position.z, node.rotation.y]


func _boat_body_ancestor(node: Node) -> BoatBody:
	var current := node
	while current != null:
		if current is BoatBody:
			return current as BoatBody
		current = current.get_parent()
	return null


func _cargo_replication_meta(pallet: Resource, node: Node3D) -> String:
	var com := String(pallet.get("commodity")) if pallet.get("commodity") != null else "cargo"
	var units := int(pallet.get("units")) if pallet.get("units") != null else 1
	var fp := Vector2i(1, 1)
	var fp_raw: Variant = pallet.get("footprint")
	if fp_raw is Vector2i:
		fp = fp_raw
	var parts: PackedStringArray = [
		"com=%s" % com,
		"units=%d" % units,
		"fp=%d,%d" % [fp.x, fp.y],
	]
	var display := str(pallet.get("display_name")) if pallet.get("display_name") != null else ""
	if not display.is_empty():
		parts.append("dn=%s" % display)
	var ship := _boat_body_ancestor(node)
	var parent_id := entity_id_for_node(ship) if ship != null else ""
	if not parent_id.is_empty():
		parts.append("parent=%s" % parent_id)
	return ";".join(parts)


func unregister_cargo(cargo_id: String, delivered: bool = false) -> void:
	if delivered:
		_flush_cargo_delivered(cargo_id)
	if drawing_service != null and drawing_service.has_method("clear_entity_remote_state"):
		drawing_service.call("clear_entity_remote_state", cargo_id)
	unregister_sender(cargo_id)


func _flush_cargo_delivered(cargo_id: String) -> void:
	var sender: Variant = _local_senders.get(cargo_id, null)
	if sender == null or client == null:
		return
	var node: Node3D = sender["node"] as Node3D
	if node == null or not is_instance_valid(node):
		return
	var payload: Array = sender["state_callable"].call()
	var local_id := get_local_player_id()
	if local_id.is_empty():
		return
	var observer_pos := Vector3.ZERO
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null:
			observer_pos = cam.global_position
	_outbound_seq += 1
	var pkt := WireProtocolClass.encode_client_update(
		_outbound_seq,
		local_id,
		observer_pos,
		[{
			"id": cargo_id,
			"type": "cargo",
			"format": 4,
			"payload": payload,
			"meta": "state=delivered",
		}]
	)
	client.call("send_packet", pkt)


func register_ship_spawn(ship_id: String, hull_id: String, ship_node: Node3D) -> void:
	if ship_id.is_empty() or ship_node == null or not is_instance_valid(ship_node):
		return
		
	# Ensure the ship ID is globally unique across the network to prevent collisions
	var unique_ship_id := ship_id
	var local_player_id := get_local_player_id()
	if not ship_id.begins_with(local_player_id + "_"):
		unique_ship_id = local_player_id + "_" + ship_id

	var resolved_hull_id := HullRegistry.resolve_network_hull_id(hull_id)
		
	_unregister_other_local_ships(unique_ship_id)
	_local_ships_board_states[unique_ship_id] = false
	_register_ship_sender(unique_ship_id, resolved_hull_id, ship_node, false)
	_force_sender_sync(unique_ship_id)
	_wire_board_signals_recursive(unique_ship_id, ship_node)


func unregister_ship_for_node(ship: Node) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var ship_id := entity_id_for_node(ship)
	if ship_id.is_empty():
		return
	unregister_ship_entity(ship_id)


func unregister_ship_entity(ship_id: String) -> void:
	if ship_id.is_empty():
		return
	_flush_ship_despawned(ship_id)
	if drawing_service != null:
		drawing_service.clear_entity_remote_state(ship_id)
	_local_ships_board_states.erase(ship_id)
	unregister_sender(ship_id)


func _unregister_other_local_ships(keep_id: String) -> void:
	var to_remove: Array[String] = []
	for sid in _local_senders.keys():
		var sender: Dictionary = _local_senders[sid]
		if str(sender.get("type", "")).begins_with("ship_") and str(sid) != keep_id:
			to_remove.append(str(sid))
	for sid in to_remove:
		unregister_ship_entity(sid)


func _flush_ship_despawned(ship_id: String) -> void:
	if client == null:
		return
	var local_id := get_local_player_id()
	if local_id.is_empty():
		return

	var payload: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var ent_type := "ship_cargo_ship_medium"
	var sender: Variant = _local_senders.get(ship_id, null)
	if sender != null:
		var node: Node3D = sender["node"] as Node3D
		if node != null and is_instance_valid(node):
			payload = sender["state_callable"].call()
		ent_type = str(sender.get("type", ent_type))

	var observer_pos := Vector3.ZERO
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null:
			observer_pos = cam.global_position
	_outbound_seq += 1
	var pkt := WireProtocolClass.encode_client_update(
		_outbound_seq,
		local_id,
		observer_pos,
		[{
			"id": ship_id,
			"type": ent_type,
			"format": maxi(payload.size(), 3),
			"payload": payload,
			"meta": "state=despawned",
		}]
	)
	client.call("send_packet", pkt)


func _force_sender_sync(sender_id: String) -> void:
	var sender: Variant = _local_senders.get(sender_id, null)
	if sender == null:
		return
	sender["last_sent_pos"] = Vector3(INF, INF, INF)
	sender["last_sent_payload"] = []
	sender["last_sent_meta"] = ""
	sender["last_sent_time_ms"] = 0


func _ensure_local_ship_registered() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var ship := PlayerVessel.find_active_ship(tree)
	if ship == null or not is_instance_valid(ship):
		return
	for sender_id in _local_senders.keys():
		var sender: Dictionary = _local_senders[sender_id]
		if not str(sender.get("type", "")).begins_with("ship_"):
			continue
		var node: Node3D = sender.get("node") as Node3D
		if node == ship:
			return

	var hull_id := ""
	var ship_id := "player_ship"
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.get("data") != null:
		var record: Dictionary = session.data.get_active_vessel_record()
		if not record.is_empty():
			hull_id = str(record.get("hull_id", ""))
			ship_id = String(record.get("uid", "player_ship"))
			var template_path := str(record.get("template_path", ""))
			if hull_id.is_empty() and not template_path.is_empty():
				hull_id = HullRegistry.resolve_id_from_template(template_path, hull_id)
	if hull_id.is_empty():
		hull_id = "cargo_ship_medium"
	register_ship_spawn(ship_id, hull_id, ship)


func unregister_ship(ship_id: String) -> void:
	unregister_ship_entity(ship_id)


func _register_ship_sender(ship_id: String, hull_id: String, ship_node: Node3D, boarded: bool) -> void:
	register_sender(
		ship_node,
		ship_id,
		"ship_" + hull_id,
		6, # Vector6: [x, y, z, global_rx, global_ry, global_rz]
		func():
			var pos := ship_node.global_position
			var rot := ship_node.global_rotation
			return [pos.x, pos.y, pos.z, rot.x, rot.y, rot.z],
		func():
			var pilot := get_local_player_id() if boarded else ""
			var berth_tag := ""
			
			# Scan PortDock instances to check if this ship is currently moored/berthed locally
			var docks := get_tree().get_nodes_in_group("port_docks")
			for dock in docks:
				var port_dock := dock as PortDock
				if port_dock != null:
					var idx := port_dock.find_player_berth(PortDock.local_player_owner_id())
					if idx >= 0 and port_dock.get_ship_at_berth(idx) == ship_node:
						berth_tag = "berth=%s_%d" % [port_dock.port_id, idx]
						break
			
			var parts: PackedStringArray = []
			if not pilot.is_empty():
				parts.append("pilot=" + pilot)
			if not berth_tag.is_empty():
				parts.append(berth_tag)
			var fishing := ship_node.find_child("FishingSystem", true, false) as FishingSystem
			if fishing != null and fishing.trawling:
				parts.append("trawl=1")
			return ";".join(parts)
	)


func _wire_board_signals_recursive(ship_id: String, n: Node) -> void:
	if (
		n.is_in_group(VehicleGroups.BOARDING_HIDES_OCCUPANT)
		and n.has_signal("player_boarded")
		and n.has_signal("player_exited")
	):
		if not n.is_connected("player_boarded", _on_local_ship_boarded):
			n.connect("player_boarded", _on_local_ship_boarded.bind(ship_id))
		if not n.is_connected("player_exited", _on_local_ship_exited):
			n.connect("player_exited", _on_local_ship_exited.bind(ship_id))
	for c in n.get_children():
		_wire_board_signals_recursive(ship_id, c)


func _on_local_ship_boarded(ship_id: String) -> void:
	_local_ships_board_states[ship_id] = true
	var sender = _local_senders.get(ship_id, null)
	if sender != null:
		var hull_id := HullRegistry.resolve_network_hull_id(
			HullRegistry.hull_id_from_network_type(String(sender["type"]))
		)
		_register_ship_sender(ship_id, hull_id, sender["node"], true)


func _on_local_ship_exited(ship_id: String) -> void:
	_local_ships_board_states[ship_id] = false
	var sender = _local_senders.get(ship_id, null)
	if sender != null:
		var hull_id := HullRegistry.resolve_network_hull_id(
			HullRegistry.hull_id_from_network_type(String(sender["type"]))
		)
		_register_ship_sender(ship_id, hull_id, sender["node"], false)


func is_local_ship(ship_id: String) -> bool:
	return _local_senders.has(ship_id)


func is_local_cargo(cargo_id: String) -> bool:
	return _local_senders.has(cargo_id)


func find_any_ship_near(global_pos: Vector3, max_dist: float = 25.0) -> Node3D:
	var closest: Node3D = null
	var min_dist := max_dist
	
	# Check local senders that are ships
	for s_id in _local_senders.keys():
		var sender: Dictionary = _local_senders[s_id]
		if sender["type"].begins_with("ship_"):
			var node := sender["node"] as Node3D
			if is_instance_valid(node):
				var d := node.global_position.distance_to(global_pos)
				if d < min_dist:
					min_dist = d
					closest = node
				
	# Check remote ships (queried from drawing service)
	if drawing_service != null:
		var visible_ents: Dictionary = drawing_service.get_visible_entities()
		for s_id in visible_ents.keys():
			var state: Dictionary = visible_ents[s_id]
			if state["type"].begins_with("ship_"):
				var node_raw: Variant = state.get("node", null)
				if node_raw == null or not is_instance_valid(node_raw):
					continue
				var node := node_raw as Node3D
				var d := node.global_position.distance_to(global_pos)
				if d < min_dist:
					min_dist = d
					closest = node
					
	return closest


# ── Connection & Bootstrap Helpers ───────────────────────────────────────────

func get_local_player_id() -> String:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return ""
	var pdata = session.get("data")
	if pdata != null:
		var pid := OS.get_process_id()
		return "%s_%d" % [pdata.display_name, pid]
	return ""


func is_connected_to_host() -> bool:
	return bool(client.call("is_connected_to_host"))


func is_session_active() -> bool:
	return _session_active


func begin_multiplayer_session() -> void:
	if _session_active:
		return
	_session_active = true
	if drawing_service != null:
		drawing_service.visible = true
	client.call("request_connect")


func end_multiplayer_session(silent: bool = false) -> void:
	if _session_active and not silent:
		_send_logout_packet()
	_session_active = false
	if drawing_service != null:
		drawing_service.visible = false
	close_connection()


func logout() -> void:
	end_multiplayer_session(false)


func _send_logout_packet() -> void:
	var local_id := get_local_player_id()
	if local_id.is_empty():
		return
	print("[NetworkManager] Gracefully declaring logout to server for: ", local_id)
	var pkt := WireProtocolClass.encode_logout(local_id)
	client.call("send_packet", pkt)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		end_multiplayer_session(false)


func _exit_tree() -> void:
	end_multiplayer_session(false)


func close_connection() -> void:
	client.call("close_connection")
	_local_senders.clear()
	_local_ships_board_states.clear()
	if drawing_service != null:
		drawing_service.clear_all(_scene_nodes)
	_scene_nodes.clear()
