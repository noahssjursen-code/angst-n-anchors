@tool
class_name NpcBase
extends Node3D

## Base visual NPC — articulated rig + colour tinting + overlay slots + hand
## anchors for tool attachment. Pure Node3D, no collision body. Subclasses
## that need to be raycast-hit by player interaction (NpcInteractable) add
## their own StaticBody3D collider; ambient walkers (WalkingNpc) inherit
## directly and skip the physics cost entirely.
##
## Build is synchronous in _ready — no `call_deferred` chain. Subclasses can
## set colours / call add_overlay() / attach a WalkAnimator immediately after
## super._ready() without waiting an extra frame.

const MODEL_PATH := AssetPaths.NPC_BASE_MESH

@export var skin_color: Color = Color(0.72, 0.55, 0.40):
	set(v): skin_color = v; if not _color_apply_blocked: _apply_colors()

@export var clothing_color: Color = Color(0.18, 0.20, 0.30):
	set(v): clothing_color = v; if not _color_apply_blocked: _apply_colors()

@export var trousers_color: Color = Color(0.18, 0.18, 0.20):
	set(v): trousers_color = v; if not _color_apply_blocked: _apply_colors()

var assembler: ModelAssembler
var _overlays: Dictionary = {}
var _tools:    Dictionary = {}   ## hand_side ("left"/"right") → Node3D
var _color_apply_blocked: bool = false


func _ready() -> void:
	_build()


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	# Wipe any prior generated nodes (in case of hot-reload / rebuild).
	for child in get_children():
		if child is ModelAssembler:
			if Engine.is_editor_hint():
				child.free()
			else:
				child.queue_free()

	assembler                      = ModelAssembler.new()
	assembler.name                 = "NpcModel"
	assembler.model_data_path      = MODEL_PATH
	assembler.build_part_colliders = false
	add_child(assembler)

	if Engine.is_editor_hint():
		_own_subtree(assembler)

	_apply_colors()


# ── Colours ───────────────────────────────────────────────────────────────────

func _apply_colors() -> void:
	if assembler == null or not is_instance_valid(assembler):
		return
	_tint("head",        skin_color)
	_tint("hand_left",   skin_color)
	_tint("hand_right",  skin_color)
	_tint("face_nose",   skin_color)
	_tint("torso",       clothing_color)
	_tint("arm_left",    clothing_color)
	_tint("arm_right",   clothing_color)
	_tint("leg_left",    trousers_color)
	_tint("leg_right",   trousers_color)


func set_colors(skin: Color, clothing: Color, trousers: Color) -> void:
	_color_apply_blocked = true
	skin_color = skin
	clothing_color = clothing
	trousers_color = trousers
	_color_apply_blocked = false
	_apply_colors()


func _tint(part_name: String, color: Color) -> void:
	var t := assembler.get_part(part_name)
	if t != null:
		t.mesh_color = color


# ── Overlays (hats, capes, badges) ────────────────────────────────────────────

func add_overlay(overlay_id: String, json_path: String) -> ModelAssembler:
	if _overlays.has(overlay_id):
		var old := _overlays[overlay_id] as ModelAssembler
		if old != null:
			if Engine.is_editor_hint():
				old.free()
			else:
				old.queue_free()
	var ma                     := ModelAssembler.new()
	ma.name                    = "Overlay_%s" % overlay_id
	ma.model_data_path         = json_path
	ma.build_part_colliders    = false
	add_child(ma)
	if Engine.is_editor_hint():
		_own_subtree(ma)
	_overlays[overlay_id] = ma
	return ma


func remove_overlay(overlay_id: String) -> void:
	if not _overlays.has(overlay_id):
		return
	var old := _overlays[overlay_id] as ModelAssembler
	if old != null and is_instance_valid(old):
		if Engine.is_editor_hint():
			old.free()
		else:
			old.queue_free()
	_overlays.erase(overlay_id)


# ── Hand anchors (for tools) ──────────────────────────────────────────────────

## Returns the `hand_left` or `hand_right` MeshTransformer — these are
## children of the corresponding arm in the articulated rig, so anything
## attached as a child of the returned node will follow the arm swing
## naturally. `side` is "left" or "right".
func get_hand_anchor(side: String) -> Node3D:
	if assembler == null:
		return null
	var part_name := "hand_left" if side == "left" else "hand_right"
	return assembler.get_part(part_name)


## Attach a Node3D (a tool model, a clipboard, a lantern) to the named hand.
## Replaces any existing tool in that hand. Pass null to clear the slot.
## Local offset / rotation are applied on top of the hand transform — useful
## for "tool tip points forward" adjustments without modifying the tool scene.
func attach_tool(side: String, tool: Node3D, local_offset: Vector3 = Vector3.ZERO,
				 local_rotation_deg: Vector3 = Vector3.ZERO) -> void:
	var hand := get_hand_anchor(side)
	if hand == null:
		return
	clear_tool(side)
	if tool == null:
		return
	tool.position          = local_offset
	tool.rotation_degrees  = local_rotation_deg
	hand.add_child(tool)
	_tools[side] = tool


func clear_tool(side: String) -> void:
	var existing := _tools.get(side, null) as Node3D
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	_tools.erase(side)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _nearest_player_in(range_m: float) -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= range_m:
			return body
	return null


func _own_subtree(node: Node) -> void:
	if get_tree() == null:
		return
	var esc := get_tree().edited_scene_root
	if esc == null:
		return
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child)
