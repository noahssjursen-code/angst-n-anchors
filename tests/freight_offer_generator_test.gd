extends SceneTree

const CARGO_CONSIGNMENT := preload("res://scripts/cargo/cargo_consignment.gd")
const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("freight_offer_generator_test")
	var ports: Array[Dictionary] = [
		_port("origin", Vector3.ZERO, ["containers"], []),
		_port("near", Vector3(1000.0, 0.0, 0.0), [], ["containers"]),
		_port("far", Vector3(5000.0, 0.0, 0.0), [], ["containers"]),
		_port("bulk", Vector3(2000.0, 0.0, 0.0), [], ["grain"]),
		_port("liquid", Vector3(3000.0, 0.0, 0.0), [], ["diesel"]),
	]
	ports[0]["commodity_exports"] = ["containers", "grain", "diesel"]
	var first := FreightOfferGenerator.generate("origin", ports, 4)
	var second := FreightOfferGenerator.generate("origin", ports, 4)
	t.check("same port and day must generate identical freight", first == second)
	t.check("container and bulk destinations become offers", first.size() == 3)
	t.check("unfinished liquid handling stays filtered", _offer_to(first, "liquid").is_empty())
	var near_offer := _offer_to(first, "near")
	var far_offer := _offer_to(first, "far")
	t.check("near and far offers both exist", not near_offer.is_empty() and not far_offer.is_empty())
	t.check("near offer carries at least four units", float(near_offer.get("quantity", 0.0)) >= 4.0)
	t.check("near offer carries at most twelve units", float(near_offer.get("quantity", 0.0)) <= 12.0)
	t.check(
		"far offer is further out than near offer",
		float(far_offer.get("distance_m", 0.0)) > float(near_offer.get("distance_m", 0.0)),
	)
	t.check("far offer pays at least the floor", int(far_offer.get("pay_marks", 0)) >= FreightOfferGenerator.MIN_PAY)
	var bulk_offer := _offer_to(first, "bulk")
	t.check("bulk destination uses bulk handling", str(bulk_offer.get("handling_mode", "")) == "bulk")
	t.check("bulk offer is measured in tonnes", str(bulk_offer.get("quantity_unit", "")) == "tonnes")
	t.check("unknown origin port yields no offers", FreightOfferGenerator.generate("missing", ports).is_empty())
	var routed := ContainerFactory.make_one("origin", "near", "containers", "freight:test")
	var restored := ContainerUnit.from_dict(routed.to_dict())
	t.check("round-tripped unit keeps its destination", restored.destination_port_id == "near")
	t.check("round-tripped unit keeps its contract id", restored.freight_contract_id == "freight:test")
	var freight := root.get_node("FreightService")
	freight.restore_contracts([])
	t.check("near offer is accepted", freight.accept_offer(near_offer))
	t.check("manifest accepts multiple movements", freight.accept_offer(far_offer))
	t.check("same offer cannot be accepted twice", not freight.accept_offer(near_offer))
	if not t.check("manifest holds both movements", freight.active_contracts().size() == 2):
		t.finish(self)
		return
	var units: Array = freight.make_container_units(str(near_offer.get("id", "")), 2)
	if not t.check("two container units are made", units.size() == 2):
		t.finish(self)
		return
	t.check("made unit is routed to near", units[0].destination_port_id == "near")
	t.check("made unit carries the offer's contract id", units[0].freight_contract_id == str(near_offer.get("id", "")))
	t.check("made unit has a consignment id", not units[0].consignment_id.is_empty())
	t.check("made unit is worth marks on delivery", units[0].delivery_value_marks > 0)
	t.check(
		"sibling units are distinguishable",
		units[0].paint_variant != units[1].paint_variant or units[0].id != units[1].id,
	)
	var consignment = CARGO_CONSIGNMENT.from_dict(
		(freight.active_contracts()[0] as Dictionary).get("consignment", {}) as Dictionary
	)
	t.check("consignment records the origin port", consignment.origin_port_id == "origin")
	t.check("consignment records the destination port", consignment.destination_port_id == "near")
	t.check(
		"consignment pays the offer's marks",
		consignment.delivery_value_marks == int(near_offer.get("pay_marks", 0)),
	)
	freight.sync_from_player_data({"accepted_contracts": freight.active_contracts()})
	t.check("syncing the same manifest keeps both contracts", freight.active_contracts().size() == 2)
	freight.sync_from_player_data({"accepted_contracts": []})
	t.check("new captain must not inherit prior manifest", freight.active_contracts().is_empty())
	var payout_offer := near_offer.duplicate(true)
	payout_offer["id"] = "freight:payout_test"
	payout_offer["quantity"] = 2.0
	payout_offer["pay_marks"] = 777
	t.check("payout offer is accepted", freight.accept_offer(payout_offer))
	var payout_units: Array[ContainerUnit] = freight.make_container_units("freight:payout_test")
	if not t.check("payout offer makes two units", payout_units.size() == 2):
		t.finish(self)
		return
	var session := root.get_node("PlayerSession")
	var marks_before: int = int(session.get_marks())
	var completed_before: int = int(session.data.contracts_completed)
	t.check("first payout unit loads at origin", freight.record_unit_loaded(payout_units[0], "origin"))
	t.check("second payout unit loads at origin", freight.record_unit_loaded(payout_units[1], "origin"))
	t.check("wrong port rejects delivery", not freight.record_unit_delivered(payout_units[0], "far"))
	t.check("first payout unit delivers at near", freight.record_unit_delivered(payout_units[0], "near"))
	t.check("second payout unit delivers at near", freight.record_unit_delivered(payout_units[1], "near"))
	t.check("completed delivery must pay captain", session.get_marks() == marks_before + 777)
	t.check("completed delivery counts a contract", session.data.contracts_completed == completed_before + 1)
	t.check("paid contract leaves active manifest", freight.active_contracts().is_empty())
	var return_offer := payout_offer.duplicate(true)
	return_offer["id"] = "freight:return_test"
	return_offer["origin_port_id"] = "near"
	return_offer["destination_port_id"] = "origin"
	return_offer["status"] = "offered"
	t.check("return offer is accepted", freight.accept_offer(return_offer))
	var return_units: Array[ContainerUnit] = freight.make_container_units("freight:return_test")
	t.check(
		"completed inbound cargo must never be selected for a return voyage",
		not freight.can_load_unit(payout_units[0], "near"),
	)
	t.check(
		"new outbound cargo remains selectable beside old inbound cargo",
		freight.can_load_unit(return_units[0], "near"),
	)
	freight.restore_contracts([])
	t.finish(self)


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
