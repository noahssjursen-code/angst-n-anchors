class_name BulkCraneEquipmentJob
extends QuayEquipmentJob

## QuayEquipmentJob adapter for BulkCrane auto load/unload.

var _crane: BulkCrane


func bind_crane(crane: BulkCrane) -> void:
	_crane = crane
	var op := crane.get_auto_operator() if crane != null else null
	if op != null:
		if not op.job_finished.is_connected(_on_auto_job_finished):
			op.job_finished.connect(_on_auto_job_finished)
		if not op.job_stopped.is_connected(_on_auto_job_stopped):
			op.job_stopped.connect(_on_auto_job_stopped)


func _on_auto_job_finished(_operation: Variant = null, _cycles: int = 0) -> void:
	_clear_job_state()


func _on_auto_job_stopped() -> void:
	_clear_job_state()


func _clear_job_state() -> void:
	_served_ship = null
	_job_mode = ""
	_commodity_id = ""


func is_job_active() -> bool:
	if _crane != null and is_instance_valid(_crane) and _crane.is_auto_active():
		return true
	return super.is_job_active()


func can_serve(ship: BoatBody, mode: String) -> bool:
	if _crane == null or not is_instance_valid(_crane):
		return false
	if ship == null or not is_instance_valid(ship):
		return false
	if ship.get_bulk_holds().is_empty():
		return false
	if not _crane.can_reach_ship(ship):
		return false
	var m := mode.strip_edges().to_lower()
	if m == MODE_LOAD:
		return _has_loadable_hold(ship) and _nearest_mound("") != null
	if m == MODE_UNLOAD:
		return _has_unloadable_hold(ship)
	return false


func can_reach_ship(ship: BoatBody) -> bool:
	if _crane == null or not is_instance_valid(_crane):
		return false
	return _crane.can_reach_ship(ship)


func _begin_job(ship: BoatBody, mode: String, commodity_id: String) -> bool:
	if _crane == null:
		return false
	if mode == MODE_LOAD:
		var cid := commodity_id if not commodity_id.is_empty() else _default_load_commodity(ship)
		return _crane.start_auto_load(ship, cid)
	return _crane.start_auto_unload(ship, commodity_id)


func _end_job() -> void:
	if _crane != null and is_instance_valid(_crane):
		_crane.stop_auto()


func status_lines() -> PackedStringArray:
	var lines := super.status_lines()
	if _crane != null and is_instance_valid(_crane):
		for line in _crane.get_status_lines():
			lines.append(line)
	return lines


func _has_loadable_hold(ship: BoatBody) -> bool:
	for hold in ship.get_bulk_holds():
		if hold.state.available_tonnes_t() > BulkCargoLot.TONNES_EPS:
			return true
	return false


func _has_unloadable_hold(ship: BoatBody) -> bool:
	for hold in ship.get_bulk_holds():
		if not hold.state.is_empty():
			return true
	return false


func _default_load_commodity(ship: BoatBody) -> String:
	for hold in ship.get_bulk_holds():
		if not hold.state.is_empty():
			return hold.state.commodity_id
	## Match the quay stockpile (coal berth → coal), not a hard-coded iron ore.
	var mound := _nearest_mound("")
	if mound != null and not mound.commodity_id.is_empty():
		return mound.commodity_id
	return "iron_ore"


func _nearest_mound(commodity_id: String) -> OreMound:
	if _crane == null or not is_instance_valid(_crane):
		return null
	return _crane.find_nearest_ore_mound(commodity_id)


func serve_hint(ship: BoatBody, mode: String) -> String:
	if _crane == null or not is_instance_valid(_crane):
		return "No crane on this tool"
	if ship == null or not is_instance_valid(ship):
		return "No ship at berth"
	if ship.get_bulk_holds().is_empty():
		return "Ship has no bulk holds"
	if not _crane.can_reach_ship(ship):
		return "Sorry mac — crane won't reach."
	var m := mode.strip_edges().to_lower()
	if m == MODE_LOAD:
		if not _has_loadable_hold(ship):
			return "Holds are full"
		if _nearest_mound("") == null:
			return "No stockpile in reach"
		return ""
	if m == MODE_UNLOAD:
		if not _has_unloadable_hold(ship):
			return "Holds are empty"
		return ""
	return "Unknown job"
