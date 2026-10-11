class_name ContainerUnit
extends Resource

## Freight identity and contents are independent of its physical container type.
## Old records without container_type retain their original break-bulk footprint.

const DEFAULT_FOOTPRINT := Vector2i(3, 7) # 20 ft on the legacy 1 m pad lattice.
const DEFAULT_SIZE_M := 2.438
const DEFAULT_HEIGHT_M := 2.591
const TYPES := {"20ft": Vector3(2.438,2.591,6.058), "40ft": Vector3(2.438,2.591,12.192), "legacy_4m": Vector3(3.8,3.8,3.8)}
const DEFAULT_COMMODITY := "provisions"

@export var id: String = ""
@export var commodity_id: String = DEFAULT_COMMODITY
@export var mass_kg: float = 3200.0
@export var value_gold: int = 0
@export var footprint: Vector2i = DEFAULT_FOOTPRINT
@export var origin_port_id: String = ""
@export var destination_port_id: String = ""
@export var freight_contract_id: String = ""
@export var consignment_id: String = ""
@export var delivery_value_marks: int = 0
@export var paint_variant: int = 0
@export var container_type: String = "20ft"

func dimensions_m() -> Vector3:
	return TYPES.get(container_type, TYPES["legacy_4m"])

func footprint_cells(cell_m: float) -> Vector2i:
	var metres := Vector2(footprint) if container_type == "legacy_4m" else Vector2(2.5, 12.5 if container_type == "40ft" else 6.5)
	return Vector2i(ceili(metres.x / cell_m), ceili(metres.y / cell_m))


static func create(
	unit_id: String = "",
	commodity: String = DEFAULT_COMMODITY,
	mass: float = -1.0,
	type: String = "20ft",
) -> ContainerUnit:
	var u := ContainerUnit.new()
	u.id = unit_id if not unit_id.is_empty() else "ctr_%s" % UuidUtil.generate()
	u.commodity_id = commodity if not commodity.is_empty() else DEFAULT_COMMODITY
	u.footprint = DEFAULT_FOOTPRINT
	u.container_type = type if TYPES.has(type) else "20ft"
	if u.container_type == "40ft": u.footprint = Vector2i(3,13)
	if u.container_type == "legacy_4m": u.footprint = Vector2i(4,4)
	if mass >= 0.0:
		u.mass_kg = mass
	else:
		u.mass_kg = float(CommodityCatalog.commodity_info(u.commodity_id).get(
			"mass_kg",
			CommodityCatalog.general_cargo_mass_kg(),
		))
	u.value_gold = int(CommodityCatalog.commodity_info(u.commodity_id).get("value", 0))
	u.paint_variant = posmod(u.id.hash(), 8)
	return u


func to_dict() -> Dictionary:
	return {
		"id": id,
		"commodity_id": commodity_id,
		"mass_kg": mass_kg,
		"value_gold": value_gold,
		"footprint": [footprint.x, footprint.y],
		"origin_port_id": origin_port_id,
		"destination_port_id": destination_port_id,
		"freight_contract_id": freight_contract_id,
		"consignment_id": consignment_id,
		"delivery_value_marks": delivery_value_marks,
		"paint_variant": paint_variant,
		"container_type": container_type,
	}


static func from_dict(data: Dictionary) -> ContainerUnit:
	var u := ContainerUnit.new()
	u.container_type = str(data.get("container_type", "legacy_4m"))
	if not TYPES.has(u.container_type): u.container_type = "legacy_4m"
	u.id = str(data.get("id", ""))
	u.commodity_id = str(data.get("commodity_id", DEFAULT_COMMODITY))
	u.mass_kg = float(data.get("mass_kg", CommodityCatalog.general_cargo_mass_kg()))
	u.value_gold = int(data.get("value_gold", 0))
	var fp: Variant = data.get("footprint", [4, 4])
	if fp is Array and (fp as Array).size() >= 2:
		var a: Array = fp
		u.footprint = Vector2i(maxi(int(a[0]), 1), maxi(int(a[1]), 1))
	else:
		u.footprint = DEFAULT_FOOTPRINT
	u.origin_port_id = str(data.get("origin_port_id", ""))
	u.destination_port_id = str(data.get("destination_port_id", ""))
	u.freight_contract_id = str(data.get("freight_contract_id", ""))
	u.consignment_id = str(data.get("consignment_id", ""))
	u.delivery_value_marks = maxi(int(data.get("delivery_value_marks", 0)), 0)
	u.paint_variant = int(data.get("paint_variant", posmod(u.id.hash(), 8)))
	return u
