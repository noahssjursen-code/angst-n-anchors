extends Node3D

## Replicates port gantry cranes in-world.
## Wires boarding state changes and joint state updates for operated cranes.

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

@export var remote_crane_smoothness: float = 12.0
@export var crane_state_send_interval_s: float = 0.15
@export var crane_force_send_joint_threshold_m: float = 0.15
@export var crane_force_send_yaw_threshold_rad: float = 0.15

var _local_cranes: Dictionary = {}
var _remote_cranes: Dictionary = {}
var _crane_outbound: Dictionary = {}

var _piloting_player_ids: Dictionary = {}


func register_crane(crane_id: String, crane_node: Node) -> void:
	print("[CraneReplicator] Registering crane: ", crane_id, " node: ", crane_node.name if crane_node else "null")
	if crane_id.is_empty() or crane_node == null:
		return
	if not is_instance_valid(crane_node):
		return
		
	var was_known := _local_cranes.has(crane_id)
	_local_cranes[crane_id] = crane_node
	
	if crane_node.has_method("set_meta"):
		crane_node.set_meta("network_crane_id", crane_id)
		
	# Successfully registered local crane


func set_local_crane_boarded(crane_id: String, boarded: bool) -> void:
	print("[CraneReplicator] set_local_crane_boarded: ", crane_id, " boarded: ", boarded)
	var state: Dictionary = _crane_outbound.get(crane_id, {})
	state["boarded"] = boarded
	if boarded:
		state["state_seq"] = int(state.get("state_seq", 0))
		state["operate_seq"] = int(state.get("operate_seq", 0))
		state["last_sent_at_s"] = 0.0
		state["last_sent_joints"] = Vector4.ZERO
	_crane_outbound[crane_id] = state


func apply_cranes(cranes_list: Array) -> void:
	_piloting_player_ids.clear()
	var visible_ids: Dictionary = {}
	var manager := get_parent()
	var local_id := ""
	if manager != null and manager.has_method("get_local_player_id"):
		local_id = manager.call("get_local_player_id")
		
	for c_data: Dictionary in cranes_list:
		var crane_id: String = c_data.get("crane_id", "").strip_edges()
		if crane_id.is_empty():
			continue
			
		var operator_id: String = c_data.get("operator_id", "")
		if operator_id.is_empty():
			_remote_cranes.erase(crane_id)
			var node_val: Variant = _local_cranes.get(crane_id, null)
			if is_instance_valid(node_val):
				var node := node_val as Node
				node.set("_remotely_operated_by", "")
			continue
			
		visible_ids[crane_id] = true
		_piloting_player_ids[operator_id] = true
			
		# A local crane operated by us is the source of truth — don't fight
		# our own input by lerping back to a stale server echo.
		if not local_id.is_empty() and operator_id == local_id:
			_remote_cranes.erase(crane_id)
			var node_val: Variant = _local_cranes.get(crane_id, null)
			if is_instance_valid(node_val):
				var node := node_val as Node
				node.set("_remotely_operated_by", operator_id)
			continue
			
		var state: Dictionary = _remote_cranes.get(crane_id, {})
		state["operator_id"] = operator_id
		
		var now_ms := Time.get_ticks_msec()
		var target_x := float(c_data.get("gantry_x", 0.0))
		var target_z := float(c_data.get("trolley_z", 0.0))
		var target_drop := float(c_data.get("hook_drop", 0.0))
		var target_yaw := float(c_data.get("hook_yaw", 0.0))
		
		var last_x := float(state.get("target_gantry_x", target_x))
		var last_z := float(state.get("target_trolley_z", target_z))
		var last_drop := float(state.get("target_hook_drop", target_drop))
		var last_yaw := float(state.get("target_hook_yaw", target_yaw))
		var last_time := float(state.get("last_packet_time_ms", now_ms))
		
		var dt := (now_ms - last_time) * 0.001
		if dt > 0.001:
			var vel_x := (target_x - last_x) / dt
			var vel_z := (target_z - last_z) / dt
			var vel_drop := (target_drop - last_drop) / dt
			var vel_yaw := wrapf(target_yaw - last_yaw, -PI, PI) / dt
			
			# Low-pass filter joint velocities to smooth out jitter
			var prev_vel_x := float(state.get("vel_x", 0.0))
			var prev_vel_z := float(state.get("vel_z", 0.0))
			var prev_vel_drop := float(state.get("vel_drop", 0.0))
			var prev_vel_yaw := float(state.get("vel_yaw", 0.0))
			
			state["vel_x"] = lerpf(prev_vel_x, vel_x, 0.5)
			state["vel_z"] = lerpf(prev_vel_z, vel_z, 0.5)
			state["vel_drop"] = lerpf(prev_vel_drop, vel_drop, 0.5)
			state["vel_yaw"] = lerpf(prev_vel_yaw, vel_yaw, 0.5)
		else:
			state["vel_x"] = 0.0
			state["vel_z"] = 0.0
			state["vel_drop"] = 0.0
			state["vel_yaw"] = 0.0
			
		state["target_gantry_x"] = target_x
		state["target_trolley_z"] = target_z
		state["target_hook_drop"] = target_drop
		state["target_hook_yaw"] = target_yaw
		state["last_packet_time_ms"] = now_ms
		
		state["base_position"] = Vector3(
			float(c_data.get("base_x", 0.0)),
			float(c_data.get("base_y", 0.0)),
			float(c_data.get("base_z", 0.0))
		)
		state["base_yaw"] = float(c_data.get("base_yaw", 0.0))
		_remote_cranes[crane_id] = state
		
		# Tag the local crane node so its own input checks can refuse
		# to fight us when operated by someone else
		var node_val: Variant = _local_cranes.get(crane_id, null)
		if is_instance_valid(node_val):
			var node := node_val as Node
			node.set("_remotely_operated_by", operator_id)
			
	# When a crane is no longer in any snapshot, clear the remote-operator marker
	for known_id_variant in _remote_cranes.keys():
		var known_id := String(known_id_variant)
		if not visible_ids.has(known_id):
			var node_val: Variant = _local_cranes.get(known_id, null)
			if is_instance_valid(node_val):
				var node := node_val as Node
				node.set("_remotely_operated_by", "")
			_remote_cranes.erase(known_id)
			
	# Notify manager of crane piloting list
	if manager != null and manager.has_method("apply_crane_pilot_visibilities"):
		manager.call("apply_crane_pilot_visibilities", _piloting_player_ids)


