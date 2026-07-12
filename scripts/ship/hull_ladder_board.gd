class_name HullLadderBoard
extends Node3D

## Climb interactable spawned with a hull_ladder brick.
## Press F near the quay-side foot to board the deck; press F at the deck pad to climb down.
## Uses `_input` (not unhandled) so it wins over BridgeInteractable helm boarding.

signal boarded
signal disembarked

const GROUP := "hull_ladder_board"

@export var interact_range: float = 3.2
@export var prompt_board: String = "Press F — climb aboard"
@export var prompt_down: String = "Press F — climb down"

## Ladder hangs in local −X; drop matches BrickCatalog visual.
const DROP_M := 4.2

var _prompt_layer: CanvasLayer
var _prompt_label: Label


func _ready() -> void:
	add_to_group(GROUP)
	_ensure_prompt_ui()


func _process(_delta: float) -> void:
	_update_prompt()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var player := nearby_player()
	if player == null:
		return
	if player_on_deck(player):
		_climb_down(player)
	else:
		_climb_up(player)
	get_viewport().set_input_as_handled()


## True when this ladder would handle interact for the player (helm must yield).
func would_handle(player: CharacterBody3D) -> bool:
	return player != null and nearby_player() == player


static func blocks_helm_for(player: CharacterBody3D) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	for node in player.get_tree().get_nodes_in_group(GROUP):
		var ladder := node as HullLadderBoard
		if ladder != null and ladder.would_handle(player):
			return true
	return false


func _climb_up(player: CharacterBody3D) -> void:
	player.global_position = deck_stand_global()
	player.velocity = Vector3.ZERO
	boarded.emit()


func _climb_down(player: CharacterBody3D) -> void:
	player.global_position = quay_stand_global()
	player.velocity = Vector3.ZERO
	disembarked.emit()


func nearby_player() -> CharacterBody3D:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body == null:
			continue
		if player_on_deck(body):
			if body.global_position.distance_to(deck_stand_global()) <= interact_range:
				return body
		elif body.global_position.distance_to(quay_stand_global()) <= interact_range:
			return body
	return null


func player_on_deck(player: CharacterBody3D) -> bool:
	var top := deck_stand_global()
	return player.global_position.y > top.y - 1.5 \
		and player.global_position.distance_to(top) < interact_range + 2.0


func deck_stand_global() -> Vector3:
	## Stand on the inboard half of the pad.
	return global_transform * Vector3(0.35, 0.15, 0.0)


func quay_stand_global() -> Vector3:
	## Stand at the foot plate outboard of the hull.
	return global_transform * Vector3(-1.4, -DROP_M + 0.15, 0.0)


func _ensure_prompt_ui() -> void:
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.layer = 40
	add_child(_prompt_layer)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_top = 0.78
	_prompt_label.anchor_bottom = 0.78
	_prompt_label.offset_left = -220.0
	_prompt_label.offset_right = 220.0
	_prompt_label.offset_top = -18.0
	_prompt_label.offset_bottom = 18.0
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	_prompt_label.visible = false
	_prompt_layer.add_child(_prompt_label)


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	var player := nearby_player()
	if player == null:
		_prompt_label.visible = false
		return
	_prompt_label.text = prompt_down if player_on_deck(player) else prompt_board
	_prompt_label.visible = true
