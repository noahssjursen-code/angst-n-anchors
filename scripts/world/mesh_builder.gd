class_name MeshBuilder
extends RefCounted

## Shared factory for building in-world geometry from Godot primitives.
## No imported meshes. Every in-world object comes from here.

static func make_material(color: Color, roughness: float = 0.55, metallic: float = 0.05, double_sided: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func box(size: Vector3, color: Color, roughness: float = 0.85, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, metallic)
	return mi


static func cylinder(radius: float, height: float, color: Color, roughness: float = 0.85, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, metallic)
	return mi


static func sphere(radius: float, color: Color, roughness: float = 0.8, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, metallic)
	return mi


static func prism(size: Vector3, color: Color, roughness: float = 0.85, metallic: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, metallic)
	return mi


static func plane(
	size: Vector2,
	color: Color,
	roughness: float = 0.9,
	subdivide_w: int = 0,
	subdivide_d: int = 0,
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = size
	if subdivide_w > 0:
		mesh.subdivide_width = subdivide_w
	if subdivide_d > 0:
		mesh.subdivide_depth = subdivide_d
	mi.mesh = mesh
	mi.material_override = make_material(color, roughness, 0.0)
	return mi


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


## Builds a custom mesh from a flat array of vertices and indices.
##
## JSON meshes use flat normals and a plain StandardMaterial3D. No UVs, no shader,
## no procedural colour variation — just simple lighting and shadows.
static func from_data(
	vertices: Array,
	indices: Array,
	color: Color,
	roughness: float = 0.55,
	metallic: float = 0.05,
) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat := make_material(color, roughness, metallic, true)
	st.set_material(mat)

	var v3_array: Array[Vector3] = []
	for i in range(0, vertices.size(), 3):
		v3_array.append(Vector3(vertices[i], vertices[i+1], vertices[i+2]))

	# JSON authoring uses CW winding; Godot expects CCW — swap the last two indices.
	# Each triangle emits 3 unique vertices so generate_normals() gives flat shading.
	for i in range(0, indices.size(), 3):
		st.add_vertex(v3_array[indices[i]])
		st.add_vertex(v3_array[indices[i + 2]])
		st.add_vertex(v3_array[indices[i + 1]])

	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi
