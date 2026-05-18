class_name PalletFactory
extends RefCounted

## Default cap when a commodity declares no max_pallet_units.
const DEFAULT_MAX_PALLET_UNITS := 4


## Split a contract into Pallet resources. Each unit = 1 grid cell. A pallet
## stretches up to max_pallet_units cells (laid out as a 1×N strip along Z),
## then the next pallet starts.
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
		# 1×N strip: width 1 cell, length = unit count.
		p.footprint = Vector2i(1, batch)
		pallets.append(p)
		remaining -= batch

	return pallets


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
