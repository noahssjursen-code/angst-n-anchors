extends Node3D

## ReplicationDrawingService handles instantiation, interpolation,
## and destruction of visual remote entities in the world scene.
## Pure visual and tree management; no socket I/O or packet routing.

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

# Tracks active visual remote representations: id -> { "node": Node3D, "type": String, "target_pos": Vector3, "target_payload": Array, "interpolated_payload": Array, "meta": String, "last_seen_ms": int }
var _visible_entities: Dictionary = {}

# Keep track of active berth locks established by remote ships: "portID_berthIndex" -> ship_entity_id
var _occupied_berths: Dictionary = {}

## Returns a duplicate of currently visible remote entities dictionary (for read-only queries)
func get_visible_entities() -> Dictionary:
	return _visible_entities

# Custom scene templates mapping
const TYPE_SCENE_MAP := {
}


## Processes snapshot frames to add, update, or remove remote entity nodes.
func apply_entities(entities_list: Array, local_id: String, scene_nodes: Dictionary, local_sender_ids: Array, now_ms: int, timeout_ms: int) -> void:
	var active_snapshot_ids: Dictionary = {}
	var active_pilot_ids: Dictionary = {}
	var current_frame_berths: Dictionary = {}
	
	for ent: Dictionary in entities_list:
		var id: String = ent["id"]
		
		# 1. Skip ourselves and anything we currently have authority over (local senders)
		if id == local_id or local_sender_ids.has(id):
			continue
			
		active_snapshot_ids[id] = true
		
		# Track piloted/operated players to handle visual avatar hiding
		var meta: String = ent["meta"]
		_parse_pilot_meta(meta, active_pilot_ids)
		
		# 2. Check if we already have this entity drawn
		var state: Dictionary = _visible_entities.get(id, {})
		var node: Node3D = state.get("node", null)
		
		if node == null or not is_instance_valid(node):
			# New entity! First check if it is a pre-placed level node (like cranes)
			if scene_nodes.has(id):
				node = scene_nodes[id] as Node3D
				print("[ReplicationDrawingService] Binding pre-placed node: ", id)
			else:
				# Spawn dynamic visual node
				node = _spawn_dynamic_entity_node(id, ent["type"])
				if node != null:
					add_child(node)
					node.global_position = ent["pos"]
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
			
			# Process Berth Occupancy Meta: "berth=portID_index"
			_parse_berth_meta(id, ent["type"], meta, current_frame_berths)
			
			# Process Dynamic Parent/Relational Attachment Meta: "parent=parent_entity_id"
			_process_attachment_meta(node, id, meta)
		
	# Update remote players avatar visibility (hide those driving ships/cranes)
	_update_avatar_visibilities(active_pilot_ids)
	
	# Reconcile Berth Occupancy changes
	_reconcile_berth_locks(current_frame_berths)
			
	# 3. Clean up expired/lost entities.
	# With standstill throttling, an entity might be omitted from snapshot packets simply because
	# it is stationary. Therefore, we ONLY despawn an entity if we haven't heard from it in timeout_ms (3.0s),
	# rather than immediately when it is missing from a single packet.
	for id_variant in _visible_entities.keys():
		var id := String(id_variant)
		var state: Dictionary = _visible_entities[id]
		var age := now_ms - int(state["last_seen_ms"])
		
		if age > timeout_ms:
			var node: Node3D = state.get("node", null)
			if is_instance_valid(node):
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
	var pos_alpha := 1.0 - exp(-position_smoothness * delta)
	var pay_alpha := 1.0 - exp(-payload_smoothness * delta)
	
	for id in _visible_entities.keys():
		var state: Dictionary = _visible_entities[id]
		var node: Node3D = state.get("node", null)
		if node == null or not is_instance_valid(node):
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

		if state["type"] == "player":
			_drive_player_walk_cycle(state, node, delta)


