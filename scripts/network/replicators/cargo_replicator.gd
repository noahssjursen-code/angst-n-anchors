extends Node3D

## Replicates remote cargo (pallets) in-world using high-fidelity PalletNode models.

const REMOTE_CARGO_PREFIX := "RemoteCargo_"
const REMOTE_CARGO_LABEL_NAME := "CargoLabel"
const REMOTE_CARGO_LABEL_RANGE_M := 25.0

@export var remote_cargo_position_smoothness: float = 14.0
@export var remote_cargo_yaw_smoothness: float = 14.0

var _remote_cargos: Dictionary = {}


func apply_cargos(cargos_list: Array) -> void:
	var visible_ids: Dictionary = {}
	var manager := get_parent()
	
	for c_data: Dictionary in cargos_list:
		var c_id: String = c_data.get("cargo_id", "")
		if c_id.is_empty():
			continue
			
		# Skip cargos managed/owned locally (authoritative)
		if manager != null and manager.has_method("is_local_cargo") and manager.call("is_local_cargo", c_id):
			continue
			
		visible_ids[c_id] = true
		_upsert_cargo(c_id, c_data)
		
	# Clean up missing cargos
	for known_id_variant in _remote_cargos.keys():
		var known_id := String(known_id_variant)
		if not visible_ids.has(known_id):
			var state: Dictionary = _remote_cargos[known_id]
			var node_val: Variant = state.get("node", null)
			if is_instance_valid(node_val):
				node_val.queue_free()
			_remote_cargos.erase(known_id)


func _upsert_cargo(cargo_id: String, c_data: Dictionary) -> void:
	var state: Dictionary = _remote_cargos.get(cargo_id, {})
	var node_val: Variant = state.get("node", null)
	var node: Node3D = null
	if is_instance_valid(node_val):
		node = node_val as Node3D
	
	var commodity := String(c_data.get("commodity", ""))
	var fp_x := maxi(int(c_data.get("footprint_x", 1)), 1)
	var fp_z := maxi(int(c_data.get("footprint_z", 1)), 1)
	var units := int(c_data.get("units", 0))
	
	var target_pos := Vector3(c_data.get("x", 0.0), c_data.get("y", 0.0), c_data.get("z", 0.0))
	var target_yaw := float(c_data.get("yaw", 0.0))
	
	if (
		node == null 
		or not is_instance_valid(node) 
		or int(state.get("footprint_x", -1)) != fp_x 
		or int(state.get("footprint_z", -1)) != fp_z
		or int(state.get("units", -1)) != units
	):
		if node != null and is_instance_valid(node):
			node.queue_free()
			
		node = _build_remote_cargo_visual(cargo_id, commodity, fp_x, fp_z, units)
		add_child(node)
		node.global_position = target_pos
		_set_node_global_yaw(node, target_yaw)
		
		state["node"] = node
		state["footprint_x"] = fp_x
		state["footprint_z"] = fp_z
		state["units"] = units
		state.erase("target_position")
		
	var label := node.get_node_or_null(REMOTE_CARGO_LABEL_NAME) as Label3D
	if label != null:
		label.text = "%s ×%d" % [_commodity_display_name(commodity), units] if not commodity.is_empty() else "cargo"
		
	if not state.has("target_position"):
		node.global_position = target_pos
		_set_node_global_yaw(node, target_yaw)
		
	state["target_position"] = target_pos
	state["target_yaw"] = target_yaw
	state["commodity"] = commodity
	var carried_by := String(c_data.get("carried_by", ""))
	state["carried_by"] = carried_by
	
	# Update attachment state (sitting on ship deck) if not carried by a crane
	var manager := get_parent()
	if not carried_by.is_empty():
		state["attached_ship"] = null
		state["rel_transform"] = null
	else:
		if manager != null and manager.has_method("find_any_ship_near"):
			var ship = manager.call("find_any_ship_near", target_pos, 20.0) as Node3D
			if ship != null:
				var cargo_target_transform := Transform3D(Basis.from_euler(Vector3(0.0, target_yaw, 0.0)), target_pos)
				var rel_transform = ship.global_transform.affine_inverse() * cargo_target_transform
				state["attached_ship"] = ship
				state["rel_transform"] = rel_transform
			else:
				state["attached_ship"] = null
				state["rel_transform"] = null
		else:
			state["attached_ship"] = null
			state["rel_transform"] = null
			
	_remote_cargos[cargo_id] = state


func _build_remote_cargo_visual(cargo_id: String, commodity: String, fp_x: int, fp_z: int, units: int) -> Node3D:
	var pallet_res := Pallet.new()
	pallet_res.id = cargo_id
	pallet_res.commodity = commodity
	pallet_res.units = units
	pallet_res.footprint = Vector2i(fp_x, fp_z)
	pallet_res.display_name = _commodity_display_name(commodity)
	
	var pallet_node := PalletNode.new()
	pallet_node.name = "%s%s" % [REMOTE_CARGO_PREFIX, cargo_id]
	pallet_node.setup(pallet_res, 1.5 * float(fp_x), 1.5 * float(fp_z), Vector2i(fp_x, fp_z))
	
	var label := pallet_node.get_node_or_null("PalletLabel") as Label3D
	if label != null:
		label.name = REMOTE_CARGO_LABEL_NAME
		label.visible = false
		
	return pallet_node


