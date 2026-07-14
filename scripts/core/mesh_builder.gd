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


## Ship planform: parallel midbody + pointed bow at −Z (bow), blunt stern at +Z.
## Origin at midships; keel at y=0; deck at y=height.
static func pointed_hull_shell(
	loa: float,
	beam: float,
	height: float,
	bow_frac: float = 0.28,
	color: Color = Color(0.12, 0.14, 0.16),
	roughness: float = 0.9,
	metallic: float = 0.05,
	double_sided: bool = false,
) -> MeshInstance3D:
	var mat := make_material(color, roughness, metallic, double_sided)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_material(mat)
	var ring := _pointed_plan_ring(loa, beam, bow_frac)
	_extrude_plan_ring(st, ring, 0.0, height)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


## Thin deck plate matching pointed_hull_shell planform (top face at y = deck_y).
static func pointed_deck_plate(
	loa: float,
	beam: float,
	deck_y: float,
	thickness: float = 0.12,
	bow_frac: float = 0.28,
	color: Color = Color(0.35, 0.32, 0.28),
	roughness: float = 0.95,
) -> MeshInstance3D:
	var mat := make_material(color, roughness, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_material(mat)
	var ring := _pointed_plan_ring(loa, beam, bow_frac)
	var y0 := deck_y - thickness
	_extrude_plan_ring(st, ring, y0, deck_y)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


## Convex points for a bow wedge collision (keel→deck), tip at −Z.
static func pointed_bow_collision_points(
	loa: float,
	beam: float,
	height: float,
	bow_frac: float = 0.28,
) -> PackedVector3Array:
	var hz := loa * 0.5
	var hb := beam * 0.5
	## bow_frac = bow_len/LOA. Half-beam run (bow_frac = beam/(2*loa)) is exactly 45° in plan.
	var bow_len := clampf(bow_frac, 0.0, 0.5) * loa
	var shoulder_z := -hz + bow_len
	var pts := PackedVector3Array()
	for y in [0.0, height]:
		pts.append(Vector3(-hb, y, shoulder_z))
		pts.append(Vector3(hb, y, shoulder_z))
		pts.append(Vector3(0.0, y, -hz))
	return pts


static func _pointed_plan_ring(loa: float, beam: float, bow_frac: float) -> PackedVector2Array:
	## XZ ring, CCW when viewed from above: stern → stbd shoulder → tip → port shoulder.
	var hz := loa * 0.5
	var hb := beam * 0.5
	## Do not floor bow_frac at 0.12 — long feeders need ~0.10 for a true 45° bow.
	var bow_len := clampf(bow_frac, 0.0, 0.5) * loa
	var shoulder_z := -hz + bow_len
	return PackedVector2Array([
		Vector2(-hb, hz),           ## stern port
		Vector2(hb, hz),            ## stern starboard
		Vector2(hb, shoulder_z),    ## bow shoulder stbd
		Vector2(0.0, -hz),          ## bow tip (−Z)
		Vector2(-hb, shoulder_z),   ## bow shoulder port
	])


static func _extrude_plan_ring(st: SurfaceTool, ring: PackedVector2Array, y0: float, y1: float) -> void:
	var n := ring.size()
	if n < 3:
		return
	## Bottom + top fans (unique verts per triangle for flat shading).
	var c0 := Vector3.ZERO
	var c1 := Vector3.ZERO
	for p in ring:
		c0 += Vector3(p.x, y0, p.y)
		c1 += Vector3(p.x, y1, p.y)
	c0 /= float(n)
	c1 /= float(n)
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var a0 := Vector3(a.x, y0, a.y)
		var b0 := Vector3(b.x, y0, b.y)
		var a1 := Vector3(a.x, y1, a.y)
		var b1 := Vector3(b.x, y1, b.y)
		## Bottom (downward) — reverse winding.
		st.add_vertex(c0)
		st.add_vertex(b0)
		st.add_vertex(a0)
		## Top (upward).
		st.add_vertex(c1)
		st.add_vertex(a1)
		st.add_vertex(b1)
		## Side quad → two tris (outward normals for CCW plan ring).
		st.add_vertex(a0)
		st.add_vertex(b1)
		st.add_vertex(b0)
		st.add_vertex(a0)
		st.add_vertex(a1)
		st.add_vertex(b1)


## Right-triangle wedge filling `size` AABB.
## High edge at local −Z, slopes down to +Z (rotate yaw to aim the slope).
## Emit triangles with outward windings. SurfaceTool treats clockwise triangles as
## front-facing, so outward geometric (CCW) faces must be emitted in reverse order.
static func _commit_solid_mesh(faces: Array, color: Color, roughness: float, metallic: float) -> MeshInstance3D:
	var mat := make_material(color, roughness, metallic)
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	mat.roughness = 1.0

	var centroid := Vector3.ZERO
	var vert_count := 0
	for face in faces:
		centroid += face[0] as Vector3
		centroid += face[1] as Vector3
		centroid += face[2] as Vector3
		vert_count += 3
	if vert_count > 0:
		centroid /= float(vert_count)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_material(mat)
	for face in faces:
		var a: Vector3 = face[0]
		var b: Vector3 = face[1]
		var c: Vector3 = face[2]
		var n := (b - a).cross(c - a)
		var face_center := (a + b + c) / 3.0
		## A positive dot means the cross-product normal points outward. Reverse
		## that CCW triangle because Godot's visible front face is clockwise.
		if n.dot(face_center - centroid) > 0.0:
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
		else:
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


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

	return _commit_solid_mesh([
		[v0, v2, v1], [v0, v3, v2], # bottom
		[v0, v1, v5], [v0, v5, v4], # high back (−Z)
		[v4, v5, v2], [v4, v2, v3], # slope
		[v0, v4, v3],               # port
		[v1, v2, v5],               # starboard
	], color, roughness, metallic)


## Inverted right-triangle wedge — solid above the diagonal (upside-down roof / eave).
## High edge at local −Z, underside slopes up toward +Z.
static func wedge_45_inverted(size: Vector3, color: Color, roughness: float = 0.92, metallic: float = 0.0) -> MeshInstance3D:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var v0 := Vector3(-hx,  hy, -hz)
	var v1 := Vector3( hx,  hy, -hz)
	var v2 := Vector3( hx,  hy,  hz)
	var v3 := Vector3(-hx,  hy,  hz)
	var v4 := Vector3(-hx, -hy, -hz)
	var v5 := Vector3( hx, -hy, -hz)

	return _commit_solid_mesh([
		[v0, v1, v2], [v0, v2, v3], # top
		[v0, v4, v5], [v0, v5, v1], # high back (−Z)
		[v4, v3, v2], [v4, v2, v5], # underside slope
		[v0, v3, v4],               # port
		[v1, v5, v2],               # starboard
	], color, roughness, metallic)


## Corner / hip wedge — full bottom, peak only at local (−X, −Z).
## Yaw to seat the high corner against two meeting roof slopes.
static func wedge_45_corner(size: Vector3, color: Color, roughness: float = 0.92, metallic: float = 0.0) -> MeshInstance3D:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b0 := Vector3(-hx, -hy, -hz)
	var b1 := Vector3( hx, -hy, -hz)
	var b2 := Vector3( hx, -hy,  hz)
	var b3 := Vector3(-hx, -hy,  hz)
	var t0 := Vector3(-hx,  hy, -hz)

	return _commit_solid_mesh([
		[b0, b1, b2], [b0, b2, b3], # bottom
		[b0, b1, t0],               # −Z wall
		[b0, t0, b3],               # −X wall
		[t0, b1, b2], [t0, b2, b3], # outer slopes
	], color, roughness, metallic)


## Inverted corner wedge — full top, only (−X, −Z) drops to the cell floor.
static func wedge_45_corner_inverted(size: Vector3, color: Color, roughness: float = 0.92, metallic: float = 0.0) -> MeshInstance3D:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var t0 := Vector3(-hx,  hy, -hz)
	var t1 := Vector3( hx,  hy, -hz)
	var t2 := Vector3( hx,  hy,  hz)
	var t3 := Vector3(-hx,  hy,  hz)
	var b0 := Vector3(-hx, -hy, -hz)

	return _commit_solid_mesh([
		[t0, t1, t2], [t0, t2, t3], # top
		[t0, b0, t1],               # −Z wall
		[t0, t3, b0],               # −X wall
		[b0, t1, t2], [b0, t2, t3], # underside slopes
	], color, roughness, metallic)


## Inner / valley corner — high along −X and −Z (three high corners), low tip at (+X, +Z).
## Complements the outer corner wedge when two slopes meet in an inside corner.
static func wedge_45_inner(size: Vector3, color: Color, roughness: float = 0.92, metallic: float = 0.0) -> MeshInstance3D:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b0 := Vector3(-hx, -hy, -hz)
	var b1 := Vector3( hx, -hy, -hz)
	var b2 := Vector3( hx, -hy,  hz)
	var b3 := Vector3(-hx, -hy,  hz)
	var t0 := Vector3(-hx,  hy, -hz)
	var t1 := Vector3( hx,  hy, -hz)
	var t3 := Vector3(-hx,  hy,  hz)

	return _commit_solid_mesh([
		[b0, b1, b2], [b0, b2, b3], # bottom
		[b0, b1, t1], [b0, t1, t0], # −Z wall (full)
		[b0, t0, t3], [b0, t3, b3], # −X wall (full)
		[t0, t3, t1],               # top L
		[b1, t1, b2],               # +X wall
		[b3, b2, t3],               # +Z wall
		[t1, t0, b2], [t0, t3, b2], # valley slopes
	], color, roughness, metallic)


## Inverted inner corner — full top, low L hanging along −X / −Z (soffit for inside corner).
static func wedge_45_inner_inverted(size: Vector3, color: Color, roughness: float = 0.92, metallic: float = 0.0) -> MeshInstance3D:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var t0 := Vector3(-hx,  hy, -hz)
	var t1 := Vector3( hx,  hy, -hz)
	var t2 := Vector3( hx,  hy,  hz)
	var t3 := Vector3(-hx,  hy,  hz)
	var b0 := Vector3(-hx, -hy, -hz)
	var b1 := Vector3( hx, -hy, -hz)
	var b3 := Vector3(-hx, -hy,  hz)

	return _commit_solid_mesh([
		[t0, t1, t2], [t0, t2, t3], # top
		[t0, t1, b1], [t0, b1, b0], # −Z wall
		[t0, b0, b3], [t0, b3, t3], # −X wall
		[b0, b1, b3],               # bottom L
		[t1, t2, b1],               # +X face
		[t3, b3, t2],               # +Z face
		[t2, b3, b1],               # underside toward (+X, +Z)
	], color, roughness, metallic)


## Vertical block with a right-triangle plan footprint. The missing corner is
## local (+X,+Z); yaw rotates that cut face around a 45-degree hull/building edge.
static func wedge_45_plan(size: Vector3, color: Color, roughness: float = 0.92, metallic: float = 0.0) -> MeshInstance3D:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b0 := Vector3(-hx, -hy, -hz)
	var b1 := Vector3( hx, -hy, -hz)
	var b3 := Vector3(-hx, -hy,  hz)
	var t0 := Vector3(-hx,  hy, -hz)
	var t1 := Vector3( hx,  hy, -hz)
	var t3 := Vector3(-hx,  hy,  hz)

	return _commit_solid_mesh([
		[b0, b1, b3],               # bottom
		[t0, t3, t1],               # top
		[b0, t0, t1], [b0, t1, b1], # −Z wall
		[b0, b3, t3], [b0, t3, t0], # −X wall
		[b1, t1, t3], [b1, t3, b3], # diagonal wall
	], color, roughness, metallic)


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
