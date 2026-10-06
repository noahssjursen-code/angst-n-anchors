class_name ContainerNode
extends Node3D

## World visual for a ContainerUnit. Provision crane can grab nodes in this group.

const GROUP := "container_node"
const MODELS := {"20ft":"container_20ft", "40ft":"container_40ft", "legacy_4m":"legacy_breakbulk_4m"}
const SIZE_M := ContainerUnit.DEFAULT_SIZE_M
const HEIGHT_M := ContainerUnit.DEFAULT_HEIGHT_M
## Lift above pad deck lines / slot marks to avoid z-fighting.
const PAD_SURFACE_Y := 0.05

static func floor_offset_y() -> float:
	return PAD_SURFACE_Y

signal grabbed(node: ContainerNode)
signal released(node: ContainerNode)

var unit: ContainerUnit = null
var _visual: Node3D
var _labels: Array[Label3D] = []
var _highlighted: bool = false
var _halo: MeshInstance3D
var _body: StaticBody3D
var _decorative_only: bool = false
var _lifting_frame: Node3D

func dimensions_m() -> Vector3:
	return unit.dimensions_m() if unit != null else ContainerUnit.TYPES["20ft"]

func lift_height_m() -> float:
	return dimensions_m().y + .5


func _ready() -> void:
	add_to_group(GROUP)


func setup(u: ContainerUnit, decorative_only: bool = false) -> void:
	unit = u
	_decorative_only = decorative_only
	_rebuild()


func set_collision_enabled(on: bool) -> void:
	if _body != null and is_instance_valid(_body):
		_body.collision_layer = 1 if on else 0


func _rebuild() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
		_body = null
	if not _decorative_only:
		_body = StaticBody3D.new()
		_body.name = "Collision"
		_body.collision_layer = 1
		_body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.name = "Shape"
		var shape := BoxShape3D.new()
		shape.size = dimensions_m()
		col.shape = shape
		col.position = Vector3(0.0, dimensions_m().y * 0.5, 0.0)
		_body.add_child(col)
		add_child(_body)
	var asset: String = MODELS.get(unit.container_type if unit != null else "20ft", "legacy_breakbulk_4m")
	_visual = (load("res://resources/models/cargo/%s.glb" % asset) as PackedScene).instantiate()
	_visual.name = "Model"
	add_child(_visual)
	if unit != null:
		# Paint the authored shell/doors only; zinc locks, seals and floor stay fixed.
		for mesh: MeshInstance3D in _visual.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if original != null and original.resource_name.begins_with("Container_Paint"):
					var material := original.duplicate() as StandardMaterial3D
					material.albedo_color = ContainerPaintMaterial.FREIGHT_PALETTE[posmod(unit.paint_variant,8)]
					mesh.set_surface_override_material(surface, material)
	_rebuild_route_labels()
	_build_halo()


func _rebuild_route_labels() -> void:
	for old_label in _labels:
		if old_label != null and is_instance_valid(old_label):
			old_label.queue_free()
	_labels.clear()
	if unit == null or unit.destination_port_id.is_empty():
		return
	var size := dimensions_m()
	var placements := [
		[Vector3(size.x*.5+.01, size.y*.64, 0.0), PI * 0.5],
		[Vector3(-size.x*.5-.01, size.y*.64, 0.0), -PI * 0.5],
	]
	for index in range(placements.size()):
		var placement: Array = placements[index]
		var label := Label3D.new()
		label.name = "CargoMark_%d" % index
		label.text = _route_label_text()
		## Small painted shipping stencil, constrained to the container panel.
		label.font_size = 36
		label.pixel_size = 0.0036
		label.width = 820.0
		label.position = placement[0] as Vector3
		label.rotation.y = float(placement[1])
		label.outline_size = 7
		label.modulate = Color(0.92, 0.92, 0.84)
		label.outline_modulate = Color(0.015, 0.02, 0.025, 0.96)
		label.visibility_range_end = 65.0
		label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(label)
		_labels.append(label)


func set_highlighted(on: bool) -> void:
	_highlighted = on
	if _halo != null:
		_halo.visible = on
	for label in _labels:
		if label != null:
			label.modulate = Color.WHITE if on else Color(0.92, 0.92, 0.84)


func _route_label_text() -> String:
	if unit == null:
		return ""
	if unit.destination_port_id.is_empty():
		return CommodityCatalog.commodity_display(unit.commodity_id)
	var origin := unit.origin_port_id
	var destination := unit.destination_port_id
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog != null:
		origin = catalog.get_port_display_name(unit.origin_port_id)
		destination = catalog.get_port_display_name(unit.destination_port_id)
	return "TO    %s\nFROM  %s\n%s  |  %s" % [
		_short_port_label(destination),
		_short_port_label(origin),
		_short_cargo_label(CommodityCatalog.commodity_display(unit.commodity_id)),
		PlayerData.format_money(unit.delivery_value_marks),
	]


static func _short_port_label(port_name: String) -> String:
	var clean := port_name.strip_edges().to_upper()
	return clean.left(12) if clean.length() > 12 else clean


static func _short_cargo_label(cargo_name: String) -> String:
	var clean := cargo_name.strip_edges().to_upper()
	return clean.left(12) if clean.length() > 12 else clean


func _build_halo() -> void:
	if _halo != null and is_instance_valid(_halo):
		return
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	var disc := CylinderMesh.new()
	## Stay inside the visual footprint so the disc never rims past the cube sides.
	var radius := dimensions_m().x * 0.46
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
	if not is_instance_valid(_lifting_frame):
		var asset: String = MODELS.get(unit.container_type,"legacy_breakbulk_4m")
		_lifting_frame = (load("res://resources/models/cargo/%s_spreader.glb" % asset) as PackedScene).instantiate()
		add_child(_lifting_frame)
	set_collision_enabled(false)
	set_highlighted(false)
	grabbed.emit(self)


func notify_released() -> void:
	if is_instance_valid(_lifting_frame):
		_lifting_frame.queue_free()
		_lifting_frame = null
	if not _decorative_only:
		set_collision_enabled(true)
	released.emit(self)
