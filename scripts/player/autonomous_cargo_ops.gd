class_name AutonomousCargoOps
extends RefCounted

## Loads synthetic outbound cargo onto cargo-haul NPCs at home port DOCK.
## Does not draw from player export stock — deterministic per vessel + cycle.

static var _load_state: Dictionary = {}  ## uid -> leg_key


static func clear_state(vessel_uid: String) -> void:
	if not vessel_uid.is_empty():
		_load_state.erase(vessel_uid)


static func process_dock_load(
	record: Dictionary,
	body: BoatBody,
	port_id: String,
	cycle_index: int,
	leg_index: int,
) -> void:
	var uid := str(record.get("uid", ""))
	if uid.is_empty() or body == null or port_id.is_empty():
		return

	var av := AutonomousVesselRecord.from_owned_vessel(record)
	if av.role_is_fishing() or not av.has_visit_port():
		return
	if port_id != av.home_port_id:
		return

	var leg_key := "%d:%d" % [cycle_index, leg_index]
	if str(_load_state.get(uid, "")) == leg_key:
		return

	if _outbound_cargo_count(body, av.visit_port_id) > 0:
		_load_state[uid] = leg_key
		return

	var loaded := _load_outbound_cargo(record, body, av, cycle_index)
	if loaded > 0:
		_load_state[uid] = leg_key


static func _outbound_cargo_count(body: BoatBody, visit_port_id: String) -> int:
	var count := 0
	for deck_node in body.find_children("*", "CargoDeckComponent", true, false):
		var deck := deck_node as CargoDeckComponent
		if deck == null or not deck.port_id.is_empty():
			continue
		for pallet in deck.get_all_pallets():
			if pallet != null and pallet.destination_port_id == visit_port_id:
				count += 1
	return count


static func _load_outbound_cargo(
	record: Dictionary,
	body: BoatBody,
	av: AutonomousVesselRecord,
	cycle_index: int,
) -> int:
	var registry := _registry()
	if registry == null:
		return 0

	av.hydrate_ports(registry)
	var home_info := registry.call("get_port_info", av.home_port_id) as Dictionary
	if home_info.is_empty():
		return 0

	var commodity_id := str(home_info.get("commodity_export", "provisions"))
	if commodity_id.is_empty():
		commodity_id = "provisions"

	var rules := _commodity_rules(commodity_id)
	if rules.is_empty():
		return 0

	var max_units := int(rules.get("max_pallet_units", PalletFactory.DEFAULT_MAX_PALLET_UNITS))
	max_units = maxi(max_units, 1)

	var free_cells := _free_ship_cells(body)
	if free_cells <= 0:
		return 0

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d:%s" % [str(record.get("uid", "")), cycle_index, av.visit_port_id])

	var origin_size := int(home_info.get("size", 1))
	var units := ContractPricing.quantity_for_port(origin_size, rng)
	units = PalletFactory.max_units_in_cells(units, max_units, free_cells)
	if units <= 0:
		return 0

	var distance_nm := ContractPricing.route_distance_nm(av.home_pos, av.visit_pos)
	var value_per := ContractPricing.reward_per_unit(
		int(rules.get("value", 10)),
		distance_nm,
		false,
	)
	var mass_per := float(rules.get("mass_kg", 200.0))
	var display := str(rules.get("display", commodity_id.capitalize()))

	var remaining := units
	var placed := 0
	while remaining > 0:
		var batch := mini(remaining, max_units)
		var pallet := Pallet.new()
		pallet.id = UuidUtil.generate()
		pallet.contract_id = ""
		pallet.origin_port_id = av.home_port_id
		pallet.destination_port_id = av.visit_port_id
		pallet.commodity = commodity_id
		pallet.display_name = display
		pallet.units = batch
		pallet.max_units = max_units
		pallet.mass_kg = mass_per * float(batch)
		pallet.value_gold = value_per * batch
		pallet.footprint = PalletFactory.best_footprint(batch, max_units)

		if not _place_on_ship(body, pallet):
			break
		placed += 1
		remaining -= batch

	return placed


static func _place_on_ship(body: BoatBody, pallet: Pallet) -> bool:
	for deck_node in body.find_children("*", "CargoDeckComponent", true, false):
		var deck := deck_node as CargoDeckComponent
		if deck == null or not deck.port_id.is_empty():
			continue
		if deck.add_pallet(pallet) >= 0:
			return true
	return false


static func _free_ship_cells(body: BoatBody) -> int:
	var total := 0
	for deck_node in body.find_children("*", "CargoDeckComponent", true, false):
		var deck := deck_node as CargoDeckComponent
		if deck == null or not deck.port_id.is_empty():
			continue
		total += deck.get_available()
	return total


static func _commodity_rules(commodity_id: String) -> Dictionary:
	for entry in ContractRegistry.COMMODITIES:
		if str((entry as Dictionary).get("id", "")) == commodity_id:
			return entry as Dictionary
	return {}


static func _registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("/root/ContractRegistry")
