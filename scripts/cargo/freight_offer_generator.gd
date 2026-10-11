class_name FreightOfferGenerator
extends RefCounted

## Pure deterministic offer generation. The ledger is cargo-agnostic; this
## availability gate only exposes handling modes that have working equipment.

const OFFER_COUNT := 6
const MIN_PAY := 600
## Gameplay freight tariff: dispatch fee plus handling and distance per unit.
## These are transport earnings, not the sale value of the goods aboard.
const CONTAINER_HANDLING_PAY := 350.0
const CONTAINER_PAY_PER_KM := 120.0
const BULK_HANDLING_PAY_PER_TONNE := 12.0
const BULK_PAY_PER_TONNE_KM := 4.0
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
				small["pay_marks"] = payment_for(float(small.distance_m), "bulk", 20.0)
				candidates.append(small)
	return select_offers(candidates, max_offers)


## Nearest compatible destinations first. Alternate cargo to the same port may
## fill spare slots, but cannot crowd neighbouring ports off the board.
static func select_offers(candidates: Array[Dictionary], max_offers: int = OFFER_COUNT) -> Array[Dictionary]:
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.distance_m) != float(b.distance_m):
			return float(a.distance_m) < float(b.distance_m)
		return str(a.id) < str(b.id))
	if max_offers <= 0:
		return sorted
	var selected: Array[Dictionary] = []
	var destinations: Dictionary = {}
	for offer in sorted:
		if destinations.has(offer.destination_port_id): continue
		selected.append(offer)
		destinations[offer.destination_port_id] = true
		if selected.size() >= max_offers: return selected
	for offer in sorted:
		if selected.has(offer): continue
		selected.append(offer)
		if selected.size() >= max_offers: break
	return selected


static func _make_offer(origin: Dictionary, destination: Dictionary, commodity_id: String, day: int) -> Dictionary:
	var a := origin.get("position", Vector3.ZERO) as Vector3
	var b := destination.get("position", Vector3.ZERO) as Vector3
	var distance_m := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var stable_seed := str(origin.get("id", "")).hash() ^ str(destination.get("id", "")).hash() ^ day
	var handling_mode := CommodityCatalog.commodity_handling_mode(commodity_id)
	var quantity := _quantity_for(handling_mode, stable_seed)
	var quantity_unit := "tonnes" if handling_mode == "bulk" else "units"
	var pay := payment_for(distance_m, handling_mode, quantity)
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


static func payment_for(distance_m: float, handling_mode: String, quantity: float) -> int:
	if quantity <= 0.0 or not is_finite(quantity) or not is_finite(distance_m): return 0
	var handling := BULK_HANDLING_PAY_PER_TONNE if handling_mode == "bulk" else CONTAINER_HANDLING_PAY
	var rate := BULK_PAY_PER_TONNE_KM if handling_mode == "bulk" else CONTAINER_PAY_PER_KM
	return MIN_PAY + roundi(quantity * (handling + maxf(0.0, distance_m) / 1000.0 * rate))


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
