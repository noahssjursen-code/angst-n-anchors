extends Node3D

## Replicates remote player avatars in-world with smooth movement.

const REMOTE_PLAYER_PREFIX := "RemotePlayer_"
const REMOTE_BODY_NAME := "BodyMesh"
const REMOTE_NAME_LABEL_NAME := "PlayerNameLabel"

@export var remote_position_smoothness: float = 18.0
@export var remote_yaw_smoothness: float = 16.0
@export var remote_nameplate_height: float = 2.2
@export var remote_nameplate_pixel_size: float = 0.01

var _remote_players: Dictionary = {}


func apply_players(players_list: Array) -> void:
	var visible_ids: Dictionary = {}
	var manager := get_parent()
	var local_player_id := ""
	if manager != null and manager.has_method("get_local_player_id"):
		local_player_id = manager.call("get_local_player_id")
		
	for p_data: Dictionary in players_list:
		var p_id: String = p_data.get("player_id", "")
		if p_id.is_empty():
			continue
		# Don't replicate ourselves
		if p_id == local_player_id:
			continue
			
		visible_ids[p_id] = true
		_upsert_player(p_id, p_data)
		
	# Clean up players that are no longer in our relevance range
	for known_id_variant in _remote_players.keys():
		var known_id := String(known_id_variant)
		if not visible_ids.has(known_id):
			var state: Dictionary = _remote_players[known_id]
			var node_val: Variant = state.get("node", null)
			if is_instance_valid(node_val):
				node_val.queue_free()
			_remote_players.erase(known_id)


func _upsert_player(player_id: String, p_data: Dictionary) -> void:
	var state: Dictionary = _remote_players.get(player_id, {})
	var node_val: Variant = state.get("node", null)
	var node: Node3D = null
	if is_instance_valid(node_val):
		node = node_val as Node3D
	
	var target_pos := Vector3(p_data.get("x", 0.0), p_data.get("y", 0.0), p_data.get("z", 0.0))
	var target_yaw := float(p_data.get("yaw", 0.0))
	
	var now_ms := Time.get_ticks_msec()
	
	if node == null or not is_instance_valid(node):
		node = _spawn_remote_player_node(player_id)
		add_child(node)
		node.global_position = target_pos
		node.rotation.y = target_yaw
		state["node"] = node
		state["target_position"] = target_pos
		state["target_yaw"] = target_yaw
		state["velocity"] = Vector3.ZERO
		state["yaw_velocity"] = 0.0
		state["last_packet_time_ms"] = now_ms
	else:
		var last_pos: Vector3 = state.get("target_position", target_pos)
		var last_yaw: float = state.get("target_yaw", target_yaw)
		var last_time: float = state.get("last_packet_time_ms", now_ms)
		
		var dt := (now_ms - last_time) * 0.001
		if dt > 0.001:
			var raw_vel := (target_pos - last_pos) / dt
			if raw_vel.length() > 30.0:
				raw_vel = raw_vel.limit_length(30.0)
				
			var prev_vel: Vector3 = state.get("velocity", Vector3.ZERO)
			state["velocity"] = prev_vel.lerp(raw_vel, 0.5)
			
			var diff := wrapf(target_yaw - last_yaw, -PI, PI)
			var raw_yaw_vel := diff / dt
			var prev_yaw_vel: float = state.get("yaw_velocity", 0.0)
			state["yaw_velocity"] = lerpf(prev_yaw_vel, raw_yaw_vel, 0.5)
			
		state["target_position"] = target_pos
		state["target_yaw"] = target_yaw
		state["last_packet_time_ms"] = now_ms
		
	_remote_players[player_id] = state


func _spawn_remote_player_node(player_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "%s%s" % [REMOTE_PLAYER_PREFIX, player_id]
	
	# Visual model body
	var body := NpcBase.new()
	body.name = REMOTE_BODY_NAME
	body.skin_color = Color(0.65, 0.48, 0.38)
	body.clothing_color = Color(0.24, 0.28, 0.44)
	body.trousers_color = Color(0.18, 0.18, 0.22)
	root.add_child(body)
	
	# Nameplate
	var label := Label3D.new()
	label.name = REMOTE_NAME_LABEL_NAME
	label.text = player_id
	label.font_size = 48
	label.pixel_size = remote_nameplate_pixel_size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.96, 0.92, 0.78, 0.95)
	label.position = Vector3(0.0, remote_nameplate_height, 0.0)
	root.add_child(label)
	
	return root


func interpolate(delta: float) -> void:
	if _remote_players.is_empty():
		return
		
	var pos_alpha := 1.0 - exp(-remote_position_smoothness * delta)
	var yaw_alpha := 1.0 - exp(-remote_yaw_smoothness * delta)
	
	var now_ms := Time.get_ticks_msec()
	
	for id_variant in _remote_players.keys():
		var player_id := String(id_variant)
		var state: Dictionary = _remote_players[player_id]
		var node_val: Variant = state.get("node", null)
		if node_val == null or not is_instance_valid(node_val):
			continue
		var node := node_val as Node3D
			
		var target_pos: Vector3 = state.get("target_position", node.global_position)
		var target_yaw: float = state.get("target_yaw", node.rotation.y)
		
		var vel: Vector3 = state.get("velocity", Vector3.ZERO)
		var yaw_vel: float = state.get("yaw_velocity", 0.0)
		var last_time: float = state.get("last_packet_time_ms", now_ms)
		
		var dt := (now_ms - last_time) * 0.001
		# Cap prediction at 1.0 second to avoid running forever if connection drops
		var prediction_time := minf(dt, 1.0)
		
		var predicted_pos := target_pos + vel * prediction_time
		var predicted_yaw := target_yaw + yaw_vel * prediction_time
		
		node.global_position = node.global_position.lerp(predicted_pos, pos_alpha)
		node.rotation.y = lerp_angle(node.rotation.y, predicted_yaw, yaw_alpha)


func set_player_visibility(player_id: String, is_visible: bool) -> void:
	var state: Dictionary = _remote_players.get(player_id, {})
	var node_val: Variant = state.get("node", null)
	if is_instance_valid(node_val):
		(node_val as Node3D).visible = is_visible


func clear_all() -> void:
	for id_variant in _remote_players.keys():
		var state: Dictionary = _remote_players[id_variant]
		var node_val: Variant = state.get("node", null)
		if is_instance_valid(node_val):
			node_val.queue_free()
	_remote_players.clear()
