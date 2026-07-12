## BridgeInteractable — helm access for the parent vessel.
## Press F while looking at this station's interact volume (player-placed helm brick).

class_name BridgeInteractable
extends Node3D

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

func _init() -> void:
	add_to_group(VehicleGroups.SHIP_OWNER_ONLY)
	add_to_group(VehicleGroups.BOARDING_HIDES_OCCUPANT)


signal player_boarded
signal player_exited

const LAYER_WORLD := 1

@export var look_distance: float = 4.0
@export var interact_range: float = 2.8
@export var prompt_text: String = "Press F to helm"
@export var exit_deck_offset: Vector2 = Vector2(0.0, 1.2)
@export var interaction_volume_size: Vector3 = Vector3(1.0, 1.4, 1.0)

var _occupied: bool = false
var _player: CharacterBody3D = null
var _prompt_layer: CanvasLayer
var _prompt_label: Label
var _boat_cam: Camera3D = null
var _boat_controller: BoatController = null
var _boat_rigid_cached: RigidBody3D = null
var _interact_area: Area3D


func _ready() -> void:
	_cache_boat_nodes()
	_ensure_interact_area()
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
		if HullLadderBoard.blocks_helm_for(body):
			continue
		if global_position.distance_to(body.global_position) > interact_range:
			continue
		if _player_looking_at_station(body):
			return body
	return null


func _player_looking_at_station(body: CharacterBody3D) -> bool:
	## Camera ray must hit this helm's Area — not the hull, deck, or a door.
	if _interact_area == null:
		return false
	var camera := body.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * look_distance
	var space := get_world_3d().direct_space_state

	var area_q := PhysicsRayQueryParameters3D.create(from, to)
	area_q.exclude = [body.get_rid()]
	area_q.collide_with_areas = true
	area_q.collide_with_bodies = false
	var area_hit := space.intersect_ray(area_q)
	if area_hit.is_empty() or area_hit.get("collider") != _interact_area:
		return false

	var body_q := PhysicsRayQueryParameters3D.create(from, to)
	body_q.exclude = [body.get_rid()]
	body_q.collide_with_areas = false
	body_q.collide_with_bodies = true
	var body_hit := space.intersect_ray(body_q)
	if body_hit.is_empty():
		return true
	var area_dist := from.distance_to(area_hit.position as Vector3)
	var body_dist := from.distance_to(body_hit.position as Vector3)
	## Solid closer than the helm (door leaf / wall) wins.
	return body_dist + 0.05 >= area_dist


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
		if _boat_cam is BoatCamera:
			(_boat_cam as BoatCamera).begin_helm(self)
	if _boat_controller != null:
		_boat_controller.activate()
	player_boarded.emit()


func _exit() -> void:
	_occupied = false
	if _boat_cam is BoatCamera:
		(_boat_cam as BoatCamera).end_helm()
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
	## Step back from the wheel in station-local +Z (behind the helm).
	var local_exit := Vector3(exit_deck_offset.x, 0.15, exit_deck_offset.y)
	body.global_position = to_global(local_exit)
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


func _ensure_interact_area() -> void:
	_interact_area = get_node_or_null("HelmInteractionArea") as Area3D
	if _interact_area == null:
		_interact_area = Area3D.new()
		_interact_area.name = "HelmInteractionArea"
		add_child(_interact_area)
	_interact_area.position = Vector3(0.0, 0.2, -0.1)
	_interact_area.collision_layer = LAYER_WORLD
	_interact_area.collision_mask = 0
	_interact_area.monitoring = false
	_interact_area.monitorable = true
	var col := _interact_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		_interact_area.add_child(col)
	var box := col.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		col.shape = box
	box.size = interaction_volume_size


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
