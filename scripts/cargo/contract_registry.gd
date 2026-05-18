extends Node

## Autoload — register in Project > Autoloads as "ContractRegistry".
## Single source of truth for ports and trade contracts.
## No knowledge of the physical world; operates purely on data.

signal contract_accepted(contract: Contract, pallets: Array[Pallet])
signal unit_delivered(contract: Contract, reward_gold: int)
signal contract_completed(contract: Contract)

const COMMODITIES := [
	{ "id": "grain",      "display": "Grain",      "mass_kg": 180.0, "value": 8  },
	{ "id": "timber",     "display": "Timber",     "mass_kg": 320.0, "value": 12 },
	{ "id": "iron_ore",   "display": "Iron Ore",   "mass_kg": 480.0, "value": 18 },
	{ "id": "coal",       "display": "Coal",       "mass_kg": 280.0, "value": 10 },
	{ "id": "provisions", "display": "Provisions", "mass_kg": 150.0, "value": 14 },
]

const CONTRACT_RADIUS      := 3500.0
const MAX_ACTIVE_CONTRACTS := 3

## port_id -> { id, display_name, position, spawn_pos, commodity_export, commodity_imports, ... }
var _ports: Dictionary = {}
## contract_id -> Contract
var _contracts: Dictionary = {}


# ── Port registration ─────────────────────────────────────────────────────────

func register_port(
	port_id: String,
	display_name: String,
	world_pos: Vector3,
	spawn_pos: Vector3 = Vector3(INF, INF, INF),
	commodity_export: String = "",
	commodity_imports: Array = [],
	island_width: float = 0.0,
	plot_depth: float = 140.0,
	layout_seed: int = 0,
	population: int = 0,
	features: Array = [],
	rotation_y: float = -INF,
	berth_count: int = 0,
	size: int = -1,
) -> void:
	var already_known := _ports.has(port_id)
	var entry := {
		"id":                port_id,
		"display_name":      display_name,
		"position":          world_pos,
		"spawn_pos":         spawn_pos if spawn_pos != Vector3(INF, INF, INF) else world_pos,
		"commodity_export":  commodity_export,
		"commodity_imports": commodity_imports,
		"island_width":      island_width,
		"plot_depth":        plot_depth,
		"layout_seed":       layout_seed,
		"population":        population,
		"features":          features,
		"rotation_y":        rotation_y if rotation_y != -INF else 0.0,
		"berth_count":       berth_count if berth_count > 0 else 1,
		"size":              size if size >= 0 else 1,
	}
	if already_known:
		var prev := _ports[port_id] as Dictionary
		if island_width == 0.0:
			entry["island_width"] = prev.get("island_width", 0.0)
			entry["plot_depth"]   = prev.get("plot_depth",   140.0)
			entry["layout_seed"]  = prev.get("layout_seed",  0)
		if commodity_export.is_empty():
			entry["commodity_export"] = prev.get("commodity_export", "")
		if commodity_imports.is_empty():
			entry["commodity_imports"] = prev.get("commodity_imports", [])
		if population == 0:
			entry["population"] = prev.get("population", 0)
		if features.is_empty():
			entry["features"] = prev.get("features", [])
		if rotation_y == -INF:
			entry["rotation_y"] = prev.get("rotation_y", 0.0)
		if berth_count == 0:
			entry["berth_count"] = prev.get("berth_count", 1)
		if size < 0:
			entry["size"] = prev.get("size", 1)
	_ports[port_id] = entry
	if not already_known:
		_generate_contracts_for(port_id)


func get_port_display_name(port_id: String) -> String:
	var info := _ports.get(port_id, {}) as Dictionary
	return str(info.get("display_name", "Unknown Port"))


func get_port_ids() -> Array:
	return _ports.keys()


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


func get_accepted_contracts() -> Array[Contract]:
	var out: Array[Contract] = []
	for c in _contracts.values():
		var contract := c as Contract
		if contract != null and contract.state == Contract.State.ACCEPTED:
			out.append(contract)
	return out


func get_port_position(port_id: String) -> Vector3:
	var info := _ports.get(port_id, {}) as Dictionary
	if info.is_empty():
		return Vector3(INF, INF, INF)
	return info.get("position", Vector3(INF, INF, INF)) as Vector3


func get_port_info(port_id: String) -> Dictionary:
	return _ports.get(port_id, {}) as Dictionary


func get_port_spawn_position(port_id: String) -> Vector3:
	var info := _ports.get(port_id, {}) as Dictionary
	if info.is_empty():
		return Vector3(INF, INF, INF)
	return info.get("spawn_pos", Vector3(INF, INF, INF)) as Vector3


func unregister_port(port_id: String) -> void:
	_ports.erase(port_id)


# ── Accept ────────────────────────────────────────────────────────────────────

