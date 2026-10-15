class_name HomeFishSale
extends RefCounted

## Small Fiskemottak: one sale, with prices and custody decided by authority.
static var busy := false

static func available(port: Dictionary) -> bool:
	if port.get("services", {}).has("fish_reception"):
		return bool(port.services.fish_reception)
	# Existing starter saves already have the reception, but no service flags.
	if int(port.get("starter_version", 0)) < 1: return false
	for part in port.get("placements", []):
		if part.get("asset_id", "") == "sign_fish": return true
	return false

static func snapshot(port_id: String) -> Dictionary:
	var data: PlayerData = PlayerSession.data
	if data == null or data.home_port_id != port_id or not available(data.home_port_document): return {}
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	var states: Array[CatchHoldState] = []
	if ship != null:
		for hold in ship.get_catch_holds(): states.append(hold.state)
	var quote := FishingLandingService.quote(states)
	var reason := ""
	if busy: reason = "Selling catch…"
	elif not WorldGateway.is_ready(): reason = "Waiting for harbour connection."
	elif ship == null or ship.get_harbour_port_id() != port_id or ship.get_moored_berth() == null:
		reason = "Moor your boat at your home quay."
	else:
		var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
		if mooring == null or not mooring.bow_line_tied or not mooring.stern_line_tied:
			reason = "Secure both mooring lines."
		elif data.find_owned_vessel(str(ship.get_meta("vessel_uid", ""))).is_empty(): reason = "Sell catch from your own vessel."
		elif int(quote.lot_count) == 0: reason = "Your catch crate is empty."
		elif int(quote.value_marks) <= 0: reason = "No saleable catch aboard."
		elif WorldGateway.is_remote():
			for hold in ship.get_catch_holds():
				if WorldGateway.fishing_catches.pending_mass(HarbourController.ship_id_of(ship), hold.hold_id) > 0:
					reason = "Storing your last catch…"
	quote["reason"] = reason
	quote["label"] = "Sell catch · %s" % PlayerData.format_money(int(quote.value_marks))
	quote["line"] = "Fiskemottak · %.1f kg aboard" % float(quote.mass_kg)
	return quote

static func sell(port_id: String) -> Dictionary:
	var offer := snapshot(port_id)
	if offer.is_empty(): return {"ok":false,"message":"No Fiskemottak at this port."}
	if not str(offer.reason).is_empty(): return {"ok":false,"message":offer.reason}
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	var ids: Array[String] = []
	for hold in ship.get_catch_holds():
		for lot in hold.state.lots: ids.append(lot.lot_id)
	ids.sort()
	var vessel_id := HarbourController.ship_id_of(ship)
	# Stable across timeouts/reconnects; a lost reply cannot create a second sale.
	var sale_id := "home-fish-" + JSON.stringify([vessel_id, port_id, ids]).sha256_text()
	busy = true
	var result := await HomePortService.request("fishing.catch.sell", {
		"vessel_id":vessel_id,"port_id":port_id,"operation_id":sale_id,"lot_ids":ids})
	busy = false
	if result.get("ok", false):
		var receipt: Dictionary = result.data
		if WorldGateway.is_remote():
			WorldGateway.query_projections("fishing_hold")
			WorldGateway.refresh_captain_balance()
		result.data["message"] = "Sold %.1f kg · +%s" % [float(receipt.mass_kg), PlayerData.format_money(int(receipt.value_nok))]
	return result

static func execute_local(body: Dictionary, actor: String, berth: Dictionary) -> Dictionary:
	var data: PlayerData = PlayerSession.data
	var sale_id := str(body.get("operation_id", ""))
	var vessel_id := str(body.get("vessel_id", ""))
	var port_id := str(body.get("port_id", ""))
	var receipts: Dictionary = data.local_fishing.get("sales", {})
	if receipts.has(sale_id):
		var saved: Dictionary = receipts[sale_id]
		if saved.owner_actor_id == actor and saved.vessel_id == vessel_id and saved.port_id == port_id:
			return {"ok":true,"data":saved.duplicate(true)}
		return {"ok":false,"message":"This sale belongs to another vessel."}
	if sale_id.is_empty() or data.home_port_id != port_id or data.home_port_document.get("owner_actor_id", "") != actor or not available(data.home_port_document):
		return {"ok":false,"message":"Your home Fiskemottak is unavailable."}
	if berth.get("owner_actor_id", "") != actor or berth.get("status", "") != "assigned" or berth.get("port_id", "") != port_id or not berth.get("bow_line", false) or not berth.get("stern_line", false):
		return {"ok":false,"message":"Moor both lines at your Fiskemottak before selling."}
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if ship == null or HarbourController.ship_id_of(ship) != vessel_id or data.find_owned_vessel(str(ship.get_meta("vessel_uid", ""))).is_empty():
		return {"ok":false,"message":"Only your own vessel's catch can be sold."}
	var harbour := HarbourRegistry.controller(port_id)
	if harbour != null and not harbour.equipment_serving(ship).is_empty():
		return {"ok":false,"message":"Finish the current cargo transfer before selling."}
	var wanted := {}
	for id in body.get("lot_ids", []):
		if str(id).is_empty() or wanted.has(id): return {"ok":false,"message":"Invalid catch selection."}
		wanted[id] = true
	if wanted.is_empty(): return {"ok":false,"message":"Your catch crate is empty."}
	var receipt := {"operation_id":sale_id,"vessel_id":vessel_id,"port_id":port_id,
		"owner_actor_id":actor,"mass_kg":0.0,"value_nok":0,"lots":[]}
	var next := PlayerData.from_dict(data.to_dict())
	var value := 0.0
	var remaining := {}
	for hold in ship.get_catch_holds():
		var state: Dictionary = hold.state.to_dict()
		state.lots = []
		for lot in hold.state.lots:
			if not wanted.has(lot.lot_id): state.lots.append(lot.to_dict()); continue
			wanted.erase(lot.lot_id)
			receipt.mass_kg += lot.mass_kg
			receipt.lots.append(lot.to_dict())
			value += FishingLandingService.lot_value(lot, lot.mass_kg)
		remaining[hold.hold_id] = state
		LocalCatchStore.put(next, ship, hold.hold_id, state)
	if not wanted.is_empty() or receipt.mass_kg <= 0 or roundi(value) <= 0:
		return {"ok":false,"message":"Catch is missing or already sold."}
	receipt.value_nok = roundi(value)
	var company := CompanyService.new()
	company.bind(next)
	var paid := company.post_transaction({"request_id":sale_id,"amount_marks":receipt.value_nok,
		"category":"fish_landing","description":"Fish sold at Fiskemottak","related_entity_id":port_id,"count_as_earned":true})
	if not paid.get("ok", false): return paid
	var sales: Dictionary = next.local_fishing.get("sales", {})
	sales[sale_id] = receipt.duplicate(true)
	next.local_fishing["sales"] = sales
	# Money, emptied holds and receipt live in one verified, atomic save.
	if PlayerSession._persistent_io_enabled and not PlayerSaveStore.save_player(next):
		return {"ok":false,"message":"Could not save the sale. Your fish and money are unchanged."}
	PlayerSession.data = next
	PlayerSession.company_service.bind(next)
	for hold in ship.get_catch_holds(): hold.apply_state(remaining[hold.hold_id])
	PlayerSession.marks_changed.emit(next.marks)
	PlayerSession.company_changed.emit(PlayerSession.company_service.company_summary())
	return {"ok":true,"data":receipt}
