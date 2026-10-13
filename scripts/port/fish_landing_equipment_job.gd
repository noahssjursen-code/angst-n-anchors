class_name FishLandingEquipmentJob
extends QuayEquipmentJob

## Berth equipment adapter for the RSW landing pump. The pump moves CatchLot
## data; this job performs the company settlement after the physical transfer.

var _pump: FishLandingPump
var _bank: ShoreRswTankBank
var _landing_lot_ids: Array[String] = []


func bind_plant(pump: FishLandingPump, bank: ShoreRswTankBank) -> void:
	_pump = pump
	_bank = bank
	if _pump != null and not _pump.transfer_completed.is_connected(_on_transfer_completed):
		_pump.transfer_completed.connect(_on_transfer_completed)


func can_serve(ship: BoatBody, mode: String) -> bool:
	if WorldGateway.is_remote() and not WorldGateway.is_ready(): return false
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
	if WorldGateway.is_remote() and not WorldGateway.is_ready(): return "Waiting for server connection"
	if mode.strip_edges().to_lower() == MODE_LOAD:
		return "This plant only lands catch ashore"
	if ship == null:
		return "No ship at berth"
	if ship.get_catch_holds().is_empty():
		return "No catch hold fitted"
	if not can_reach_ship(ship):
		return "Vessel out of hose reach"
	if _bank == null or _bank.available_kg() <= CatchLot.MASS_EPS_KG:
		return "Shore tanks full"
	return "No fresh catch aboard"


func _begin_job(ship: BoatBody, mode: String, _commodity_id: String) -> bool:
	_landing_lot_ids.clear()
	if WorldGateway.is_remote():
		for hold in ship.get_catch_holds():
			for lot in hold.state.lots: _landing_lot_ids.append(lot.lot_id)
		var service:=WorldGateway.fishing_catches
		if service==null:return false
		if not service.landing_finished.is_connected(_on_landing_finished):service.landing_finished.connect(_on_landing_finished)
	return mode == MODE_UNLOAD and _pump != null and _pump.start_unload(ship)


func _end_job() -> void:
	if _pump != null and is_instance_valid(_pump):
		_pump.stop()


## Player-facing status stays separate from diagnostic status_lines().
func progress_label() -> String:
	if not is_instance_valid(_pump): return "Landing equipment unavailable."
	match _pump.state_label():
		FishLandingPump.STATE_CONNECTING: return "Connecting hose…"
		FishLandingPump.STATE_PUMPING: return "Landing catch · %.0f kg ashore" % _pump.landed_mass_kg()
		FishLandingPump.STATE_FLUSHING: return "Finishing landing…"
		FishLandingPump.STATE_COMPLETE:
			return "Confirming payment…" if is_job_active() else "Catch landed."
	return "Ready to land catch."


func status_lines() -> PackedStringArray:
	var lines := super.status_lines()
	if _pump != null and is_instance_valid(_pump):
		for line in _pump.get_status_lines():
			lines.append(line)
	return lines


func _on_transfer_completed(report: Dictionary) -> void:
	if WorldGateway.is_remote():
		if str(authority_context().get("owner_actor_id",""))==WorldGateway.actor_id():
			WorldGateway.fishing_catches.land(str(_served_ship.get_meta("server_vessel_id","")),operation_id(),_landing_lot_ids)
		else:
			notify_job_completed(report)
		return
	## Every interested client presents the same pump operation, but only the
	## operation owner may touch the transitional local captain ledger. The
	## economy itself moves to server projections in the next domain migration.
	var context := authority_context()
	var owns_settlement := (
		not WorldGateway.is_remote()
		or str(context.get("owner_actor_id", "")) == WorldGateway.actor_id()
	)
	if owns_settlement:
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
	notify_job_completed(report)

func _on_landing_finished(id:String,result:Dictionary)->void:
	if id!=operation_id():return
	if bool(result.get("ok",false)):
		notify_job_completed(result.get("data",{}))
	else:
		GameMenu.notify(str(result.get("message","Fish landing rejected by server")))
		stop_job()
