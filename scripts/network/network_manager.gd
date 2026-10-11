extends Node

## Loss-tolerant transform replication. Identity comes from WorldGateway's
## authenticated reliable session; gameplay facts never travel here.
## Coordinates the NetworkClient backend, stateless WireProtocol, local registered senders,
## and delegates visual rendering / interpolation to the ReplicationDrawingService.
## Autoloaded as NetworkManager.

signal realtime_session_started
signal realtime_session_failed(code: String, message: String)

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
var _local_ship_entity_ids: Dictionary = {}

## Outbound despawn signals: entity_id -> {"type","format","payload","sends_left"}.
## The server removes an entity the moment it receives `state=despawned` meta;
## repeated a few sends because UDP is lossy. Without this, replaced or freed
## ships linger on remote clients until the ~12 s server TTL.
var _pending_tombstones: Dictionary = {}

# Sequence counter for outbound packets
var _outbound_seq: int = 0

# Network settings and throttling
@export var send_interval_s: float = 0.05
var send_clock: float = 0.0
@export var force_move_threshold_m: float = 0.15
@export var force_yaw_threshold_rad: float = 0.05
@export var entity_heartbeat_ms: int = 4000
@export var session_heartbeat_ms: int = 4000
@export var entity_timeout_ms: int = 15000

# Interpolation speeds passed to drawing service
@export var position_smoothness: float = 14.0
@export var payload_smoothness: float = 12.0

var _session_active: bool = false
var _session_pending: bool = false
var _last_session_send_ms: int = 0
var _local_view: Node = null
var _gateway: Node = null


func _ready() -> void:
	if ShipyardPlaytestMode.active():
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_local_view = get_node_or_null("/root/LocalPlayerView")
	_gateway = get_node_or_null("/root/WorldGateway")
	if _gateway != null:
		if not _gateway.session_ready.is_connected(_on_authority_session_ready):
			_gateway.session_ready.connect(_on_authority_session_ready)
		if not _gateway.authority_error.is_connected(_on_authority_error):
			_gateway.authority_error.connect(_on_authority_error)
		if not _gateway.session_closed.is_connected(_on_authority_session_closed):
			_gateway.session_closed.connect(_on_authority_session_closed)
	
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


## Unregisters a node from replication.
func unregister_sender(id: String) -> void:
	_local_senders.erase(id)


## Queues the server removal signal for an entity this client owns. Must be
## called BEFORE the sender is erased so the entity's wire shape can be reused.
func _queue_tombstone(entity_id: String) -> void:
	var sender: Dictionary = _local_senders.get(entity_id, {})
	if sender.is_empty():
		return
	var format := int(sender.get("format", 4))
	var payload: Array = (sender.get("last_sent_payload", []) as Array).duplicate()
	var node: Variant = sender.get("node")
	if payload.is_empty() and node is Node3D and is_instance_valid(node):
		var pos: Vector3 = (node as Node3D).global_position
		payload = [pos.x, pos.y, pos.z]
	while payload.size() < format:
		payload.append(0.0)
	_pending_tombstones[entity_id] = {
		"type": str(sender.get("type", "player")),
		"format": format,
		"payload": payload,
		"sends_left": 4,
	}


## Registers a static/pre-placed scene node by its ID (e.g. static cranes).
func register_scene_node(id: String, node: Node) -> void:
	if not id.is_empty() and node != null:
		_scene_nodes[id] = node


# ── Outbound Serialization Loop ──────────────────────────────────────────────

