extends Node3D

## ReplicationDrawingService handles instantiation, interpolation,
## and destruction of visual remote entities in the world scene.
## Pure visual and tree management; no socket I/O or packet routing.

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")
const LARGE_SHIP_FULL_DETAIL_DISTANCE_M := 50.0
const SHIP_DETAIL_REFRESH_S := 0.5

# Tracks active visual remote representations: id -> { "node": Node3D, "type": String, "target_pos": Vector3, "target_payload": Array, "interpolated_payload": Array, "meta": String, "last_seen_ms": int }
var _visible_entities: Dictionary = {}
var _wake_field: OceanWakeField
var _ship_detail_elapsed := 0.0


func _live_node(state: Dictionary) -> Node3D:
	var raw: Variant = state.get("node", null)
	if raw == null:
		return null
	if not is_instance_valid(raw):
		return null
	return raw as Node3D


func _prune_stale_entries() -> void:
	var stale: Array[String] = []
	for id_variant in _visible_entities.keys():
		var id := String(id_variant)
		var state: Dictionary = _visible_entities[id]
		if _live_node(state) == null:
			stale.append(id)
	for id in stale:
		_visible_entities.erase(id)


func _purge_entities_under(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	var stale: Array[String] = []
	for id_variant in _visible_entities.keys():
		var id := String(id_variant)
		var node := _live_node(_visible_entities[id_variant] as Dictionary)
		if node == null:
			stale.append(id)
			continue
		if node != root and root.is_ancestor_of(node):
			stale.append(id)
	for id in stale:
		_visible_entities.erase(id)

# Active continuous-quay call locks established by remote ships:
# call_id -> { ship_id, port_id, start_m, end_m }.
var _occupied_calls: Dictionary = {}

## Cache of fetched deck layouts: server_vessel_id -> { "hash": String, "layout": Dictionary }
var _layout_cache: Dictionary = {}
## In-flight HTTP fetches keyed by server_vessel_id.
var _layout_inflight: Dictionary = {}

## Returns a duplicate of currently visible remote entities dictionary (for read-only queries)
func get_visible_entities() -> Dictionary:
	return _visible_entities


## Drop cached remote state for an entity we own locally again (sold/released).
func clear_entity_remote_state(id: String) -> void:
	if not _visible_entities.has(id):
		return
	var state: Dictionary = _visible_entities[id]
	var node := _live_node(state)
	if node != null:
		_purge_entities_under(node)
		if node.has_method("set"):
			node.set("_remotely_operated_by", "")
		# Dynamic remotes are children of this service; pre-placed scene nodes are not.
		if node.get_parent() == self:
			node.queue_free()
	_visible_entities.erase(id)


## Back-compat alias for crane vacate cleanup.
func clear_scene_node_remote_state(id: String) -> void:
	clear_entity_remote_state(id)

# Custom scene templates mapping
const TYPE_SCENE_MAP := {
}


## Processes snapshot frames to add, update, or remove remote entity nodes.
func apply_entities(entities_list: Array, local_id: String, scene_nodes: Dictionary, local_sender_ids: Array, now_ms: int, timeout_ms: int) -> void:
	_prune_stale_entries()
	var active_snapshot_ids: Dictionary = {}
	var active_pilot_ids: Dictionary = {}
	var current_frame_calls: Dictionary = {}
	
	for ent: Dictionary in entities_list:
		var id: String = ent["id"]
		
		# 1. Skip ourselves and anything we currently have authority over (local senders)
		if id == local_id or local_sender_ids.has(id):
			continue

		# Ignore snapshot echo of our own released entities — stale cargo/crane
		# state otherwise respawns visuals and blocks gameplay.
		if str(ent.get("owner_id", "")) == local_id:
			continue
			
		active_snapshot_ids[id] = true
		
		# Track piloted/operated players to handle visual avatar hiding
		var meta: String = ent["meta"]
		if _is_delivered_cargo_meta(meta):
			_despawn_remote_entity(id, scene_nodes)
			continue

		_parse_pilot_meta(meta, active_pilot_ids)
		
		# 2. Check if we already have this entity drawn
		var state: Dictionary = _visible_entities.get(id, {})
		var node := _live_node(state)
		
		if node == null:
			# New entity! First check if it is a pre-placed level node (like cranes)
			if scene_nodes.has(id):
				node = scene_nodes[id] as Node3D
				print("[ReplicationDrawingService] Binding pre-placed node: ", id)
			else:
				# Spawn dynamic visual node
				node = _spawn_dynamic_entity_node(id, ent["type"], meta)
				if node != null:
					add_child(node)
					node.global_position = ent["pos"]
					var payload: Array = ent.get("payload", [])
					if str(ent["type"]).begins_with("ship_") and payload.size() >= 6:
						node.global_rotation = Vector3(payload[3], payload[4], payload[5])
					print("[ReplicationDrawingService] Spawned dynamic: ", id, " (", ent["type"], ")")
			
			if node != null:
				state["node"] = node
				state["type"] = ent["type"]
				state["interpolated_payload"] = ent["payload"].duplicate()
				state["walk_distance_m"] = 0.0
				state["walk_sample_pos"] = ent["pos"]
		
		if node != null:
			state["target_pos"] = ent["pos"]
			state["target_payload"] = ent["payload"]
			state["meta"] = ent["meta"]
			state["last_seen_ms"] = now_ms
			_visible_entities[id] = state
			
			_parse_call_meta(id, ent["type"], meta, current_frame_calls)
			
			# Process Dynamic Parent/Relational Attachment Meta: "parent=parent_entity_id"
			_process_attachment_meta(node, id, meta)

			if str(ent["type"]).begins_with("ship_"):
				_sync_remote_ship_layout(id, node as BoatBody, meta, state)
		
	# Update remote players avatar visibility (hide those driving ships/cranes)
	_update_avatar_visibilities(active_pilot_ids)
	
	# Reconcile shared-quay call occupancy changes.
	_reconcile_call_locks(current_frame_calls)
			
	# 3. Clean up expired/lost entities.
	# With standstill throttling, an entity might be omitted from snapshot packets simply because
	# it is stationary. Therefore, we ONLY despawn an entity if we haven't heard from it in timeout_ms (3.0s),
	# rather than immediately when it is missing from a single packet.
	for id_variant in _visible_entities.keys():
		var id := String(id_variant)
		var state: Dictionary = _visible_entities[id]
		var age := now_ms - int(state["last_seen_ms"])
		
		if age > timeout_ms:
			var node := _live_node(state)
			if node != null:
				_purge_entities_under(node)
				if not scene_nodes.has(id):
					print("[ReplicationDrawingService] Despawning expired: ", id)
					node.queue_free()
				else:
					# Reset pre-placed level node operator tags
					if node.has_method("set"):
						node.set("_remotely_operated_by", "")
			_visible_entities.erase(id)


## Interpolates active visual entities towards their goals.
func interpolate_entities(delta: float, position_smoothness: float, payload_smoothness: float) -> void:
	_prune_stale_entries()
	var pos_alpha := 1.0 - exp(-position_smoothness * delta)
	var pay_alpha := 1.0 - exp(-payload_smoothness * delta)
	_ship_detail_elapsed += delta
	var refresh_ship_detail := _ship_detail_elapsed >= SHIP_DETAIL_REFRESH_S
	if refresh_ship_detail:
		_ship_detail_elapsed = 0.0
	
	for id in _visible_entities.keys():
		var state: Dictionary = _visible_entities[id]
		var node := _live_node(state)
		if node == null:
			continue
			
		var target_pos: Vector3 = state["target_pos"]
		var target_payload: Array = state["target_payload"]
		var current_payload: Array = state["interpolated_payload"]
		
		# 1. Smoothly interpolate 3D Pivot Position (skip if parented to avoid override conflicts)
		if node.get_parent() == self:
			node.global_position = node.global_position.lerp(target_pos, pos_alpha)
		else:
			# If parented, we Lerp local position towards relative offsets instead
			node.position = node.position.lerp(target_pos, pos_alpha)
		
		# 2. Smoothly interpolate Payload Floats
		if current_payload.size() != target_payload.size():
			current_payload = target_payload.duplicate()
			state["interpolated_payload"] = current_payload
		else:
			for k in current_payload.size():
				current_payload[k] = lerpf(current_payload[k], target_payload[k], pay_alpha)
		
		# 3. Apply state back to actual Godot properties
		_apply_state_to_node(node, state["type"], current_payload, state["meta"])
		if str(state["type"]).begins_with("ship_") and node is BoatBody:
			_submit_remote_ship_wake(str(id), node as BoatBody, state, delta)
			if refresh_ship_detail:
				_promote_remote_ship_detail(str(id), node as BoatBody, state)

		if state["type"] == "player":
			_drive_player_walk_cycle(state, node, delta)


func _submit_remote_ship_wake(
	entity_id: String,
	ship: BoatBody,
	state: Dictionary,
	delta: float,
) -> void:
	if delta <= 0.0001:
		return
	if _wake_field == null or not is_instance_valid(_wake_field):
		_wake_field = get_tree().get_first_node_in_group(
			"ocean_wake_field"
		) as OceanWakeField
	if _wake_field == null:
		return
	var current := ship.global_position
	var previous: Vector3 = state.get("wake_sample_pos", current)
	state["wake_sample_pos"] = current
	var velocity := (current - previous) / delta
	var planar_velocity := Vector2(velocity.x, velocity.z)
	var speed := minf(planar_velocity.length(), 25.0)
	if speed < 0.35:
		return
	var trailing_axis := -planar_velocity.normalized()
	var propeller_local := Vector3(
		0.0, ship.depth_m * 0.25, ship.length_m * 0.45
	)
	if ship.physics_profile != null:
		propeller_local = ship.physics_profile.propeller_position
	var propeller_world := ship.to_global(propeller_local)
	var speed_strength := smoothstep(0.35, 7.0, speed)
	_wake_field.submit_emitter(
		"remote:" + entity_id,
		Vector2(propeller_world.x, propeller_world.z),
		trailing_axis,
		ship.get_half_beam_m(),
		speed,
		speed_strength * 0.45,
		speed_strength * 0.75,
		30.0
	)


## Parses metadata to identify pilot IDs that should be hidden.
func _parse_pilot_meta(meta: String, active_pilot_ids: Dictionary) -> void:
	var parsed := _parse_meta_map(meta)
	var pid: String = parsed.get("pilot", "")
	if not pid.is_empty():
		active_pilot_ids[pid] = true
	var op_id: String = parsed.get("op", "")
	if not op_id.is_empty():
		active_pilot_ids[op_id] = true


## Updates avatar visibilities based on current piloting set.
func _update_avatar_visibilities(piloting_player_ids: Dictionary) -> void:
	for id in _visible_entities.keys():
		var state: Dictionary = _visible_entities[id]
		if state["type"] == "player":
			var node := _live_node(state)
			if node != null:
				node.visible = not piloting_player_ids.has(id)


## Parses `call=port_id,call_id,start_m,end_m` from ship metadata.
func _parse_call_meta(ship_id: String, type: String, meta: String, current_frame_calls: Dictionary) -> void:
	if not type.begins_with("ship_"):
		return
	var parsed := _parse_meta_map(meta)
	var raw := str(parsed.get("call", ""))
	var fields := raw.split(",")
	if fields.size() != 4:
		return
	var call_id := str(fields[1])
	if call_id.is_empty():
		return
	current_frame_calls[call_id] = {
		"ship_id": ship_id,
		"port_id": str(fields[0]),
		"call_id": call_id,
		"start_m": float(fields[2]),
		"end_m": float(fields[3]),
		"crane_ids": str(parsed.get("cranes", "")).split(
			",",
			false,
		),
	}


## Handles generic parent-child reparenting loops
func _process_attachment_meta(node: Node3D, entity_id: String, meta: String) -> void:
	var parsed := _parse_meta_map(meta)
	var parent_tag: String = parsed.get("parent", "")
	
	if not parent_tag.is_empty():
		# Locate parent node
		if _visible_entities.has(parent_tag):
			var parent_state: Dictionary = _visible_entities[parent_tag]
			var parent_node := _live_node(parent_state)
			
			if parent_node != null:
				# Optional: Resolve sub-node anchor target (e.g. parent=crane_1:hook_anchor)
				var actual_parent: Node3D = parent_node
				var path_parts := parent_tag.split(":")
				if path_parts.size() == 2:
					var sub_node := parent_node.find_child(path_parts[1], true, false) as Node3D
					if is_instance_valid(sub_node):
						actual_parent = sub_node
						
				if node.get_parent() != actual_parent:
					print("[Replication] Reparenting entity: ", entity_id, " under parent: ", parent_tag)
					node.reparent(actual_parent, true)
		return
		
	# If it has no parent tags but is nested inside another entity, bring it back to drawings root
	if node.get_parent() != self:
		print("[Replication] Detaching entity back to root: ", entity_id)
		node.reparent(self, true)


## Projects server-owned VesselCall locks onto streamed port presentation.
func _reconcile_call_locks(current_frame_calls: Dictionary) -> void:
	for call_id in current_frame_calls.keys():
		var call_data := current_frame_calls[call_id] as Dictionary
		_set_call_lock_state(call_data, true)
		_occupied_calls[call_id] = call_data
	for call_id in _occupied_calls.keys().duplicate():
		if current_frame_calls.has(call_id):
			continue
		_set_call_lock_state(_occupied_calls[call_id] as Dictionary, false)
		_occupied_calls.erase(call_id)


func _set_call_lock_state(call_data: Dictionary, active: bool) -> void:
	var port_id := str(call_data.get("port_id", ""))
	var ship_id := str(call_data.get("ship_id", ""))
	for dock in get_tree().get_nodes_in_group("port_docks"):
		var port_dock := dock as Node
		if port_dock == null or str(port_dock.get("port_id")) != port_id:
			continue
		var ship_node: BoatBody = null
		if active and _visible_entities.has(ship_id):
			ship_node = _live_node(_visible_entities[ship_id]) as BoatBody
		if port_dock.has_method("set_remote_call_lock"):
			port_dock.call("set_remote_call_lock", call_data, ship_node, active)
		if ship_node != null:
			ship_node.set_meta("port_call_id", str(call_data.get("call_id", "")))
			ship_node.set_meta("port_call_port_id", port_id)
			ship_node.set_meta("quay_start_m", float(call_data.get("start_m", 0.0)))
			ship_node.set_meta("quay_end_m", float(call_data.get("end_m", 0.0)))
		break


## Spawns custom visual remote scenes based on generic types.
func _spawn_dynamic_entity_node(id: String, type: String, meta: String = "") -> Node3D:
	# Custom mapping
	if TYPE_SCENE_MAP.has(type):
		var scene_res = load(TYPE_SCENE_MAP[type])
		if scene_res != null:
			var inst := scene_res.instantiate() as Node3D
			inst.name = "RemoteEntity_" + id
			return inst
			
	# A. Remote Players (Fallback/Direct)
	if type == "player":
		var root := Node3D.new()
		root.name = "RemotePlayer_" + id
		
		var body := NpcBase.new()
		body.name = "BodyMesh"
		body.skin_color = Color(0.65, 0.48, 0.38)
		body.clothing_color = Color(0.24, 0.28, 0.44)
		body.trousers_color = Color(0.18, 0.18, 0.22)
		root.add_child(body)
		
		var label := Label3D.new()
		label.name = "PlayerNameLabel"
		label.text = id.split("_")[0]
		label.font_size = 48
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(0.96, 0.92, 0.78, 0.95)
		label.position = Vector3(0.0, 2.2, 0.0)
		root.add_child(label)
		return root
		
	# B. Remote cargo packing removed — ignore legacy type until containers land.
	if type == "cargo":
		return null

	# C. Remote Ships
	if type.begins_with("ship_"):
		var hull_id := HullRegistry.resolve_network_hull_id(
			HullRegistry.hull_id_from_network_type(type)
		)
		## Spawn bare hull first; layout applied async when vid/lh meta arrives.
		var ship := VesselSpawn.instantiate(hull_id) as BoatBody
		if ship != null:
			ship.name = "RemoteShip_" + id
			ship.set_meta("remote_replica", true)
			ship.freeze = true
			ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			_disable_physics_in_subtree(ship)

			var label := Label3D.new()
			label.name = "ShipNameLabel"
			label.text = "%s (%s)" % [id.split("_")[0], hull_id.capitalize()]
			label.font_size = 64
			label.pixel_size = 0.015
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.modulate = Color(0.96, 0.92, 0.78, 0.95)
			label.position = Vector3(0.0, 5.0, 0.0)
			ship.add_child(label)
			return ship
		push_warning(
			"ReplicationDrawingService: failed to spawn remote ship hull_id=%s"
			% hull_id
		)

	return null


func _sync_remote_ship_layout(entity_id: String, ship: BoatBody, meta: String, state: Dictionary) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var parsed := _parse_meta_map(meta)
	var vid := str(parsed.get("vid", ""))
	var lh := str(parsed.get("lh", ""))
	if vid.is_empty():
		return

	var applied_vid := str(state.get("layout_vid", ""))
	var applied_hash := str(state.get("layout_hash", ""))
	## Already applied this vessel; only refetch when layout hash changes.
	if applied_vid == vid and (lh.is_empty() or applied_hash == lh):
		return

	var cached: Dictionary = _layout_cache.get(vid, {})
	if not cached.is_empty() and (lh.is_empty() or str(cached.get("hash", "")) == lh):
		_apply_remote_ship_layout(ship, cached.get("layout", {}) as Dictionary)
		state["layout_vid"] = vid
		state["layout_hash"] = str(cached.get("hash", lh))
		_visible_entities[entity_id] = state
		return

	if _layout_inflight.has(vid):
		return

	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		session = get_tree().root.get_node_or_null("/root/PlayerSession")
	if session == null:
		return

	_layout_inflight[vid] = true
	VesselSync.fetch_vessel_layout(session, vid, func(layout: Dictionary, hash: String) -> void:
		_layout_inflight.erase(vid)
		if layout.is_empty() and hash.is_empty():
			return
		var use_hash := hash if not hash.is_empty() else lh
		_layout_cache[vid] = {"hash": use_hash, "layout": layout}
		## Entity may have despawned while the request was in flight.
		if not _visible_entities.has(entity_id):
			return
		var live_state: Dictionary = _visible_entities[entity_id]
		var live_ship := _live_node(live_state) as BoatBody
		if live_ship == null:
			return
		_apply_remote_ship_layout(live_ship, layout)
		live_state["layout_vid"] = vid
		live_state["layout_hash"] = use_hash
		_visible_entities[entity_id] = live_state
	)


func _apply_remote_ship_layout(ship: BoatBody, layout: Dictionary) -> void:
	if ship == null or not is_instance_valid(ship) or layout.is_empty():
		return
	ship.set_meta("remote_replica", true)
	if ship.has_method("apply_brick_layout"):
		ship.call("apply_brick_layout", layout)
	## Keep remote ships kinematic / owner-stripped after fit-out rebuild.
	ship.freeze = true
	ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_disable_physics_in_subtree(ship)
	_strip_owner_only_after_fitout(ship)
	var job := ship.get_node_or_null(DeckFitout.FITOUT_JOB)
	if job != null and job.has_signal("readiness_changed"):
		var callback := Callable(self, "_on_remote_fitout_readiness").bind(ship)
		if not job.is_connected("readiness_changed", callback):
			job.connect("readiness_changed", callback)


func _promote_remote_ship_detail(
	entity_id: String,
	ship: BoatBody,
	state: Dictionary,
) -> void:
	if ship == null or bool(state.get("full_detail_requested", false)):
		return
	if ship.get_node_or_null(DeckFitout.FITOUT_JOB) == null:
		return
	var observer := WorldReference.stream_position(get_viewport())
	if not should_promote_large_ship(observer, ship.global_position):
		return
	state["full_detail_requested"] = true
	_visible_entities[entity_id] = state
	DeckFitout.request_full_detail(ship)


static func should_promote_large_ship(observer: Vector3, ship_position: Vector3) -> bool:
	return observer.distance_to(ship_position) <= LARGE_SHIP_FULL_DETAIL_DISTANCE_M


func _on_remote_fitout_readiness(readiness: int, ship: BoatBody) -> void:
	if readiness < DeckFitout.READINESS_INTERACTIVE or ship == null or not is_instance_valid(ship):
		return
	ship.freeze = true
	ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_disable_physics_in_subtree(ship)
	_strip_owner_only_after_fitout(ship)


func _strip_owner_only_after_fitout(ship: Node) -> void:
	## DeckFitout may re-add helm interactables; strip owner-only groups again.
	var doomed: Array[Node] = []
	_collect_owner_only(ship, doomed)
	for n in doomed:
		if is_instance_valid(n):
			n.queue_free()


func _collect_owner_only(node: Node, out: Array[Node]) -> void:
	if node.is_in_group(VehicleGroups.SHIP_OWNER_ONLY):
		out.append(node)
		return
	for child in node.get_children():
		_collect_owner_only(child, out)


func _is_delivered_cargo_meta(meta: String) -> bool:
	return _parse_meta_map(meta).get("state", "") == "delivered"


func _despawn_remote_entity(id: String, scene_nodes: Dictionary) -> void:
	if not _visible_entities.has(id):
		return
	var state: Dictionary = _visible_entities[id]
	var node := _live_node(state)
	if node != null:
		_purge_entities_under(node)
		if not scene_nodes.has(id) and node.get_parent() == self:
			node.queue_free()
	_visible_entities.erase(id)


func _disable_physics_in_subtree(n: Node) -> void:
	n.set_physics_process(false)
	if n.is_in_group(VehicleGroups.SHIP_OWNER_ONLY):
		n.queue_free()
		return
	for c in n.get_children():
		_disable_physics_in_subtree(c)


## Maps payload floats back onto actual node properties based on format/type.
func _apply_state_to_node(node: Node3D, type: String, payload: Array, meta: String) -> void:
	var format := payload.size()
	
	# Extract standard spatial variables based on selected format vector size
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	
	if format == 2:
		# Vector2 (XY): X=f[0], Z=f[1], flat height Y=global height
		node.global_position.x = payload[0]
		node.global_position.z = payload[1]
	elif format >= 3:
		# Vector3/4/6 (XYZ): coordinates are f[0], f[1], f[2]
		# Apply locally if reparented under ship deck/hook, globally otherwise
		if node.get_parent() == self:
			node.global_position = Vector3(payload[0], payload[1], payload[2])
		else:
			node.position = Vector3(payload[0], payload[1], payload[2])
		
	# Format-specific rotation extraction
	if format == 4:
		if type.begins_with("ship_"):
			node.global_rotation = Vector3(node.global_rotation.x, payload[3], node.global_rotation.z)
		elif type == "player":
			# Payload yaw is the visible BodyMesh heading (see NetworkManager sender).
			node.rotation.y = lerp_angle(node.rotation.y, float(payload[3]), 1.0)
		else:
			# Vector4 (XYZ Yaw): f[3] = yaw
			node.rotation.y = lerp_angle(node.rotation.y, payload[3], 1.0)
	elif format == 6:
		if type.begins_with("ship_"):
			node.global_rotation = Vector3(payload[3], payload[4], payload[5])
		# Cranes use Format 6 payload for joint values, not body rotation — handled below.
		elif not (type == "crane" or type.begins_with("crane")):
			node.rotation.x = payload[3]
			node.rotation.y = payload[4]
			node.rotation.z = payload[5]

	# Specialized non-spatial joint replication
	if type == "player":
		if node.has_method("_sync_walk_deck_transform"):
			node.call("_sync_walk_deck_transform")
			
		var body := node.get_node_or_null("BodyMesh") as NpcBase
		if body != null and is_instance_valid(body):
			var parsed_meta := _parse_meta_map(meta)
			var encoded_appearance: String = parsed_meta.get("appearance", "")
			if not encoded_appearance.is_empty() and body.get_meta("wire_appearance", "") != encoded_appearance:
				var appearance_json := Marshalls.base64_to_raw(encoded_appearance).get_string_from_utf8()
				var remote_appearance := CharacterAppearance.from_json_string(appearance_json)
				if remote_appearance != null:
					body.apply_appearance(remote_appearance)
					body.set_meta("wire_appearance", encoded_appearance)
			var skin_hex: String = parsed_meta.get("skin", "")
			var coat_hex: String = parsed_meta.get("coat", "")
			var pants_hex: String = parsed_meta.get("pants", "")
			var hat: String = parsed_meta.get("hat", "")
			var display_name: String = parsed_meta.get("name", "")

			var next_skin := body.skin_color
			var next_coat := body.clothing_color
			var next_pants := body.trousers_color
			var colors_changed := false

			if not skin_hex.is_empty():
				var new_color := Color.from_string(skin_hex, next_skin)
				if not next_skin.is_equal_approx(new_color):
					next_skin = new_color
					colors_changed = true
			if not coat_hex.is_empty():
				var new_color := Color.from_string(coat_hex, next_coat)
				if not next_coat.is_equal_approx(new_color):
					next_coat = new_color
					colors_changed = true
			if not pants_hex.is_empty():
				var new_color := Color.from_string(pants_hex, next_pants)
				if not next_pants.is_equal_approx(new_color):
					next_pants = new_color
					colors_changed = true

			if colors_changed:
				body.set_colors(next_skin, next_coat, next_pants)

			if not display_name.is_empty():
				var label := node.get_node_or_null("PlayerNameLabel") as Label3D
				if label != null:
					label.text = display_name
					
			var current_hat_node = body.get_node_or_null("Overlay_hat") as ModelAssembler
			if hat.is_empty():
				if current_hat_node != null:
					body.remove_overlay("hat")
			else:
				var target_hat_path: String = CharacterAppearance.HAT_PATHS.get(hat, "")
				if not target_hat_path.is_empty():
					if current_hat_node == null or current_hat_node.model_data_path != target_hat_path:
						body.add_overlay("hat", target_hat_path)

	elif type.begins_with("ship_"):
		if node.has_method("_sync_walk_deck_transform"):
			node.call("_sync_walk_deck_transform")
		if node is BoatBody:
			var systems: Array[FishingSystem] = (node as BoatBody).get_fishing_systems()
			if not systems.is_empty():
				var ship_meta := _parse_meta_map(meta)
				systems[0].trawling = ship_meta.get("trawl", "0") == "1"

	elif type == "crane" or type.begins_with("crane"):
		# Cranes use Format 6 payload: [base_x, base_y, base_z, gantry_x, trolley_z, hoist_drop]
		# plus metadata string carrying crane joint states
		if format >= 6:
			# Joint values are custom mapped:
			node.set("_gantry_x_offset", payload[3])
			node.set("_trolley_z", payload[4])
			node.set("_hoist_drop", payload[5])
			
			# Extract Operator and Crane Hook Yaw from metadata
			var parsed_meta := _parse_meta_map(meta)
			var op_id: String = parsed_meta.get("op", "")
			node.set("_remotely_operated_by", op_id)
			
			var hook_yaw_str: String = parsed_meta.get("hy", "0.0")
			var hook_node := node.get("_hook") as Node3D
			if hook_node != null and is_instance_valid(hook_node):
				hook_node.rotation.y = float(hook_yaw_str)


func _parse_meta_map(meta: String) -> Dictionary:
	var out: Dictionary = {}
	var parts := meta.split(";")
	for part in parts:
		var kv := part.split("=", true, 1)
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	return out


func _drive_player_walk_cycle(state: Dictionary, node: Node3D, _delta: float) -> void:
	var body := node.get_node_or_null("BodyMesh") as NpcBase
	if body == null:
		return

	var last_pos: Vector3 = state.get("walk_sample_pos", node.global_position)
	var delta_h := node.global_position - last_pos
	delta_h.y = 0.0
	var step_m := delta_h.length()
	state["walk_sample_pos"] = node.global_position

	if step_m > 0.002:
		var dist: float = float(state.get("walk_distance_m", 0.0))
		dist += step_m
		state["walk_distance_m"] = dist
		body.set_walk_distance(dist)
	else:
		body.set_idle()


func clear_all(scene_nodes: Dictionary) -> void:
	for id in _visible_entities.keys():
		var state: Dictionary = _visible_entities[id]
		var node := _live_node(state)
		if node != null and not scene_nodes.has(id):
			node.queue_free()
	_visible_entities.clear()
