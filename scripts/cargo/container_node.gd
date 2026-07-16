class_name ContainerNode
extends Node3D

## World visual for a ContainerUnit. Provision crane can grab nodes in this group.

const GROUP := "container_node"
const MODEL_PATH := "res://resources/data/models/cargo/container_cube.json"
const ASSEMBLER_SCRIPT := preload("res://scripts/core/model_assembler.gd")
const SIZE_M := ContainerUnit.DEFAULT_SIZE_M
const HEIGHT_M := ContainerUnit.DEFAULT_HEIGHT_M
## Visual mesh scale — grid footprint stays full size; mesh shrinks for gaps between neighbours.
const VISUAL_SCALE := 0.95
## Lift above pad deck lines / slot marks to avoid z-fighting.
const PAD_SURFACE_Y := 0.05

static func floor_offset_y() -> float:
	return PAD_SURFACE_Y
const CORNER_SIZE_M := 0.18
const CORNER_OUTSET_M := 0.04
const CORNER_HEIGHT_M := HEIGHT_M * 0.992

signal grabbed(node: ContainerNode)
signal released(node: ContainerNode)

var unit: ContainerUnit = null
var _assembler: Node3D
var _corners: Node3D
var _label: Label3D
var _highlighted: bool = false
var _halo: MeshInstance3D
var _body: StaticBody3D


func _ready() -> void:
	add_to_group(GROUP)


func setup(u: ContainerUnit) -> void:
	unit = u
	_rebuild()


func set_collision_enabled(on: bool) -> void:
	if _body != null and is_instance_valid(_body):
		_body.collision_layer = 1 if on else 0


func _rebuild() -> void:
	if _assembler != null and is_instance_valid(_assembler):
		_assembler.queue_free()
		_assembler = null
		_corners = null
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
		_body = null
	## Footprint box — reliable walk/block even if mesh convex fails to host.
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE_M * VISUAL_SCALE, HEIGHT_M * VISUAL_SCALE, SIZE_M * VISUAL_SCALE)
	col.shape = shape
	col.position = Vector3(0.0, HEIGHT_M * VISUAL_SCALE * 0.5, 0.0)
	_body.add_child(col)
	add_child(_body)
	_assembler = ASSEMBLER_SCRIPT.new()
	_assembler.name = "Model"
	_assembler.absolute_scale = VISUAL_SCALE
	## Mesh convex is redundant with the box; keep visuals light.
	_assembler.build_part_colliders = false
	add_child(_assembler)
	_assembler.model_data_path = MODEL_PATH
	if unit != null:
		var seed := ContainerPaintMaterial.seed_from_unit(unit)
		ContainerPaintMaterial.apply_to_node(_assembler, unit.commodity_id, seed)
		_build_corners(unit.commodity_id, seed)
	if _label == null:
		_label = Label3D.new()
		_label.name = "ContainerLabel"
		_label.font_size = 48
		_label.pixel_size = 0.005
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.position = Vector3(0.0, HEIGHT_M * VISUAL_SCALE + 0.35, 0.0)
		_label.visible = false
		add_child(_label)
	if unit != null:
		_label.text = CommodityCatalog.commodity_display(unit.commodity_id)
	_build_halo()


func _build_corners(commodity_id: String, seed: float) -> void:
	if _assembler == null:
		return
	_corners = Node3D.new()
	_corners.name = "CornerCastings"
	_assembler.add_child(_corners)
	var half := SIZE_M * 0.5
	var offset := half + CORNER_OUTSET_M - CORNER_SIZE_M * 0.5
	var signs := [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			var mi := MeshBuilder.box(
				Vector3(CORNER_SIZE_M, CORNER_HEIGHT_M, CORNER_SIZE_M),
				Color.WHITE,
				0.78,
				0.32,
			)
			mi.name = "Corner"
			mi.position = Vector3(sx * offset, CORNER_HEIGHT_M * 0.5, sz * offset)
			_corners.add_child(mi)
	ContainerPaintMaterial.apply_to_node(_corners, commodity_id, seed + 13.7)


func set_highlighted(on: bool) -> void:
	_highlighted = on
	if _halo != null:
		_halo.visible = on
	if _label != null:
		_label.visible = on and unit != null


func _build_halo() -> void:
	if _halo != null and is_instance_valid(_halo):
		return
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	var disc := CylinderMesh.new()
	## Stay inside the visual footprint so the disc never rims past the cube sides.
	var radius := SIZE_M * 0.46 * VISUAL_SCALE
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.04
	_halo.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.78, 0.15, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo.material_override = mat
	_halo.position = Vector3(0.0, PAD_SURFACE_Y, 0.0)
	_halo.visible = false
	add_child(_halo)


func notify_grabbed() -> void:
	set_collision_enabled(false)
	set_highlighted(false)
	grabbed.emit(self)


func notify_released() -> void:
	set_collision_enabled(true)
	released.emit(self)
