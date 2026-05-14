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
const LAYER_BOAT_WALK: int = 4
const LAYER_PLAYER:    int = 8
const MERGED_COLLIDER_NAME := "MergedBoatCollider"
const WALK_DECK_COLLIDER_NAME := "WalkDeckCollider"
const WALK_MODEL_COLLIDER_NAME := "WalkModelCollider"

@export_group("Physics")
## Manual mass override (kg). Used when `auto_mass_from_hull = false`. Ignored otherwise.
## Realistic ship mass = displaced water volume × water density. A 14 m steel workboat is
## ~15–60 t; a 28 m coastal cargo is ~120–250 t. Don't ad-hoc weight to fight wave wobble —
## tune `Stability` group + buoyancy multiplier instead.
@export var hull_mass:           float = 22000.0:
	set(v):
		hull_mass = v
		_refresh_mass()
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

@export_group("Mass model")
## When true, hull share = water_density × hull bbox area × design draft × block coefficient
## (Archimedes for a loaded hull). Component masses below are added on top.
## Block coefficient and water density are read from BuoyancyComponent so lift and weight
## stay consistent — buoyancy_multiplier ≈ 1.0 should leave the hull at design_draft_fraction.
@export var auto_mass_from_hull: bool = false:
	set(v):
		auto_mass_from_hull = v
		_refresh_mass()
## Targeted equilibrium draft (fraction of hull height submerged) used by auto mass.
## A laden coastal cargo sits ~0.4–0.5; a planing skiff ~0.15–0.25.
@export_range(0.05, 0.95, 0.01) var design_draft_fraction: float = 0.42:
	set(v):
		design_draft_fraction = clampf(v, 0.05, 0.95)
		_refresh_mass()

@export_group("Component masses (kg)")
## Engine + drivetrain (steel block, low and aft).
@export var engine_mass: float = 0.0:
	set(v):
		engine_mass = maxf(0.0, v)
		_refresh_mass()
## Permanent ballast / iron keel — adds mass; set `artificial_keel_extra_depth` to bias COM.
@export var keel_ballast_mass: float = 0.0:
	set(v):
		keel_ballast_mass = maxf(0.0, v)
		_refresh_mass()
## Fuel + freshwater + lubes + stores.
@export var fuel_stores_mass: float = 0.0:
	set(v):
		fuel_stores_mass = maxf(0.0, v)
		_refresh_mass()
## Cargo / payload (variable per voyage). Plays into mass; visual cargo lives in the model.
@export var cargo_mass: float = 0.0:
	set(v):
		cargo_mass = maxf(0.0, v)
		_refresh_mass()

@export_group("Stability (artificial keel)")
## Push the rigid-body center of mass below the mesh geometric center (ballast / keel).
## Vertical offset from `hull_center` = `hull_size.y * center_of_mass_depth_fraction`
## + `artificial_keel_extra_depth` (metres, along body −Y).
var _center_of_mass_depth_fraction: float = 0.4

@export_range(0.0, 1.5, 0.01) var center_of_mass_depth_fraction: float:
	get:
		return _center_of_mass_depth_fraction
	set(v):
		_center_of_mass_depth_fraction = clampf(v, 0.0, 2.0)
		_refresh_center_of_mass()

## Additional downward shift in metres (dense keel, fuel, engines) — same axis as depth fraction.
var _artificial_keel_extra_depth: float = 0.0

@export_range(0.0, 10.0, 0.01) var artificial_keel_extra_depth: float:
	get:
		return _artificial_keel_extra_depth
	set(v):
		_artificial_keel_extra_depth = maxf(0.0, v)
		_refresh_center_of_mass()

@export_group("Hull")
## Absolute uniform scale applied to the mesh. The physical hull_size is calculated automatically.
@export var mesh_scale: float = 1.0:
	set(v):
		mesh_scale = v
		if _transformer:
			_transformer.set("absolute_scale", v)
			_build_merged_collision()
		if _model_assembler:
			_model_assembler.set("absolute_scale", v)
			_sync_hull_size_from_mesh()
			_build_merged_collision()