func _tick_outbound(delta: float) -> void:
	send_clock += delta
	if send_clock < send_interval_s:
		return
	send_clock = 0.0
	
	var local_id := get_local_player_id()
	var token := _session_token()
	if local_id.is_empty():
		_fail_realtime_session(
			"captain_identity_lost",
			"Multiplayer replication lost the selected captain identity.",
		)
		return
	if token.is_empty():
		_fail_realtime_session(
			"authority_session_lost",
			"Multiplayer replication lost its authority session.",
		)
		return

	_ensure_local_ship_registered()
		
	# Resolve our main observer camera position
	var vp := get_viewport()
	var observer_pos := WorldReference.stream_position(vp)

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
				return _build_player_meta()
		)

	# Collect states from all active registered senders with delta compression / standstill filtering
	var entities_payload: Array = []
	var now_ms := Time.get_ticks_msec()
	
	for id in _local_senders.keys():
		var sender: Dictionary = _local_senders[id]
		var node = sender["node"]
		if not is_instance_valid(node):
			## Node freed without an explicit unregister (scene change, sale,
			## despawn) — tell the server instead of leaving a ghost replica.
			_queue_tombstone(str(id))
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
		var pay_changed := _payload_changed(payload, last_pay, str(sender["type"]))
					
		var meta_changed := (meta != last_meta)
		var heartbeat_elapsed := (now_ms - last_time) >= entity_heartbeat_ms
		
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

	# Flush queued despawn tombstones alongside regular updates.
	for entity_id in _pending_tombstones.keys().duplicate():
		var tombstone: Dictionary = _pending_tombstones[entity_id]
		entities_payload.append({
			"id": entity_id,
			"type": tombstone["type"],
			"format": tombstone["format"],
			"payload": tombstone["payload"],
			"meta": "state=despawned",
		})
		tombstone["sends_left"] = int(tombstone["sends_left"]) - 1
		if int(tombstone["sends_left"]) <= 0:
			_pending_tombstones.erase(entity_id)

	# Observer-only heartbeats keep the session alive without blasting empty
	# packets at the 20 Hz entity sampling rate.
	var session_heartbeat_elapsed := (now_ms - _last_session_send_ms) >= session_heartbeat_ms
	if not entities_payload.is_empty() or session_heartbeat_elapsed:
		_send_update_batches(local_id, token, observer_pos, entities_payload)
		_last_session_send_ms = now_ms


func _send_update_batches(local_id: String, token: String, observer_pos: Vector3, entities: Array) -> void:
	if entities.is_empty():
		_outbound_seq += 1
		client.call("send_packet", WireProtocolClass.encode_client_update(
			_outbound_seq, local_id, token, observer_pos, []
		))
		return

	var batch: Array = []
	for entity_variant in entities:
		var next_batch := batch.duplicate()
		next_batch.append(entity_variant)
		var probe := WireProtocolClass.encode_client_update(
			_outbound_seq + 1, local_id, token, observer_pos, next_batch
		)
		if (
			batch.size() >= WireProtocolClass.MAX_ENTITIES_PER_UPDATE
			or (probe.size() > WireProtocolClass.MAX_PACKET_BYTES and not batch.is_empty())
		):
			_send_update_batch(local_id, token, observer_pos, batch)
			batch = [entity_variant]
		else:
			batch = next_batch
	if not batch.is_empty():
		_send_update_batch(local_id, token, observer_pos, batch)


func _send_update_batch(local_id: String, token: String, observer_pos: Vector3, batch: Array) -> void:
	_outbound_seq += 1
	var packet := WireProtocolClass.encode_client_update(_outbound_seq, local_id, token, observer_pos, batch)
	if packet.size() > WireProtocolClass.MAX_PACKET_BYTES:
		push_warning("NetworkManager: skipped an oversized local entity update (%d bytes)." % packet.size())
		return
	client.call("send_packet", packet)


func _payload_changed(payload: Array, last_payload: Array, _entity_type: String) -> bool:
	if payload.size() != last_payload.size():
		return true
	# XYZ is already covered by the positional threshold. Comparing it again
	# made moving entities send on nearly every 20 Hz sample.
	var first_state_index := 3 if payload.size() >= 3 else 0
	for k in range(first_state_index, payload.size()):
		if absf(float(payload[k]) - float(last_payload[k])) >= force_yaw_threshold_rad:
			return true
	return false


func _build_player_meta() -> String:
	if _local_view == null:
		return ""
	var captain_id := str(_local_view.call("get_captain_id"))
	var appearance := _local_view.call("get_appearance") as CharacterAppearance
	var appearance_hash := ""
	if appearance != null:
		appearance_hash = appearance.to_json_string().sha256_text().substr(0, 12)
	return "cid=%s;app=%s" % [captain_id, appearance_hash]


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


func register_ship_spawn(ship_id: String, hull_id: String, ship_node: Node3D) -> void:
	if ship_id.is_empty() or ship_node == null or not is_instance_valid(ship_node):
		return
		
	var unique_ship_id := _network_ship_id(ship_id)
	_local_ship_entity_ids[ship_id] = unique_ship_id

	var resolved_hull_id := HullRegistry.resolve_network_hull_id(hull_id)
		
	_local_ships_board_states[unique_ship_id] = false
	_register_ship_sender(unique_ship_id, resolved_hull_id, ship_node, false)
	_force_sender_sync(unique_ship_id)
	_wire_board_signals_recursive(unique_ship_id, ship_node)


func _force_sender_sync(sender_id: String) -> void:
	var sender: Variant = _local_senders.get(sender_id, null)
	if sender == null:
		return
	sender["last_sent_pos"] = Vector3(INF, INF, INF)
	sender["last_sent_payload"] = []
	sender["last_sent_meta"] = ""
	sender["last_sent_time_ms"] = 0


