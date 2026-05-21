extends Node

## Polls the MP API world snapshot and keeps remote players visible in-world.
## This service is intentionally simple for bootstrap MP: remote players are
## represented as lightweight Node3D roots with a visible NpcBase body mesh.

@export var use_udp_transport: bool = true
@export var snapshot_poll_interval_s: float = 0.08
@export var udp_server_host: String = "127.0.0.1"
@export var udp_server_port: int = 7777
@export var udp_send_interval_s: float = 0.05
@export var udp_min_send_interval_s: float = 0.05
@export var udp_max_send_interval_s: float = 300.0
@export var udp_presence_refresh_interval_s: float = 30.0
@export var udp_force_send_move_threshold_m: float = 0.6
@export var udp_force_send_yaw_threshold_rad: float = 0.16
@export var udp_force_send_min_interval_s: float = 0.08
@export var remote_root_name: String = "RemotePlayers"
@export var remote_position_smoothness: float = 18.0
@export var remote_yaw_smoothness: float = 16.0
@export var remote_prediction_lead_s: float = 0.03
@export var remote_prediction_max_s: float = 0.10
@export var remote_max_speed: float = 14.0
@export var remote_max_turn_speed: float = 6.0
@export var remote_velocity_damping: float = 0.65
@export var remote_nameplate_height: float = 2.2
@export var remote_nameplate_pixel_size: float = 0.01
@export var remote_nameplate_color: Color = Color(0.96, 0.92, 0.78, 0.95)

const REMOTE_PLAYER_PREFIX := "RemotePlayer_"
const REMOTE_BODY_NAME := "BodyMesh"
const REMOTE_NAME_LABEL_NAME := "PlayerNameLabel"

# Binary UDP protocol — must match cmd/server/main.go
const UDP_PROTOCOL_VERSION := 1
const UDP_MSG_TYPE_POSITION := 1
const UDP_MSG_TYPE_SNAPSHOT := 2
const UDP_MAX_PLAYER_ID_LEN := 64
const UDP_POSITION_HEADER_SIZE := 7  # version + type + seq(4) + id_len
const UDP_POSITION_FLOATS_SIZE := 16  # x + y + z + yaw (float32 each)
const UDP_SNAPSHOT_HEADER_SIZE := 11  # version + type + next_update(4) + nearest(4) + count
const UDP_SNAPSHOT_PLAYER_FLOATS_SIZE := 16  # x + y + z + yaw

var _poll_clock: float = 0.0
var _snapshot_request: HTTPRequest = null
var _request_in_flight: bool = false
var _udp_peer: PacketPeerUDP = null
var _udp_send_clock: float = 0.0
var _udp_server_interval_s: float = -1.0
var _udp_since_last_send_s: float = 0.0
var _udp_out_seq: int = 0
var _udp_last_sent_position: Vector3 = Vector3.ZERO
var _udp_last_sent_yaw: float = 0.0
var _udp_has_last_sent_pose: bool = false
var _remote_root: Node3D = null
var _remote_players: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if use_udp_transport:
		_ensure_udp_peer()
	else:
		_ensure_snapshot_request()


func _process(delta: float) -> void:
	_tick_remote_interpolation(delta)
	if use_udp_transport:
		_tick_udp_transport(delta)
		return

	if snapshot_poll_interval_s <= 0.0:
		return
	if _request_in_flight:
		return
	if _resolve_local_player() == null:
		return

	_poll_clock += delta
	if _poll_clock < snapshot_poll_interval_s:
		return
	_poll_clock = 0.0
	_request_world_snapshot()


func _ensure_udp_peer() -> void:
	if _udp_peer != null:
		return
	_udp_peer = PacketPeerUDP.new()
	var err := _udp_peer.connect_to_host(udp_server_host, udp_server_port)
	if err != OK:
		push_warning(
			"PlayerVisibilityService: UDP connect failed host=%s port=%d err=%d"
			% [udp_server_host, udp_server_port, err]
		)
		_udp_peer = null


func _tick_udp_transport(delta: float) -> void:
	_drain_udp_packets()
	_udp_since_last_send_s += delta
	var target_interval_s := _resolve_udp_send_interval_s()
	if target_interval_s <= 0.0:
		return
	var local_player := _resolve_local_player()
	if local_player == null:
		return
	if not _udp_has_last_sent_pose:
		# First-contact presence packet: register this client with server now.
		_send_udp_position_update(local_player)
		return
	if _udp_since_last_send_s >= udp_presence_refresh_interval_s:
		# Keep coarse presence fresh for server-side interest logic.
		_send_udp_position_update(local_player)
		return
	if _should_force_udp_send(local_player):
		_send_udp_position_update(local_player)
		return
	_udp_send_clock += delta
	if _udp_send_clock < target_interval_s:
		return
	_udp_send_clock = 0.0
	_send_udp_position_update(local_player)