var hull_size: Vector3 = Vector3(6.0, 2.0, 14.0)
var hull_center: Vector3 = Vector3.ZERO

const DEFAULT_HULL_JSON := "res://resources/data/meshes/ship_hull_flat_deck.json"

@export_file("*.json") var model_data_path: String:
	set(v):
		model_data_path = v
		if _model_assembler:
			_model_assembler.set("model_data_path", v)
			_sync_hull_size_from_mesh()
			_build_merged_collision()

@export_file("*.json") var mesh_data_path: String = DEFAULT_HULL_JSON:
	set(v):
		mesh_data_path = v
		if _transformer:
			_transformer.set("mesh_data_path", v)
			_sync_hull_size_from_mesh()
			_build_merged_collision()

@export var mesh_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0):
	set(v):
		mesh_rotation_degrees = v
		if _transformer:
			_transformer.set("mesh_rotation_degrees", v)
			_sync_hull_size_from_mesh()
			_build_merged_collision()

var _transformer: Node3D
var _model_assembler: ModelAssembler
var _walk_deck:   AnimatableBody3D

## Mooring positional solve runs here (inside Jolt/Godot integration), not via impulses.
var _mooring_integrate: Callable = Callable()


func mount_mooring_integrate(callback: Callable) -> void:
	_mooring_integrate = callback


func clear_mooring_integrate() -> void:
	_mooring_integrate = Callable()


func _ready() -> void:
	linear_damp  = linear_damp_coeff
	angular_damp = angular_damp_coeff

	# Hull vs world: player mask excludes boat_hull so CharacterBody does not shove the ship.
	collision_layer = LAYER_BOAT_HULL
	collision_mask  = LAYER_WORLD

	var pm := PhysicsMaterial.new()
	pm.bounce = 0.0
	physics_material_override = pm

	_ensure_model()
	_build_merged_collision()
	_refresh_mass()

	if not Engine.is_editor_hint():
		call_deferred("_ensure_walk_deck")


func _exit_tree() -> void:
	if _walk_deck != null and is_instance_valid(_walk_deck):
		_walk_deck.queue_free()
		_walk_deck = null


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not Engine.is_editor_hint() and _mooring_integrate.is_valid():
		_mooring_integrate.call(state)

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
	_model_assembler.build_part_colliders = false
	_model_assembler.absolute_scale = mesh_scale
	_model_assembler.model_data_path = model_data_path
	_sync_hull_size_from_mesh()
	_build_merged_collision()


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
	_transformer.set("create_collision", false)
	_sync_hull_size_from_mesh()
	_build_merged_collision()


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
	# _ready() runs before JSON bounds are known. Keep stability and mass tied to the
	# real mesh-derived hull dimensions, not the fallback default.
	_refresh_mass()
	_resize_walk_deck_shape()


func _refresh_center_of_mass() -> void:
	if not is_node_ready():
		return
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var down: float = hull_size.y * _center_of_mass_depth_fraction + _artificial_keel_extra_depth
	center_of_mass = hull_center + Vector3(0.0, -down, 0.0)


func _refresh_mass() -> void:
	if not is_node_ready():
		return
	var components: float = engine_mass + keel_ballast_mass + fuel_stores_mass + cargo_mass
	var hull_share: float
	if auto_mass_from_hull:
		hull_share = _hull_displacement_kg()
	else:
		hull_share = hull_mass
	mass = maxf(hull_share + components, 1.0)
	_refresh_center_of_mass()


