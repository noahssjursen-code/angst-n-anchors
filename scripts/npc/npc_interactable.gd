class_name NpcInteractable
extends NpcBase

## NPC the player can talk to. Adds a child StaticBody3D + capsule collider
## so the camera-forward raycast hit-tests against the figure. The body is
## a child of the Node3D root, not the root itself, so the player can never
## physically bump into the NPC (mass-less, immovable, no awkward shoving).
##
## Subclasses implement `_on_interact()` (called when player presses interact
## while looking at the NPC within `interact_range`). No game panel is installed.

const LAYER_WORLD := 1

@export var interact_range: float = 4.0
## Harbour services now live in the tablet. Keep the established service
## controllers, without constructing a character, collider or input listener.
@export var tablet_only := true

signal interaction_requested

@export var prompt_text: String = "Press F"

var _body:         StaticBody3D


func _ready() -> void:
	if tablet_only:
		add_to_group("port_tablet_service")
		set_process_unhandled_input(false)
		return
	super._ready()
	_build_collider()
	if not Engine.is_editor_hint(): add_to_group("port_service_npc")


func _build_collider() -> void:
	_body                  = StaticBody3D.new()
	_body.name             = "InteractBody"
	_body.collision_layer  = LAYER_WORLD
	_body.collision_mask   = 0
	add_child(_body)

	var capsule    := CapsuleShape3D.new()
	capsule.radius = 0.15
	capsule.height = 1.70
	var col        := CollisionShape3D.new()
	col.name       = "BodyShape"
	col.shape      = capsule
	col.position   = Vector3(0.0, 0.85, 0.0)
	_body.add_child(col)

	if Engine.is_editor_hint():
		_own_subtree(_body)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or event.is_echo():
		return
	if GameMenu.is_modal_open():
		return
	if event.is_action_pressed("interact") and _can_interact():
		_on_interact()
		get_viewport().set_input_as_handled()


func _can_interact() -> bool:
	var player := _nearest_player()
	if player == null:
		return false
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false
	var from  := camera.global_position
	var to    := from - camera.global_transform.basis.z * interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude             = [player.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas  = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	# Collider is our inner StaticBody3D — check it's the right one (ours).
	return collider == _body or (collider != null and is_ancestor_of(collider))


func _nearest_player() -> CharacterBody3D:
	if tablet_only:return _nearest_player_in(600.0)
	return _nearest_player_in(interact_range)


func _on_interact() -> void:
	interaction_requested.emit()
	var menu := get_node_or_null("/root/GameMenu")
	if menu != null and menu.has_method("open_service"):
		menu.open_service(self)
