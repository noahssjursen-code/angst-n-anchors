class_name PortServiceDesk
extends RefCounted

## Gameplay-facing service adapter. Screens render snapshots and send intents;
## NPCs, freight, harbour and company services retain mutation authority.
static func describe(npc: NpcInteractable) -> Dictionary:
	if not is_instance_valid(npc):
		return {}
	var result := {"title": "Port services", "line": "How can I help?", "items": [], "actions": []}
	if npc is ShipwrightNpc:
		result.title = "Shipwright"
		result.line = "Choose a vessel for the work you want to do. The quoted price includes its installed equipment."
		for entry in PrebuiltVesselCatalog.for_sale_entries():
			var item := entry.duplicate(true)
			item["id"] = str(entry.prebuilt_id)
			item["label"] = str(entry.prebuilt_name)
			item["price"] = ShipwrightPricing.commission_price(entry, HullStations.from_box(float(entry.get("loa_m",24)),float(entry.get("beam_m",8)),4,10), PlayerSession.data)
			item["detail"] = "%.0f × %.0f m\n%s kW installed\n%s" % [float(entry.get("loa_m",0)),float(entry.get("beam_m",0)),str(entry.get("shaft_power_kw",0)), ", ".join(HarbourDeploy.terminal_families_for_record(entry)).replace("bulk_ore", "bulk cargo")]
			item["reason"] = "Insufficient funds" if int(item.price) > LocalPlayerView.get_marks() else ""
			if PlayerSession.is_remote_voyage(): item.reason = "Remote purchases are not available on this server."
			result.items.append(item)
	elif npc is HarbourMasterNpc:
		result.title = "Harbourmaster"
		result.line = "Bring a vessel alongside at a suitable quay. Your other vessels remain in your fleet."
		result["port_id"] = npc.port_id
		var selected:=LocalPlayerView.get_active_vessel_record()
		if VesselEquipment.has_mount(selected):
			for id in ["fishing_rod","harpe"]:
				var equipped:bool=str(selected.get("equipped_fishing_item","fishing_rod"))==id
				result.actions.append({"id":"equip:"+id,"label":("Equipped: " if equipped else "Equip ")+str(VesselEquipment.item(id).name),"reason":"Already equipped" if equipped else ("Buy this for your ship first." if id=="harpe" and VesselEquipment.count(selected,id)==0 else "")})
		for stock:Dictionary in VesselEquipment.catalog():
			var reason:="" if not selected.is_empty() else "Select a vessel first."
			if PlayerSession.is_remote_voyage():reason="Equipment purchases are not available on this server."
			elif int(stock.price_nok)>LocalPlayerView.get_marks():reason="Insufficient funds."
			result.actions.append({"id":"equipment:"+str(stock.id),"label":"Buy %s · %s · %d aboard %s"%[stock.name,PlayerData.format_money(stock.price_nok),VesselEquipment.count(selected,stock.id),VesselSpawn.vessel_name_of(selected)],"reason":reason})

		var ship := LocalPlayerView.get_active_ship() as BoatBody
		if ship != null:
			var reason := storage_reason(npc, ship)
			result.actions.append({"id":"store", "label":"Return empty vessel to storage", "reason":reason})
			var fuel_reason := ""
			if not npc._can_offer_refuel() or ship.get_harbour_port_id() != npc.port_id or ship.get_moored_berth() == null: fuel_reason = "Secure your vessel at a fuel-equipped port."
			elif PlayerSession.is_remote_voyage(): fuel_reason = "This server does not provide a fuel purchase service."
			var litres := maxf(0.0,ship.fuel_capacity_l-ship.fuel_l)
			var price := ceili(litres*HarbourMasterNpc.FUEL_PRICE_PER_LITRE)
			if fuel_reason.is_empty():
				if litres < .1: fuel_reason = "Fuel tank is full."
				elif price > LocalPlayerView.get_marks(): fuel_reason = "Insufficient funds to fill the tank."
			result.actions.append({"id":"refuel", "label":"Fill fuel tank · %s" % PlayerData.format_money(price), "reason":fuel_reason})
		for record in LocalPlayerView.get_company_summary().get("vessels", []):
			var candidates := HarbourDeploy.free_slots_for(npc._harbour(), record, npc._max_ship_class())
			var berth_label := "No suitable free berth"
			if not candidates.is_empty(): berth_label = friendly_berth(candidates[0])
			var item := {"id": str(record.get("uid","")), "label": VesselSpawn.vessel_name_of(record), "record":record,
				"detail": "Preferred free quay: " + berth_label, "reason":"" if not candidates.is_empty() else berth_label}
			var active := LocalPlayerView.get_active_ship() as BoatBody
			if active != null:
				item.reason = "A vessel is already deployed. Return it to storage before deploying another."
			if not WorldGateway.is_ready(): item.reason = "Waiting for harbour authority."
			result.items.append(item)
	elif npc is CargoAgentNpc:
		result.title = "Cargo agent"
		result.line = "All available destinations, nearest first. Distances are direct. Payment is for the whole shipment."
		result["port_id"] = npc.port_id
		var ship: BoatBody = npc._berthed_player_ship()
		var offers := FreightService.eligible_offers_at(npc.port_id, ship) if ship != null else FreightService.offers_at(npc.port_id)
		for offer in offers:
			var item := offer.duplicate(true)
			item["label"] = LocalPlayerView.get_port_display_name(str(offer.get("destination_port_id","")))
			item["detail"] = "%s\n%.0f %s · %.1f nm\nPayment: %s" % [CommodityCatalog.commodity_display(str(offer.get("commodity_id",""))),float(offer.get("quantity",0)),str(offer.get("quantity_unit","units")),float(offer.get("distance_m",0))/1852.0,PlayerData.format_money(int(offer.get("pay_marks",0)))]
			item["reason"] = ""
			if ship == null: item.reason = "Deploy and secure your vessel at this port first."
			elif not FreightService.is_offer_compatible_with_ship(offer, ship): item.reason = "Cargo does not fit the available equipment, capacity or quay."
			elif not FreightService.can_accept(offer): item.reason = "Already booked, or your active job list is full."
			result.items.append(item)
	elif npc is CraneOperatorNpc:
		result.title = npc.operator_role.capitalize()
		var harbour: HarbourController = npc._harbour_controller()
		var equipment: QuayEquipmentJob = npc._this_equipment(harbour)
		var ship: BoatBody = harbour.moored_ship(npc.berth_id) if harbour != null else null
		result["equipment"] = equipment
		result["port_id"] = npc.harbour_port_id
		result["berth_id"] = npc.berth_id
		result.line = "No equipment is available at this station."
		if equipment != null:
			result.line = equipment.progress_label() if equipment.has_method("progress_label") else "\n".join(equipment.status_lines())
			result["active"] = equipment.is_job_active()
			for mode in [QuayEquipmentJob.MODE_LOAD, QuayEquipmentJob.MODE_UNLOAD]:
				var reason := ""
				if ship == null or ship != LocalPlayerView.get_active_ship(): reason = "Secure your own vessel at this operator's quay."
				elif equipment.is_job_active(): reason = "A transfer is already running."
				elif not equipment.can_serve(ship, mode):
					reason = equipment.serve_hint(ship,mode) if equipment.has_method("serve_hint") else "No compatible cargo or receiving space."
				result.actions.append({"id":mode,"label":mode.capitalize()+" cargo","reason":reason})
			result.actions.append({"id":"stop","label":"Stop transfer","reason":"" if equipment.is_job_active() and ship == LocalPlayerView.get_active_ship() else "No transfer on your vessel."})
	return result


