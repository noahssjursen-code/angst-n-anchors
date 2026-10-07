extends Node

## World-authority side of First Freight. Cargo equipment reports movement
## here; per-player UI reads its projection through LocalPlayerView.

signal contracts_changed(contracts: Array)

const MAX_ACTIVE_CONTRACTS := 8
const CARGO_CONSIGNMENT := preload("res://scripts/cargo/cargo_consignment.gd")

var _active: Array[Dictionary] = []


func _ready() -> void:
	## FreightService is registered before PlayerSession, so defer the initial
	## bind until every autoload exists. Captain changes happen without a process
	## restart and must replace—not merge—the in-memory manifest.
	call_deferred("_wire_player_session")


func _wire_player_session() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return
	if not session.data_loaded.is_connected(_on_player_data_loaded):
		session.data_loaded.connect(_on_player_data_loaded)
	sync_from_player_data(session.data)


func _on_player_data_loaded(data: PlayerData) -> void:
	sync_from_player_data(data)


func sync_from_player_data(data: Variant) -> void:
	if data is PlayerData:
		restore_contracts((data as PlayerData).accepted_contracts)
	elif typeof(data) == TYPE_DICTIONARY:
		restore_contracts((data as Dictionary).get("accepted_contracts", []) as Array)
	else:
		restore_contracts([])


func offers_at(port_id: String) -> Array[Dictionary]:
	return _generated_offers(port_id, FreightOfferGenerator.OFFER_COUNT)


func eligible_offers_at(port_id: String, ship: BoatBody) -> Array[Dictionary]:
	if not is_ship_ready_at_port(ship, port_id):
		return []
	var eligible: Array[Dictionary] = []
	for offer in _generated_offers(port_id, 0):
		if is_offer_compatible_with_ship(offer, ship):
			eligible.append(offer)
		if eligible.size() >= FreightOfferGenerator.OFFER_COUNT:
			break
	return eligible


func _generated_offers(port_id: String, max_offers: int) -> Array[Dictionary]:
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null:
		return []
	var ports: Array[Dictionary] = []
	for id in catalog.get_port_ids():
		ports.append(catalog.get_port_info(id))
	return FreightOfferGenerator.generate(port_id, ports, _current_day(), max_offers)


func active_contracts() -> Array[Dictionary]:
	return _active.duplicate(true)


## Called after the authoritative world port directory is populated. This also
## upgrades saves made while a presentation-only port leaked into contracts.
func prune_unknown_ports() -> int:
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null:
		return 0
	var valid_ids: Array[String] = catalog.get_port_ids()
	var before := _active.size()
	_active = _active.filter(func(contract: Dictionary) -> bool:
		return valid_ids.has(str(contract.get("origin_port_id", ""))) \
			and valid_ids.has(str(contract.get("destination_port_id", "")))
	)
	var removed := before - _active.size()
	if removed > 0:
		_publish()
	return removed


func accept_offer(offer: Dictionary) -> bool:
	if offer.is_empty() or str(offer.get("status", "")) != "offered":
		return false
	if _active.size() >= MAX_ACTIVE_CONTRACTS or _contract_index(str(offer.get("id", ""))) >= 0:
		return false
	var accepted := offer.duplicate(true)
	accepted["status"] = "accepted"
	if not accepted.has("consignment"):
		accepted["consignment"] = CARGO_CONSIGNMENT.from_contract(accepted).to_dict()
	_active.append(accepted)
	_publish()
	call_deferred("_stage_contract", str(accepted.get("id", "")))
	return true


func accept_offer_for_ship(offer: Dictionary, ship: BoatBody, port_id: String) -> bool:
	if str(offer.get("origin_port_id", "")) != port_id:
		return false
	if not is_ship_ready_at_port(ship, port_id) or not is_offer_compatible_with_ship(offer, ship):
		return false
	var accepted := offer.duplicate(true)
	accepted["vessel_uid"] = _vessel_uid(ship)
	accepted["berth_id"] = ship.get_moored_berth_id()
	accepted["consignment"] = CARGO_CONSIGNMENT.from_contract(accepted).to_dict()
	return accept_offer(accepted)


func is_ship_ready_at_port(ship: BoatBody, port_id: String) -> bool:
	return ship != null \
		and is_instance_valid(ship) \
		and not ship.get_moored_berth_id().is_empty() \
		and ship.get_harbour_port_id() == port_id


