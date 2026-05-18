class_name PalletFactory
extends RefCounted

## Default cargo units per pallet slot. Can be overridden per-call.
## e.g. 4 units/pallet → a 5-unit contract gives [4, 1].
const DEFAULT_UNITS_PER_PALLET := 4


## Split a contract into one or more Pallet resources.
## units_per_pallet: how many cargo units stack onto one pallet / one grid cell.
## Returns an Array[Pallet] ordered first → last, last pallet may be partial.
static func split(contract: Contract, units_per_pallet: int = DEFAULT_UNITS_PER_PALLET) -> Array[Pallet]:
	var pallets: Array[Pallet] = []
	if contract == null or contract.quantity <= 0:
		return pallets

	var upc           := maxi(units_per_pallet, 1)
	var value_per_unit := contract.reward_per_unit()
	var remaining      := contract.quantity

	while remaining > 0:
		var batch := mini(remaining, upc)
		pallets.append(Pallet.create(
			contract,
			batch,
			upc,
			contract.mass_per_unit_kg,
			value_per_unit,
		))
		remaining -= batch

	return pallets


## How many pallets a contract will produce given units_per_pallet.
static func pallet_count(quantity: int, units_per_pallet: int = DEFAULT_UNITS_PER_PALLET) -> int:
	if quantity <= 0:
		return 0
	return int(ceil(float(quantity) / float(maxi(units_per_pallet, 1))))
