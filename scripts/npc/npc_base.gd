@tool
class_name NpcBase
extends Node3D

## Compatibility-facing character actor. Gameplay NPC subclasses still inherit
## NpcBase, but their Blender visual is the same CharacterVisual used by
## captain creation and replicated players.

@export var skin_color: Color = Color(0.72, 0.55, 0.40):
	set(value):
		skin_color = value
		_sync_legacy_colors()
@export var clothing_color: Color = Color(0.18, 0.20, 0.30):
	set(value):
		clothing_color = value
		_sync_legacy_colors()
@export var trousers_color: Color = Color(0.18, 0.18, 0.20):
	set(value):
		trousers_color = value
		_sync_legacy_colors()
## Body-only showcases opt out explicitly; gameplay and creator characters use
## the same fitted wardrobe path by default.
@export var wardrobe_enabled := true

var appearance: CharacterAppearance = CharacterAppearance.default_appearance()
var visual: CharacterVisual
var animator: CharacterAnimator
## Kept temporarily for crane/showcase code that asks for articulated parts.
var assembler: ModelAssembler
var _tools: Dictionary = {}
var _color_apply_blocked := false


func _ready() -> void:
	_build()


func _build() -> void:
	if visual != null and is_instance_valid(visual):
		visual.free()
	visual = CharacterVisual.new()
	visual.name = "CharacterVisual"
	visual.appearance = appearance.duplicate()
	visual.set_decorated(wardrobe_enabled)
	add_child(visual)
	assembler = visual.get_base_assembler()
	animator = CharacterAnimator.new()
	animator.name = "CharacterAnimator"
	add_child(animator)
	animator.bind(self)
	if Engine.is_editor_hint():
		_own_subtree(visual)


func apply_appearance(value: CharacterAppearance) -> void:
	appearance = value.duplicate() if value != null else CharacterAppearance.default_appearance()
	_color_apply_blocked = true
	skin_color = appearance.skin_color
	clothing_color = appearance.clothing_color
	trousers_color = appearance.trousers_color
	_color_apply_blocked = false
	if visual != null:
		visual.apply_appearance(appearance)
		assembler = visual.get_base_assembler()
		if animator != null:
			animator.refresh_rig()


func set_colors(skin: Color, clothing: Color, trousers: Color) -> void:
	_color_apply_blocked = true
	skin_color = skin
	clothing_color = clothing
	trousers_color = trousers
	_color_apply_blocked = false
	appearance.skin_color = skin
	appearance.clothing_color = clothing
	appearance.top_color = clothing
	appearance.trousers_color = trousers
	if visual != null:
		visual.apply_appearance(appearance)
		assembler = visual.get_base_assembler()
		if animator != null:
			animator.refresh_rig()


func _sync_legacy_colors() -> void:
	if _color_apply_blocked:
		return
	set_colors(skin_color, clothing_color, trousers_color)


## Legacy overlay calls are intentionally ignored by the body-only checkpoint.
## They remain as API seams so specialised NPC scripts keep running while the
## replacement equipment-slot contract is reviewed.
func add_overlay(overlay_id: String, json_path: String) -> ModelAssembler:
	return null


func remove_overlay(overlay_id: String) -> void:
	pass


func get_part(part_name: String) -> Node3D:
	return visual.get_part(part_name) if visual != null else null


func get_hand_anchor(side: String) -> Node3D:
	return visual.get_hand_anchor(side) if visual != null else null


func set_motion_speed(speed_m_s: float, delta: float) -> void:
	if animator != null:
		animator.set_locomotion(speed_m_s, delta)


func set_walk_distance(distance_m: float) -> void:
	if animator != null:
		animator.set_walk_distance(distance_m)


func set_idle() -> void:
	if animator != null:
		animator.set_idle()


func attach_tool(side: String, tool: Node3D, local_offset := Vector3.ZERO,
		local_rotation_deg := Vector3.ZERO) -> void:
	var hand := get_hand_anchor(side)
	if hand == null:
		return
	clear_tool(side)
	if tool == null:
		return
	tool.position = local_offset
	tool.rotation_degrees = local_rotation_deg
	hand.add_child(tool)
	_tools[side] = tool


func clear_tool(side: String) -> void:
	var existing := _tools.get(side, null) as Node3D
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	_tools.erase(side)


func _nearest_player_in(range_m: float) -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= range_m:
			return body
	return null


func _own_subtree(node: Node) -> void:
	if get_tree() == null or get_tree().edited_scene_root == null:
		return
	node.owner = get_tree().edited_scene_root
	for child in node.get_children():
		_own_subtree(child)