static func friendly_berth(berth: QuayBerthSlot) -> String:
	if berth == null: return "assigned quay"
	return "%s · %s" % [berth.family.replace("_", " ").capitalize(), berth.station_id.get_file()]


static func storage_reason(npc: HarbourMasterNpc, ship: BoatBody) -> String:
	var passengers := PassengerOperations.storage_reason(ship)
	if not passengers.is_empty(): return passengers
	if ship == null: return "No vessel is deployed."
	if PlayerSession.is_remote_voyage(): return "Remote vessel storage is not available."
	if ship.get_harbour_port_id() != npc.port_id or ship.get_moored_berth() == null: return "Secure your vessel at this port first."
	if LocalPlayerView.is_helming(): return "Leave the helm and speak to the harbourmaster on the quay."
	for pad in ship.get_cargo_pads():
		if not pad.get_containers().is_empty(): return "Unload the vessel before returning it to storage."
	for hold in ship.get_bulk_holds():
		if not hold.state.is_empty(): return "Unload the bulk holds before returning it to storage."
	for hold in ship.get_catch_holds():
		if not hold.state.is_empty(): return "Land your catch before returning it to storage."
	var harbour := npc._harbour()
	if harbour != null and not harbour.equipment_serving(ship).is_empty(): return "Stop the transfer before returning the vessel to storage."
	if not WorldGateway.is_ready(): return "Waiting for harbour authority."
	return ""


