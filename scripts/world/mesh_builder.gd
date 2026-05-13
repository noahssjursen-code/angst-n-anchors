class_name MeshBuilder
extends RefCounted

## Shared factory for building in-world geometry from Godot primitives.
## No imported meshes. Every in-world object comes from here.


static func make_material(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


## Visual-only box. Adds no collision.
static func box(size: Vector3, color: Color, roughness: float = 0.85, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, metallic)
	return mi


## Visual-only cylinder. Adds no collision.
static func cylinder(radius: float, height: float, color: Color, roughness: float = 0.85, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, metallic)
	return mi


## Visual-only sphere. Adds no collision.
static func sphere(radius: float, color: Color, roughness: float = 0.8, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, metallic)
	return mi


## Visual-only prism (wedge). Adds no collision.
static func prism(size: Vector3, color: Color, roughness: float = 0.85, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, metallic)
	return mi


## Visual-only plane. Adds no collision.
static func plane(size: Vector2, color: Color, roughness: float = 0.9) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, 0.0)
	return mi


## Solid box with collision. Returns a StaticBody3D containing a matching visual and a BoxShape3D.
static func static_box(size: Vector3, color: Color, roughness: float = 0.85) -> StaticBody3D:
	var body := StaticBody3D.new()

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	var visual := box(size, color, roughness)
	body.add_child(visual)

	return body
