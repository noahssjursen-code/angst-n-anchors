@tool
class_name Port
extends Node3D

## Self-contained port location: piers, mooring posts, warehouse, dock terminal, ship spawner.
## Place this node anywhere in the world; all internal positions are local to this node.
## The world sets the node's global position — Port knows nothing about the world around it.

const DockFacilitiesScript        := preload("res://scripts/systems/dock/dock_facilities.gd")
const WarehouseContractZoneScript := preload("res://scripts/systems/cargo/warehouse_contract_zone.gd")
const ContractNpcScript           := preload("res://scripts/systems/dock/contract_npc.gd")
const DeliveryNpcScript           := preload("res://scripts/systems/dock/delivery_npc.gd")

@export var ship_scene: PackedScene = preload("res://scenes/boats/test_boat.tscn")
@export var port_id: String = ""
@export var port_display_name: String = "Port"

# --- Layout constants (local space) ---
const DOCK_SURFACE_Y          := 0.08
const MOORING_BERTH_FRONT_Z   := 36.5
const MOORING_BERTH_REAR_Z    := 57.5
const BERTH_SHIP_POSITION     := Vector3(12.5, WaveSurface.WATER_LEVEL, 47.0)
const TERMINAL_POSITION       := Vector3(4.5, DOCK_SURFACE_Y, 37.8)
const PLAYER_SPAWN_OFFSET     := Vector3(3.0, 0.0, -15.0)

const CONCRETE_PIER_MODEL     := "res://resources/data/meshes/docks/concrete_pier.json"
const PIER_DECK_TOP_LOCAL_Y   := 2.0
const PIER_ABS_SCALE          := 1.3
## Pier deck narrow half-span (1.8 m local) minus small inset so bollards sit near the rail.
const MOORING_SIDE_OFFSET     := 1.8 * PIER_ABS_SCALE - 0.08
const PIER_POSITION           := Vector3(5.6, DOCK_SURFACE_Y - PIER_DECK_TOP_LOCAL_Y * PIER_ABS_SCALE, 42.0)
const PIER_ROTATION           := Vector3(0.0, 90.0, 0.0)
const PIER_DECK_LENGTH_LOCAL  := 20.0   # authored deck span along local +X in concrete_pier.json
const PIER_CHAIN_GAP          := 0.0   # extra separation between chained pier centers
const PIER_CHAIN_SIGN         := -1.0  # negate to flip which end hooks to pier 1

const OPEN_WAREHOUSE_MODEL    := "res://resources/data/meshes/port_buildings/open_warehouse.json"
const OPEN_WAREHOUSE_SCALE    := 1.0
const OPEN_WAREHOUSE_POSITION := Vector3(-22.0, 0.03, -8.0)
const OPEN_WAREHOUSE_ROTATION := Vector3(0.0, 55.0, 0.0)

var _open_warehouse: StaticBody3D
var _warehouse:      Warehouse


func _ready() -> void:
	for child in get_children():
		child.queue_free()

	if not Engine.is_editor_hint() and port_id.is_empty():
		port_id = UuidUtil.generate()

	_build_piers()
	_build_dock()
	_build_warehouse()

	if not Engine.is_editor_hint():
		_build_npcs()
		call_deferred("_register_with_registry")


func get_player_spawn_position() -> Vector3:
	var local_pos      := TERMINAL_POSITION + PLAYER_SPAWN_OFFSET
	local_pos.y        = DOCK_SURFACE_Y + 0.02
	return to_global(local_pos)


# --- Pier construction ---

func _build_piers() -> void:
	_build_pier_instance(PIER_POSITION, "")
	_build_pier_instance(_second_pier_center(), "2")


func _build_pier_instance(center: Vector3, name_suffix: String) -> void:
	var pier              := StaticBody3D.new()
	pier.name             = "ConcretePier" + name_suffix
	pier.position         = center
	pier.rotation_degrees = PIER_ROTATION
	add_child(pier)

	var assembler                   := ModelAssembler.new()
	assembler.model_data_path       = CONCRETE_PIER_MODEL
	assembler.absolute_scale        = PIER_ABS_SCALE
	assembler.collision_parent_path = NodePath("..")
	assembler.build_part_colliders  = true
	pier.add_child(assembler)

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			pier.owner     = esc
			assembler.owner = esc


# --- Dock and mooring posts ---