## Forces the next lossy snapshot to contain a registered entity. Components
## use this after teleports, attachment changes, or ownership handoffs.
func force_sender_sync(sender_id: String) -> void:
	_force_sender_sync(sender_id)


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
	if _local_view != null:
		var record: Dictionary = _local_view.call("get_active_vessel_record") as Dictionary
		if not record.is_empty():
			hull_id = str(record.get("hull_id", ""))
			ship_id = String(record.get("uid", "player_ship"))
			var template_path := str(record.get("template_path", ""))
			if hull_id.is_empty() and not template_path.is_empty():
				hull_id = HullRegistry.resolve_id_from_template(template_path, hull_id)
	if hull_id.is_empty():
		hull_id = "fishing_trawler_small"
	register_ship_spawn(ship_id, hull_id, ship)


func unregister_ship(ship_id: String) -> void:
	var entity_id := str(_local_ship_entity_ids.get(ship_id, ship_id))
	_local_ship_entity_ids.erase(ship_id)
	_local_ships_board_states.erase(entity_id)
	_queue_tombstone(entity_id)
	unregister_sender(entity_id)


func _network_ship_id(ship_id: String) -> String:
	if ship_id.begins_with("ship:") and ship_id.length() <= WireProtocolClass.MAX_STRING_LEN:
		return ship_id
	var local_id := get_local_player_id()
	return "ship:" + (local_id + "|" + ship_id).sha256_text().substr(0, 32)


func _register_ship_sender(ship_id: String, hull_id: String, ship_node: Node3D, boarded: bool) -> void:
	## Durable identity is captured ONCE at registration, from the ship node
	## itself. Reading the globally active vessel record per send let an
	## outgoing ship advertise its replacement's vessel id and layout while
	## both briefly coexisted during deployment.
	var bound_vid := str(ship_node.get_meta("server_vessel_id", "")).strip_edges()
	var bound_lh := str(ship_node.get_meta("layout_hash", "")).strip_edges()
	if bound_vid.is_empty() and _local_view != null:
		var record: Dictionary = _local_view.call("get_active_vessel_record") as Dictionary
		bound_vid = str(record.get("server_vessel_id", "")).strip_edges()
		if bound_lh.is_empty():
			bound_lh = str(record.get("layout_hash", "")).strip_edges()
		## Stamp the node so boarding/unboarding re-registrations keep the
		## same identity even after the active record moves on.
		if not bound_vid.is_empty():
			ship_node.set_meta("server_vessel_id", bound_vid)
		if not bound_lh.is_empty():
			ship_node.set_meta("layout_hash", bound_lh)
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
			var parts: PackedStringArray = []
			if not pilot.is_empty():
				parts.append("pilot=" + pilot)
			if ship_node is BoatBody:
				var systems: Array[FishingSystem] = (ship_node as BoatBody).get_fishing_systems()
				if not systems.is_empty() and systems[0].trawling:
					parts.append("trawl=1")
			## Deck fit-out identity — remotes fetch layout via HTTP using vid + lh.
			## Refresh the hash from node meta so refits update it, but the vessel
			## id stays the one bound at registration.
			var vid := bound_vid
			var lh := str(ship_node.get_meta("layout_hash", bound_lh)).strip_edges()
			if not vid.is_empty():
				parts.append("vid=" + vid)
			if not lh.is_empty():
				parts.append("lh=" + lh)
			var port_id := str(ship_node.get_meta("harbour_port_id", "")).strip_edges()
			var berth_id := str(ship_node.get_meta("harbour_berth_id", "")).strip_edges()
			if not port_id.is_empty():
				parts.append("port=" + port_id)
			if not berth_id.is_empty():
				parts.append("berth=" + berth_id)
			var mooring := _find_mooring_component(ship_node)
			if mooring != null:
				parts.append("bow=%d" % int(mooring.bow_line_tied))
				parts.append("stern=%d" % int(mooring.stern_line_tied))
			return ";".join(parts)
	)


## After layout push/refit, force the next ship ClientUpdate to include new meta.
func force_local_ship_meta_resync() -> void:
	for sender_id in _local_senders.keys():
		var sender: Dictionary = _local_senders[sender_id]
		if not str(sender.get("type", "")).begins_with("ship_"):
			continue
		_force_sender_sync(str(sender_id))


