@tool
class_name MooringPoint
extends Node3D

@export_enum("port", "starboard") var side: String = "port":
	set(v):
		side = v
		_update_marker()

@export_enum("bow", "stern") var station: String = "bow":
	set(v):
		station = v
		_update_marker()

@export var marker_radius: float = 0.16:
	set(v):
		marker_radius = maxf(v, 0.03)
		_update_marker()

@export var marker_height: float = 0.22:
	set(v):
		marker_height = maxf(v, 0.04)
		_update_marker()


func _ready() -> void:
	_update_marker()


func get_anchor_global_position() -> Vector3:
	return global_position


func matches(requested_side: String, requested_station: String) -> bool:
	return side == requested_side and station == requested_station


func _update_marker() -> void:
	if not is_inside_tree():
		return

	for child in get_children():
		if child.name == "Marker":
			child.queue_free()

	var marker := MeshInstance3D.new()
	marker.name = "Marker"

	var mesh := CylinderMesh.new()
	mesh.top_radius = marker_radius
	mesh.bottom_radius = marker_radius
	mesh.height = marker_height
	marker.mesh = mesh

	var color := Color(0.85, 0.68, 0.28) if side == "port" else Color(0.35, 0.65, 0.95)
	marker.material_override = MeshBuilder.make_material(color, 0.72, 0.02)
	marker.position = Vector3.UP * (marker_height * 0.5)
	add_child(marker)

	if Engine.is_editor_hint():
		marker.owner = get_tree().edited_scene_root
