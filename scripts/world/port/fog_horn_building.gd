@tool
class_name FogHornBuilding
extends Node3D

## Foghorn warning tower.
## Drop this scene onto a dock or port plot. It will automatically build its
## visual mesh and the fog horn audio player child will handle blast logic.

const MODEL_PATH := "res://resources/data/models/buildings/foghorn_building.json"

var assembler: ModelAssembler

func _ready() -> void:
	_build()

func _build() -> void:
	if assembler != null:
		assembler.queue_free()

	for child in get_children():
		if child is ModelAssembler:
			child.queue_free()

	assembler = ModelAssembler.new()
	assembler.name = "FogHornModel"
	assembler.model_data_path = MODEL_PATH
	assembler.build_part_colliders = not Engine.is_editor_hint()
	add_child(assembler)

	if Engine.is_editor_hint():
		assembler.owner = get_tree().edited_scene_root
		_own_subtree(assembler)

func _own_subtree(node: Node) -> void:
	var esc := get_tree().edited_scene_root
	if esc == null:
		return
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child)
