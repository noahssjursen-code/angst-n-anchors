class_name AutonomousCraneOps
extends RefCounted

## Sim-backed crane unload for autonomous NPC vessels (local only).
## Sells ship-deck pallets during CRANE stage and credits vessel pending_earnings.

static var _crane_state: Dictionary = {}  ## uid -> { leg_key, initial_count, sold_count }


static func clear_state(vessel_uid: String) -> void:
	if not vessel_uid.is_empty():
		_crane_state.erase(vessel_uid)


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
	if uid.is_empty() or body == null or dock == null or berth_index < 0:
		return record

	var apron := dock.get_berth_apron_deck(berth_index)
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

	var initial := int(state.get("initial_count", 0))
	var sold := int(state.get("sold_count", 0))
	_crane_state[uid] = state
	if initial <= 0 or sold >= initial:
		return record

	var target := int(ceil(clampf(leg_t, 0.0, 1.0) * float(initial)))
	target = clampi(target, sold, initial)
	if target <= sold:
		return record

	var out := record.duplicate(true)
	var earnings := int(out.get("pending_earnings", 0))
	while sold < target:
		var pallet := _take_next_sellable(body, apron)
		if pallet == null:
			break
		earnings += _sale_value(pallet, apron)
		sold += 1

	state["sold_count"] = sold
	_crane_state[uid] = state

	if earnings == int(out.get("pending_earnings", 0)):
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
	var session := _session()
	if session == null or session.get("data") == null:
		return
	var data: PlayerData = session.data as PlayerData
	data.upsert_owned_vessel(record)
	if session.has_method("_request_save"):
		session.call("_request_save")


static func _session() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/PlayerSession")
