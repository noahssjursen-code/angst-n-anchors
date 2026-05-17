class_name Warehouse
extends Node3D

## Owns a CargoItem inventory and maintains physical CargoPickup nodes for each item.
## Place a WarehouseContractZone as a child to define where crates appear.
## Independent: no knowledge of players, ships, or specific ports.

signal inventory_changed(warehouse: Warehouse)

const WAREHOUSE_GROUP := "warehouse"

@export var slot_y_offset: float = 0.02
@export_file("*.json") var crate_mesh_path: String = "res://resources/data/meshes/props/crate_wooden.json"
@export var crate_scale: float = 0.78

var _inventory: Array[CargoItem] = []
var _pickups: Dictionary = {}  # cargo_item.id -> CargoPickup


func _ready() -> void:
	add_to_group(WAREHOUSE_GROUP)


# ── Inventory API ─────────────────────────────────────────────────────────────

func add_item(item: CargoItem) -> void:
	if item == null:
		return
	_inventory.append(item)
	_spawn_pickup(item)
	inventory_changed.emit(self)


func remove_item(item: CargoItem) -> void:
	_inventory.erase(item)
	_despawn_pickup(item.id)
	inventory_changed.emit(self)


## Replace entire inventory (e.g. when a contract is accepted).
func set_inventory(items: Array[CargoItem]) -> void:
	_clear_all()
	for item in items:
		_inventory.append(item)
		_spawn_pickup(item)
	inventory_changed.emit(self)


func get_inventory() -> Array[CargoItem]:
	return _inventory.duplicate()


func item_count() -> int:
	return _inventory.size()


## Removes and returns all items, despawning their physical pickups.
func take_all() -> Array[CargoItem]:
	var taken: Array[CargoItem] = _inventory.duplicate()
	_clear_all()
	inventory_changed.emit(self)
	return taken


# ── Internal ──────────────────────────────────────────────────────────────────

func _spawn_pickup(item: CargoItem) -> void:
	var zone      := _find_contract_zone()
	var slot_idx  := _inventory.find(item)
	var world_pos := (
		zone.get_world_slot_position(slot_idx, slot_y_offset)
		if zone != null
		else global_position
	)

	var pickup              := CargoPickup.new()
	pickup.name             = "Pickup_" + item.id.left(8)
	pickup.mesh_path        = crate_mesh_path
	pickup.mesh_scale       = crate_scale
	add_child(pickup)
	pickup.global_position  = world_pos
	pickup.setup(item)
	pickup.picked_up.connect(_on_item_picked_up)
	_pickups[item.id] = pickup


func _despawn_pickup(item_id: String) -> void:
	if not _pickups.has(item_id):
		return
	var node := _pickups[item_id] as Node
	_pickups.erase(item_id)
	if node != null and is_instance_valid(node):
		node.queue_free()


func _clear_all() -> void:
	for id in _pickups.keys().duplicate():
		_despawn_pickup(id)
	_inventory.clear()


func _on_item_picked_up(item: CargoItem) -> void:
	_inventory.erase(item)
	_pickups.erase(item.id)
	inventory_changed.emit(self)


func _find_contract_zone() -> WarehouseContractZone:
	for child in get_children():
		var z := child as WarehouseContractZone
		if z != null:
			return z
	return null
