class_name AutonomousCraneOps
extends RefCounted

## Sim-backed crane unload for autonomous NPC vessels.
## Sells ship-deck pallets during CRANE stage and credits vessel pending_earnings.

static var _crane_state: Dictionary = {}  ## uid -> { leg_key, initial_count, sold_count }


static func clear_state(vessel_uid: String) -> void:
	if not vessel_uid.is_empty():
		_crane_state.erase(vessel_uid)


static func resolve_apron(dock: PortDock, berth_index: int) -> CargoDeckComponent:
	if dock == null:
		return null
	if berth_index >= 0:
		var preferred := dock.get_berth_apron_deck(berth_index)
		if preferred != null:
			return preferred
	for i in range(dock.berth_count()):
		var apron := dock.get_berth_apron_deck(i)
		if apron != null:
			return apron
	return null


static func process_crane_tick(
	record: Dictionary,
	body: BoatBody,
	dock: PortDock,
	berth_index: int,
	cycle_index: int,
	leg_index: int,
	leg_t: float,
) -> Dictionary:
	var uid := str(record.get("uid", ""))
	if uid.is_empty() or body == null or dock == null:
		return record

	var apron := resolve_apron(dock, berth_index)
	if apron == null:
		return record

	var leg_key := "%d:%d" % [cycle_index, leg_index]
	var state: Dictionary = _crane_state.get(uid, {}) as Dictionary
	if str(state.get("leg_key", "")) != leg_key:
		state = {
			"leg_key": leg_key,
			"initial_count": _count_sellable(body, apron),
			"sold_count": 0,
		}

	var sold := int(state.get("sold_count", 0))
	var sellable_now := _count_sellable(body, apron)
	var initial := int(state.get("initial_count", 0))

	# Ship may spawn mid-leg (proximity load) after initial_count was captured as 0.
	if sellable_now > initial:
		state["initial_count"] = sold + sellable_now
		initial = int(state["initial_count"])
	elif initial <= 0 and sellable_now > 0:
		state["initial_count"] = sellable_now
		initial = sellable_now

	_crane_state[uid] = state
	if initial <= 0 or sold >= initial:
		return record

	var target := int(ceil(clampf(leg_t, 0.0, 1.0) * float(initial)))
	target = clampi(target, sold, initial)
	if target <= sold:
		return record

	var out := record.duplicate(true)
	var earnings_before := int(out.get("pending_earnings", 0))
	var earnings := earnings_before
	var sold_before := sold

	while sold < target:
		var pallet := _take_next_sellable(body, apron)
		if pallet == null:
			break
		earnings += _sale_value(pallet, apron)
		sold += 1

	state["sold_count"] = sold
	_crane_state[uid] = state

	if sold <= sold_before:
		return record

	out["pending_earnings"] = earnings
	_persist_record(out)
	return out


static func _count_sellable(body: BoatBody, apron: CargoDeckComponent) -> int:
	var count := 0
	for pallet in _ship_pallets(body):
		if apron.accepts_delivery(pallet):
			count += 1
	return count


static func _take_next_sellable(body: BoatBody, apron: CargoDeckComponent) -> Pallet:
	for pallet in _ship_pallets(body):
		if not apron.accepts_delivery(pallet):
			continue
		for deck_node in body.find_children("*", "CargoDeckComponent", true, false):
			var deck := deck_node as CargoDeckComponent
			if deck == null or not deck.port_id.is_empty():
				continue
			if deck.remove_pallet_by_resource(pallet) != null:
				return pallet
	return null


static func _ship_pallets(body: BoatBody) -> Array[Pallet]:
	var out: Array[Pallet] = []
	var seen := {}
	for deck_node in body.find_children("*", "CargoDeckComponent", true, false):
		var deck := deck_node as CargoDeckComponent
		if deck == null or not deck.port_id.is_empty():
			continue
		for pallet in deck.get_all_pallets():
			if pallet != null and not seen.has(pallet.id):
				seen[pallet.id] = true
				out.append(pallet)
	return out


static func _sale_value(pallet: Pallet, apron: CargoDeckComponent) -> int:
	if pallet == null or not apron.accepts_delivery(pallet):
		return 0
	return maxi(pallet.value_gold, 0)


static func _persist_record(record: Dictionary) -> void:
	var uid := str(record.get("uid", ""))
	var mgr := _manager()
	if mgr != null and mgr.has_method("apply_record_update"):
		mgr.call("apply_record_update", uid, record)


static func _manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/AutonomousVesselManager")