func _build_dock() -> void:
	var moorings := PackedVector3Array()
	var sz       := DOCK_SURFACE_Y
	var sx       := _starboard_row_x()
	var px       := _port_row_x()

	moorings.push_back(Vector3(sx, sz, MOORING_BERTH_FRONT_Z))
	moorings.push_back(Vector3(sx, sz, MOORING_BERTH_REAR_Z))
	moorings.push_back(Vector3(px, sz, MOORING_BERTH_FRONT_Z))
	moorings.push_back(Vector3(px, sz, MOORING_BERTH_REAR_Z))

	for pt in _extended_pier_pair_at_x(sx):
		moorings.push_back(pt)
	for pt in _extended_pier_pair_at_x(px):
		moorings.push_back(pt)

	DockFacilitiesScript.attach(
		self,
		moorings,
		TERMINAL_POSITION,
		180.0,
		BERTH_SHIP_POSITION,
		ship_scene,
	)


func _starboard_row_x() -> float:
	return PIER_POSITION.x + MOORING_SIDE_OFFSET


func _port_row_x() -> float:
	return PIER_POSITION.x - MOORING_SIDE_OFFSET


func _extended_pier_pair_at_x(row_x: float) -> PackedVector3Array:
	var along := _pier_long_axis() * (_pier_center_to_center() * 0.32)
	var pier2  := _second_pier_center()

	var pa := pier2 + along
	var pb := pier2 - along
	pa.x   = row_x
	pb.x   = row_x
	pa.y   = DOCK_SURFACE_Y
	pb.y   = DOCK_SURFACE_Y

	var out := PackedVector3Array()
	out.push_back(pa)
	out.push_back(pb)
	return out


func _pier_long_axis() -> Vector3:
	return Basis.from_euler(Vector3(
		deg_to_rad(PIER_ROTATION.x),
		deg_to_rad(PIER_ROTATION.y),
		deg_to_rad(PIER_ROTATION.z),
	)).x.normalized()


func _pier_center_to_center() -> float:
	return PIER_DECK_LENGTH_LOCAL * PIER_ABS_SCALE + PIER_CHAIN_GAP


func _second_pier_center() -> Vector3:
	var p := PIER_POSITION + _pier_long_axis() * _pier_center_to_center() * PIER_CHAIN_SIGN
	p.y   = PIER_POSITION.y
	return p


# --- Warehouse ---

func _build_warehouse() -> void:
	var esc := get_tree().edited_scene_root if Engine.is_editor_hint() else null

	# Geometry — static collision + visual model.
	var body              := StaticBody3D.new()
	body.name             = "OpenWarehouse"
	body.position         = OPEN_WAREHOUSE_POSITION
	body.rotation_degrees = OPEN_WAREHOUSE_ROTATION
	add_child(body)
	_open_warehouse = body
	if esc != null:
		body.owner = esc

	var assembler                   := ModelAssembler.new()
	assembler.model_data_path       = OPEN_WAREHOUSE_MODEL
	assembler.absolute_scale        = OPEN_WAREHOUSE_SCALE
	assembler.collision_parent_path = NodePath("..")
	assembler.build_part_colliders  = true
	body.add_child(assembler)
	if esc != null:
		assembler.owner = esc

	# Warehouse logic node — owns the slot zone and cargo inventory.
	var wh              := Warehouse.new()
	wh.name             = "PortWarehouse"
	wh.position         = OPEN_WAREHOUSE_POSITION
	wh.rotation_degrees = OPEN_WAREHOUSE_ROTATION
	add_child(wh)
	_warehouse = wh
	if esc != null:
		wh.owner = esc

	var zone          := WarehouseContractZoneScript.new()
	zone.name         = "ContractZone"
	zone.position     = Vector3(0.0, 0.03, -0.6)
	zone.set("zone_width_m",    6.2)
	zone.set("zone_length_m",   8.4)
	zone.set("slot_size_x_m",   1.2)
	zone.set("slot_size_z_m",   1.2)
	zone.set("show_debug_area", true)
	zone.set("debug_color",     Color(0.18, 0.76, 0.30, 0.25))
	wh.add_child(zone)
	if esc != null:
		zone.owner = esc


# --- NPCs ---

func _build_npcs() -> void:
	var contract_npc              := ContractNpcScript.new()
	contract_npc.name             = "ContractNpc"
	contract_npc.port_id          = port_id
	contract_npc.position         = TERMINAL_POSITION + Vector3(-2.5, 0.0, 0.0)
	add_child(contract_npc)

	var delivery_npc              := DeliveryNpcScript.new()
	delivery_npc.name             = "DeliveryNpc"
	delivery_npc.port_id          = port_id
	delivery_npc.position         = TERMINAL_POSITION + Vector3(2.5, 0.0, 0.0)
	add_child(delivery_npc)


func _register_with_registry() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	registry.register_port(port_id, port_display_name, global_position)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	registry.unregister_port(port_id)