func is_offer_compatible_with_ship(offer: Dictionary, ship: BoatBody) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var commodity_id := str(offer.get("commodity_id", ""))
	var berth := ship.get_moored_berth() as QuayBerthSlot
	if berth == null or not berth.commodities.has(commodity_id):
		return false
	var required := float(offer.get("quantity", 0.0))
	if not is_finite(required) or required <= 0.0:
		return false
	var handling := str(offer.get("handling_mode", ""))
	if handling in ["general", "container"]:
		if not is_equal_approx(required, roundf(required)):
			return false
		# Match the units issued by make_container_units, including real ISO size
		# and each pad's cell resolution. Legacy nominal slots can be too short.
		var unit := ContainerFactory.make_one("", "", commodity_id)
		var free_units := 0
		for pad in ship.get_cargo_pads():
			free_units += pad.get_free_slot_count(unit.footprint_cells(pad.cell_size_m))
		return float(free_units) - _reserved_quantity(ship, false) >= required
	if handling == "bulk":
		var available_t := 0.0
		for hold in ship.get_bulk_holds():
			if hold.can_accept_commodity(commodity_id):
				available_t += hold.get_state().available_tonnes_t()
		return available_t - _reserved_quantity(ship, true) >= required
	return false


func can_accept(offer: Dictionary) -> bool:
	return not offer.is_empty() \
		and str(offer.get("status", "")) == "offered" \
		and _active.size() < MAX_ACTIVE_CONTRACTS \
		and _contract_index(str(offer.get("id", ""))) < 0


func make_container_units(contract_id: String, count: int = -1) -> Array[ContainerUnit]:
	var index := _contract_index(contract_id)
	var out: Array[ContainerUnit] = []
	if index < 0:
		return out
	var contract := _active[index]
	if str(contract.get("handling_mode", "")) not in ["general", "container"]:
		return out
	var remaining := maxi(int(round(float(contract.get("quantity", 0.0)))) - int(contract.get("issued_quantity", 0)), 0)
	var issue_count := remaining if count < 0 else mini(remaining, maxi(count, 0))
	var first_unit_index := int(contract.get("issued_quantity", 0))
	for unit_offset in range(issue_count):
		var unit := ContainerFactory.make_one(
			str(contract.get("origin_port_id", "")),
			str(contract.get("destination_port_id", "")),
			str(contract.get("commodity_id", "provisions")),
			contract_id,
		)
		var consignment := contract.get("consignment", {}) as Dictionary
		unit.consignment_id = str(consignment.get("consignment_id", ""))
		unit.delivery_value_marks = int(round(
			float(contract.get("pay_marks", 0)) / maxf(float(contract.get("quantity", 1.0)), 1.0)
		))
		## Adjacent boxes from one movement must remain visually distinguishable.
		## Contract salt changes the starting colour; unit offset guarantees rotation.
		unit.paint_variant = posmod(
			str(contract.get("id", "")).hash() + first_unit_index + unit_offset,
			ContainerPaintMaterial.FREIGHT_PALETTE.size(),
		)
		out.append(unit)
	contract["issued_quantity"] = int(contract.get("issued_quantity", 0)) + issue_count
	_active[index] = contract
	if issue_count > 0:
		_publish()
	return out


## Immediate contract staging seam. Today accepted cargo appears in the quay
## yard; later this method can enqueue warehouse/forklift work instead.
func stage_yard(yard: Node, berth_id: String, port_id: String) -> void:
	if yard is not CargoSlotPadComponent or not is_instance_valid(yard):
		return
	var controller := HarbourRegistry.controller(port_id)
	if controller == null:
		return
	var ship := controller.moored_ship(berth_id)
	if ship == null:
		return
	var vessel_uid := _vessel_uid(ship)
	var pad := yard as CargoSlotPadComponent
	for contract in _active:
		if str(contract.get("origin_port_id", "")) != port_id:
			continue
		if str(contract.get("berth_id", "")) != berth_id:
			continue
		if str(contract.get("vessel_uid", "")) != vessel_uid:
			continue
		if str(contract.get("handling_mode", "")) not in ["general", "container"]:
			continue
		var count := mini(
			pad.get_free_slot_count(),
			maxi(
				int(round(float(contract.get("quantity", 0.0))))
					- int(contract.get("issued_quantity", 0)),
				0,
			),
		)
		for unit in make_container_units(str(contract.get("id", "")), count):
			if pad.add_container(unit) < 0:
				break


