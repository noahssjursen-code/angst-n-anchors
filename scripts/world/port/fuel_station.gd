@tool
class_name FuelStation
extends Node3D

## Dock fuel station — large horizontal tank with dispensing pump.
## Drop this scene onto a dock or port plot. The interactable part
## is the `fuel_pump` mesh role; higher-level systems can query it via
##   assembler.get_first_part_by_role("interactable")

const MODEL_PATH := "res://resources/data/meshes/props/fuel_station.json"

var assembler: ModelAssembler


func _ready() -> void:
	_build()


func _build() -> void:
	if assembler != null:
		assembler.queue_free()

	for child in get_children():
		child.queue_free()

	assembler = ModelAssembler.new()
	assembler.name = "FuelStationModel"
	assembler.model_data_path = MODEL_PATH
	assembler.build_part_colliders = not Engine.is_editor_hint()
	add_child(assembler)

	_add_labels()

	if Engine.is_editor_hint() and get_tree() != null:
		assembler.owner = get_tree().edited_scene_root
		_own_subtree(assembler)


func _add_labels() -> void:
	# Tank sits with its long axis along X, centre at (0, 1.5, 0), radius 1.0 m.
	# Place one label flush against each long side (+Z and -Z) facing outward.
	for side in [1, -1]:
		var label := Label3D.new()
		label.name = "DieselLabel_" + ("Z" if side > 0 else "Zn")
		label.text = "DIESEL"
		label.font_size = 52
		label.pixel_size = 0.007
		label.modulate = Color.BLACK
		label.position = Vector3(0.0, 1.5, 1.03 * side)
		label.rotation_degrees = Vector3(0.0, 0.0 if side > 0 else 180.0, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.double_sided = false
		add_child(label)
		if Engine.is_editor_hint() and get_tree() != null:
			label.owner = get_tree().edited_scene_root


func get_pump_position() -> Vector3:
	if assembler == null:
		return global_position
	var pump := assembler.get_first_part_by_role("interactable")
	if pump == null:
		return global_position
	return pump.global_position


func _own_subtree(node: Node) -> void:
	if get_tree() == null:
		return
	var esc := get_tree().edited_scene_root
	if esc == null:
		return
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child)
