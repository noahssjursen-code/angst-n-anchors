## BridgeInteractable — helm access for the parent vessel.
## Press F while looking at any part of the boat (hull, deck, wheelhouse) in range.

class_name BridgeInteractable
extends Node3D

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

func _init() -> void:
	add_to_group(VehicleGroups.SHIP_OWNER_ONLY)
	add_to_group(VehicleGroups.BOARDING_HIDES_OCCUPANT)


signal player_boarded
signal player_exited

const BOARDING_RAY_COLLISION_MASK: int = (1 << 0) | (1 << 1) | (1 << 2)

@export var look_distance: float = 45.0
@export var interact_range: float = 10.0
@export var prompt_text: String = "Press F to helm"
@export var exit_deck_offset: Vector2 = Vector2(0.0, 2.0)

var _occupied: bool = false
var _player: CharacterBody3D = null
var _prompt_layer: CanvasLayer
var _prompt_label: Label
var _boat_cam: Camera3D = null
var _boat_controller: BoatController = null
var _boat_rigid_cached: RigidBody3D = null


func _ready() -> void:
	_cache_boat_nodes()
	_ensure_prompt_ui()


func _process(_delta: float) -> void:
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _occupied:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_exit()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("interact") and _boarding_player() != null:
			_board()
			get_viewport().set_input_as_handled()


func _boarding_player() -> CharacterBody3D:
	var boat := _boat_rigid_body()
	if boat == null:
		return null
	for node: Node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body == null:
			continue
		if not _player_near_boat(body, boat):
			continue
		if _player_looking_at_boat(body, boat):
			return body
	return null


func _player_near_boat(body: CharacterBody3D, boat: RigidBody3D) -> bool:
	var local := boat.to_local(body.global_position)
	var body_boat := boat as BoatBody
	if body_boat != null and body_boat.hull_stations != null:
		var half_len := body_boat.hull_stations.length_m * body_boat.mesh_scale * 0.5
		var half_beam := body_boat.get_half_beam_m()
		var margin := maxf(interact_range, 6.0)
		return absf(local.x) <= half_beam + margin and absf(local.z) <= half_len + margin
	return body.global_position.distance_to(boat.global_position) <= interact_range


func _player_looking_at_boat(body: CharacterBody3D, boat: RigidBody3D) -> bool:
	var camera := body.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false

	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * look_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, BOARDING_RAY_COLLISION_MASK)
	query.exclude = [body.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider := hit.get("collider") as Node
	return _collider_belongs_to_boat(collider, boat)


func _collider_belongs_to_boat(collider: Node, boat: RigidBody3D) -> bool:
	if collider == null:
		return false
	if collider == boat or boat.is_ancestor_of(collider):
		return true
	var owner_boat := _collision_owning_boat(collider)
	return owner_boat != null and owner_boat == boat


func _board() -> void:
	_player = _boarding_player()
	if _player == null:
		return
	_occupied = true
	if _prompt_label != null:
		_prompt_label.visible = false
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player.velocity = Vector3.ZERO
	if _boat_cam != null:
		_boat_cam.current = true
	if _boat_controller != null:
		_boat_controller.activate()
	player_boarded.emit()


func _exit() -> void:
	_occupied = false
	if _player != null:
		_place_player_on_deck(_player)
		_player.set_physics_process(true)
		_player.set_process_unhandled_input(true)
		var player_cam := _player.get_node_or_null("Camera3D") as Camera3D
		if player_cam != null:
			player_cam.current = true
		_player = null
	if _boat_controller != null:
		_boat_controller.deactivate()
	player_exited.emit()


func _place_player_on_deck(body: CharacterBody3D) -> void:
	var boat := _boat_rigid_body()
	if boat == null:
		return
	var hull_size := Vector3(6.0, 2.0, 14.0)
	if "hull_size" in boat:
		hull_size = boat.get("hull_size")
	var half := hull_size * 0.5
	var local_exit := Vector3(
		clampf(exit_deck_offset.x, -half.x * 0.85, half.x * 0.85),
		half.y + 0.5,
		clampf(exit_deck_offset.y, -half.z * 0.85, half.z * 0.85)
	)
	body.global_position = boat.to_global(local_exit)
	body.velocity = Vector3.ZERO


func _boat_rigid_body() -> RigidBody3D:
	if _boat_rigid_cached != null and is_instance_valid(_boat_rigid_cached):
		return _boat_rigid_cached
	var p := get_parent()
	while p != null:
		if p is RigidBody3D:
			_boat_rigid_cached = p as RigidBody3D
			return _boat_rigid_cached
		p = p.get_parent()
	return null


func _cache_boat_nodes() -> void:
	var rb := _boat_rigid_body()
	if rb == null:
		return
	_boat_cam = rb.get_node_or_null("BoatCamera") as Camera3D
	_boat_controller = rb.get_node_or_null("BoatController") as BoatController


func _collision_owning_boat(collider: Node) -> RigidBody3D:
	if collider == null:
		return null
	var co := collider as CollisionObject3D
	if co != null and co.has_meta("_boat_owner"):
		var owner_node = co.get_meta("_boat_owner")
		if owner_node is RigidBody3D:
			return owner_node as RigidBody3D
	var p := collider
	while p != null:
		if p is RigidBody3D:
			return p as RigidBody3D
		p = p.get_parent()
	return null


func _ensure_prompt_ui() -> void:
	if _prompt_layer != null:
		return
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "BoardPromptLayer"
	add_child(_prompt_layer)
	_prompt_label = Label.new()
	_prompt_label.name = "BoardPrompt"
	_prompt_label.text = prompt_text
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.visible = false
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -180.0
	_prompt_label.offset_right = 180.0
	_prompt_label.offset_top = -92.0
	_prompt_label.offset_bottom = -48.0
	_prompt_layer.add_child(_prompt_label)


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	_prompt_label.visible = not _occupied and _boarding_player() != null


func is_occupied() -> bool:
	return _occupied