func stage_berth(port_id: String, berth_id: String) -> void:
	var controller := HarbourRegistry.controller(port_id)
	if controller == null:
		return
	var ship := controller.moored_ship(berth_id)
	if ship == null:
		return
	for yard in controller.serviceable_yards_on_berth(berth_id, ship):
		stage_yard(yard as Node, berth_id, port_id)
		## A contract movement belongs to the one crane bay serving the ship,
		## never every cargo pad along the same long quay.
		break


## Uncollected freight belongs in warehouse authority, not on an empty quay.
## Removing it rolls back issuance so the same units can be staged when the
## assigned vessel returns and plugs into this berth again.
func unstage_berth(port_id: String, berth_id: String, ship: BoatBody) -> void:
	var controller := HarbourRegistry.controller(port_id)
	if controller == null or ship == null:
		return
	var vessel_uid := _vessel_uid(ship)
	var removed_by_contract: Dictionary = {}
	for yard in controller.yards_on_berth(berth_id):
		if yard is not CargoSlotPadComponent:
			continue
		var pad := yard as CargoSlotPadComponent
		for node in pad.iter_container_nodes():
			if node == null or node.unit == null:
				continue
			var contract_id := node.unit.freight_contract_id
			var index := _contract_index(contract_id)
			if index < 0 or str(_active[index].get("vessel_uid", "")) != vessel_uid:
				continue
			pad.take_container_node(node)
			node.queue_free()
			removed_by_contract[contract_id] = int(removed_by_contract.get(contract_id, 0)) + 1
	for contract_id in removed_by_contract:
		var index := _contract_index(str(contract_id))
		if index < 0:
			continue
		var contract := _active[index]
		contract["issued_quantity"] = maxi(
			int(contract.get("issued_quantity", 0)) - int(removed_by_contract[contract_id]),
			0,
		)
		_active[index] = contract
	if not removed_by_contract.is_empty():
		_publish()


func record_loaded(contract_id: String, quantity: float = 1.0) -> bool:
	var index := _contract_index(contract_id)
	if index < 0 or quantity <= 0.0:
		return false
	var contract := _active[index]
	var required := float(contract.get("quantity", 0.0))
	contract["loaded_quantity"] = minf(required, float(contract.get("loaded_quantity", 0.0)) + quantity)
	contract["status"] = "loaded" if float(contract["loaded_quantity"]) >= required else "accepted"
	_active[index] = contract
	_publish()
	return true


func can_load_unit(unit: ContainerUnit, port_id: String, ship: BoatBody = null) -> bool:
	if unit == null:
		return false
	var index := _contract_index(unit.freight_contract_id)
	if index < 0:
		return false
	var contract := _active[index]
	if str(contract.get("status", "")) not in ["accepted", "loaded"]:
		return false
	if float(contract.get("loaded_quantity", 0.0)) >= float(contract.get("quantity", 0.0)):
		return false
	if not _unit_matches_contract_authority(unit, contract):
		return false
	if ship != null and str(contract.get("vessel_uid", "")) != _vessel_uid(ship):
		return false
	return port_id == str(contract.get("origin_port_id", "")) \
		and unit.origin_port_id == port_id \
		and unit.destination_port_id == str(contract.get("destination_port_id", ""))


func can_deliver_unit(unit: ContainerUnit, port_id: String, ship: BoatBody = null) -> bool:
	if unit == null:
		return false
	var index := _contract_index(unit.freight_contract_id)
	if index < 0:
		return false
	var contract := _active[index]
	if not _unit_matches_contract_authority(unit, contract):
		return false
	if ship != null and str(contract.get("vessel_uid", "")) != _vessel_uid(ship):
		return false
	if float(contract.get("delivered_quantity", 0.0)) >= float(contract.get("loaded_quantity", 0.0)):
		return false
	return port_id == str(contract.get("destination_port_id", "")) \
		and unit.destination_port_id == port_id \
		and unit.origin_port_id == str(contract.get("origin_port_id", ""))


func record_unit_loaded(unit: ContainerUnit, port_id: String, ship: BoatBody = null) -> bool:
	return can_load_unit(unit, port_id, ship) and record_loaded(unit.freight_contract_id, 1.0)


func record_unit_delivered(unit: ContainerUnit, port_id: String, ship: BoatBody = null) -> bool:
	return can_deliver_unit(unit, port_id, ship) \
		and record_delivered(unit.freight_contract_id, port_id, 1.0)


