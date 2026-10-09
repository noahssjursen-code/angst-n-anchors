extends "res://tests/world_gateway_lifecycle_test.gd"

class StagingReach extends QuayEquipmentJob:
	func can_reach_yard(yard: Node) -> bool:
		return not yard.get_meta("outside_reach", false)
	func can_reach_ship(_ship: BoatBody) -> bool:
		return true

func _test_harbourmaster_deployment() -> void:
	var harbour := HarbourController.new()
	harbour.setup("routing")
	var slots: Array[QuayBerthSlot] = []
	for family in ["liquid", "bulk_grain", "container", "bulk_ore", "fishing", "general"]:
		var slot := QuayBerthSlot.new()
		slot.setup("routing/" + family, family, family, [], 100.0 if family == "general" else 60.0, 20.0)
		harbour.register_berth(slot)
		slots.append(slot)
	for pair in [["general_cargo", "general"], ["fishing", "fishing"], ["bulk", "bulk_ore"]]:
		var record := CompanyService.build_starter_vessel_record(pair[0])
		check(not record.is_empty(), "Starter exists: " + pair[0])
		var candidates := HarbourDeploy.compatible_slots_for(harbour, record)
		check(not candidates.is_empty() and candidates[0].family == pair[1], "Installed equipment selects " + pair[1])
		for candidate in candidates:
			check(candidate.family != "liquid", "Non-tankers never route to LNG")
		var stale := record.duplicate(true)
		stale["registration_id"] = "fishing_vessel"
		check(HarbourDeploy.terminal_families_for_record(stale) == HarbourDeploy.terminal_families_for_record(record), "Stale legal registration cannot override imported fit-out")
	var cargo := CompanyService.build_starter_vessel_record("general_cargo")
	var candidate_ids: Array = []
	for slot in HarbourDeploy.compatible_slots_for(harbour, cargo): candidate_ids.append(slot.berth_id)
	WorldGateway.send_command(WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body("routing-busy", "routing", ["routing/general"]), "routing-occupy")
	WorldGateway.send_command(WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body("routing-cargo", "routing", candidate_ids), "routing-fallback")
	check(results["routing-fallback"].get("data", {}).get("assignment", {}).get("berth_id") == "routing/container", "Occupied general quay falls back to a compatible container quay")
	WorldGateway.send_command(WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body("routing-full", "routing", candidate_ids), "routing-full")
	check(not results["routing-full"].get("ok", true), "All suitable quays occupied cannot redirect cargo to LNG or grain")
	for vessel_id in ["routing-busy", "routing-cargo"]:
		WorldGateway.send_command(WorldContracts.COMMAND_VESSEL_BERTH_RELEASE, {"vessel_id":vessel_id}, "release-" + vessel_id)
	var before := JSON.stringify(cargo)
	check(HarbourDeploy.pick_slot(harbour, cargo).family == "general", "Local selection agrees with authority order")
	check(HarbourDeploy.pick_slot(harbour, cargo, ShipClass.Type.DEEP_SEA_FREIGHTER, "routing/liquid") == null, "Explicit incompatible berth is rejected")
	check(before == JSON.stringify(cargo), "Routing does not rewrite captain data")
	var custom := cargo.duplicate(true)
	custom.brick_layout.parts = []
	check(HarbourDeploy.terminal_families_for_record(custom) == PackedStringArray(["general"]), "Removing equipment updates service routing")
	check(HarbourDeploy.terminal_families_for_record({"registration_id":"fishing_vessel"}) == PackedStringArray(["fishing"]), "Legacy vessel retains its existing policy")
	harbour.unregister_all()
	for slot in slots: slot.free()
	harbour.free()
	await super._test_harbourmaster_deployment()
	print("HARBOUR SERVICE ROUTING checked: stock/custom fit-outs, legacy compatibility, rejected LNG, real NPC deployment")

