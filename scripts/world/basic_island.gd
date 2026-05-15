class_name BasicIsland
extends Node3D

## A self-contained island: sand ground slab + a Port.
## Place via ProximityLoader. Rotation is applied before add_child so Port's
## internal layout rotates with it — rotation_degrees.y = 180 faces the dock south.

const C_SAND := Color(0.82, 0.74, 0.58)

## Which direction the dock faces. 0 = north (default Port orientation), 180 = south.
@export_range(0.0, 360.0, 90.0) var dock_facing_degrees: float = 0.0

## Which boat the dock spawns. Passed through to Port.
@export var ship_scene: PackedScene


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	_add_ground()
	_add_port()


func _add_ground() -> void:
	var ground      := MeshBuilder.static_box(Vector3(80, 2, 60), C_SAND)
	ground.position = Vector3(0, -1.0, 0)
	add_child(ground)


func _add_port() -> void:
	var port                := Port.new()
	port.name               = "Port"
	port.rotation_degrees.y = dock_facing_degrees
	if ship_scene != null:
		port.ship_scene = ship_scene
	add_child(port)