func _commodity_display_name(comm: String) -> String:
	match comm:
		"grain":      return "Grain"
		"timber":     return "Timber"
		"iron_ore":   return "Iron Ore"
		"coal":       return "Coal"
		"provisions": return "Provisions"
		_:            return comm.capitalize()


func interpolate(delta: float) -> void:
	if _remote_cargos.is_empty():
		return
		
	var pos_alpha := 1.0 - exp(-remote_cargo_position_smoothness * delta)
	var yaw_alpha := 1.0 - exp(-remote_cargo_yaw_smoothness * delta)
	
	var cam_pos: Variant = _resolve_active_camera_position()
	var range_sq := REMOTE_CARGO_LABEL_RANGE_M * REMOTE_CARGO_LABEL_RANGE_M
	
	for id_variant in _remote_cargos.keys():
		var cargo_id := String(id_variant)
		var state: Dictionary = _remote_cargos[cargo_id]
		var node_val: Variant = state.get("node", null)
		if node_val == null or not is_instance_valid(node_val):
			continue
		var node := node_val as Node3D
			
		var target_pos: Vector3
		var target_yaw: float
		
		var carried_by: String = state.get("carried_by", "")
		var attached_ship_val: Variant = state.get("attached_ship", null)
		var attached_ship: Node3D = null
		if is_instance_valid(attached_ship_val):
			attached_ship = attached_ship_val as Node3D
		var is_attached := false
		
		if not carried_by.is_empty():
			var hook: Node3D = null
			var manager := get_parent()
			if manager != null and manager.get("cranes") != null:
				var cranes_rep = manager.get("cranes")
				if cranes_rep.has_method("find_crane_operated_by"):
					var crane_val: Variant = cranes_rep.call("find_crane_operated_by", carried_by)
					if is_instance_valid(crane_val):
						var crane := crane_val as Node3D
						if crane.has_method("get_hook_node"):
							hook = crane.call("get_hook_node") as Node3D
						
			if hook != null and is_instance_valid(hook):
				target_pos = hook.global_position + Vector3(0.0, -1.4, 0.0)
				var hook_basis := hook.global_transform.basis
				target_yaw = atan2(hook_basis.z.x, hook_basis.z.z)
				is_attached = true
			else:
				target_pos = state.get("target_position", node.global_position)
				target_yaw = state.get("target_yaw", _node_global_yaw_rad(node))
		elif attached_ship != null and is_instance_valid(attached_ship):
			var rel_transform_val = state.get("rel_transform")
			if rel_transform_val is Transform3D:
				var cur_target_transform = attached_ship.global_transform * (rel_transform_val as Transform3D)
				target_pos = cur_target_transform.origin
				target_yaw = atan2(cur_target_transform.basis.z.x, cur_target_transform.basis.z.z)
				is_attached = true
			else:
				target_pos = state.get("target_position", node.global_position)
				target_yaw = state.get("target_yaw", _node_global_yaw_rad(node))
		else:
			target_pos = state.get("target_position", node.global_position)
			target_yaw = state.get("target_yaw", _node_global_yaw_rad(node))
			
		if is_attached:
			node.global_position = target_pos
			_set_node_global_yaw(node, target_yaw)
		else:
			node.global_position = node.global_position.lerp(target_pos, pos_alpha)
			var new_yaw := lerp_angle(_node_global_yaw_rad(node), target_yaw, yaw_alpha)
			_set_node_global_yaw(node, new_yaw)
		
		var label := node.get_node_or_null(REMOTE_CARGO_LABEL_NAME) as Label3D
		if label != null and cam_pos != null:
			var d_sq: float = (cam_pos as Vector3).distance_squared_to(node.global_position)
			label.visible = (d_sq <= range_sq)


func _resolve_active_camera_position() -> Variant:
	var vp := get_viewport()
	if vp == null:
		return null
	var cam := vp.get_camera_3d()
	if cam == null:
		return null
	return cam.global_position


func _node_global_yaw_rad(node: Node3D) -> float:
	var basis := node.global_transform.basis
	return atan2(basis.z.x, basis.z.z)


func _set_node_global_yaw(node: Node3D, yaw_rad: float) -> void:
	var pos := node.global_position
	node.global_transform.basis = Basis.from_euler(Vector3(0.0, yaw_rad, 0.0))
	node.global_position = pos


func clear_all() -> void:
	for id_variant in _remote_cargos.keys():
		var state: Dictionary = _remote_cargos[id_variant]
		var node_val: Variant = state.get("node", null)
		if is_instance_valid(node_val):
			node_val.queue_free()
	_remote_cargos.clear()
