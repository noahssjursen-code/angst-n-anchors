@tool
class_name MooringPost
extends StaticBody3D

## Visual style: timber cylinder (legacy), or the docking bollard mesh used on ship cleats
## (`MooringPoint`).
enum MooringVisual {
	TIMBER_POST,
	DOCKING_BOLLARD,
}

const DEFAULT_DOCKING_BOLLARD_MODEL := "res://resources/data/meshes/docks/docking_bollard.json"
const IMPORTED_BOLLARD := "res://resources/models/parts/port_kit/quay_tee_bollard.glb"
var _rope_anchor: Node3D
## Read-only imported harbour previews keep the model/collision only.
var service_discovery_enabled := true

## Line attachment height differs per visual; docking bollard follows `MooringPoint` cleat height.
@export var anchor_local_position: Vector3 = Vector3(0.0, 0.52, 0.0)


@export var mooring_visual: MooringVisual = MooringVisual.DOCKING_BOLLARD:
	set(v):
		if mooring_visual == v:
			return
		mooring_visual = v
		if is_node_ready():
			_rebuild()


@export var post_height: float = 1.1
@export var post_radius: float = 0.16
@export var post_color: Color = Color(0.18, 0.11, 0.06)

@export_file("*.json") var bollard_model_path: String = DEFAULT_DOCKING_BOLLARD_MODEL:
	set(v):
		bollard_model_path = v
		_rebuild_if_docking_bollard_visual()

@export_range(0.05, 4.0, 0.01) var bollard_scale: float = 1.0:
	set(v):
		bollard_scale = maxf(v, 0.05)
		_rebuild_if_docking_bollard_visual()

@export var bollard_rotation_degrees: Vector3 = Vector3(0.0, 90.0, 0.0):
	set(v):
		bollard_rotation_degrees = v
		_rebuild_if_docking_bollard_visual()

## Loose fit around `docking_bollard.json` at scale 1; scales with `bollard_scale` for rays / bump.
@export var bollard_collision_size: Vector3 = Vector3(0.62, 0.98, 0.62):
	set(v):
		bollard_collision_size = v
		_rebuild_if_docking_bollard_visual()

var _moor_interact_range: float = 3.2

## Editor gizmo radius around the rope anchor. Lines are ordered from the helm.
@export var interact_range: float:
	get:
		return _moor_interact_range
	set(v):
		_moor_interact_range = maxf(0.05, v)
		_refresh_editor_range_gizmo_deferred()


var _show_interact_sphere: bool = true

## Editor-only: translucent sphere at the mooring anchor; matches interact_range.
@export var show_editor_interact_range_gizmo: bool:
	get:
		return _show_interact_sphere
	set(v):
		_show_interact_sphere = v
		_refresh_editor_range_gizmo_deferred()

func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint() and service_discovery_enabled:
		add_to_group(MooringComponent.DOCK_MOORING_GROUP)


func get_anchor_global_position() -> Vector3:
	if is_instance_valid(_rope_anchor):
		return _rope_anchor.global_position
	return to_global(anchor_local_position)


func _rebuild_if_docking_bollard_visual() -> void:
	if is_node_ready() and mooring_visual == MooringVisual.DOCKING_BOLLARD:
		_rebuild()


func _refresh_editor_range_gizmo_deferred() -> void:
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_range_gizmo")


func _refresh_editor_range_gizmo() -> void:
	if not Engine.is_editor_hint():
		return
	var prev := get_node_or_null("EditorMooringInteractSphere")
	if prev != null:
		prev.queue_free()
	if not show_editor_interact_range_gizmo:
		return

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "EditorMooringInteractSphere"
	var sphere := SphereMesh.new()
	sphere.radius = interact_range
	sphere.height = interact_range * 2.0
	mesh_inst.mesh = sphere
	mesh_inst.position = anchor_local_position

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.72, 0.18, 0.12)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.no_depth_test = true
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mesh_inst)


func _rebuild() -> void:
	_rope_anchor = null
	for child in get_children():
		remove_child(child)
		child.queue_free()

	match mooring_visual:
		MooringVisual.DOCKING_BOLLARD:
			_rebuild_docking_bollard()
		_:
			_rebuild_timber_post()

	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_range_gizmo")


func _rebuild_docking_bollard() -> void:
	var sc := maxf(bollard_scale, 0.05)
	var box := CollisionShape3D.new()
	box.name = "PostCollision"
	var shape := BoxShape3D.new()
	shape.size = bollard_collision_size * sc
	box.shape = shape
	box.position = Vector3.UP * (shape.size.y * 0.5)
	add_child(box)

	var visual: Node3D
	if bollard_model_path == DEFAULT_DOCKING_BOLLARD_MODEL:
		visual = (load(IMPORTED_BOLLARD) as PackedScene).instantiate()
		SurfaceMaterialLibrary.apply(visual)
		visual.scale = Vector3.ONE * sc
		_rope_anchor = visual.find_child("RopeAnchor",true,false) as Node3D
		assert(_rope_anchor != null)
	else:
		visual = ModelCache.instance(bollard_model_path, sc)
	visual.name = "DockingBollard"
	visual.rotation_degrees = bollard_rotation_degrees
	add_child(visual)

	if Engine.is_editor_hint() and get_tree() != null:
		var esc := get_tree().edited_scene_root
		if esc != null:
			visual.owner = esc
			for child in visual.get_children():
				child.owner = esc


func _rebuild_timber_post() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = post_radius
	shape.height = post_height

	var collision := CollisionShape3D.new()
	collision.name = "PostCollision"
	collision.shape = shape
	collision.position = Vector3.UP * (post_height * 0.5)
	add_child(collision)

	var visual := MeshBuilder.cylinder(post_radius, post_height, post_color, 0.95, 0.0)
	visual.name = "PostVisual"
	visual.material_override = SurfaceMaterialLibrary.material("pallet_wood",post_color) if SurfaceMaterialLibrary.enabled else visual.material_override
	visual.position = Vector3.UP * (post_height * 0.5)
	add_child(visual)

	var cap := MeshBuilder.cylinder(post_radius * 1.28, 0.16, post_color.lightened(0.08), 0.9, 0.0)
	cap.name = "PostCap"
	cap.material_override = SurfaceMaterialLibrary.material("pallet_wood",post_color.lightened(.08)) if SurfaceMaterialLibrary.enabled else cap.material_override
	cap.position = Vector3.UP * post_height
	add_child(cap)