func _unit_matches_contract_authority(unit: ContainerUnit, contract: Dictionary) -> bool:
	if unit.freight_contract_id != str(contract.get("id", "")) \
			or unit.origin_port_id != str(contract.get("origin_port_id", "")) \
			or unit.destination_port_id != str(contract.get("destination_port_id", "")) \
			or unit.commodity_id != str(contract.get("commodity_id", "")):
		return false
	var consignment := contract.get("consignment", {}) as Dictionary
	var authority_id := str(consignment.get("consignment_id", ""))
	return not authority_id.is_empty() and unit.consignment_id == authority_id


func record_delivered(contract_id: String, port_id: String, quantity: float = 1.0) -> bool:
	var index := _contract_index(contract_id)
	if index < 0 or quantity <= 0.0:
		return false
	var contract := _active[index]
	if port_id != str(contract.get("destination_port_id", "")):
		return false
	var loaded := float(contract.get("loaded_quantity", 0.0))
	var delivered := minf(loaded, float(contract.get("delivered_quantity", 0.0)) + quantity)
	contract["delivered_quantity"] = delivered
	_active[index] = contract
	if delivered >= float(contract.get("quantity", 0.0)):
		_complete(index)
	else:
		_publish()
	return true


func restore_contracts(saved: Array) -> void:
	_clear_registered_yards()
	_active.clear()
	for raw in saved:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var contract := (raw as Dictionary).duplicate(true)
		if str(contract.get("status", "")) in ["accepted", "loaded"]:
			if not contract.has("consignment"):
				contract["consignment"] = CARGO_CONSIGNMENT.from_contract(contract).to_dict()
			contract["loaded_quantity"] = 0.0
			contract["delivered_quantity"] = 0.0
			contract["issued_quantity"] = 0
			contract["status"] = "accepted"
			_active.append(contract)
	_publish()
	call_deferred("_stage_all_contracts")


func _publish() -> void:
	contracts_changed.emit(active_contracts())
	var state := get_node_or_null("/root/GameState")
	if state != null:
		state.contract.active = active_contracts()


func _complete(index: int) -> void:
	var contract := _active[index]
	_active.remove_at(index)
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		session.earn_marks(
			int(contract.get("pay_marks", 0)),
			"freight_delivery",
			"Delivered cargo to %s" % str(contract.get("destination_name", contract.get("destination_port_id", "port"))),
			str(contract.get("id", "")),
		)
		session.data.contracts_completed += 1
	_publish()


func _contract_index(contract_id: String) -> int:
	for index in range(_active.size()):
		if str(_active[index].get("id", "")) == contract_id:
			return index
	return -1


func _stage_contract(contract_id: String) -> void:
	var index := _contract_index(contract_id)
	if index < 0:
		return
	var contract := _active[index]
	var controller := HarbourRegistry.controller(str(contract.get("origin_port_id", "")))
	if controller == null:
		return
	stage_berth(controller.port_id(), str(contract.get("berth_id", "")))


func _stage_all_contracts() -> void:
	for contract in _active:
		_stage_contract(str(contract.get("id", "")))


func _clear_registered_yards() -> void:
	for port_id in HarbourRegistry.all_port_ids():
		var controller := HarbourRegistry.controller(port_id)
		if controller == null:
			continue
		for berth in controller.berths():
			for yard in controller.yards_on_berth((berth as QuayBerthSlot).berth_id):
				if yard is CargoSlotPadComponent:
					(yard as CargoSlotPadComponent).clear_all()


func _reserved_quantity(ship: BoatBody, bulk: bool) -> float:
	var uid := _vessel_uid(ship)
	var reserved := 0.0
	for contract in _active:
		if str(contract.get("vessel_uid", "")) != uid:
			continue
		var is_bulk := str(contract.get("handling_mode", "")) == "bulk"
		if is_bulk != bulk:
			continue
		reserved += maxf(
			float(contract.get("quantity", 0.0)) - float(contract.get("loaded_quantity", 0.0)),
			0.0,
		)
	return reserved


func _vessel_uid(ship: BoatBody) -> String:
	var uid := str(ship.get_meta("vessel_uid", "")).strip_edges()
	return uid if not uid.is_empty() else str(ship.get_instance_id())


func _current_day() -> int:
	var clock := get_node_or_null("/root/WorldClock")
	if clock != null and clock.has_method("get_game_hours_elapsed"):
		return int(floor(float(clock.call("get_game_hours_elapsed")) / 24.0))
	return 0
