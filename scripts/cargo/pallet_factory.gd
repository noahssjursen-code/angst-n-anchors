class_name PalletFactory
extends RefCounted

## Default cap when a commodity declares no max_pallet_units.
const DEFAULT_MAX_PALLET_UNITS := 4


## Split a contract into Pallet resources. Each unit = 1 grid cell. A pallet
## stretches up to max_pallet_units cells. Footprint is the most-square
## rectangle that fits the batch (4 → 2×2, 6 → 2×3, 5 → 2×3 with one empty).
##   max_units_override > 0 overrides the commodity's max_pallet_units.
static func split(contract: Contract, max_units_override: int = 0) -> Array[Pallet]:
	var pallets: Array[Pallet] = []
	if contract == null or contract.quantity <= 0:
		return pallets

	var rules := _commodity_rules(contract.commodity)
	var max_units: int = max_units_override if max_units_override > 0 else int(rules.get("max_pallet_units", DEFAULT_MAX_PALLET_UNITS))
	max_units = maxi(max_units, 1)

	var value_per_unit := contract.reward_per_unit()
	var remaining      := contract.quantity

	while remaining > 0:
		var batch := mini(remaining, max_units)
		var p := Pallet.create(
			contract,
			batch,
			max_units,
			contract.mass_per_unit_kg,
			value_per_unit,
		)
		p.footprint = best_footprint(batch, max_units)
		pallets.append(p)
		remaining -= batch

	return pallets


## Returns the most-square (w, h) rectangle that holds at least `units` cells
## without exceeding `max_units` cells. Ties broken by lower overfill.
## Examples (max_units 6):
##   1 → 1×1   2 → 1×2   3 → 2×2 (one empty)   4 → 2×2
##   5 → 2×3 (one empty)   6 → 2×3
## Examples (max_units 4):
##   3 → 2×2 (one empty)   4 → 2×2
static func best_footprint(units: int, max_units: int) -> Vector2i:
	units = maxi(units, 1)
	max_units = maxi(max_units, units)

	var best := Vector2i(1, units)
	var best_score := INF
	# Width sweep is bounded by ceil(sqrt(max_units)) since beyond that any
	# valid (w, h) is just the mirror of (h, w).
	var w_cap := int(ceil(sqrt(float(max_units))))
	for w in range(1, w_cap + 1):
		var h := int(ceil(float(units) / float(w)))
		var cells := w * h
		if cells > max_units:
			continue
		var overfill := cells - units
		# Heavy weight on squareness, plus a small penalty for empty cells.
		var score := absi(w - h) + overfill
		if score < best_score:
			best_score = score
			best = Vector2i(w, h)
	return best


## How many pallets a contract will produce.
static func pallet_count(contract: Contract) -> int:
	if contract == null or contract.quantity <= 0:
		return 0
	var rules := _commodity_rules(contract.commodity)
	var max_units := int(rules.get("max_pallet_units", DEFAULT_MAX_PALLET_UNITS))
	return int(ceil(float(contract.quantity) / float(maxi(max_units, 1))))


static func _commodity_rules(commodity_id: String) -> Dictionary:
	for entry in ContractRegistry.COMMODITIES:
		if str((entry as Dictionary)["id"]) == commodity_id:
			return entry as Dictionary
	return {}
