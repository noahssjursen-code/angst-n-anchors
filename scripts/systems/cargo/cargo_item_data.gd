class_name CargoItemData
extends Resource

@export var cargo_id: String = "wooden_crate"
@export var display_name: String = "Wooden Crate"
@export var crate_size: Vector3 = Vector3(0.8, 0.8, 0.8)
@export var crate_color: Color = Color(0.42, 0.27, 0.13)
@export var mass_kg: float = 25.0


static func default_crate() -> CargoItemData:
	var data := CargoItemData.new()
	return data


func duplicate_data() -> CargoItemData:
	var copy := CargoItemData.new()
	copy.cargo_id = cargo_id
	copy.display_name = display_name
	copy.crate_size = crate_size
	copy.crate_color = crate_color
	copy.mass_kg = mass_kg
	return copy


func make_crate_visual() -> MeshInstance3D:
	var visual := MeshBuilder.box(crate_size, crate_color, 0.9, 0.0)
	visual.name = display_name.replace(" ", "_") + "_Visual"
	return visual
