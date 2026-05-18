class_name DeliveryZone
extends Node3D

## Placed at a port. Accepts cargo whose destination_port_id matches this port's UUID.
## Independent: no knowledge of warehouses, ships, or players.

const GROUP := "cargo_delivery_zone"

signal pallet_delivered(pallet: Pallet, value_gold: int)

## UUID of the port this zone belongs to. Set when the port is created.
@export var port_id: String = ""
@export var zone_width_m: float  = 4.0
@export var zone_length_m: float = 4.0

@export_group("Debug")
@export var show_debug_area: bool = true:
	set(v):
		show_debug_area = v
		_rebuild_debug_visual()
@export var debug_color: Color = Color(0.82, 0.55, 0.18, 0.22):
	set(v):
		debug_color = v
		_rebuild_debug_visual()

var _debug_mesh: MeshInstance3D


func _ready() -> void:
	add_to_group(GROUP)
	_rebuild_debug_visual()


func accepts_pallet(pallet: Pallet) -> bool:
	if pallet == null or port_id.is_empty():
		return false
	return pallet.destination_port_id == port_id


## Delivers a pallet if it matches. Calls ContractRegistry, emits signal, returns gold earned.
func deliver_pallet(pallet: Pallet) -> int:
	if not accepts_pallet(pallet):
		return 0
	var registry := get_node_or_null("/root/ContractRegistry")
	var reward   := 0
	if registry != null:
		reward = int(registry.deliver_pallet(pallet))
	else:
		reward = pallet.value_gold
	pallet_delivered.emit(pallet, reward)
	return reward


func _rebuild_debug_visual() -> void:
	if not is_inside_tree():
		return
	if _debug_mesh == null:
		_debug_mesh = get_node_or_null("DeliveryZoneDebug") as MeshInstance3D
	if _debug_mesh == null:
		_debug_mesh               = MeshInstance3D.new()
		_debug_mesh.name          = "DeliveryZoneDebug"
		_debug_mesh.cast_shadow   = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_mesh)

	if not show_debug_area:
		_debug_mesh.visible = false
		return

	var mesh      := BoxMesh.new()
	mesh.size     = Vector3(zone_width_m, 0.03, zone_length_m)
	_debug_mesh.mesh     = mesh
	_debug_mesh.position = Vector3(0.0, 0.015, 0.0)
	_debug_mesh.visible  = true

	var mat                  := StandardMaterial3D.new()
	mat.albedo_color         = debug_color
	mat.transparency         = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode         = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode            = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test        = true
	_debug_mesh.material_override = mat
