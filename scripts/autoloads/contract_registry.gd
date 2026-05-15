extends Node

## Autoload — register in Project > Autoloads as "ContractRegistry".
## Single source of truth for ports and trade contracts.
## No knowledge of the physical world; operates purely on data.

signal contract_accepted(contract: Contract)
signal unit_delivered(contract: Contract, reward_gold: int)
signal contract_completed(contract: Contract)

const COMMODITIES := [
	{ "id": "grain",      "display": "Grain",      "mass_kg": 180.0, "value": 8  },
	{ "id": "timber",     "display": "Timber",     "mass_kg": 320.0, "value": 12 },
	{ "id": "iron_ore",   "display": "Iron Ore",   "mass_kg": 480.0, "value": 18 },
	{ "id": "coal",       "display": "Coal",       "mass_kg": 280.0, "value": 10 },
	{ "id": "provisions", "display": "Provisions", "mass_kg": 150.0, "value": 14 },
]

## port_id -> { id, display_name, position, warehouse }
var _ports: Dictionary = {}
## contract_id -> Contract
var _contracts: Dictionary = {}


# ── Port registration ─────────────────────────────────────────────────────────

func register_port(
	port_id: String,
	display_name: String,
	world_pos: Vector3,
	warehouse: Warehouse,
) -> void:
	var already_known := _ports.has(port_id)
	_ports[port_id] = {
		"id":           port_id,
		"display_name": display_name,
		"position":     world_pos,
		"warehouse":    warehouse,
	}
	if not already_known:
		_generate_contracts_for(port_id)


func get_port_display_name(port_id: String) -> String:
	var info := _ports.get(port_id, {}) as Dictionary
	return str(info.get("display_name", "Unknown Port"))


# ── Contract queries ──────────────────────────────────────────────────────────

## Returns contracts originating from port_id, sorted by reward descending.
func get_contracts_from_port(port_id: String) -> Array[Contract]:
	var out: Array[Contract] = []
	for c in _contracts.values():
		var contract := c as Contract
		if contract != null and contract.origin_port_id == port_id:
			out.append(contract)
	out.sort_custom(func(a: Contract, b: Contract) -> bool:
		return a.reward_gold > b.reward_gold
	)
	return out


func get_destination_name(contract: Contract) -> String:
	return get_port_display_name(contract.destination_port_id)


# ── Accept ────────────────────────────────────────────────────────────────────

func accept_contract(contract_id: String) -> bool:
	var contract := _contracts.get(contract_id) as Contract
	if contract == null or contract.state != Contract.State.AVAILABLE:
		return false

	contract.state = Contract.State.ACCEPTED

	var origin_info := _ports.get(contract.origin_port_id, {}) as Dictionary
	var warehouse   := origin_info.get("warehouse") as Warehouse
	if warehouse != null and is_instance_valid(warehouse):
		var items: Array[CargoItem] = []
		for i in range(contract.quantity):
			items.append(CargoItem.create(
				contract.commodity,
				contract.destination_port_id,
				contract.mass_per_unit_kg,
				contract.reward_per_unit(),
				contract.origin_port_id,
				contract.id,
			))
		warehouse.set_inventory(items)

	contract_accepted.emit(contract)
	return true


# ── Delivery ──────────────────────────────────────────────────────────────────

## Called when a player delivers one cargo unit. Returns gold earned (0 on failure).
func deliver_cargo(item: CargoItem) -> int:
	if item == null:
		return 0

	var contract := _contracts.get(item.contract_id, null) as Contract
	if contract == null or contract.state == Contract.State.COMPLETED:
		return item.value_gold

	contract.delivered_count += 1
	var reward := contract.reward_per_unit()
	unit_delivered.emit(contract, reward)

	if contract.is_complete():
		contract.state = Contract.State.COMPLETED
		contract_completed.emit(contract)

	return reward


# ── Generation ────────────────────────────────────────────────────────────────

func _generate_contracts_for(new_port_id: String) -> void:
	for existing_id in _ports.keys():
		if existing_id == new_port_id:
			continue
		var inbound  := _make_contract(existing_id, new_port_id)
		var outbound := _make_contract(new_port_id, existing_id)
		_contracts[inbound.id]  = inbound
		_contracts[outbound.id] = outbound


func _make_contract(from_id: String, to_id: String) -> Contract:
	var from_info := _ports.get(from_id, {}) as Dictionary
	var to_info   := _ports.get(to_id,   {}) as Dictionary
	var from_pos  := from_info.get("position", Vector3.ZERO) as Vector3
	var to_pos    := to_info.get("position",   Vector3.ZERO) as Vector3
	var distance  := maxf(from_pos.distance_to(to_pos), 1.0)

	var commodity: Dictionary = COMMODITIES[randi() % COMMODITIES.size()]
	var quantity   := randi() % 7 + 4
	var value_per  := int(commodity["value"])
	var reward     := int(distance * float(quantity) * float(value_per) * 0.12)

	var c                    := Contract.new()
	c.id                     = UuidUtil.generate()
	c.commodity              = str(commodity["id"])
	c.display_name           = str(commodity["display"])
	c.quantity               = quantity
	c.mass_per_unit_kg       = float(commodity["mass_kg"])
	c.reward_gold            = reward
	c.origin_port_id         = from_id
	c.destination_port_id    = to_id
	c.state                  = Contract.State.AVAILABLE
	c.delivered_count        = 0
	return c
