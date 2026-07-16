class_name ContainerUnit
extends Resource

## One cubed general-cargo unit (break-bulk). Same footprint grid as shipping boxes.
## Commodity id is usually provisions — not ISO shipping containers.

const DEFAULT_FOOTPRINT := Vector2i(4, 4)
const DEFAULT_SIZE_M := 4.0
const DEFAULT_HEIGHT_M := 4.0
const DEFAULT_COMMODITY := "provisions"

@export var id: String = ""
@export var commodity_id: String = DEFAULT_COMMODITY
@export var mass_kg: float = 3200.0
@export var value_gold: int = 0
@export var footprint: Vector2i = DEFAULT_FOOTPRINT
@export var origin_port_id: String = ""
@export var destination_port_id: String = ""


static func create(
	unit_id: String = "",
	commodity: String = DEFAULT_COMMODITY,
	mass: float = -1.0,
) -> ContainerUnit:
	var u := ContainerUnit.new()
	u.id = unit_id if not unit_id.is_empty() else "ctr_%d" % Time.get_ticks_msec()
	u.commodity_id = commodity if not commodity.is_empty() else DEFAULT_COMMODITY
	u.footprint = DEFAULT_FOOTPRINT
	if mass >= 0.0:
		u.mass_kg = mass
	else:
		u.mass_kg = float(CommodityCatalog.commodity_info(u.commodity_id).get(
			"mass_kg",
			CommodityCatalog.general_cargo_mass_kg(),
		))
	u.value_gold = int(CommodityCatalog.commodity_info(u.commodity_id).get("value", 0))
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
	}


static func from_dict(data: Dictionary) -> ContainerUnit:
	var u := ContainerUnit.new()
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
	return u
