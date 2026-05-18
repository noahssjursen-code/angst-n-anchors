class_name CargoItem
extends Resource

## Unique ID for this cargo instance — UUID v4, generated at creation time.
@export var id: String = ""
## Commodity type key ("grain", "timber", "iron_ore"). Display-independent.
@export var commodity: String = ""
## Human-readable label shown to the player.
@export var display_name: String = ""
## UUID of the port this cargo originated from. Empty = no origin tracking.
@export var origin_port_id: String = ""
## UUID of the port that accepts this cargo for payment.
@export var destination_port_id: String = ""
## UUID of the contract this cargo fulfils. Empty = free cargo (no contract).
@export var contract_id: String = ""
@export var units: int = 1
@export var mass_kg: float = 0.0
@export var value_gold: int = 0


static func create(
	commodity_id: String,
	dest_port_id: String,
	mass: float,
	value: int,
	origin_port: String = "",
	contract: String = "",
) -> CargoItem:
	var item      := CargoItem.new()
	item.id                  = UuidUtil.generate()
	item.commodity           = commodity_id
	item.display_name        = commodity_id.replace("_", " ").capitalize()
	item.origin_port_id      = origin_port
	item.destination_port_id = dest_port_id
	item.contract_id         = contract
	item.mass_kg             = mass
	item.value_gold          = value
	return item