func accept_contract(contract_id: String) -> bool:
	var contract := _contracts.get(contract_id) as Contract
	if contract == null or contract.state != Contract.State.AVAILABLE:
		return false
	if get_accepted_contracts().size() >= MAX_ACTIVE_CONTRACTS:
		return false

	contract.state = Contract.State.ACCEPTED

	var pallets := PalletFactory.split(contract, PalletFactory.DEFAULT_UNITS_PER_PALLET)
	contract_accepted.emit(contract, pallets)
	return true


# ── Delivery ──────────────────────────────────────────────────────────────────

## Called when a pallet is delivered. Returns gold earned (0 on failure).
func deliver_pallet(pallet: Pallet) -> int:
	if pallet == null:
		return 0

	var contract := _contracts.get(pallet.contract_id, null) as Contract
	if contract == null or contract.state == Contract.State.COMPLETED:
		return pallet.value_gold

	contract.delivered_count += pallet.units
	var reward := pallet.value_gold
	unit_delivered.emit(contract, reward)

	if contract.is_complete():
		contract.state = Contract.State.COMPLETED
		contract_completed.emit(contract)
		contract.delivered_count = 0
		contract.state           = Contract.State.AVAILABLE

	return reward


# ── Generation ────────────────────────────────────────────────────────────────

func _generate_contracts_for(new_port_id: String) -> void:
	var new_info := _ports.get(new_port_id, {}) as Dictionary
	var new_pos  := new_info.get("position", Vector3.ZERO) as Vector3

	for existing_id in _ports.keys():
		if existing_id == new_port_id:
			continue
		var ex_info := _ports.get(existing_id, {}) as Dictionary
		var ex_pos  := ex_info.get("position", Vector3.ZERO) as Vector3
		if new_pos.distance_to(ex_pos) > CONTRACT_RADIUS:
			continue
		var inbound  := _make_contract(existing_id, new_port_id)
		var outbound := _make_contract(new_port_id, existing_id)
		_contracts[inbound.id]  = inbound
		_contracts[outbound.id] = outbound


func _make_contract(from_id: String, to_id: String) -> Contract:
	var from_info    := _ports.get(from_id, {}) as Dictionary
	var to_info      := _ports.get(to_id,   {}) as Dictionary
	var from_pos     := from_info.get("position", Vector3.ZERO) as Vector3
	var to_pos       := to_info.get("position",   Vector3.ZERO) as Vector3
	var distance     := maxf(from_pos.distance_to(to_pos), 1.0)

	var commodity_id := str(from_info.get("commodity_export", "provisions"))
	var commodity: Dictionary = {}
	for entry in COMMODITIES:
		if str((entry as Dictionary)["id"]) == commodity_id:
			commodity = entry as Dictionary
			break
	if commodity.is_empty():
		commodity = COMMODITIES[0] as Dictionary

	var rng       := RandomNumberGenerator.new()
	rng.seed      = _hash_route(from_id, to_id)
	var quantity  := rng.randi() % 3 + 3    # 3–5 items per run
	var value_per := int(commodity["value"])
	var reward    := int(distance * float(quantity) * float(value_per) * 0.14)

	var c                 := Contract.new()
	c.id                  = from_id + "::" + to_id
	c.commodity           = commodity_id
	c.display_name        = str(commodity["display"])
	c.quantity            = quantity
	c.mass_per_unit_kg    = float(commodity["mass_kg"])
	c.reward_gold         = reward
	c.origin_port_id      = from_id
	c.destination_port_id = to_id
	c.state               = Contract.State.AVAILABLE
	c.delivered_count     = 0
	return c



# ── Debug ─────────────────────────────────────────────────────────────────────

## Spawns a contract whose origin AND destination are the given port, then
## immediately accepts it so pallets stage on the apron right away. Lets the
## crane system be tested without sailing anywhere. Reward is flat (not
## distance-scaled, since distance is zero).
func debug_spawn_local_contract(
	port_id: String,
	commodity_id: String = "provisions",
	quantity: int = 4,
	reward: int = 200,
) -> Contract:
	if not _ports.has(port_id):
		push_warning("ContractRegistry: debug_spawn_local_contract — unknown port_id: " + port_id)
		return null

	var commodity: Dictionary = {}
	for entry in COMMODITIES:
		if str((entry as Dictionary)["id"]) == commodity_id:
			commodity = entry as Dictionary
			break
	if commodity.is_empty():
		commodity = COMMODITIES[0] as Dictionary

	var c                 := Contract.new()
	c.id                  = "debug::%s::%d" % [port_id, Time.get_ticks_msec()]
	c.commodity           = str(commodity["id"])
	c.display_name        = str(commodity["display"])
	c.quantity            = quantity
	c.mass_per_unit_kg    = float(commodity["mass_kg"])
	c.reward_gold         = reward
	c.origin_port_id      = port_id
	c.destination_port_id = port_id
	c.state               = Contract.State.AVAILABLE
	c.delivered_count     = 0
	_contracts[c.id]      = c

	accept_contract(c.id)
	return c


static func _hash_route(from_id: String, to_id: String) -> int:
	var h := 5381
	for ch in (from_id + "|" + to_id):
		h = ((h << 5) + h) ^ ch.unicode_at(0)
	return h