func _wire_board_signals_recursive(ship_id: String, n: Node) -> void:
	if n is MooringComponent:
		var mooring_callback := Callable(
			self,
			"_on_local_ship_mooring_changed",
		).bind(ship_id)
		if not (n as MooringComponent).mooring_state_changed.is_connected(mooring_callback):
			(n as MooringComponent).mooring_state_changed.connect(mooring_callback)
	if (
		n.is_in_group(VehicleGroups.BOARDING_HIDES_OCCUPANT)
		and n.has_signal("player_boarded")
		and n.has_signal("player_exited")
	):
		var boarded_callback := Callable(self, "_on_local_ship_boarded").bind(ship_id)
		var exited_callback := Callable(self, "_on_local_ship_exited").bind(ship_id)
		if not n.is_connected("player_boarded", boarded_callback):
			n.connect("player_boarded", boarded_callback)
		if not n.is_connected("player_exited", exited_callback):
			n.connect("player_exited", exited_callback)
	for c in n.get_children():
		_wire_board_signals_recursive(ship_id, c)


func _find_mooring_component(root: Node) -> MooringComponent:
	if root is MooringComponent:
		return root as MooringComponent
	for child in root.get_children():
		var found := _find_mooring_component(child)
		if found != null:
			return found
	return null


func _on_local_ship_mooring_changed(
		_port_id: String,
		_berth_id: String,
		_bow_line: bool,
		_stern_line: bool,
		ship_id: String,
) -> void:
	_force_sender_sync(ship_id)


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
	if _local_view == null:
		_local_view = get_node_or_null("/root/LocalPlayerView")
	if _local_view == null:
		return ""
	return str(_local_view.call("get_network_player_id")).strip_edges()


func _session_token() -> String:
	var gateway := get_node_or_null("/root/WorldGateway")
	if gateway == null or not gateway.has_method("session_token"):
		return ""
	return str(gateway.call("session_token"))


func is_connected_to_host() -> bool:
	return bool(client.call("is_connected_to_host"))


func is_session_active() -> bool:
	return _session_active


func is_session_pending() -> bool:
	return _session_pending


func begin_multiplayer_session() -> void:
	if _session_active or _session_pending:
		return
	if _gateway == null:
		_gateway = get_node_or_null("/root/WorldGateway")
	if _gateway == null:
		_fail_realtime_session("authority_unavailable", "World authority is unavailable.")
		return
	if not bool(_gateway.call("is_ready")):
		_session_pending = true
		print("[NetworkManager] Waiting for the authority session before opening UDP replication.")
		return
	_activate_multiplayer_transport()


func _activate_multiplayer_transport() -> void:
	var local_id := get_local_player_id()
	var token := _session_token()
	if local_id.is_empty() or token.is_empty():
		_fail_realtime_session(
			"authority_session_invalid",
			"Authority accepted the join without a usable captain identity or session token.",
		)
		return
	_session_pending = false
	_session_active = true
	_last_session_send_ms = 0
	if drawing_service != null:
		drawing_service.visible = true
	print(
		"[NetworkManager] Starting UDP replication actor=%s endpoint=%s:%d"
		% [local_id, str(ServerConfig.udp_host), int(ServerConfig.udp_port)]
	)
	client.call("request_connect")
	realtime_session_started.emit()


func _on_authority_session_ready(remote: bool, _session: Dictionary) -> void:
	if not remote or not _session_pending:
		return
	_activate_multiplayer_transport()


func _on_authority_error(code: String, message: String) -> void:
	if _session_pending or (_session_active and _session_token().is_empty()):
		_fail_realtime_session(code, message)


func _on_authority_session_closed() -> void:
	if not _session_active and not _session_pending:
		return
	_fail_realtime_session("authority_session_closed", "The server closed the multiplayer session.")


func _fail_realtime_session(code: String, message: String) -> void:
	var was_running := _session_active or _session_pending
	_session_active = false
	_session_pending = false
	if drawing_service != null:
		drawing_service.visible = false
	close_connection()
	push_error("[NetworkManager] Realtime session failed (%s): %s" % [code, message])
	if was_running:
		realtime_session_failed.emit(code, message)


func end_multiplayer_session(silent: bool = false) -> void:
	if _session_active and not silent:
		_send_logout_packet()
	_session_active = false
	_session_pending = false
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
	var token := _session_token()
	if token.is_empty():
		return
	var pkt := WireProtocolClass.encode_logout(local_id, token)
	client.call("send_packet", pkt)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		end_multiplayer_session(false)


func _exit_tree() -> void:
	end_multiplayer_session(false)


func close_connection() -> void:
	if client != null:
		client.call("close_connection")
	_local_senders.clear()
	_local_ships_board_states.clear()
	_local_ship_entity_ids.clear()
	_last_session_send_ms = 0
	if drawing_service != null:
		drawing_service.clear_all(_scene_nodes)
	_scene_nodes.clear()
