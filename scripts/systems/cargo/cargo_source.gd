class_name CargoSource
extends StaticBody3D

const CARGO_ITEM_DATA_SCRIPT := preload("res://scripts/systems/cargo/cargo_item_data.gd")

@export var cargo_id: String = "wooden_crate"
@export var display_name: String = "Wooden Crate"
@export var crate_size: Vector3 = Vector3(0.8, 0.8, 0.8)
@export var crate_color: Color = Color(0.42, 0.27, 0.13)
@export var mass_kg: float = 25.0
@export var source_size: Vector3 = Vector3(2.6, 1.4, 2.0)

var _visual_root: Node3D


func _ready() -> void:
	_rebuild()


func try_take_cargo() -> Resource:
	var data := CARGO_ITEM_DATA_SCRIPT.new() as Resource
	data.set("cargo_id", cargo_id)
	data.set("display_name", display_name)
	data.set("crate_size", crate_size)
	data.set("crate_color", crate_color)
	data.set("mass_kg", mass_kg)
	return data


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var shape := BoxShape3D.new()
	shape.size = source_size

	var collision := CollisionShape3D.new()
	collision.name = "CargoSourceShape"
	collision.shape = shape
	collision.position = Vector3.UP * (source_size.y * 0.5)
	add_child(collision)

	_visual_root = Node3D.new()
	_visual_root.name = "CargoSourceVisuals"
	add_child(_visual_root)
	_build_visuals()


func _build_visuals() -> void:
	var base := MeshBuilder.box(source_size, Color(0.34, 0.24, 0.15), 0.9, 0.0)
	base.name = "WarehouseCrateStack"
	base.position = Vector3.UP * (source_size.y * 0.5)
	_visual_root.add_child(base)

	for i in range(3):
		var crate := MeshBuilder.box(crate_size, crate_color.lightened(0.08), 0.9, 0.0)
		crate.name = "LooseCrate_%d" % i
		crate.position = Vector3(
			-0.9 + float(i) * 0.9,
			source_size.y + crate_size.y * 0.5,
			0.0
		)
		_visual_root.add_child(crate)
