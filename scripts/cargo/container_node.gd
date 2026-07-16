class_name ContainerNode
extends Node3D

## World visual for a ContainerUnit. Provision crane can grab nodes in this group.

const GROUP := "container_node"
const MODEL_PATH := "res://resources/data/models/cargo/container_cube.json"
const ASSEMBLER_SCRIPT := preload("res://scripts/core/model_assembler.gd")
const SIZE_M := ContainerUnit.DEFAULT_SIZE_M
const HEIGHT_M := ContainerUnit.DEFAULT_HEIGHT_M

signal grabbed(node: ContainerNode)
signal released(node: ContainerNode)

var unit: ContainerUnit = null
var _assembler: Node3D
var _label: Label3D
var _highlighted: bool = false
var _halo: MeshInstance3D


func _ready() -> void:
	add_to_group(GROUP)


func setup(u: ContainerUnit) -> void:
	unit = u
	_rebuild()


func _rebuild() -> void:
	if _assembler != null and is_instance_valid(_assembler):
		_assembler.queue_free()
		_assembler = null
	_assembler = ASSEMBLER_SCRIPT.new()
	_assembler.name = "Model"
	add_child(_assembler)
	_assembler.model_data_path = MODEL_PATH
	if unit != null:
		_apply_tint(CommodityCatalog.commodity_color(unit.commodity_id))
	if _label == null:
		_label = Label3D.new()
		_label.name = "ContainerLabel"
		_label.font_size = 48
		_label.pixel_size = 0.005
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.position = Vector3(0.0, HEIGHT_M + 0.35, 0.0)
		add_child(_label)
	if unit != null:
		_label.text = CommodityCatalog.commodity_display(unit.commodity_id)
	_build_halo()


func set_highlighted(on: bool) -> void:
	_highlighted = on
	if _halo != null:
		_halo.visible = on


func _apply_tint(tint: Color) -> void:
	if _assembler == null:
		return
	for mi in _assembler.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		if mesh_i == null:
			continue
		var mat := mesh_i.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh_i.material_override = mat
		else:
			mat = mat.duplicate() as StandardMaterial3D
			mesh_i.material_override = mat
		mat.albedo_color = tint


func _build_halo() -> void:
	if _halo != null and is_instance_valid(_halo):
		return
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	var disc := CylinderMesh.new()
	disc.top_radius = SIZE_M * 0.52
	disc.bottom_radius = SIZE_M * 0.52
	disc.height = 0.04
	_halo.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.78, 0.15, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo.material_override = mat
	_halo.position = Vector3(0.0, 0.03, 0.0)
	_halo.visible = false
	add_child(_halo)


func notify_grabbed() -> void:
	grabbed.emit(self)


func notify_released() -> void:
	released.emit(self)