## Parses metadata to identify pilot IDs that should be hidden.
func _parse_pilot_meta(meta: String, active_pilot_ids: Dictionary) -> void:
	if meta.begins_with("pilot="):
		var pid := meta.replace("pilot=", "")
		if not pid.is_empty():
			active_pilot_ids[pid] = true
	elif meta.begins_with("op="):
		var op_id := meta.replace("op=", "")
		if not op_id.is_empty():
			active_pilot_ids[op_id] = true


## Updates avatar visibilities based on current piloting set.
func _update_avatar_visibilities(piloting_player_ids: Dictionary) -> void:
	for id in _visible_entities.keys():
		var state: Dictionary = _visible_entities[id]
		if state["type"] == "player":
			var node: Node3D = state.get("node", null)
			if is_instance_valid(node):
				node.visible = not piloting_player_ids.has(id)


## Resolves and parses berth tags from metadata: "berth=portID_index"
func _parse_berth_meta(ship_id: String, type: String, meta: String, current_frame_berths: Dictionary) -> void:
	if type.begins_with("ship_"):
		var parsed := _parse_meta_map(meta)
		var berth_tag: String = parsed.get("berth", "")
		if not berth_tag.is_empty():
			current_frame_berths[berth_tag] = ship_id


## Handles generic parent-child reparenting loops
func _process_attachment_meta(node: Node3D, entity_id: String, meta: String) -> void:
	var parsed := _parse_meta_map(meta)
	var parent_tag: String = parsed.get("parent", "")
	
	if not parent_tag.is_empty():
		# Locate parent node
		if _visible_entities.has(parent_tag):
			var parent_state: Dictionary = _visible_entities[parent_tag]
			var parent_node: Node3D = parent_state.get("node", null)
			
			if is_instance_valid(parent_node):
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


## Updates and matches Godot physical docks to active lock registrations
func _reconcile_berth_locks(current_frame_berths: Dictionary) -> void:
	# 1. Establish new locks
	for berth_tag in current_frame_berths.keys():
		if not _occupied_berths.has(berth_tag):
			var ship_id: String = current_frame_berths[berth_tag]
			_set_berth_lock_state(berth_tag, ship_id, true)
			_occupied_berths[berth_tag] = ship_id
			
	# 2. Release lost locks
	for berth_tag in _occupied_berths.keys():
		if not current_frame_berths.has(berth_tag):
			var ship_id: String = _occupied_berths[berth_tag]
			_set_berth_lock_state(berth_tag, ship_id, false)
			_occupied_berths.erase(berth_tag)


func _set_berth_lock_state(berth_tag: String, ship_id: String, active: bool) -> void:
	var parts := berth_tag.split("_")
	if parts.size() < 2:
		return
		
	var port_id := parts[0]
	var berth_index := int(parts[1])
	
	# Find matching physical PortDock in scene
	var docks := get_tree().get_nodes_in_group("port_docks")
	for dock in docks:
		var port_dock := dock as PortDock
		if port_dock != null and port_dock.port_id == port_id:
			if active:
				var ship_node: BoatBody = null
				if _visible_entities.has(ship_id):
					ship_node = _visible_entities[ship_id].get("node") as BoatBody
				
				# Occupy the dock slot
				print("[Replication] Remote lock established on port: ", port_id, " berth: ", berth_index)
				port_dock.register_ship_at_berth(berth_index, ship_node, "remote")
			else:
				# Free up dock slot
				print("[Replication] Remote lock released on port: ", port_id, " berth: ", berth_index)
				port_dock.release_berth(berth_index)
			break