static func request(npc: NpcInteractable, action: String, payload: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(npc) or npc._nearest_player() == null:
		return CompanyContracts.result_error("out_of_range", "Return to the operator to place this order.")
	if action.begins_with("equip:") and npc is HarbourMasterNpc:
		return PlayerSession.equip_ship_fishing_item({"vessel_id":str(LocalPlayerView.get_active_vessel_record().get("uid","")),"item_id":action.trim_prefix("equip:")})
	if action.begins_with("equipment:") and npc is HarbourMasterNpc:
		return PlayerSession.purchase_ship_equipment({"request_id":str(payload.get("request_id",PlayerData.new_uuid())),"vessel_id":str(LocalPlayerView.get_active_vessel_record().get("uid","")),"item_id":action.trim_prefix("equipment:"),"quantity":1})
	if action == "buy" and npc is ShipwrightNpc:
		return PlayerSession.purchase_yard_vessel(payload)
	if action in ["store","refuel"] and npc is HarbourMasterNpc:
		for item in describe(npc).actions:
			if item.id != action: continue
			if not str(item.reason).is_empty(): return CompanyContracts.result_error("cannot_service",str(item.reason))
			var ship := LocalPlayerView.get_active_ship() as BoatBody
			if action == "store":
				npc.request_storage(ship)
				return CompanyContracts.result_ok({"message":"Storage requested. Your vessel remains in your fleet."})
			var litres := maxf(0.0,ship.fuel_capacity_l-ship.fuel_l)
			npc._commit_refuel(litres,ceili(litres*HarbourMasterNpc.FUEL_PRICE_PER_LITRE))
			return CompanyContracts.result_ok({"message":"Fuel tank filled."})
	if action == "deploy" and npc is HarbourMasterNpc:
		if LocalPlayerView.has_active_ship():
			return CompanyContracts.result_error("already_deployed", "Store your deployed vessel first.")
		for item in describe(npc).items:
			if str(item.id) == str(payload.get("id","")):
				if not str(item.reason).is_empty(): return CompanyContracts.result_error("cannot_deploy",str(item.reason))
				npc._deploy_fleet_vessel(item.record)
				if npc._pending_berth_claims.is_empty():
					var deployed := LocalPlayerView.get_active_ship() as BoatBody
					if deployed != null and deployed.get_moored_berth() != null:
						return CompanyContracts.result_ok({"message": "%s is alongside at %s." % [VesselSpawn.vessel_name_of(item.record), friendly_berth(deployed.get_moored_berth())]})
					return CompanyContracts.result_error("deploy_failed", "The harbour could not deploy this vessel. Refresh the available berths and retry.")
				return CompanyContracts.result_ok({"message":"Berth requested; waiting for deployment confirmation."})
	if action == "book" and npc is CargoAgentNpc:
		var ship: BoatBody = npc._berthed_player_ship()
		if ship == null: return CompanyContracts.result_error("not_berthed","Secure your ship at this port first.")
		for offer in FreightService.eligible_offers_at(npc.port_id,ship):
			if str(offer.id) == str(payload.get("id","")):
				if FreightService.accept_offer_for_ship(offer,ship,npc.port_id):
					LocalPlayerView.save_player_state()
					return CompanyContracts.result_ok({"message":"Job booked. Ask the operator at your quay to load it."})
		return CompanyContracts.result_error("offer_changed","That job no longer fits or is no longer available. Refresh the list.")
	if action in ["load","unload","stop"] and npc is CraneOperatorNpc:
		var snapshot := describe(npc)
		for item in snapshot.actions:
			if item.id != action: continue
			if not str(item.reason).is_empty(): return CompanyContracts.result_error("cannot_transfer",str(item.reason))
			if action == "stop": npc._on_request_stop()
			elif action == "load": npc._on_request_load()
			else: npc._on_request_unload()
			return CompanyContracts.result_ok({"message":"Order sent. Watch the transfer status for confirmation."})
	return CompanyContracts.result_error("unavailable","That service is no longer available.")
