@tool
class_name CaptainsChair
extends Node3D

## The helm interaction point. When the player presses E within range,
## they take control of the boat: player movement is suspended, the boat
## camera activates, and BoatController starts reading input.
## Press E or Escape to exit.

signal player_boarded
signal player_exited

@export var interact_range: float = 2.8
@export var look_distance: float = 35.0
@export var look_dot_threshold: float = 0.72
@export var prompt_text: String = "Press E to board"
## Local X/Z deck position used when leaving the helm. Y is calculated from
## the mesh-derived hull height so the player lands on top of the current deck.
@export var exit_deck_offset: Vector2 = Vector2(-3.4, -8.0)

var _occupied: bool = false
var _player:   CharacterBody3D = null
var _prompt_layer: CanvasLayer
var _prompt_label: Label

@onready var _boat_cam:   Camera3D    = get_node_or_null("../BoatCamera")
@onready var _controller: BoatController = get_node_or_null("../BoatController")


func _ready() -> void:
	if not Engine.is_editor_hint():
		_ensure_prompt_ui()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _occupied:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_exit()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("interact") and _boarding_player() != null:
			_board()
			get_viewport().set_input_as_handled()


func _nearest_player_in_range() -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body and _distance_to_hull(body.global_position) <= interact_range:
			return body
	return null


func _distance_to_hull(world_pos: Vector3) -> float:
	var boat := get_parent() as Node3D
	if boat == null:
		return global_position.distance_to(world_pos)

	var hull_size := Vector3(6.0, 2.0, 14.0)
	if "hull_size" in boat:
		hull_size = boat.get("hull_size")

	var local_pos := boat.to_local(world_pos)
	var half := hull_size * 0.5
	var closest := Vector3(
		clampf(local_pos.x, -half.x, half.x),
		clampf(local_pos.y, -half.y, half.y),
		clampf(local_pos.z, -half.z, half.z)
	)
	return local_pos.distance_to(closest)


func _boarding_player() -> CharacterBody3D:
	var body := _nearest_player_in_range()
	if body == null:
		return null
	if not _player_is_looking_at_boat(body):
		return null
	return body


func _player_is_looking_at_boat(body: CharacterBody3D) -> bool:
	var camera := body.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false

	var boat := get_parent() as Node3D
	if boat == null:
		return false

	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * look_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, 3)
	query.exclude = [body.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider := hit.get("collider") as Node
		if collider == boat:
			return true
		if collider != null and boat.is_ancestor_of(collider):
			return true
		var is_walk_deck := collider != null and collider.name == "WalkDeck"
		if is_walk_deck and collider.get_parent() == boat.get_parent():
			return true

	# Fallback: visual meshes are not ray-collidable. If the camera is aimed at the
	# closest point on the hull bounds, treat that as looking at the boat.
	var target := _closest_hull_point(camera.global_position)
	var to_target := target - camera.global_position
	if to_target.length_squared() <= 0.01:
		return true
	var forward := -camera.global_transform.basis.z.normalized()
	return forward.dot(to_target.normalized()) >= look_dot_threshold


func _closest_hull_point(world_pos: Vector3) -> Vector3:
	var boat := get_parent() as Node3D
	if boat == null:
		return global_position

	var hull_size := Vector3(6.0, 2.0, 14.0)
	if "hull_size" in boat:
		hull_size = boat.get("hull_size")

	var local_pos := boat.to_local(world_pos)
	var half := hull_size * 0.5
	var closest := Vector3(
		clampf(local_pos.x, -half.x, half.x),
		clampf(local_pos.y, -half.y, half.y),
		clampf(local_pos.z, -half.z, half.z)
	)
	return boat.to_global(closest)


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


func _board() -> void:
	_player = _boarding_player()
	if _player == null:
		return

	_occupied = true
	if _prompt_label != null:
		_prompt_label.visible = false

	# Suspend the player — they are now a passenger
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player.velocity = Vector3.ZERO

	if _boat_cam != null:
		_boat_cam.current = true

	if _controller != null:
		_controller.activate()

	player_boarded.emit()


func _exit() -> void:
	_occupied = false

	if _player != null:
		_place_player_on_deck(_player)
		_player.set_physics_process(true)
		_player.set_process_unhandled_input(true)

		# Return camera to player
		var player_cam := _player.get_node_or_null("Camera3D") as Camera3D
		if player_cam != null:
			player_cam.current = true

		_player = null

	if _controller != null:
		_controller.deactivate()

	player_exited.emit()


func _place_player_on_deck(body: CharacterBody3D) -> void:
	var boat := get_parent() as Node3D
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