func _resolve_udp_send_interval_s() -> float:
	if _udp_server_interval_s > 0.0:
		return clampf(_udp_server_interval_s, udp_min_send_interval_s, udp_max_send_interval_s)
	return clampf(udp_send_interval_s, udp_min_send_interval_s, udp_max_send_interval_s)


func _send_udp_position_update(local_player: Node = null) -> void:
	_ensure_udp_peer()
	if _udp_peer == null:
		return
	if local_player == null:
		local_player = _resolve_local_player()
	if local_player == null:
		return
	if not local_player.has_method("get_network_player_id"):
		return
	if not (local_player is Node3D):
		return

	var local_node := local_player as Node3D
	var self_id := String(local_player.call("get_network_player_id")).strip_edges()
	if self_id.is_empty():
		return

	var id_bytes := self_id.to_utf8_buffer()
	if id_bytes.size() == 0 or id_bytes.size() > UDP_MAX_PLAYER_ID_LEN:
		push_warning(
			"PlayerVisibilityService: player_id length %d outside [1..%d]"
			% [id_bytes.size(), UDP_MAX_PLAYER_ID_LEN]
		)
		return

	_udp_out_seq += 1

	var packet := PackedByteArray()
	packet.resize(UDP_POSITION_HEADER_SIZE)
	packet.encode_u8(0, UDP_PROTOCOL_VERSION)
	packet.encode_u8(1, UDP_MSG_TYPE_POSITION)
	packet.encode_u32(2, _udp_out_seq)
	packet.encode_u8(6, id_bytes.size())
	packet.append_array(id_bytes)

	var floats := PackedByteArray()
	floats.resize(UDP_POSITION_FLOATS_SIZE)
	floats.encode_float(0, local_node.global_position.x)
	floats.encode_float(4, local_node.global_position.y)
	floats.encode_float(8, local_node.global_position.z)
	floats.encode_float(12, local_node.rotation.y)
	packet.append_array(floats)

	_udp_peer.put_packet(packet)
	_udp_send_clock = 0.0
	_udp_since_last_send_s = 0.0
	_udp_last_sent_position = local_node.global_position
	_udp_last_sent_yaw = local_node.rotation.y
	_udp_has_last_sent_pose = true


func _should_force_udp_send(local_player: Node) -> bool:
	if _udp_since_last_send_s < udp_force_send_min_interval_s:
		return false
	if not (local_player is Node3D):
		return false
	var local_node := local_player as Node3D
	if not _udp_has_last_sent_pose:
		return true
	var moved_m := local_node.global_position.distance_to(_udp_last_sent_position)
	if moved_m >= udp_force_send_move_threshold_m:
		return true
	var yaw_delta := absf(wrapf(local_node.rotation.y - _udp_last_sent_yaw, -PI, PI))
	return yaw_delta >= udp_force_send_yaw_threshold_rad


func _drain_udp_packets() -> void:
	if _udp_peer == null:
		return
	while _udp_peer.get_available_packet_count() > 0:
		var packet := _udp_peer.get_packet()
		_decode_snapshot_packet(packet)


func _decode_snapshot_packet(packet: PackedByteArray) -> void:
	if packet.size() < UDP_SNAPSHOT_HEADER_SIZE:
		return
	if packet.decode_u8(0) != UDP_PROTOCOL_VERSION:
		return
	if packet.decode_u8(1) != UDP_MSG_TYPE_SNAPSHOT:
		return

	var next_update_ms := packet.decode_u32(2)
	if next_update_ms > 0:
		_udp_server_interval_s = float(next_update_ms) / 1000.0

	# nearest_distance at offset 6 is unused on the client right now;
	# kept on the wire as float32 for future HUD/debug, skip past it.
	var count := packet.decode_u8(10)
	var off := UDP_SNAPSHOT_HEADER_SIZE
	var players: Array = []
	for _i in count:
		if off + 1 > packet.size():
			return
		var name_len := packet.decode_u8(off)
		off += 1
		if name_len == 0 or name_len > UDP_MAX_PLAYER_ID_LEN:
			return
		if off + name_len + UDP_SNAPSHOT_PLAYER_FLOATS_SIZE > packet.size():
			return
		var id_bytes := packet.slice(off, off + name_len)
		var player_id := id_bytes.get_string_from_utf8()
		off += name_len
		var x := packet.decode_float(off)
		off += 4
		var y := packet.decode_float(off)
		off += 4
		var z := packet.decode_float(off)
		off += 4
		var yaw := packet.decode_float(off)
		off += 4
		players.append({
			"player_id": player_id,
			"x": x,
			"y": y,
			"z": z,
			"yaw": yaw,
		})
	_apply_snapshot_players(players)


