class_name FreightOfferGenerator
extends RefCounted

## Pure deterministic offer generation. The ledger is cargo-agnostic; this
## availability gate only exposes handling modes that have working equipment.

const OFFER_COUNT := 3
const MIN_PAY := 180
const COMPLETED_HANDLING_MODES: Array[String] = ["general", "container", "bulk"]


static func generate(
		origin_id: String,
		ports: Array[Dictionary],
		day: int = 0,
		max_offers: int = OFFER_COUNT,
) -> Array[Dictionary]:
	var origin := _find_port(origin_id, ports)
	if origin.is_empty():
		return []
	var exports := _string_array(origin.get("commodity_exports", []))
	if exports.is_empty():
		var primary := str(origin.get("commodity_export", ""))
		if not primary.is_empty():
			exports.append(primary)
	var candidates: Array[Dictionary] = []
	for destination in ports:
		var destination_id := str(destination.get("id", ""))
		if destination_id.is_empty() or destination_id == origin_id:
			continue
		var imports := _string_array(destination.get("commodity_imports", []))
		for commodity_id in exports:
			if not imports.has(commodity_id) or not is_handling_available(commodity_id):
				continue
			candidates.append(_make_offer(origin, destination, commodity_id, day))
			if CommodityCatalog.commodity_handling_mode(commodity_id) == "bulk":
				# A separate small consignment, not a silently resized accepted job.
				var small := _make_offer(origin, destination, commodity_id, day)
				small["id"] += ":small"
				small["quantity"] = 20.0
				small["pay_marks"] = maxi(MIN_PAY, int(round(float(small.distance_m) * 0.055)) + 160)
				candidates.append(small)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", "")))
	if max_offers <= 0 or candidates.size() <= max_offers:
		return candidates
	var selected: Array[Dictionary] = []
	var start := posmod(origin_id.hash() ^ (day * 0x45d9f3b), candidates.size())
	for index in range(max_offers):
		selected.append(candidates[(start + index) % candidates.size()])
	return selected


static func _make_offer(origin: Dictionary, destination: Dictionary, commodity_id: String, day: int) -> Dictionary:
	var a := origin.get("position", Vector3.ZERO) as Vector3
	var b := destination.get("position", Vector3.ZERO) as Vector3
	var distance_m := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var stable_seed := str(origin.get("id", "")).hash() ^ str(destination.get("id", "")).hash() ^ day
	var handling_mode := CommodityCatalog.commodity_handling_mode(commodity_id)
	var quantity := _quantity_for(handling_mode, stable_seed)
	var quantity_unit := "tonnes" if handling_mode == "bulk" else "units"
	var cargo_factor := 8.0 if handling_mode == "bulk" else 95.0
	var pay := maxi(MIN_PAY, int(round(distance_m * 0.055)) + int(round(quantity * cargo_factor)))
	return {
		"id": "freight:%s:%s:%s:%d" % [origin.get("id", ""), destination.get("id", ""), commodity_id, day],
		"status": "offered",
		"origin_port_id": str(origin.get("id", "")),
		"destination_port_id": str(destination.get("id", "")),
		"commodity_id": commodity_id,
		"handling_mode": handling_mode,
		"terminal_family": CommodityCatalog.commodity_terminal_family(commodity_id),
		"quantity": quantity,
		"quantity_unit": quantity_unit,
		"loaded_quantity": 0.0,
		"delivered_quantity": 0.0,
		"distance_m": distance_m,
		"pay_marks": pay,
		"offer_day": day,
	}


static func is_handling_available(commodity_id: String) -> bool:
	return COMPLETED_HANDLING_MODES.has(CommodityCatalog.commodity_handling_mode(commodity_id))


static func _quantity_for(handling_mode: String, stable_seed: int) -> float:
	if handling_mode == "bulk":
		## Whole tonnes keep contract display and grab accounting predictable.
		return float(40 + posmod(stable_seed, 17) * 10)
	if handling_mode == "container":
		return float(4 + posmod(stable_seed, 9))
	return float(2 + posmod(stable_seed, 7))


static func _find_port(port_id: String, ports: Array[Dictionary]) -> Dictionary:
	for port in ports:
		if str(port.get("id", "")) == port_id:
			return port
	return {}


static func _string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for value in raw as Array:
		var item := str(value)
		if not item.is_empty() and not out.has(item):
			out.append(item)
	return out
