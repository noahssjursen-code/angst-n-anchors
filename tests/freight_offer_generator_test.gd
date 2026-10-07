extends SceneTree

const CARGO_CONSIGNMENT := preload("res://scripts/cargo/cargo_consignment.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Shipment identity must survive partial grabs, overflow and save round-trips.
	var hold := BulkHoldState.new()
	hold.capacity_tonnes_t = 40.0
	var overflow := hold.accept_lot(BulkCargoLot.create("iron_ore", 55.0, "shipment-a"))
	assert(is_equal_approx(overflow.tonnes_t, 15.0) and overflow.consignment_id == "shipment-a")
	var scoop := hold.withdraw_tonnes(12.5)
	assert(scoop.consignment_id == "shipment-a" and is_equal_approx(scoop.tonnes_t, 12.5))
	assert(is_equal_approx(hold.accept_lot(BulkCargoLot.create("iron_ore", 5.0, "shipment-b")).tonnes_t, 5.0), "different bookings cannot lose identity by mixing")
	hold = BulkHoldState.from_dict(hold.to_dict())
	assert(hold.consignment_id == "shipment-a" and is_equal_approx(hold.filled_tonnes_t, 27.5))
	assert(hold.withdraw_tonnes(100).consignment_id == "shipment-a")
	assert(hold.is_empty() and hold.consignment_id.is_empty())
	var ports: Array[Dictionary] = [
		_port("origin", Vector3.ZERO, ["containers"], []),
		_port("near", Vector3(1000.0, 0.0, 0.0), [], ["containers"]),
		_port("far", Vector3(5000.0, 0.0, 0.0), [], ["containers"]),
		_port("bulk", Vector3(2000.0, 0.0, 0.0), [], ["grain"]),
		_port("liquid", Vector3(3000.0, 0.0, 0.0), [], ["diesel"]),
	]
	ports[0]["commodity_exports"] = ["containers", "grain", "diesel"]
	var first := FreightOfferGenerator.generate("origin", ports, 4, 0)
	var second := FreightOfferGenerator.generate("origin", ports, 4, 0)
	assert(first == second, "same port and day must generate identical freight")
	assert(first.size() == 4, "container routes plus standard and small bulk loads become offers")
	assert(FreightOfferGenerator.generate("origin", ports, 4).size() == 3, "board remains bounded")
	assert(_offer_to(first, "liquid").is_empty(), "unfinished liquid handling stays filtered")
	var near_offer := _offer_to(first, "near")
	var far_offer := _offer_to(first, "far")
	assert(not near_offer.is_empty() and not far_offer.is_empty())
	assert(float(near_offer.get("quantity", 0.0)) >= 4.0)
	assert(float(near_offer.get("quantity", 0.0)) <= 12.0)
	assert(float(far_offer.get("distance_m", 0.0)) > float(near_offer.get("distance_m", 0.0)))
	assert(int(far_offer.get("pay_marks", 0)) >= FreightOfferGenerator.MIN_PAY)
	var bulk_offer := _offer_to(first, "bulk")
	assert(str(bulk_offer.get("handling_mode", "")) == "bulk")
	assert(str(bulk_offer.get("quantity_unit", "")) == "tonnes")
	assert(FreightOfferGenerator.generate("missing", ports).is_empty())
	var routed := ContainerFactory.make_one("origin", "near", "containers", "freight:test")
	var restored := ContainerUnit.from_dict(routed.to_dict())
	assert(restored.destination_port_id == "near")
	assert(restored.freight_contract_id == "freight:test")
	var freight := root.get_node("FreightService")
	freight.restore_contracts([])
	assert(freight.accept_offer(near_offer))
	assert(freight.accept_offer(far_offer), "manifest accepts multiple movements")
	assert(not freight.accept_offer(near_offer), "same offer cannot be accepted twice")
	assert(freight.active_contracts().size() == 2)
	var units: Array = freight.make_container_units(str(near_offer.get("id", "")), 2)
	assert(units.size() == 2)
	assert(units[0].destination_port_id == "near")
	assert(units[0].freight_contract_id == str(near_offer.get("id", "")))
	assert(not units[0].consignment_id.is_empty())
	assert(units[0].delivery_value_marks > 0)
	assert(units[0].paint_variant != units[1].paint_variant or units[0].id != units[1].id)
	var consignment = CARGO_CONSIGNMENT.from_dict(
		(freight.active_contracts()[0] as Dictionary).get("consignment", {}) as Dictionary
	)
	assert(consignment.origin_port_id == "origin")
	assert(consignment.destination_port_id == "near")
	assert(consignment.delivery_value_marks == int(near_offer.get("pay_marks", 0)))
	freight.sync_from_player_data({"accepted_contracts": freight.active_contracts()})
	assert(freight.active_contracts().size() == 2)
	freight.sync_from_player_data({"accepted_contracts": []})
	assert(freight.active_contracts().is_empty(), "new captain must not inherit prior manifest")
	var payout_offer := near_offer.duplicate(true)
	payout_offer["id"] = "freight:payout_test"
	payout_offer["quantity"] = 2.0
	payout_offer["pay_marks"] = 777
	assert(freight.accept_offer(payout_offer))
	var payout_units: Array[ContainerUnit] = freight.make_container_units("freight:payout_test")
	assert(payout_units.size() == 2)
	var session := root.get_node("PlayerSession")
	var marks_before: int = int(session.get_marks())
	var completed_before: int = int(session.data.contracts_completed)
	assert(freight.record_unit_loaded(payout_units[0], "origin"))
	assert(freight.record_unit_loaded(payout_units[1], "origin"))
	assert(not freight.record_unit_delivered(payout_units[0], "far"), "wrong port rejects delivery")
	assert(freight.record_unit_delivered(payout_units[0], "near"))
	assert(freight.record_unit_delivered(payout_units[1], "near"))
	assert(session.get_marks() == marks_before + 777, "completed delivery must pay captain")
	assert(session.data.contracts_completed == completed_before + 1)
	assert(freight.active_contracts().is_empty(), "paid contract leaves active manifest")
	var return_offer := payout_offer.duplicate(true)
	return_offer["id"] = "freight:return_test"
	return_offer["origin_port_id"] = "near"
	return_offer["destination_port_id"] = "origin"
	return_offer["status"] = "offered"
	assert(freight.accept_offer(return_offer))
	var return_units: Array[ContainerUnit] = freight.make_container_units("freight:return_test")
	assert(not freight.can_load_unit(payout_units[0], "near"),
		"completed inbound cargo must never be selected for a return voyage")
	assert(freight.can_load_unit(return_units[0], "near"),
		"new outbound cargo remains selectable beside old inbound cargo")
	freight.restore_contracts([])
	print("freight_offer_generator_test: PASS")
	quit()


func _port(id: String, position: Vector3, exports: Array, imports: Array) -> Dictionary:
	return {
		"id": id,
		"display_name": id.capitalize(),
		"position": position,
		"commodity_export": exports[0] if not exports.is_empty() else "",
		"commodity_exports": exports,
		"commodity_imports": imports,
	}


func _offer_to(offers: Array[Dictionary], destination_id: String) -> Dictionary:
	for offer in offers:
		if str(offer.get("destination_port_id", "")) == destination_id:
			return offer
	return {}