func _ensure_snapshot_request() -> void:
	if _snapshot_request != null and is_instance_valid(_snapshot_request):
		return
	_snapshot_request = HTTPRequest.new()
	_snapshot_request.name = "WorldSnapshotHttpRequest"
	add_child(_snapshot_request)
	_snapshot_request.request_completed.connect(_on_snapshot_request_completed)


func _resolve_local_player() -> Node:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node


func _request_world_snapshot() -> void:
	var local_player := _resolve_local_player()
	if local_player == null:
		return
	if not local_player.has_method("get_network_player_id"):
		return

	var self_id := String(local_player.call("get_network_player_id")).strip_edges()
	if self_id.is_empty():
		return

	var snapshot_url := _resolve_snapshot_url(local_player, self_id)
	if snapshot_url.is_empty():
		return

	_request_in_flight = true
	var err := _snapshot_request.request(snapshot_url)
	if err != OK:
		_request_in_flight = false
		push_warning(
			"PlayerVisibilityService: snapshot request failed to start err=%d url=%s"
			% [err, snapshot_url]
		)


func _resolve_snapshot_url(local_player: Node, self_id: String) -> String:
	var has_position_url := false
	var properties: Array[Dictionary] = local_player.get_property_list()
	for p: Dictionary in properties:
		if String(p.get("name", "")) == "position_api_url":
			has_position_url = true
			break
	if not has_position_url:
		return ""

	var base_url := String(local_player.get("position_api_url")).strip_edges()
	if base_url.is_empty():
		return ""

	var snapshot_url := base_url.replace("/v1/player-position", "/v1/world-snapshot")
	if snapshot_url == base_url:
		var slash := "" if base_url.ends_with("/") else "/"
		snapshot_url = "%s%sv1/world-snapshot" % [base_url, slash]

	var separator := "&" if snapshot_url.contains("?") else "?"
	return "%s%splayer_id=%s" % [snapshot_url, separator, self_id.uri_encode()]


func _on_snapshot_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	_request_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning(
			"PlayerVisibilityService: snapshot transport failure result=%d"
			% result
		)
		return
	if response_code < 200 or response_code >= 300:
		push_warning("PlayerVisibilityService: snapshot request failed HTTP=%d" % response_code)
		return

	var parsed_variant: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed_variant) != TYPE_DICTIONARY:
		push_warning("PlayerVisibilityService: invalid snapshot payload")
		return
	var parsed: Dictionary = parsed_variant

	var players_variant: Variant = parsed.get("players", [])
	if typeof(players_variant) != TYPE_ARRAY:
		push_warning("PlayerVisibilityService: snapshot missing players array")
		return
	var players: Array = players_variant
	_apply_snapshot_players(players)


func _apply_snapshot_players(players: Array) -> void:
	_ensure_remote_root()
	if _remote_root == null:
		return
	var visible_ids: Dictionary = {}
	for player_variant: Variant in players:
		if typeof(player_variant) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = player_variant as Dictionary
		var player_id := String(player.get("player_id", "")).strip_edges()
		if player_id.is_empty():
			continue
		visible_ids[player_id] = true
		_upsert_remote_player(player_id, player)
	_prune_missing_remote_players(visible_ids)


func _ensure_remote_root() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if (
		_remote_root != null
		and is_instance_valid(_remote_root)
		and _remote_root.get_parent() == scene
	):
		return

	if _remote_root != null and is_instance_valid(_remote_root):
		_remote_root.queue_free()
	_remote_players.clear()

	_remote_root = Node3D.new()
	_remote_root.name = remote_root_name
	scene.add_child(_remote_root)


