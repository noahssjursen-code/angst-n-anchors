class_name PalletFactory
extends RefCounted

## Fallback when a commodity has no explicit units_per_pallet.
const DEFAULT_UNITS_PER_PALLET := 4
const DEFAULT_FOOTPRINT := Vector2i(1, 1)


## Split a contract into one or more Pallet resources, using packing rules
## from ContractRegistry.COMMODITIES (units_per_pallet, footprint).
static func split(contract: Contract, units_per_pallet_override: int = 0) -> Array[Pallet]:
	var pallets: Array[Pallet] = []
	if contract == null or contract.quantity <= 0:
		return pallets

	var rules := _commodity_rules(contract.commodity)
	var upc   := units_per_pallet_override if units_per_pallet_override > 0 else int(rules.get("units_per_pallet", DEFAULT_UNITS_PER_PALLET))
	upc = maxi(upc, 1)
	var fp := Vector2i(
		int(rules.get("footprint_w", DEFAULT_FOOTPRINT.x)),
		int(rules.get("footprint_h", DEFAULT_FOOTPRINT.y)),
	)
	if fp.x <= 0 or fp.y <= 0:
		fp = DEFAULT_FOOTPRINT

	var value_per_unit := contract.reward_per_unit()
	var remaining      := contract.quantity

	while remaining > 0:
		var batch := mini(remaining, upc)
		var p := Pallet.create(
			contract,
			batch,
			upc,
			contract.mass_per_unit_kg,
			value_per_unit,
		)
		p.footprint = fp
		pallets.append(p)
		remaining -= batch

	return pallets


## How many pallets a contract will produce.
static func pallet_count(contract: Contract) -> int:
	if contract == null or contract.quantity <= 0:
		return 0
	var rules := _commodity_rules(contract.commodity)
	var upc := int(rules.get("units_per_pallet", DEFAULT_UNITS_PER_PALLET))
	return int(ceil(float(contract.quantity) / float(maxi(upc, 1))))


static func _commodity_rules(commodity_id: String) -> Dictionary:
	for entry in ContractRegistry.COMMODITIES:
		if str((entry as Dictionary)["id"]) == commodity_id:
			return entry as Dictionary
	return {}
