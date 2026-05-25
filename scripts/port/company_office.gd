@tool
class_name CompanyOffice
extends StaticBody3D

## A custom styled Shipping Company Office building.
## Constructed procedurally using Godot primitives.

const C_FOUNDATION := Color(0.24, 0.24, 0.26)
const C_CABIN      := Color(0.12, 0.18, 0.28) # Warm Navy Blue
const C_ROOF       := Color(0.14, 0.14, 0.16) # Dark slate charcoal
const C_WOOD       := Color(0.48, 0.36, 0.22) # Cedar brown wood
const C_GLASS      := Color(0.98, 0.88, 0.45) # Warm glowing window color

func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	# Clear any previous generated children (to handle tool mode rebuilds cleanly)
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	# Create collision shapes
	_add_collisions()

	# Create visual meshes
	_add_visuals()


func _add_collisions() -> void:
	# Base collision
	var col_base := CollisionShape3D.new()
	col_base.name = "Collision_Base"
	var box_base := BoxShape3D.new()
	box_base.size = Vector3(9.0, 0.4, 8.0)
	col_base.shape = box_base
	col_base.position = Vector3(0.0, 0.2, 0.0)
	add_child(col_base)

	# Main cabin collision
	var col_cabin := CollisionShape3D.new()
	col_cabin.name = "Collision_Cabin"
	var box_cabin := BoxShape3D.new()
	box_cabin.size = Vector3(8.0, 4.6, 6.5)
	col_cabin.shape = box_cabin
	col_cabin.position = Vector3(0.0, 2.3 + 0.4, 0.75)
	add_child(col_cabin)


func _add_visuals() -> void:
	# 1. Foundation Base Pad
	_spawn_box("BasePad", Vector3(9.0, 0.4, 8.0), Vector3(0.0, 0.2, 0.0), C_FOUNDATION, 0.9, 0.0)

	# 2. Main Cabin Wood siding
	_spawn_box("CabinWalls", Vector3(8.0, 4.2, 6.5), Vector3(0.0, 2.1 + 0.4, 0.75), C_CABIN, 0.88, 0.05)

	# 3. Gabled Prism Roof
	var roof_mi := MeshInstance3D.new()
	roof_mi.name = "GabledRoof"
	var prism := PrismMesh.new()
	prism.size = Vector3(8.2, 1.6, 6.7)
	roof_mi.mesh = prism
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = C_ROOF
	roof_mat.roughness = 0.75
	roof_mi.material_override = roof_mat
	roof_mi.position = Vector3(0.0, 4.6 + 0.8, 0.75)
	add_child(roof_mi)

	# 4. Porch base pad (lower steps/platform)
	_spawn_box("PorchBase", Vector3(8.0, 0.38, 1.5), Vector3(0.0, 0.19, -3.25), C_FOUNDATION, 0.9, 0.0)

	# 5. Porch roof overhang
	_spawn_box("PorchRoof", Vector3(8.2, 0.2, 1.6), Vector3(0.0, 4.5, -3.2), C_ROOF, 0.8, 0.0)

	# 6. Porch pillars (two wooden posts)
	_spawn_cylinder("PillarL", 0.1, 4.1, Vector3(-3.7, 2.05 + 0.4, -3.7), C_WOOD, 0.85)
	_spawn_cylinder("PillarR", 0.1, 4.1, Vector3(3.7, 2.05 + 0.4, -3.7), C_WOOD, 0.85)

	# 7. Front door
	_spawn_box("FrontDoor", Vector3(1.2, 2.2, 0.15), Vector3(0.0, 1.1 + 0.4, -2.55), C_WOOD, 0.9, 0.0)

	# 8. Front glowing windows (Left & Right)
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = C_GLASS
	glass_mat.emission_enabled = true
	glass_mat.emission = C_GLASS
	glass_mat.emission_energy_multiplier = 0.5
	glass_mat.roughness = 0.1

	_spawn_box_mat("WindowL", Vector3(1.4, 1.4, 0.08), Vector3(-2.2, 2.0 + 0.4, -2.52), glass_mat)
	_spawn_box_mat("WindowR", Vector3(1.4, 1.4, 0.08), Vector3(2.2, 2.0 + 0.4, -2.52), glass_mat)

	# 9. Shipping Office Signboard
	var sign_lbl := Label3D.new()
	sign_lbl.name = "OfficeSign"
	sign_lbl.text = "SHIPPING CO."
	sign_lbl.font_size = 48
	sign_lbl.pixel_size = 0.008
	sign_lbl.modulate = Color.WHITE
	sign_lbl.outline_modulate = Color.BLACK
	sign_lbl.position = Vector3(0.0, 3.7, -2.7)
	sign_lbl.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	sign_lbl.double_sided = false
	add_child(sign_lbl)

	# Editor ownership chain setup
	if Engine.is_editor_hint() and get_tree() != null:
		var esc := get_tree().edited_scene_root
		if esc != null:
			_own_subtree(self, esc)


func _spawn_box(part_name: String, size: Vector3, pos: Vector3, color: Color, roughness: float, metallic: float) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return _spawn_box_mat(part_name, size, pos, mat)


func _spawn_box_mat(part_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _spawn_cylinder(part_name: String, radius: float, height: float, pos: Vector3, color: Color, roughness: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 12
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _own_subtree(node: Node, esc: Node) -> void:
	node.owner = esc
	for child in node.get_children():
		_own_subtree(child, esc)
