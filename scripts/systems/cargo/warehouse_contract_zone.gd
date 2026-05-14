@tool
class_name WarehouseContractZone
extends Node3D

signal contract_zone_changed(zone: WarehouseContractZone)

@export var zone_width_m: float = 6.0:
	set(v):
		zone_width_m = maxf(v, 0.5)
		_rebuild_debug_visual()

@export var zone_length_m: float = 8.0:
	set(v):
		zone_length_m = maxf(v, 0.5)
		_rebuild_debug_visual()

@export var slot_size_x_m: float = 1.2:
	set(v):
		slot_size_x_m = maxf(v, 0.1)
		_rebuild_debug_visual()

@export var slot_size_z_m: float = 1.2:
	set(v):
		slot_size_z_m = maxf(v, 0.1)
		_rebuild_debug_visual()

@export var show_debug_area: bool = true:
	set(v):
		show_debug_area = v
		_rebuild_debug_visual()

@export var debug_color: Color = Color(0.18, 0.76, 0.30, 0.22):
	set(v):
		debug_color = v
		_rebuild_debug_visual()

var _debug_mesh: MeshInstance3D


func _ready() -> void:
	_rebuild_debug_visual()


func get_capacity_units() -> int:
	var cols := int(floor(zone_width_m / maxf(slot_size_x_m, 0.1)))
	var rows := int(floor(zone_length_m / maxf(slot_size_z_m, 0.1)))
	return maxi(cols * rows, 0)


func get_world_slot_position(slot_idx: int, y_offset: float = 0.0) -> Vector3:
	var local := get_local_slot_position(slot_idx)
	local.y += y_offset
	return to_global(local)


func get_local_slot_position(slot_idx: int) -> Vector3:
	var cols := maxi(int(floor(zone_width_m / maxf(slot_size_x_m, 0.1))), 1)
	var rows := maxi(int(floor(zone_length_m / maxf(slot_size_z_m, 0.1))), 1)
	var max_slots := maxi(cols * rows, 1)
	var idx := mini(maxi(slot_idx, 0), max_slots - 1)

	var x_idx := idx % cols
	var z_idx := int(floor(float(idx) / float(cols)))
	var step_x := zone_width_m / float(cols)
	var step_z := zone_length_m / float(rows)
	var x := -zone_width_m * 0.5 + step_x * (float(x_idx) + 0.5)
	var z := -zone_length_m * 0.5 + step_z * (float(z_idx) + 0.5)
	return Vector3(x, 0.0, z)


func contains_world_point(world_point: Vector3) -> bool:
	var local := to_local(world_point)
	var hx := zone_width_m * 0.5
	var hz := zone_length_m * 0.5
	return (
		local.x >= -hx
		and local.x <= hx
		and local.z >= -hz
		and local.z <= hz
	)


func _rebuild_debug_visual() -> void:
	if not is_inside_tree():
		return
	if _debug_mesh == null:
		_debug_mesh = get_node_or_null("ContractZoneDebug") as MeshInstance3D
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "ContractZoneDebug"
		_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_mesh)
		if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
			_debug_mesh.owner = get_tree().edited_scene_root

	if not show_debug_area:
		_debug_mesh.visible = false
		return

	var mesh := BoxMesh.new()
	mesh.size = Vector3(zone_width_m, 0.03, zone_length_m)
	_debug_mesh.mesh = mesh
	_debug_mesh.position = Vector3(0.0, 0.015, 0.0)
	_debug_mesh.visible = true

	var mat := StandardMaterial3D.new()
	mat.albedo_color = debug_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_debug_mesh.material_override = mat

	contract_zone_changed.emit(self)
