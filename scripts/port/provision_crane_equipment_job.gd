class_name ProvisionCraneEquipmentJob
extends QuayEquipmentJob

## QuayEquipmentJob adapter for ProvisionCrane general-cargo load/unload.

var _crane: ProvisionCrane
var last_failure := ""


func bind_crane(crane: ProvisionCrane) -> void:
	_crane = crane
	var op := crane.get_auto_operator() if crane != null else null
	if op != null:
		if not op.job_finished.is_connected(_on_auto_job_finished):
			op.job_finished.connect(_on_auto_job_finished)
		if not op.job_stopped.is_connected(_on_auto_job_stopped):
			op.job_stopped.connect(_on_auto_job_stopped)
		if not op.job_failed.is_connected(_on_auto_job_failed):
			op.job_failed.connect(_on_auto_job_failed)
		if not op.phase_changed.is_connected(_on_phase_changed):
			op.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(_phase: int) -> void:
	status_changed.emit()


func progress_label() -> String:
	var op := _crane.get_auto_operator() if is_instance_valid(_crane) else null
	return op.get_progress_label() if op != null else "idle"


func _on_auto_job_failed(reason: String) -> void:
	last_failure = reason
	notify_job_stopped()
	status_changed.emit()


func start_job(ship: BoatBody, mode: String, commodity_id: String = "", context: Dictionary = {}) -> bool:
	if is_job_active(): return false
	last_failure = ""
	return super.start_job(ship, mode, commodity_id, context)


func _on_auto_job_finished(_operation: Variant = null, _cycles: int = 0) -> void:
	notify_job_completed({"cycles": _cycles})


func _on_auto_job_stopped() -> void:
	notify_job_stopped()


func is_job_active() -> bool:
	if _crane != null and is_instance_valid(_crane) and _crane.is_auto_active():
		return true
	return super.is_job_active()


func can_serve(ship: BoatBody, mode: String) -> bool:
	if _crane == null or not is_instance_valid(_crane):
		return false
	if ship == null or not is_instance_valid(ship):
		return false
	if ship.get_cargo_pads().is_empty():
		return false
	if not _crane.can_reach_ship(ship):
		return false
	var m := mode.strip_edges().to_lower()
	if m == MODE_LOAD:
		return _has_yard_container(ship) and _has_free_pad_slot(ship)
	if m == MODE_UNLOAD:
		return _has_ship_container(ship) and _has_yard_slot()
	return false


func can_reach_ship(ship: BoatBody) -> bool:
	if _crane == null or not is_instance_valid(_crane):
		return false
	return _crane.can_reach_ship(ship)


func can_reach_yard(yard: Node) -> bool:
	if _crane == null or not is_instance_valid(_crane) or yard is not Node3D:
		return false
	return _crane.can_reach_point((yard as Node3D).global_position, 6.0)


func _begin_job(ship: BoatBody, mode: String, _commodity_id: String) -> bool:
	if _crane == null:
		return false
	if mode == MODE_LOAD:
		return _crane.start_auto_load(ship)
	return _crane.start_auto_unload(ship)


func _end_job() -> void:
	if _crane != null and is_instance_valid(_crane):
		_crane.stop_auto()


func status_lines() -> PackedStringArray:
	var lines := super.status_lines()
	if _crane != null and is_instance_valid(_crane):
		for line in _crane.get_status_lines():
			lines.append(line)
	return lines


func serve_hint(ship: BoatBody, mode: String) -> String:
	if not last_failure.is_empty(): return last_failure
	if _crane == null or not is_instance_valid(_crane):
		return "No crane on this tool"
	if ship == null or not is_instance_valid(ship):
		return "No ship at berth"
	if ship.get_cargo_pads().is_empty():
		return "Ship has no cargo pads"
	if not _crane.can_reach_ship(ship):
		return "Sorry mac — crane won't reach."
	var m := mode.strip_edges().to_lower()
	if m == MODE_LOAD:
		if not _has_yard_container(ship):
			return "No general cargo in the yard"
		if not _has_free_pad_slot(ship):
			return "Cargo pad is full"
		return ""
	if m == MODE_UNLOAD:
		if not _has_ship_container(ship):
			return "No general cargo on ship"
		if not _has_yard_slot():
			return "Yard is full"
		return ""
	return "Unknown job"


func _has_yard_container(ship: BoatBody) -> bool:
	var held := _crane.get_attached_container()
	if is_instance_valid(held): return _can_load_unit(held.unit, ship)
	return _find_yard_container(ship) != null


func _has_free_pad_slot(ship: BoatBody) -> bool:
	for pad in ship.get_cargo_pads():
		if pad.find_free_slot() >= 0:
			return true
	return false


func _has_yard_slot() -> bool:
	if _crane == null or not is_instance_valid(_crane) or not _crane.is_inside_tree():
		return false
	var pad := CargoSlotPadComponent.find_nearest_yard_pad(
		_crane.get_tree(),
		_crane.get_hook_global(),
		berth_id(),
		equipment_id(),
	)
	return pad != null and pad.find_free_slot() >= 0


func _has_ship_container(ship: BoatBody) -> bool:
	var held := _crane.get_attached_container()
	if is_instance_valid(held): return _can_deliver_unit(held.unit, ship)
	for pad in ship.get_cargo_pads():
		for node in pad.iter_container_nodes():
			var container := node as ContainerNode
			if container != null and container.unit != null \
					and _can_deliver_unit(container.unit, ship):
				return true
	return false


func _find_yard_container(ship: BoatBody) -> ContainerNode:
	if _crane == null or not is_instance_valid(_crane) or not _crane.is_inside_tree():
		return null
	var yard := CargoSlotPadComponent.find_nearest_yard_pad(
		_crane.get_tree(),
		_crane.get_hook_global(),
		berth_id(),
		equipment_id(),
	)
	if yard == null:
		return null
	var best: ContainerNode = null
	var best_d := INF
	for node in _crane.get_tree().get_nodes_in_group(ContainerNode.GROUP):
		if node is not ContainerNode:
			continue
		var cn := node as ContainerNode
		if CargoSlotPadComponent.is_on_ship_pad(cn):
			continue
		if not yard.contains_node(cn):
			continue
		if cn.unit == null or not _can_load_unit(cn.unit, ship):
			continue
		var d := _crane.get_hook_global().distance_to(cn.global_position)
		if d < best_d:
			best_d = d
			best = cn
	return best


func _can_load_unit(unit: ContainerUnit, ship: BoatBody) -> bool:
	if unit == null or ship == null:
		return false
	var freight := get_node_or_null("/root/FreightService")
	return freight != null and bool(freight.call(
		"can_load_unit", unit, ship.get_harbour_port_id(), ship
	))


func _can_deliver_unit(unit: ContainerUnit, ship: BoatBody) -> bool:
	if unit == null or ship == null:
		return false
	var freight := get_node_or_null("/root/FreightService")
	return freight != null and bool(freight.call(
		"can_deliver_unit", unit, ship.get_harbour_port_id(), ship
	))
