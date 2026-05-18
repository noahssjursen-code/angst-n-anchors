extends Node

## Autoload — register in Project > Autoloads as "ContractRegistry".
## Single source of truth for ports and trade contracts.
## No knowledge of the physical world; operates purely on data.

signal contract_accepted(contract: Contract, pallets: Array[Pallet])
signal unit_delivered(contract: Contract, reward_gold: int)
signal contract_completed(contract: Contract)

## Per-commodity packing rules.
##
## Rule of the system: ONE unit always occupies ONE grid cell.
## `max_pallet_units` caps how many cells a single pallet can stretch over;
## a pallet is laid out as a 1×N strip up to that maximum, then a new pallet
## starts. So provisions w/ max 6 and a 5-unit contract → 1 pallet of 1×5.
## A 7-unit contract → one 1×6 + one 1×1.
const COMMODITIES := [
	{ "id": "grain",      "display": "Grain",      "mass_kg": 180.0, "value":  8, "max_pallet_units": 4, "color": [0.90, 0.78, 0.30] },
	{ "id": "timber",     "display": "Timber",     "mass_kg": 320.0, "value": 12, "max_pallet_units": 4, "color": [0.52, 0.33, 0.18] },
	{ "id": "iron_ore",   "display": "Iron Ore",   "mass_kg": 480.0, "value": 18, "max_pallet_units": 2, "color": [0.50, 0.42, 0.38] },
	{ "id": "coal",       "display": "Coal",       "mass_kg": 280.0, "value": 10, "max_pallet_units": 4, "color": [0.20, 0.20, 0.22] },
	{ "id": "provisions", "display": "Provisions", "mass_kg": 150.0, "value": 14, "max_pallet_units": 6, "color": [0.72, 0.30, 0.22] },
]


static func commodity_info(commodity_id: String) -> Dictionary:
	for entry in COMMODITIES:
		if str((entry as Dictionary)["id"]) == commodity_id:
			return entry as Dictionary
	return {}


static func commodity_color(commodity_id: String) -> Color:
	var info := commodity_info(commodity_id)
	var arr: Array = info.get("color", [0.6, 0.6, 0.6])
	if arr.size() < 3:
		return Color(0.6, 0.6, 0.6)
	return Color(float(arr[0]), float(arr[1]), float(arr[2]))

const CONTRACT_RADIUS      := 3500.0
## One contract at a time. Stacking deliveries to multiple ports doesn't make
## sense at the scales involved — pick a single route, fill the ship for it,
## sail there, deliver, then take another contract from the destination.
const MAX_ACTIVE_CONTRACTS := 1

## port_id -> { id, display_name, position, spawn_pos, commodity_export, commodity_imports, ... }
var _ports: Dictionary = {}
## contract_id -> Contract
var _contracts: Dictionary = {}
## port_id -> { commodity_id -> units_available_to_export }
## Drawn down when a contract is accepted, replenished by future restock logic
## (TBD). Multiplayer: every player draws from the same per-port pool.
var _export_stock: Dictionary = {}


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
		if contract == null:
			continue
		# A contract is "active" while any of its units are out on the apron
		# or in transit — i.e. taken but not yet delivered.
		if contract.is_in_transit():
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

## Accept (a portion of) a contract. take_units = 0 means "as much as I can":
## limited by the contract's remaining quantity AND port stock. Returns the
## actual number of units accepted (0 if nothing fit). Pallets for the taken
## amount are emitted via contract_accepted.
func accept_contract(contract_id: String, take_units: int = 0) -> int:
	var contract := _contracts.get(contract_id) as Contract
	if contract == null:
		return 0
	if contract.available_to_take() <= 0:
		return 0
	# New contract entering the player's slate counts toward the cap. An
	# already-active contract (taken_count > 0) doesn't take a new slot.
	if contract.taken_count == 0 and get_accepted_contracts().size() >= MAX_ACTIVE_CONTRACTS:
		return 0

	var stock := get_export_stock(contract.origin_port_id, contract.commodity)
	var cap := mini(contract.available_to_take(), stock)
	var actual: int = cap if take_units <= 0 else mini(take_units, cap)
	if actual <= 0:
		return 0

	_consume_stock(contract.origin_port_id, contract.commodity, actual)
	contract.taken_count += actual
	if contract.taken_count >= contract.quantity:
		contract.state = Contract.State.ACCEPTED

	# Pallets are generated from a temporary batch contract — same id (so
	# delivery still maps), reduced quantity + reward, identical packing rules.
	var batch := Contract.new()
	batch.id                  = contract.id
	batch.commodity           = contract.commodity
	batch.display_name        = contract.display_name
	batch.quantity            = actual
	batch.mass_per_unit_kg    = contract.mass_per_unit_kg
	batch.reward_gold         = contract.reward_per_unit() * actual
	batch.origin_port_id      = contract.origin_port_id
	batch.destination_port_id = contract.destination_port_id
	var pallets := PalletFactory.split(batch)

	contract_accepted.emit(contract, pallets)
	return actual


# ── Port export pool ─────────────────────────────────────────────────────────

func get_export_stock(port_id: String, commodity_id: String) -> int:
	var pool: Dictionary = _export_stock.get(port_id, {})
	return int(pool.get(commodity_id, 0))


func add_export_stock(port_id: String, commodity_id: String, units: int) -> void:
	if units <= 0 or port_id.is_empty() or commodity_id.is_empty():
		return
	if not _export_stock.has(port_id):
		_export_stock[port_id] = {}
	var pool: Dictionary = _export_stock[port_id]
	pool[commodity_id] = int(pool.get(commodity_id, 0)) + units


func _consume_stock(port_id: String, commodity_id: String, units: int) -> bool:
	if units <= 0:
		return true
	# Same-port contracts (debug self-loops) draw from their own pool too.
	var have := get_export_stock(port_id, commodity_id)
	if have < units:
		return false
	_export_stock[port_id][commodity_id] = have - units
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
		# Reset for potential reuse. Stock pool isn't replenished here — it
		# stays drained until a future restock pass refills it.
		contract.delivered_count = 0
		contract.taken_count     = 0
		contract.state           = Contract.State.AVAILABLE

	return reward


# ── Generation ────────────────────────────────────────────────────────────────

func _generate_contracts_for(new_port_id: String) -> void:
	var new_info := _ports.get(new_port_id, {}) as Dictionary
	var new_pos  := new_info.get("position", Vector3.ZERO) as Vector3

	# Self-loop contract: pickup and dropoff at the same port. Useful for
	# in-port crane practice without sailing, and reads as a real contract
	# in the ContractNpc list.
	var local := _make_contract(new_port_id, new_port_id)
	_contracts[local.id] = local

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
	# Same-port contracts have zero distance — pay a flat in-port handling
	# fee instead so the contract is still worth taking.
	if from_id == to_id:
		reward = quantity * value_per * 5

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

	# Seed the origin port's export pool with this contract's units so
	# accept_contract() can draw against it.
	add_export_stock(from_id, commodity_id, quantity)
	return c



static func _hash_route(from_id: String, to_id: String) -> int:
	var h := 5381
	for ch in (from_id + "|" + to_id):
		h = ((h << 5) + h) ^ ch.unicode_at(0)
	return h
