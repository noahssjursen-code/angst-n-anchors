class_name Pallet
extends Resource

## A group of cargo units for one destination, occupying one grid cell on the deck or apron.
## One contract can produce multiple pallets when quantity exceeds units_per_pallet.

@export var id: String = ""
@export var contract_id: String = ""
@export var origin_port_id: String = ""
@export var destination_port_id: String = ""
@export var commodity: String = ""
@export var display_name: String = ""
## How many cargo units are stacked on this pallet.
@export var units: int = 0
## Maximum units this pallet was sized for (= units_per_pallet at creation time).
@export var max_units: int = 1
## Grid cells this pallet occupies (cols × rows). Default 1×1. Timber might be 1×4, etc.
@export var footprint: Vector2i = Vector2i(1, 1)
@export var mass_kg: float = 0.0
## Total gold value on delivery.
@export var value_gold: int = 0


static func create(
	contract: Contract,
	unit_count: int,
	max_per_pallet: int,
	mass_per_unit: float,
	value_per_unit: int,
) -> Pallet:
	var p                 := Pallet.new()
	p.id                  = UuidUtil.generate()
	p.contract_id         = contract.id
	p.origin_port_id      = contract.origin_port_id
	p.destination_port_id = contract.destination_port_id
	p.commodity           = contract.commodity
	p.display_name        = contract.display_name
	p.units               = unit_count
	p.max_units           = max_per_pallet
	p.mass_kg             = mass_per_unit * float(unit_count)
	p.value_gold          = value_per_unit * unit_count
	return p


func is_partial() -> bool:
	return units < max_units