func interpolate(delta: float) -> void:
	if _remote_cranes.is_empty():
		return
		
	var alpha := 1.0 - exp(-remote_crane_smoothness * delta)
	var now_ms := Time.get_ticks_msec()
	
	for id_variant in _remote_cranes.keys():
		var crane_id := String(id_variant)
		var state: Dictionary = _remote_cranes[crane_id]
		var node_val: Variant = _local_cranes.get(crane_id, null)
		if node_val == null or not is_instance_valid(node_val):
			continue
		var node := node_val as Node
			
		var target_x := float(state.get("target_gantry_x", 0.0))
		var target_z := float(state.get("target_trolley_z", 0.0))
		var target_drop := float(state.get("target_hook_drop", 1.0))
		var target_yaw := float(state.get("target_hook_yaw", 0.0))
		
		var vel_x := float(state.get("vel_x", 0.0))
		var vel_z := float(state.get("vel_z", 0.0))
		var vel_drop := float(state.get("vel_drop", 0.0))
		var vel_yaw := float(state.get("vel_yaw", 0.0))
		var last_time := float(state.get("last_packet_time_ms", now_ms))
		
		var dt := (now_ms - last_time) * 0.001
		# Cap prediction time to 1.0 second
		var prediction_time := minf(dt, 1.0)
		
		var predicted_x := target_x + vel_x * prediction_time
		var predicted_z := target_z + vel_z * prediction_time
		var predicted_drop := target_drop + vel_drop * prediction_time
		var predicted_yaw := target_yaw + vel_yaw * prediction_time
		
		var cur_x := float(node.get("_gantry_x_offset"))
		var cur_z := float(node.get("_trolley_z"))
		var cur_drop := float(node.get("_hoist_drop"))
		
		node.set("_gantry_x_offset", lerpf(cur_x, predicted_x, alpha))
		node.set("_trolley_z", lerpf(cur_z, predicted_z, alpha))
		node.set("_hoist_drop", lerpf(cur_drop, predicted_drop, alpha))
		
		var hook_node := node.get("_hook") as Node3D
		if hook_node == null or not is_instance_valid(hook_node):
			# Fallback if _hook member isn't populated
			var gantry := node.get_node_or_null("GantryFrame") as Node3D
			if gantry != null:
				var trolley_node := gantry.find_child("trolley", true, false) as Node3D
				if trolley_node == null:
					trolley_node = gantry.find_child("Trolley", true, false) as Node3D
				if trolley_node != null:
					hook_node = trolley_node.find_child("hook", true, false) as Node3D
					if hook_node == null:
						hook_node = trolley_node.find_child("Hook", true, false) as Node3D
					if hook_node == null:
						hook_node = trolley_node.find_child("hook_block", true, false) as Node3D
						
		if hook_node != null and is_instance_valid(hook_node):
			hook_node.rotation.y = lerp_angle(
				hook_node.rotation.y,
				predicted_yaw,
				alpha
			)