func _test_deployed_door(ship: ImportedDraftVessel) -> void:
	await super._test_deployed_door(ship)
	if ship.get_cargo_pads().is_empty(): return
	var berth := ship.get_moored_berth() as QuayBerthSlot
	berth.commodities = PackedStringArray(["provisions"])
	var offer := {"id":"capacity-test", "status":"offered", "origin_port_id":ship.get_harbour_port_id(),
		"destination_port_id":"destination", "commodity_id":"provisions", "handling_mode":"general", "quantity":2.0}
	check(FreightService.is_offer_compatible_with_ship(offer, ship), "Two real ISO beds accept two issued units")
	await _test_staging(ship, offer)
	offer.quantity = 3.0
	check(not FreightService.is_offer_compatible_with_ship(offer, ship), "Cannot overbook ship capacity")
	for quantity in [0.0, -1.0, 1.5, INF, NAN]:
		offer.quantity = quantity
		check(not FreightService.is_offer_compatible_with_ship(offer, ship), "Invalid quantity rejected")
	offer.quantity = 1.0
	offer.origin_port_id = "wrong-port"
	check(not FreightService.accept_offer_for_ship(offer, ship, ship.get_harbour_port_id()), "Stale offer from another port cannot be booked")
	for pad in ship.get_cargo_pads():
		pad.deck_length_m = 4.0
		pad.container_footprint = Vector2i(5, 8)
	check(not FreightService.is_offer_compatible_with_ship(offer, ship), "Nominal short slots cannot carry issued 20-foot containers")
	print("FREIGHT BOOKING checked: ISO footprint, capacity, invalid quantities and origin")

func _test_staging(ship: BoatBody, offer: Dictionary) -> void:
	# Exercise warehouse issuance with finite yards; physical crane motion is
	# covered by fleet_world_journey. No fake cargo is credited as delivered.
	var harbour := HarbourRegistry.controller(ship.get_harbour_port_id())
	var berth_id := ship.get_moored_berth_id()
	var equipment := StagingReach.new()
	equipment.setup("staging-test", "general", berth_id)
	harbour.add_child(equipment)
	harbour.register_equipment(equipment, berth_id)
	var yards: Array[CargoSlotPadComponent] = []
	for index in 3:
		var yard := CargoSlotPadComponent.new()
		yard.deck_width_m = 3
		yard.deck_length_m = 7
		yard.show_pad_visual = false
		yard.affects_boat_cargo_mass = false
		yard.is_quay_yard_pad = true
		yard.set_meta("equipment_id", equipment.equipment_id())
		yard.set_meta("outside_reach", index == 2)
		harbour.add_child(yard)
		harbour.register_yard(yard, berth_id)
		yards.append(yard)
	check(FreightService.accept_offer_for_ship(offer, ship, ship.get_harbour_port_id()), "Book two units for finite staging yards")
	await get_tree().process_frame
	check(yards[0].get_containers().size() == 1 and yards[1].get_containers().size() == 1 and yards[2].get_containers().is_empty(), "Freight spans reachable crane yards without filling unreachable yards")
	FreightService.stage_berth(ship.get_harbour_port_id(), berth_id)
	check(int(FreightService.active_contracts()[0].issued_quantity) == 2, "Repeated staging cannot duplicate issued cargo")
	for yard in yards: yard.clear_all()
	FreightService.restore_contracts([])
	yards[1].set_meta("outside_reach", true)
	check(FreightService.accept_offer_for_ship(offer, ship, ship.get_harbour_port_id()), "Book a consignment larger than one staging yard")
	await get_tree().process_frame
	check(int(FreightService.active_contracts()[0].issued_quantity) == 1, "Unstaged cargo remains in warehouse authority")
	var node := yards[0].iter_container_nodes()[0] as ContainerNode
	yards[0].take_container_node(node)
	ship.get_cargo_pads()[0].place_container_node(node)
	check(FreightService.record_unit_loaded(node.unit, ship.get_harbour_port_id(), ship), "Confirm the first physical unit aboard")
	await get_tree().process_frame
	var contract := FreightService.active_contracts()[0]
	check(int(contract.issued_quantity) == 2 and int(contract.loaded_quantity) == 1 and yards[0].get_containers().size() == 1, "Landing aboard replenishes finite staging space without changing loaded count")
	check(yards[0].get_containers()[0].id != node.unit.id, "Replenishment issues the next distinct container")
	for pad in ship.get_cargo_pads(): pad.clear_all()
	FreightService.restore_contracts([])
	for yard in yards:
		yard.clear_all()
	harbour.unregister_equipment(equipment.equipment_id())
	equipment.queue_free()
