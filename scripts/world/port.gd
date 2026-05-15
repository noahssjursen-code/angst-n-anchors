@tool
class_name Port
extends Node3D

## Self-contained port location: piers, mooring posts, warehouse, dock terminal, ship spawner.
## Place this node anywhere in the world; all internal positions are local to this node.
## The world sets the node's global position — Port knows nothing about the world around it.

const DockFacilitiesScript        := preload("res://scripts/systems/dock/dock_facilities.gd")
const WarehouseCargoTestScript    := preload("res://scripts/systems/cargo/warehouse_cargo_test.gd")
const WarehouseContractZoneScript := preload("res://scripts/systems/cargo/warehouse_contract_zone.gd")

@export var ship_scene: PackedScene = preload("res://scenes/boats/test_boat.tscn")

# --- Layout constants (local space) ---
const DOCK_SURFACE_Y          := 0.08
const MOORING_BERTH_FRONT_Z   := 36.5
const MOORING_BERTH_REAR_Z    := 57.5
const BERTH_SHIP_POSITION     := Vector3(12.5, WaveSurface.WATER_LEVEL, 47.0)
const TERMINAL_POSITION       := Vector3(4.5, DOCK_SURFACE_Y, 37.8)
const PLAYER_SPAWN_OFFSET     := Vector3(3.0, 0.0, -15.0)

const CONCRETE_PIER_MODEL     := "res://resources/data/meshes/concrete_pier.json"
const PIER_DECK_TOP_LOCAL_Y   := 2.0
const PIER_ABS_SCALE          := 1.3
## Pier deck narrow half-span (1.8 m local) minus small inset so bollards sit near the rail.
const MOORING_SIDE_OFFSET     := 1.8 * PIER_ABS_SCALE - 0.08
const PIER_POSITION           := Vector3(5.6, DOCK_SURFACE_Y - PIER_DECK_TOP_LOCAL_Y * PIER_ABS_SCALE, 42.0)
const PIER_ROTATION           := Vector3(0.0, 90.0, 0.0)
const PIER_DECK_LENGTH_LOCAL  := 20.0   # authored deck span along local +X in concrete_pier.json
const PIER_CHAIN_GAP          := 0.0   # extra separation between chained pier centers
const PIER_CHAIN_SIGN         := -1.0  # negate to flip which end hooks to pier 1

const OPEN_WAREHOUSE_MODEL    := "res://resources/data/meshes/open_warehouse.json"
const OPEN_WAREHOUSE_SCALE    := 1.0
const OPEN_WAREHOUSE_POSITION := Vector3(-22.0, 0.03, -8.0)
const OPEN_WAREHOUSE_ROTATION := Vector3(0.0, 55.0, 0.0)

var _open_warehouse:       StaticBody3D
var _warehouse_zone:       Node3D


func _ready() -> void:
	for child in get_children():
		child.queue_free()

	_build_piers()
	_build_dock()
	_build_warehouse()
	if not Engine.is_editor_hint():
		_build_warehouse_cargo_test()


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
	var warehouse              := StaticBody3D.new()
	warehouse.name             = "OpenWarehouse"
	warehouse.position         = OPEN_WAREHOUSE_POSITION
	warehouse.rotation_degrees = OPEN_WAREHOUSE_ROTATION
	add_child(warehouse)
	_open_warehouse = warehouse

	var assembler                   := ModelAssembler.new()
	assembler.model_data_path       = OPEN_WAREHOUSE_MODEL
	assembler.absolute_scale        = OPEN_WAREHOUSE_SCALE
	assembler.collision_parent_path = NodePath("..")
	assembler.build_part_colliders  = true
	warehouse.add_child(assembler)

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			warehouse.owner  = esc
			assembler.owner  = esc

	_build_warehouse_zone()


func _build_warehouse_zone() -> void:
	if _open_warehouse == null or not is_instance_valid(_open_warehouse):
		return

	var zone          := WarehouseContractZoneScript.new()
	zone.name         = "ContractZone"
	zone.position     = Vector3(0.0, 0.03, -0.6)
	zone.set("zone_width_m",    6.2)
	zone.set("zone_length_m",   8.4)
	zone.set("slot_size_x_m",   1.2)
	zone.set("slot_size_z_m",   1.2)
	zone.set("show_debug_area", true)
	zone.set("debug_color",     Color(0.18, 0.76, 0.30, 0.25))
	_open_warehouse.add_child(zone)
	_warehouse_zone = zone

	if Engine.is_editor_hint():
		var esc := get_tree().edited_scene_root
		if esc != null:
			zone.owner = esc


func _build_warehouse_cargo_test() -> void:
	if _open_warehouse == null or not is_instance_valid(_open_warehouse):
		return

	var cargo_test                  := WarehouseCargoTestScript.new()
	cargo_test.name                 = "WarehouseCargoTest"
	add_child(cargo_test)
	cargo_test.warehouse_root_path  = cargo_test.get_path_to(_open_warehouse)
	if _warehouse_zone != null and is_instance_valid(_warehouse_zone):
		cargo_test.contract_zone_path = cargo_test.get_path_to(_warehouse_zone)
	var spawner := get_node_or_null("DockFacilities/ShipSpawner")
	if spawner != null:
		cargo_test.ship_spawner_path = cargo_test.get_path_to(spawner)
	cargo_test.call_deferred("refresh_demo_contract")
