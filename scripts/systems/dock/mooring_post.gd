class_name MooringPost
extends StaticBody3D

@export var post_height: float = 1.1
@export var post_radius: float = 0.16
@export var anchor_local_position: Vector3 = Vector3(0.0, 0.85, 0.0)
@export var post_color: Color = Color(0.18, 0.11, 0.06)


func _ready() -> void:
	_rebuild()


func get_anchor_global_position() -> Vector3:
	return to_global(anchor_local_position)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var shape := CylinderShape3D.new()
	shape.radius = post_radius
	shape.height = post_height

	var collision := CollisionShape3D.new()
	collision.name = "PostCollision"
	collision.shape = shape
	collision.position = Vector3.UP * (post_height * 0.5)
	add_child(collision)

	var visual := MeshBuilder.cylinder(post_radius, post_height, post_color, 0.95, 0.0)
	visual.name = "PostVisual"
	visual.position = Vector3.UP * (post_height * 0.5)
	add_child(visual)

	var cap := MeshBuilder.cylinder(post_radius * 1.28, 0.16, post_color.lightened(0.08), 0.9, 0.0)
	cap.name = "PostCap"
	cap.position = Vector3.UP * post_height
	add_child(cap)