func _upsert_remote_player(player_id: String, player: Dictionary) -> void:
	var state: Dictionary = _remote_players.get(player_id, {})
	var remote_node := state.get("node", null) as Node3D
	if remote_node == null or not is_instance_valid(remote_node):
		remote_node = Node3D.new()
		remote_node.name = "%s%s" % [REMOTE_PLAYER_PREFIX, player_id]
		var body := NpcBase.new()
		body.name = REMOTE_BODY_NAME
		body.visible = true
		remote_node.add_child(body)

		var name_label := Label3D.new()
		name_label.name = REMOTE_NAME_LABEL_NAME
		name_label.pixel_size = remote_nameplate_pixel_size
		name_label.modulate = remote_nameplate_color
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = true
		name_label.position = Vector3(0.0, remote_nameplate_height, 0.0)
		remote_node.add_child(name_label)

		_remote_root.add_child(remote_node)
		state = {"node": remote_node}

	var name_label := remote_node.get_node_or_null(REMOTE_NAME_LABEL_NAME) as Label3D
	if name_label != null:
		name_label.text = player_id
		name_label.position = Vector3(0.0, remote_nameplate_height, 0.0)
		name_label.pixel_size = remote_nameplate_pixel_size
		name_label.modulate = remote_nameplate_color

	var target_position := Vector3(
		float(player.get("x", 0.0)),
		float(player.get("y", 0.0)),
		float(player.get("z", 0.0))
	)
	var target_yaw := float(player.get("yaw", 0.0))
	var now_s := Time.get_ticks_msec() * 0.001

	if not state.has("target_position"):
		remote_node.global_position = target_position
		remote_node.rotation.y = target_yaw
		state["snapshot_velocity"] = Vector3.ZERO
		state["snapshot_yaw_velocity"] = 0.0
		state["last_snapshot_position"] = target_position
		state["last_snapshot_yaw"] = target_yaw
		state["last_snapshot_at"] = now_s
	else:
		var prev_position := state.get("last_snapshot_position", target_position) as Vector3
		var prev_yaw := float(state.get("last_snapshot_yaw", target_yaw))
		var prev_time := float(state.get("last_snapshot_at", now_s))
		var dt := maxf(now_s - prev_time, 0.0001)
		var raw_velocity := (target_position - prev_position) / dt
		if raw_velocity.length() > remote_max_speed:
			raw_velocity = raw_velocity.normalized() * remote_max_speed
		var prev_velocity := state.get("snapshot_velocity", Vector3.ZERO) as Vector3
		var damp := clampf(remote_velocity_damping, 0.0, 0.98)
		raw_velocity = prev_velocity * damp + raw_velocity * (1.0 - damp)
		var yaw_delta := wrapf(target_yaw - prev_yaw, -PI, PI)
		var raw_yaw_velocity := clampf(
			yaw_delta / dt,
			-remote_max_turn_speed,
			remote_max_turn_speed
		)
		var prev_yaw_velocity := float(state.get("snapshot_yaw_velocity", 0.0))
		raw_yaw_velocity = prev_yaw_velocity * damp + raw_yaw_velocity * (1.0 - damp)
		state["snapshot_velocity"] = raw_velocity
		state["snapshot_yaw_velocity"] = raw_yaw_velocity
		state["last_snapshot_position"] = target_position
		state["last_snapshot_yaw"] = target_yaw
		state["last_snapshot_at"] = now_s

	state["target_position"] = target_position
	state["target_yaw"] = target_yaw
	_remote_players[player_id] = state


func _prune_missing_remote_players(visible_ids: Dictionary) -> void:
	var known_ids := _remote_players.keys()
	for id_variant in known_ids:
		var player_id := String(id_variant)
		if visible_ids.has(player_id):
			continue
		var remote_node := _remote_players.get(player_id, null) as Node3D
		if remote_node == null:
			var state: Dictionary = _remote_players.get(player_id, {})
			remote_node = state.get("node", null) as Node3D
		if remote_node != null and is_instance_valid(remote_node):
			remote_node.queue_free()
		_remote_players.erase(player_id)


func _tick_remote_interpolation(delta: float) -> void:
	if _remote_players.is_empty():
		return

	var pos_alpha := 1.0 - exp(-remote_position_smoothness * delta)
	var yaw_alpha := 1.0 - exp(-remote_yaw_smoothness * delta)
	for id_variant in _remote_players.keys():
		var player_id := String(id_variant)
		var state: Dictionary = _remote_players.get(player_id, {})
		var remote_node := state.get("node", null) as Node3D
		if remote_node == null or not is_instance_valid(remote_node):
			continue

		var target_position := state.get("target_position", remote_node.global_position) as Vector3
		var target_yaw := float(state.get("target_yaw", remote_node.rotation.y))
		var snapshot_velocity := state.get("snapshot_velocity", Vector3.ZERO) as Vector3
		var snapshot_yaw_velocity := float(state.get("snapshot_yaw_velocity", 0.0))
		var last_snapshot_at := float(state.get("last_snapshot_at", Time.get_ticks_msec() * 0.001))
		var now_s := Time.get_ticks_msec() * 0.001
		var age_s := maxf(0.0, now_s - last_snapshot_at)
		var horizon_s := minf(age_s + remote_prediction_lead_s, remote_prediction_max_s)
		var predicted_position := target_position + snapshot_velocity * horizon_s
		var predicted_yaw := target_yaw + snapshot_yaw_velocity * horizon_s

		remote_node.global_position = remote_node.global_position.lerp(
			predicted_position,
			pos_alpha
		)
		remote_node.rotation.y = lerp_angle(remote_node.rotation.y, predicted_yaw, yaw_alpha)
