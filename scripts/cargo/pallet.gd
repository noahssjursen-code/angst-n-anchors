class_name Pallet
extends Resource

## A group of cargo units for one destination, occupying one grid cell on the deck or apron.

@export var id: String = ""
@export var contract_id: String = ""
@export var origin_port_id: String = ""
@export var destination_port_id: String = ""
@export var vessel_call_id: String = ""
@export var commodity: String = ""
@export var display_name: String = ""
@export var units: int = 0
@export var max_units: int = 1
@export var footprint: Vector2i = Vector2i(1, 1)
@export var mass_kg: float = 0.0
@export var value_gold: int = 0


static func create(
		commodity_id: String,
		origin_port_id: String,
		destination_port_id: String,
		unit_count: int,
		max_per_pallet: int,
		mass_per_unit: float,
		value_per_unit: int,
		contract_id: String = "",
		display_name: String = "",
) -> Pallet:
	var p := Pallet.new()
	p.id = UuidUtil.generate()
	p.contract_id = contract_id
	p.origin_port_id = origin_port_id
	p.destination_port_id = destination_port_id
	p.commodity = commodity_id
	p.display_name = display_name if not display_name.is_empty() \
			else CommodityCatalog.commodity_display(commodity_id)
	p.units = unit_count
	p.max_units = max_per_pallet
	p.mass_kg = mass_per_unit * float(unit_count)
	p.value_gold = value_per_unit * unit_count
	return p


func is_partial() -> bool:
	return units < max_units


func to_dict() -> Dictionary:
	return {
		"id": id,
		"contract_id": contract_id,
		"origin_port_id": origin_port_id,
		"destination_port_id": destination_port_id,
		"vessel_call_id": vessel_call_id,
		"commodity": commodity,
		"display_name": display_name,
		"units": units,
		"max_units": max_units,
		"footprint": [footprint.x, footprint.y],
		"mass_kg": mass_kg,
		"value_gold": value_gold,
	}


static func from_dict(data: Dictionary) -> Pallet:
	var pallet := Pallet.new()
	pallet.id = str(data.get("id", ""))
	pallet.contract_id = str(data.get("contract_id", ""))
	pallet.origin_port_id = str(data.get("origin_port_id", ""))
	pallet.destination_port_id = str(data.get("destination_port_id", ""))
	pallet.vessel_call_id = str(data.get("vessel_call_id", ""))
	pallet.commodity = str(data.get("commodity", ""))
	pallet.display_name = str(data.get("display_name", ""))
	pallet.units = maxi(int(data.get("units", 0)), 0)
	pallet.max_units = maxi(int(data.get("max_units", 1)), 1)
	var footprint_data: Variant = data.get("footprint", [1, 1])
	if footprint_data is Array and footprint_data.size() >= 2:
		pallet.footprint = Vector2i(
			maxi(int(footprint_data[0]), 1),
			maxi(int(footprint_data[1]), 1),
		)
	pallet.mass_kg = maxf(float(data.get("mass_kg", 0.0)), 0.0)
	pallet.value_gold = maxi(int(data.get("value_gold", 0)), 0)
	return pallet
