@tool
class_name MooringPoint
extends Node3D

## Must match MooringComponent.SHIP_MOORING_CLEAT_GROUP — discoverability only (no naming).
const _CLEAT_GROUP := "ship_mooring_cleat"

const DEFAULT_BOLLARD_MODEL := "res://resources/data/meshes/docks/docking_bollard.json"

@export_file("*.json") var bollard_model_path: String = DEFAULT_BOLLARD_MODEL:
	set(v):
		bollard_model_path = v
		_rebuild_bollard_visual()

## Uniform scale for the docking bollard assembly.
@export_range(0.05, 4.0, 0.01) var bollard_scale: float = 1.0:
	set(v):
		bollard_scale = maxf(v, 0.05)
		_rebuild_bollard_visual()

## Rotation of the assembled bollard (child node). Default yaw 90° for deck alignment.
@export var bollard_rotation_degrees: Vector3 = Vector3(0.0, 90.0, 0.0):
	set(v):
		bollard_rotation_degrees = v
		_rebuild_bollard_visual()

## Line attachment in local space (crossbar neighbourhood; tune per asset).
@export var anchor_local_position: Vector3 = Vector3(0.0, 0.52, 0.0):
	set(v):
		anchor_local_position = v

@export_enum("port", "starboard") var side: String = "port":
	set(v):
		side = v

@export_enum("bow", "stern") var station: String = "bow":
	set(v):
		station = v

## When false, only the cleat anchor/group is created (brick mesh supplies the look).
@export var build_visual: bool = true:
	set(v):
		build_visual = v
		_rebuild_bollard_visual()


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(_CLEAT_GROUP)
	_rebuild_bollard_visual()


func get_anchor_global_position() -> Vector3:
	return to_global(anchor_local_position)


func matches(requested_side: String, requested_station: String) -> bool:
	return side == requested_side and station == requested_station


func _remove_legacy_marker() -> void:
	var marker := get_node_or_null("Marker")
	if marker != null:
		marker.queue_free()


func _rebuild_bollard_visual() -> void:
	if not is_inside_tree():
		call_deferred("_rebuild_bollard_visual")
		return

	_remove_legacy_marker()

	var existing := get_node_or_null("DockingBollard")
	if existing != null:
		remove_child(existing)
		existing.free()

	if not build_visual:
		return

	var visual := ModelCache.instance(bollard_model_path, bollard_scale)
	visual.name = "DockingBollard"
	visual.rotation_degrees = bollard_rotation_degrees
	add_child(visual)
	var tree := get_tree()
	if Engine.is_editor_hint() and tree != null and tree.edited_scene_root != null:
		visual.owner = tree.edited_scene_root
		for child in visual.get_children():
			child.owner = tree.edited_scene_root

