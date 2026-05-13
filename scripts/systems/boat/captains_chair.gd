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

var _occupied: bool = false
var _player:   CharacterBody3D = null

@onready var _boat_cam:   Camera3D    = get_node_or_null("../BoatCamera")
@onready var _controller: BoatController = get_node_or_null("../BoatController")


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _occupied:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_exit()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("interact") and _nearest_player_in_range() != null:
			_board()
			get_viewport().set_input_as_handled()


func _nearest_player_in_range() -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body and global_position.distance_to(body.global_position) <= interact_range:
			return body
	return null


func _board() -> void:
	_player = _nearest_player_in_range()
	if _player == null:
		return

	_occupied = true

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
