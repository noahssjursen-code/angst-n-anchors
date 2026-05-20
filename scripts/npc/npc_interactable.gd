class_name NpcInteractable
extends NpcBase

## NPC the player can talk to. Adds a child StaticBody3D + capsule collider
## so the camera-forward raycast hit-tests against the figure. The body is
## a child of the Node3D root, not the root itself, so the player can never
## physically bump into the NPC (mass-less, immovable, no awkward shoving).
##
## Subclasses implement `_on_interact()` (called when player presses interact
## while looking at the NPC within `interact_range`) and `_on_ui_cancel()`.

const LAYER_WORLD := 1

@export var interact_range: float = 4.0

@export var prompt_text: String = "Press F":
	set(v):
		prompt_text = v
		if _prompt != null:
			_prompt.text = v

var _open:         bool         = false
var _prompt:       Label
var _prompt_layer: CanvasLayer
var _body:         StaticBody3D


func _ready() -> void:
	super._ready()
	_build_collider()
	if not Engine.is_editor_hint():
		_build_prompt()


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


func _build_prompt() -> void:
	_prompt_layer      = CanvasLayer.new()
	_prompt_layer.name = "PromptLayer"
	add_child(_prompt_layer)

	_prompt                      = Label.new()
	_prompt.text                 = prompt_text
	_prompt.visible              = false
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left   = -220.0
	_prompt.offset_right  =  220.0
	_prompt.offset_top    = -148.0
	_prompt.offset_bottom = -108.0
	_prompt.add_theme_color_override("font_color", HudStyle.C_AMBER)
	_prompt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_prompt.add_theme_constant_override("shadow_as_outline", 1)
	_prompt_layer.add_child(_prompt)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _prompt == null:
		return
	_prompt.visible = not _open and _can_interact()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("ui_cancel") and _open:
		_on_ui_cancel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and not _open and _can_interact():
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
	return _nearest_player_in(interact_range)


func open_ui() -> void:
	_open            = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_ui() -> void:
	_open            = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_interact() -> void:
	pass


func _on_ui_cancel() -> void:
	close_ui()
