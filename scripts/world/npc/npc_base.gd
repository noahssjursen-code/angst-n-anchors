@tool
class_name NpcBase
extends StaticBody3D

const LAYER_WORLD := 1
const MODEL_PATH  := "res://resources/data/meshes/characters/npc_base.json"

@export var skin_color: Color = Color(0.72, 0.55, 0.40):
	set(v): skin_color = v; _apply_colors()

@export var clothing_color: Color = Color(0.18, 0.20, 0.30):
	set(v): clothing_color = v; _apply_colors()

@export var trousers_color: Color = Color(0.18, 0.18, 0.20):
	set(v): trousers_color = v; _apply_colors()

var assembler: ModelAssembler
var _overlays: Dictionary = {}


func _ready() -> void:
	call_deferred("_build")


func _build() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	collision_layer = LAYER_WORLD
	collision_mask  = 0

	var capsule    := CapsuleShape3D.new()
	capsule.radius = 0.15
	capsule.height = 1.70
	var col        := CollisionShape3D.new()
	col.name       = "Body"
	col.shape      = capsule
	col.position   = Vector3(0.0, 0.85, 0.0)
	add_child(col)

	assembler                      = ModelAssembler.new()
	assembler.name                 = "NpcModel"
	assembler.model_data_path      = MODEL_PATH
	assembler.build_part_colliders = false
	add_child(assembler)

	if Engine.is_editor_hint():
		_own_subtree(col)
		_own_subtree(assembler)

	call_deferred("_apply_colors")


func _apply_colors() -> void:
	if assembler == null:
		return
	_tint("head",      skin_color)
	_tint("hands",     skin_color)
	_tint("face_nose", skin_color)
	_tint("torso",     clothing_color)
	_tint("arms",      clothing_color)
	_tint("legs",      trousers_color)


func _tint(part_name: String, color: Color) -> void:
	var t := assembler.get_part(part_name)
	if t != null:
		t.mesh_color = color


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
