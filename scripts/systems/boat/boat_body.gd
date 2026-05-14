@tool
class_name BoatBody
extends RigidBody3D

## Root node of every boat. Owns physics properties.
## Visuals and collision are handled by the MeshTransformer child component.
##
## Hull collision lives on layer "boat_hull" so the CharacterBody player does not
## directly push the RigidBody (infinite-mass kinematic vs dynamic = huge impulses).
## A thin AnimatableBody3D "WalkDeck" on the "world" layer follows the hull each
## physics step so the player still has a stable deck to stand on.

const LAYER_WORLD:     int = 1
const LAYER_BOAT_HULL: int = 2

@export_group("Physics")
## Mass in kilograms (test hull default — tune per vessel; buoyancy must balance this).
@export var hull_mass:           float = 22000.0:
	set(v):
		hull_mass = v
		mass = v
## Baseline linear damping (air resistance). Water resistance is handled by HydrodynamicsComponent.
@export var linear_damp_coeff:   float = 0.05:
	set(v):
		linear_damp_coeff = v
		linear_damp = v
## Baseline angular damping.
@export var angular_damp_coeff:  float = 0.05:
	set(v):
		angular_damp_coeff = v
		angular_damp = v

@export_group("Hull")
## Absolute uniform scale applied to the mesh. The physical hull_size is calculated automatically.
@export var mesh_scale: float = 1.0:
	set(v):
		mesh_scale = v
		if _transformer:
			_transformer.set("absolute_scale", v)
		if _model_assembler:
			_model_assembler.set("absolute_scale", v)
			_sync_hull_size_from_mesh()

var hull_size: Vector3 = Vector3(6.0, 2.0, 14.0)
var hull_center: Vector3 = Vector3.ZERO

const DEFAULT_HULL_JSON := "res://resources/data/meshes/ship_hull_flat_deck.json"

@export_file("*.json") var model_data_path: String:
	set(v):
		model_data_path = v
		if _model_assembler:
			_model_assembler.set("model_data_path", v)
			_sync_hull_size_from_mesh()

@export_file("*.json") var mesh_data_path: String = DEFAULT_HULL_JSON:
	set(v):
		mesh_data_path = v
		if _transformer:
			_transformer.set("mesh_data_path", v)
			_sync_hull_size_from_mesh()

@export var mesh_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0):
	set(v):
		mesh_rotation_degrees = v
		if _transformer:
			_transformer.set("mesh_rotation_degrees", v)
			_sync_hull_size_from_mesh()

var _transformer: Node3D
var _model_assembler: ModelAssembler
var _walk_deck:   AnimatableBody3D


func _ready() -> void:
	mass         = hull_mass
	linear_damp  = linear_damp_coeff
	angular_damp = angular_damp_coeff

	# Hull vs world: player mask excludes boat_hull so CharacterBody does not shove the ship.
	collision_layer = LAYER_BOAT_HULL
	collision_mask  = LAYER_WORLD

	var pm := PhysicsMaterial.new()
	pm.bounce = 0.0
	physics_material_override = pm

	# Lower the center of mass to provide natural righting moment (stabilization)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -hull_size.y * 0.4, 0.0)

	_ensure_model()

	if not Engine.is_editor_hint():
		call_deferred("_ensure_walk_deck")


func _exit_tree() -> void:
	if _walk_deck != null and is_instance_valid(_walk_deck):
		_walk_deck.queue_free()
		_walk_deck = null


func _integrate_forces(_state: PhysicsDirectBodyState3D) -> void:
	if Engine.is_editor_hint() or _walk_deck == null or not is_instance_valid(_walk_deck):
		return
	_sync_walk_deck_transform()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		var missing_single := _transformer == null or not is_instance_valid(_transformer)
		if _model_assembler == null and missing_single:
			_ensure_model()
		return

	if _walk_deck == null or not is_instance_valid(_walk_deck):
		_ensure_walk_deck()


func _ensure_model() -> void:
	if not model_data_path.is_empty():
		_ensure_model_assembler()
	else:
		_ensure_transformer()


func _ensure_model_assembler() -> void:
	_clear_single_mesh_transformer()
	_model_assembler = get_node_or_null("ModelAssembler") as ModelAssembler
	if _model_assembler == null:
		_model_assembler = ModelAssembler.new()
		_model_assembler.name = "ModelAssembler"
		add_child(_model_assembler)
		if Engine.is_editor_hint():
			_model_assembler.owner = get_tree().edited_scene_root

	_model_assembler.collision_parent_path = NodePath("..")
	_model_assembler.absolute_scale = mesh_scale
	_model_assembler.model_data_path = model_data_path
	_sync_hull_size_from_mesh()


