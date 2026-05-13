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
@export var hull_size: Vector3 = Vector3(6.0, 2.0, 14.0):
	set(v):
		hull_size = v
		if _transformer:
			_transformer.set("target_size", v)
		_resize_walk_deck_shape()

const DEFAULT_HULL_JSON := "res://resources/data/meshes/ship_hull_flat_deck.json"

@export_file("*.json") var mesh_data_path: String = DEFAULT_HULL_JSON:
	set(v):
		mesh_data_path = v
		if _transformer:
			_transformer.set("mesh_data_path", v)

@export var mesh_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0):
	set(v):
		mesh_rotation_degrees = v
		if _transformer:
			_transformer.set("mesh_rotation_degrees", v)

var _transformer: Node3D
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

	_ensure_transformer()

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
		_ensure_transformer()
		return

	if _walk_deck == null or not is_instance_valid(_walk_deck):
		_ensure_walk_deck()


func _ensure_transformer() -> void:
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
	_transformer.set("target_size", hull_size)
	_transformer.set("mesh_color", Color(0.18, 0.20, 0.22))
	_transformer.set("mesh_rotation_degrees", mesh_rotation_degrees)


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
	return Vector3(0.0, hull_size.y * 0.5 + 0.08, 0.0)


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
