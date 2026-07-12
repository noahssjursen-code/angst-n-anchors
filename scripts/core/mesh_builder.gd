class_name MeshBuilder
extends RefCounted

## Shared factory for building in-world geometry from Godot primitives.
## No imported meshes. Every in-world object comes from here.

static func make_material(color: Color, roughness: float = 0.85, metallic: float = 0.0, double_sided: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	# Keep painted surfaces matte — default specular still reads as metal on flat slopes.
	if metallic <= 0.001:
		mat.metallic_specular = 0.15
	if color.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		## Glass reads from both sides of a thin pane.
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	elif double_sided:
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


static func torus(
	inner_radius: float,
	outer_radius: float,
	color: Color,
	roughness: float = 0.85,
	metallic: float = 0.0,
	rings: int = 24,
	sides: int = 12,
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = rings
	mesh.ring_segments = sides
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


## Right-triangle wedge filling `size` AABB.
## High edge at local −Z, slopes down to +Z (rotate yaw to aim the slope).
static func wedge_45(size: Vector3, color: Color, roughness: float = 0.92, metallic: float = 0.0) -> MeshInstance3D:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var v0 := Vector3(-hx, -hy, -hz)
	var v1 := Vector3( hx, -hy, -hz)
	var v2 := Vector3( hx, -hy,  hz)
	var v3 := Vector3(-hx, -hy,  hz)
	var v4 := Vector3(-hx,  hy, -hz)
	var v5 := Vector3( hx,  hy, -hz)

	var mat := make_material(color, roughness, metallic)
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	mat.roughness = 1.0

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Flat shading — averaged normals on the slope read as chrome streaks.
	st.set_smooth_group(-1)
	st.set_material(mat)

	var faces: Array = [
		[v0, v2, v1], [v0, v3, v2], # bottom
		[v0, v1, v5], [v0, v5, v4], # high back (−Z)
		[v4, v5, v2], [v4, v2, v3], # slope
		[v0, v4, v3],               # port
		[v1, v2, v5],               # starboard
	]
	for face in faces:
		# Unique verts per triangle so generate_normals cannot smooth across edges.
		st.add_vertex(face[0])
		st.add_vertex(face[1])
		st.add_vertex(face[2])
	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
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