func tick_local_crane_outbound(delta: float) -> void:
	if _crane_outbound.is_empty():
		return
		
	var now_s := Time.get_ticks_msec() * 0.001
	for crane_id_variant in _crane_outbound.keys():
		var crane_id := String(crane_id_variant)
		var state: Dictionary = _crane_outbound[crane_id]
		if not bool(state.get("boarded", false)):
			continue
			
		var node_val: Variant = _local_cranes.get(crane_id, null)
		if node_val == null or not is_instance_valid(node_val):
			continue
		var node := node_val as Node
			
		var joints: Variant = _sample_crane_joints(node)
		if joints == null:
			continue
			
		var last := state.get("last_sent_joints", Vector4.ZERO) as Vector4
		var joint_delta := maxf(
			maxf(absf(joints["gantry_x"] - last.x), absf(joints["trolley_z"] - last.y)),
			absf(joints["hook_drop"] - last.z)
		)
		var yaw_delta := absf(wrapf(joints["hook_yaw"] - last.w, -PI, PI))
		var last_at := float(state.get("last_sent_at_s", 0.0))
		var force := (
			joint_delta >= crane_force_send_joint_threshold_m
			or yaw_delta >= crane_force_send_yaw_threshold_rad
		)
		
		# Only send if we are actively moving (force is true),
		# or as a slow background heartbeat (every 3 seconds) to keep the connection alive
		if force or now_s - last_at >= 3.0:
			var manager := get_parent()
			if manager != null and manager.has_method("send_crane_state"):
				print("[CraneReplicator] Sending crane state: ", crane_id, " joints: ", joints)
				state["last_sent_joints"] = Vector4(
					joints["gantry_x"], joints["trolley_z"],
					joints["hook_drop"], joints["hook_yaw"]
				)
				state["last_sent_at_s"] = now_s
				_crane_outbound[crane_id] = state
				manager.call("send_crane_state", crane_id, joints)


func _sample_crane_joints(crane_node: Node) -> Variant:
	if crane_node == null or not is_instance_valid(crane_node):
		return null
		
	var trolley_node := crane_node.get("_trolley") as Node3D
	var hook_node := crane_node.get("_hook") as Node3D
	
	if trolley_node == null or hook_node == null or not is_instance_valid(trolley_node) or not is_instance_valid(hook_node):
		var gantry := crane_node.get_node_or_null("GantryFrame") as Node3D
		if gantry == null:
			return null
		trolley_node = gantry.find_child("trolley", true, false) as Node3D
		if trolley_node == null:
			trolley_node = gantry.find_child("Trolley", true, false) as Node3D
		if trolley_node != null:
			hook_node = trolley_node.find_child("hook", true, false) as Node3D
			if hook_node == null:
				hook_node = trolley_node.find_child("Hook", true, false) as Node3D
			if hook_node == null:
				hook_node = trolley_node.find_child("hook_block", true, false) as Node3D
				
	if trolley_node == null or hook_node == null or not is_instance_valid(trolley_node) or not is_instance_valid(hook_node):
		return null
		
	var gantry_x_val := float(crane_node.get("_gantry_x_offset"))
	var trolley_z_val := float(crane_node.get("_trolley_z"))
	var hoist_drop_val := float(crane_node.get("_hoist_drop"))
	
	var crane3d := crane_node as Node3D
	var base_pos := crane3d.global_position
	var base_yaw := _node_global_yaw_rad(crane3d)
	
	return {
		"gantry_x": gantry_x_val,
		"trolley_z": trolley_z_val,
		"hook_drop": hoist_drop_val,
		"hook_yaw": hook_node.rotation.y,
		"base_x": base_pos.x,
		"base_y": base_pos.y,
		"base_z": base_pos.z,
		"base_yaw": base_yaw,
	}


func _node_global_yaw_rad(node: Node3D) -> float:
	var basis := node.global_transform.basis
	return atan2(basis.z.x, basis.z.z)


func find_crane_operated_by(player_id: String) -> Node3D:
	if player_id.is_empty():
		return null
	for crane_id in _local_cranes.keys():
		var node_val: Variant = _local_cranes[crane_id]
		if is_instance_valid(node_val):
			var node := node_val as Node
			if node.get("_remotely_operated_by") == player_id:
				return node as Node3D
	return null


func clear_all() -> void:
	for id_variant in _remote_cranes.keys():
		var node_val: Variant = _local_cranes.get(id_variant, null)
		if is_instance_valid(node_val):
			var node := node_val as Node
			node.set("_remotely_operated_by", "")
	_remote_cranes.clear()
	_crane_outbound.clear()