## Spawns custom visual remote scenes based on generic types.
func _spawn_dynamic_entity_node(id: String, type: String) -> Node3D:
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
		body.rotation.y = PI  # mesh authored facing +Z; body forward is -Z
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
		
	# B. Remote Cargo Pallets
	if type == "cargo":
		var pallet_res := Pallet.new()
		pallet_res.id = id
		pallet_res.commodity = "cargo"
		pallet_res.units = 1
		pallet_res.footprint = Vector2i(1, 1)
		
		var pallet_node := PalletNode.new()
		pallet_node.name = "RemoteCargo_" + id
		pallet_node.setup(pallet_res, 1.5, 1.5, Vector2i(1, 1))
		return pallet_node
		
	# C. Remote Ships
	if type.begins_with("ship_"):
		var hull_id := type.replace("ship_", "")
		var template_dir := "user://remote_ship_templates"
		DirAccess.make_dir_recursive_absolute(template_dir)
		var path := "%s/%s.json" % [template_dir, hull_id]
		
		var ship_catalog = {
			"coastal_trader": { "id": "coastal_trader", "superstructure": "bridge_coastal_trader", "hull_file": "hull_coastal_trader.json" },
			"coastal_trader_long": { "id": "coastal_trader_long", "superstructure": "bridge_coastal_trader", "hull_file": "hull_coastal_trader_long.json" },
			"cargo_ship": { "id": "cargo_ship", "superstructure": "bridge_cargo_ship", "hull_file": "hull_cargo_ship.json" },
			"short_sea_coaster": { "id": "short_sea_coaster", "superstructure": "bridge_short_sea_coaster", "hull_file": "hull_short_sea_coaster.json" },
			"short_sea_coaster_long": { "id": "short_sea_coaster_long", "superstructure": "bridge_short_sea_coaster", "hull_file": "hull_short_sea_coaster_long.json" },
			"handysize_feeder": { "id": "handysize_feeder", "superstructure": "bridge_handysize_feeder", "hull_file": "hull_handysize_feeder.json" },
			"handysize_feeder_long": { "id": "handysize_feeder_long", "superstructure": "bridge_handysize_feeder", "hull_file": "hull_handysize_feeder_long.json" },
			"deep_sea_freighter": { "id": "deep_sea_freighter", "superstructure": "bridge_deep_sea_freighter", "hull_file": "hull_deep_sea_freighter.json" },
			"deep_sea_freighter_long": { "id": "deep_sea_freighter_long", "superstructure": "bridge_deep_sea_freighter", "hull_file": "hull_deep_sea_freighter_long.json" },
			"large_freighter": { "id": "large_freighter", "superstructure": "bridge_deep_sea_freighter", "hull_file": "hull_large.json" }
		}
		
		if ship_catalog.has(hull_id):
			if not FileAccess.file_exists(path):
				var tmpl := StarterVessel.build_template(ship_catalog[hull_id])
				var f := FileAccess.open(path, FileAccess.WRITE)
				if f != null:
					f.store_string(JSON.stringify(tmpl))
					f.close()
			
			var ship := ShipBuilder.build(path) as BoatBody
			if ship != null:
				ship.name = "RemoteShip_" + id
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
				
	return null


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
		# Vector4 (XYZ Yaw): f[3] = global yaw
		node.rotation.y = lerp_angle(node.rotation.y, payload[3], 1.0)
	elif format == 6:
		# Vector6 (XYZ Rotation XYZ): f[3,4,5] = Euler Rx, Ry, Rz
		# Skip base node Euler rotation override for cranes (last 3 elements are crane joints, not rotation!)
		if not (type == "crane" or type.begins_with("crane")):
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
		var kv := part.split("=")
		if kv.size() == 2:
			out[kv[0]] = kv[1]
	return out


func _drive_player_walk_cycle(state: Dictionary, node: Node3D, _delta: float) -> void:
	var body := node.get_node_or_null("BodyMesh") as NpcBase
	if body == null:
		return

	var anim: Variant = state.get("walk_anim", null)
	if anim == null or not (anim is WalkAnimator):
		anim = WalkAnimator.new()
		(anim as WalkAnimator).attach(body)
		state["walk_anim"] = anim

	var walker := anim as WalkAnimator
	if not walker.is_ready():
		walker.attach(body)
		if not walker.is_ready():
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
		walker.update(dist)
	else:
		state["walk_distance_m"] = 0.0
		walker.reset()


func clear_all(scene_nodes: Dictionary) -> void:
	for id in _visible_entities.keys():
		var state: Dictionary = _visible_entities[id]
		var node: Node3D = state.get("node", null)
		if is_instance_valid(node) and not scene_nodes.has(id):
			node.queue_free()
	_visible_entities.clear()
