class_name DeliveryZone
extends Node3D

## Placed at a port. Accepts cargo whose destination_port_id matches this port's UUID.
## Independent: no knowledge of warehouses, ships, or players.

const GROUP := "cargo_delivery_zone"

signal cargo_delivered(item: CargoItem, value_gold: int)

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


func accepts(item: CargoItem) -> bool:
	if item == null or port_id.is_empty():
		return false
	return item.destination_port_id == port_id


## Delivers cargo if it matches. Returns true and emits signal on success.
func deliver(item: CargoItem) -> bool:
	if not accepts(item):
		return false
	cargo_delivered.emit(item, item.value_gold)
	return true


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