func _ensure_transformer() -> void:
	_clear_model_assembler()
	_transformer = get_node_or_null("MeshTransformer")
	if _transformer == null:
		var transformer_script := load("res://scripts/systems/mesh_transformer.gd")
		_transformer = Node3D.new()
		_transformer.set_script(transformer_script)
		_transformer.name = "MeshTransformer"
		add_child(_transformer)
		if Engine.is_editor_hint():
			_transformer.owner = get_tree().edited_scene_root

	_transformer.set("mesh_data_path", mesh_data_path)
	_transformer.set("absolute_scale", mesh_scale)
	_transformer.set("mesh_color", Color(0.005, 0.005, 0.005))
	_transformer.set("mesh_rotation_degrees", mesh_rotation_degrees)
	_sync_hull_size_from_mesh()


func _sync_hull_size_from_mesh() -> void:
	if _model_assembler != null and is_instance_valid(_model_assembler):
		var physics_part := _model_assembler.get_first_part_by_role("physics_body")
		if physics_part != null:
			_sync_hull_size_from_part(physics_part)
			return

	if _transformer and "actual_size" in _transformer:
		_sync_hull_size_from_part(_transformer)


func _sync_hull_size_from_part(part: Node) -> void:
	if not ("actual_size" in part):
		return
	var size: Vector3 = part.get("actual_size")
	if size.length_squared() <= 0.01:
		return

	hull_size = size
	if "actual_center" in part:
		hull_center = part.get("actual_center")
	else:
		hull_center = Vector3.ZERO
	# _ready() runs before JSON bounds are known. Keep stability tied to the
	# real mesh-derived hull height, not the fallback default.
	center_of_mass = hull_center + Vector3(0.0, -hull_size.y * 0.4, 0.0)
	_resize_walk_deck_shape()


func place_at_waterline(water_y: float, draft_fraction: float = 0.45) -> void:
	_ensure_model()
	_sync_hull_size_from_mesh()
	var draft := hull_size.y * clampf(draft_fraction, 0.0, 1.0)
	var hull_bottom_y := hull_center.y - hull_size.y * 0.5
	global_position.y = water_y - draft - hull_bottom_y
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _clear_single_mesh_transformer() -> void:
	if _transformer != null and is_instance_valid(_transformer):
		_transformer.queue_free()
		_transformer = null
	for child in get_children():
		if child.name.begins_with("Generated_MeshTransformer_"):
			child.queue_free()


func _clear_model_assembler() -> void:
	if _model_assembler != null and is_instance_valid(_model_assembler):
		_model_assembler.queue_free()
		_model_assembler = null
	for child in get_children():
		if child.name.begins_with("Generated_ModelPart_"):
			child.queue_free()


func _ensure_walk_deck() -> void:
	if Engine.is_editor_hint():
		return
	if _walk_deck != null and is_instance_valid(_walk_deck):
		return

	_walk_deck = AnimatableBody3D.new()
	_walk_deck.name = "WalkDeck"
	_walk_deck.sync_to_physics = true
	_walk_deck.collision_layer = LAYER_WORLD
	_walk_deck.collision_mask  = LAYER_WORLD

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _walk_deck_box_size()
	cs.shape = box
	_walk_deck.add_child(cs)

	var parent_node := get_parent()
	if parent_node != null:
		parent_node.add_child(_walk_deck)
	else:
		add_child(_walk_deck)

	_sync_walk_deck_transform()


func _walk_deck_box_size() -> Vector3:
	return Vector3(hull_size.x * 0.96, 0.14, hull_size.z * 0.96)


func _walk_deck_local_origin() -> Vector3:
	# Slightly above geometric deck so the slab clears the hull collider visually.
	return hull_center + Vector3(0.0, hull_size.y * 0.5 + 0.08, 0.0)


func _sync_walk_deck_transform() -> void:
	if _walk_deck == null or not is_instance_valid(_walk_deck):
		return
	_walk_deck.global_transform = global_transform * Transform3D(Basis(), _walk_deck_local_origin())


func _resize_walk_deck_shape() -> void:
	if _walk_deck == null or not is_instance_valid(_walk_deck):
		return
	var cs := _walk_deck.get_child(0) as CollisionShape3D
	if cs != null and cs.shape is BoxShape3D:
		(cs.shape as BoxShape3D).size = _walk_deck_box_size()
