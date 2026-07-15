class_name PalletFactory
extends RefCounted

## Default cap when a commodity declares no max_pallet_units.
const DEFAULT_MAX_PALLET_UNITS := 4


## Split a quantity of one commodity into Pallet resources.
static func split_units(
		commodity_id: String,
		quantity: int,
		origin_port_id: String = "",
		destination_port_id: String = "",
		contract_id: String = "",
		value_per_unit: int = -1,
		max_units_override: int = 0,
) -> Array[Pallet]:
	var pallets: Array[Pallet] = []
	if quantity <= 0 or commodity_id.is_empty():
		return pallets

	var rules := _commodity_rules(commodity_id)
	var max_units: int = max_units_override if max_units_override > 0 \
			else int(rules.get("max_pallet_units", DEFAULT_MAX_PALLET_UNITS))
	max_units = maxi(max_units, 1)
	var mass_per_unit := float(rules.get("mass_kg", 100.0))
	var unit_value := value_per_unit if value_per_unit >= 0 else int(rules.get("value", 1))
	var remaining := quantity

	while remaining > 0:
		var batch := mini(remaining, max_units)
		var p := Pallet.create(
			commodity_id,
			origin_port_id,
			destination_port_id,
			batch,
			max_units,
			mass_per_unit,
			unit_value,
			contract_id,
		)
		p.footprint = best_footprint(batch, max_units)
		pallets.append(p)
		remaining -= batch

	return pallets


static func best_footprint(units: int, max_units: int) -> Vector2i:
	units = maxi(units, 1)
	max_units = maxi(max_units, units)

	var best := Vector2i(1, units)
	var best_score := INF
	var w_cap := int(ceil(sqrt(float(max_units))))
	for w in range(1, w_cap + 1):
		var h := int(ceil(float(units) / float(w)))
		var cells := w * h
		if cells > max_units:
			continue
		var overfill := cells - units
		var score := absi(w - h) + overfill
		if score < best_score:
			best_score = score
			best = Vector2i(w, h)
	return best


static func cells_needed(units: int, commodity_id: String) -> int:
	if units <= 0:
		return 0
	var rules := _commodity_rules(commodity_id)
	var max_units := int(rules.get("max_pallet_units", DEFAULT_MAX_PALLET_UNITS))
	return cells_needed_for(units, max_units)


static func cells_needed_for(units: int, max_units: int) -> int:
	if units <= 0 or max_units <= 0:
		return 0
	var total := 0
	var remaining := units
	while remaining > 0:
		var batch := mini(remaining, max_units)
		var fp := best_footprint(batch, max_units)
		total += fp.x * fp.y
		remaining -= batch
	return total


static func max_units_in_cells(units: int, max_units: int, free_cells: int) -> int:
	if units <= 0 or max_units <= 0 or free_cells <= 0:
		return 0
	for n in range(units, 0, -1):
		if cells_needed_for(n, max_units) <= free_cells:
			return n
	return 0


static func _commodity_rules(commodity_id: String) -> Dictionary:
	for entry in CommodityCatalog.COMMODITIES:
		if str((entry as Dictionary)["id"]) == commodity_id:
			return entry as Dictionary
	return {}
