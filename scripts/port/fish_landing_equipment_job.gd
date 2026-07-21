class_name FishLandingEquipmentJob
extends QuayEquipmentJob

## Berth equipment adapter for the RSW landing pump. The pump moves CatchLot
## data; this job performs the company settlement after the physical transfer.

var _pump: FishLandingPump
var _bank: ShoreRswTankBank


func bind_plant(pump: FishLandingPump, bank: ShoreRswTankBank) -> void:
	_pump = pump
	_bank = bank
	if _pump != null and not _pump.transfer_completed.is_connected(_on_transfer_completed):
		_pump.transfer_completed.connect(_on_transfer_completed)


func can_serve(ship: BoatBody, mode: String) -> bool:
	if mode.strip_edges().to_lower() != MODE_UNLOAD:
		return false
	if ship == null or not is_instance_valid(ship) or _pump == null or _bank == null:
		return false
	if _bank.available_kg() <= CatchLot.MASS_EPS_KG:
		return false
	if not can_reach_ship(ship):
		return false
	for hold in ship.get_catch_holds():
		if not hold.get_state().is_empty():
			return true
	return false


func can_reach_ship(ship: BoatBody) -> bool:
	if ship == null or not is_instance_valid(ship) or _pump == null or not _pump.is_inside_tree():
		return false
	return _pump.global_position.distance_to(ship.global_position) <= 90.0


func serve_hint(ship: BoatBody, mode: String) -> String:
	if mode.strip_edges().to_lower() == MODE_LOAD:
		return "This plant only lands catch ashore"
	if ship == null:
		return "No ship at berth"
	if ship.get_catch_holds().is_empty():
		return "Ship has no refrigerated catch hold"
	if not can_reach_ship(ship):
		return "Landing hose cannot reach this vessel"
	if _bank == null or _bank.available_kg() <= CatchLot.MASS_EPS_KG:
		return "Shore RSW tanks are full"
	return "No fresh catch aboard"


func _begin_job(ship: BoatBody, mode: String, _commodity_id: String) -> bool:
	return mode == MODE_UNLOAD and _pump != null and _pump.start_unload(ship)


func _end_job() -> void:
	if _pump != null and is_instance_valid(_pump):
		_pump.stop()


func status_lines() -> PackedStringArray:
	var lines := super.status_lines()
	if _pump != null and is_instance_valid(_pump):
		for line in _pump.get_status_lines():
			lines.append(line)
	return lines


func _on_transfer_completed(report: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var session := tree.root.get_node_or_null("PlayerSession") if tree != null else null
	var landing_port_id := ""
	if _served_ship != null and is_instance_valid(_served_ship):
		landing_port_id = _served_ship.get_harbour_port_id()
	var result := FishingLandingService.settle_transfer(report, session, landing_port_id)
	if not bool(result.get("ok", false)):
		push_warning("Fish landing settlement failed: %s" % str(result.get("code", "unknown")))
	## The bank is a receiving buffer. Once weighed and sold, the landed batch
	## moves into the port's processing inventory so the next vessel can land.
	if _bank != null and is_instance_valid(_bank):
		_bank.withdraw_oldest(float(report.get("mass_kg", 0.0)))
	_served_ship = null
	_job_mode = ""
	_commodity_id = ""