## Archimedes mass: the volume of water the hull displaces at design draft.
## Reads block coefficient and water density from BuoyancyComponent so lift and weight stay
## in lockstep — buoyancy_multiplier ≈ 1.0 should rest the hull at design_draft_fraction.
func _hull_displacement_kg() -> float:
	var rho: float = _buoyancy_field("water_density", 1000.0)
	var coeff: float = _buoyancy_field("block_coefficient", 0.7)
	var draft: float = maxf(hull_size.y * design_draft_fraction, 0.0)
	var area: float = maxf(hull_size.x * hull_size.z, 0.0)
	return area * draft * coeff * rho


func _buoyancy_field(field: String, fallback: float) -> float:
	var b: Node = get_node_or_null("BuoyancyComponent")
	if b != null and field in b:
		return float(b.get(field))
	return fallback


func get_total_mass_kg() -> float:
	return mass


func get_hull_displacement_kg() -> float:
	return _hull_displacement_kg()


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
	_walk_deck.collision_layer = LAYER_BOAT_WALK
	_walk_deck.collision_mask  = LAYER_PLAYER

	var cs := CollisionShape3D.new()
	cs.name = WALK_DECK_COLLIDER_NAME
	var box := BoxShape3D.new()
	box.size = _walk_deck_box_size()
	cs.shape = box
	_walk_deck.add_child(cs)
	_add_walk_model_collision()

	var parent_node := get_parent()
	if parent_node != null:
		parent_node.add_child(_walk_deck)
	else:
		add_child(_walk_deck)

	_walk_deck.set_meta("_boat_owner", self)

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
	var cs := _walk_deck.get_node_or_null(WALK_DECK_COLLIDER_NAME) as CollisionShape3D
	if cs != null and cs.shape is BoxShape3D:
		(cs.shape as BoxShape3D).size = _walk_deck_box_size()
	_add_walk_model_collision()


func _add_walk_model_collision() -> void:
	if _walk_deck == null or not is_instance_valid(_walk_deck):
		return

	var existing := _walk_deck.get_node_or_null(WALK_MODEL_COLLIDER_NAME)
	if existing != null:
		_walk_deck.remove_child(existing)
		existing.free()

	var boat_faces := _walk_collision_faces()
	if boat_faces.size() < 3:
		return

	var origin := _walk_deck_local_origin()
	var walk_faces: Array[Vector3] = []
	for point in boat_faces:
		walk_faces.append(point - origin)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(walk_faces)

	var collision := CollisionShape3D.new()
	collision.name = WALK_MODEL_COLLIDER_NAME
	collision.shape = shape
	_walk_deck.add_child(collision)


func _build_merged_collision() -> void:
	_clear_merged_collision()

	var points := _merged_collision_points()
	if points.size() < 4:
		return

	var shape := ConvexPolygonShape3D.new()
	shape.points = points

	var collision := CollisionShape3D.new()
	collision.name = MERGED_COLLIDER_NAME
	collision.shape = shape
	add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root
	_add_walk_model_collision()


func _merged_collision_points() -> Array[Vector3]:
	if _model_assembler != null and is_instance_valid(_model_assembler):
		return _model_assembler.get_collision_points_in(self)
	if _transformer != null and is_instance_valid(_transformer):
		if _transformer.has_method("get_collision_points_in"):
			return _transformer.call("get_collision_points_in", self)
	return []


func _walk_collision_faces() -> Array[Vector3]:
	if _model_assembler != null and is_instance_valid(_model_assembler):
		return _model_assembler.get_collision_faces_in(self)
	if _transformer != null and is_instance_valid(_transformer):
		if _transformer.has_method("get_collision_faces_in"):
			return _transformer.call("get_collision_faces_in", self)
	return []


func _clear_merged_collision() -> void:
	for child in get_children():
		if child.name == MERGED_COLLIDER_NAME:
			remove_child(child)
			child.free()
		elif child is CollisionShape3D and child.name.begins_with("Generated_ModelPart_"):
			remove_child(child)
			child.free()
		elif child is CollisionShape3D and child.name.begins_with("Generated_MeshTransformer_"):
			remove_child(child)
			child.free()
