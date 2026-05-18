@tool
class_name FogHornBuilding
extends Node3D

## Foghorn warning tower.
## Drop this scene onto a dock or port plot. It will automatically build its
## visual mesh and an internal FogHorn audio child to drive blast logic.
##
## Both the model and the FogHorn are spawned at runtime — keeping the scene
## empty avoids name-clash warnings ("from a more nested instance") when the
## same FogHornBuilding ends up baked into a parent scene's saved tree.

const MODEL_PATH      := "res://resources/data/models/buildings/foghorn_building.json"
const FOG_HORN_SCRIPT := preload("res://scripts/port/fog_horn.gd")
const FOG_HORN_OFFSET := Vector3(0.0, 6.2, 0.0)   ## matches the old .tscn placement

var assembler: ModelAssembler

func _ready() -> void:
	_build()
	_ensure_fog_horn()

func _build() -> void:
	# In editor: if a FogHornModel already exists (baked into a parent
	# scene's saved tree, e.g. world.tscn), leave it alone. Rebuilding it on
	# every open would destroy the baked node and create a fresh one with a
	# different identity, marking the parent scene "unsaved" the instant it
	# loads — and the next save would bake the new one, triggering the same
	# churn on the next open. Editor preview still works because the baked
	# model is the real model.
	if Engine.is_editor_hint():
		var existing := get_node_or_null("FogHornModel") as ModelAssembler
		if existing != null:
			assembler = existing
			return

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

	if Engine.is_editor_hint() and get_tree() != null:
		assembler.owner = get_tree().edited_scene_root
		_own_subtree(assembler)


## Idempotent: if a FogHorn child already exists (baked .tscn, hot-reload),
## we leave it alone. Otherwise create one with the script attached.
func _ensure_fog_horn() -> void:
	if Engine.is_editor_hint():
		return
	if get_node_or_null("FogHorn") != null:
		return
	var horn := AudioStreamPlayer3D.new()
	horn.name = "FogHorn"
	horn.set_script(FOG_HORN_SCRIPT)
	horn.position = FOG_HORN_OFFSET
	add_child(horn)

func _own_subtree(node: Node) -> void:
	if get_tree() == null:
		return
	var esc := get_tree().edited_scene_root
	if esc == null:
		return
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child)
