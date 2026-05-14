@tool
class_name MooringPoint
extends Node3D

## Must match MooringComponent.SHIP_MOORING_CLEAT_GROUP — discoverability only (no naming).
const _CLEAT_GROUP := "ship_mooring_cleat"

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
	if not Engine.is_editor_hint():
		add_to_group(_CLEAT_GROUP)
	_update_marker()


func get_anchor_global_position() -> Vector3:
	return global_position


func matches(requested_side: String, requested_station: String) -> bool:
	return side == requested_side and station == requested_station


func _update_marker() -> void:
	if not is_inside_tree():
		return

	var marker := get_node_or_null("Marker") as MeshInstance3D
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "Marker"
		add_child(marker)

	var mesh := CylinderMesh.new()
	mesh.top_radius = marker_radius
	mesh.bottom_radius = marker_radius
	mesh.height = marker_height
	marker.mesh = mesh

	var color := Color(0.85, 0.68, 0.28) if side == "port" else Color(0.35, 0.65, 0.95)
	marker.material_override = MeshBuilder.make_material(color, 0.72, 0.02)
	marker.position = Vector3.UP * (marker_height * 0.5)
