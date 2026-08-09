class_name MeshBuilder
extends RefCounted

## Shared factory for building in-world geometry from Godot primitives.
## No imported meshes. Every in-world object comes from here.

static var _material_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _geometry_cache: Dictionary = {}

const PALETTE_MASK_SHADER := preload("res://resources/shaders/palette_mask_material.gdshader")


static func clear_material_cache() -> void:
	_material_cache.clear()
	_texture_cache.clear()


static func clear_geometry_cache() -> void:
	_geometry_cache.clear()


static func geometry_cache_size() -> int:
	return _geometry_cache.size()


static func material_cache_size() -> int:
	return _material_cache.size()


static func texture_cache_size() -> int:
	return _texture_cache.size()


static func make_material(color: Color, roughness: float = 0.85, metallic: float = 0.0, double_sided: bool = false) -> StandardMaterial3D:
	var key := _material_cache_key(color, roughness, metallic, double_sided)
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
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
	_material_cache[key] = mat
	return mat


## Textured companion to make_material(). Every wearer shares the imported
## Texture2D and cached GPU material; `color` is a multiplicative tint.
static func make_textured_material(
		texture_path: String,
		color: Color = Color.WHITE,
		roughness: float = 0.85,
		metallic: float = 0.0,
		double_sided: bool = false,
) -> StandardMaterial3D:
	if texture_path.is_empty():
		return make_material(color, roughness, metallic, double_sided)
	var key := "texture:%s|%s" % [
		texture_path,
		_material_cache_key(color, roughness, metallic, double_sided),
	]
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var texture := _load_texture(texture_path)
	if texture == null:
		push_warning("MeshBuilder: could not load texture `%s`" % texture_path)
		return make_material(color, roughness, metallic, double_sided)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = texture
	mat.roughness = roughness
	mat.metallic = metallic
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if metallic <= 0.001:
		mat.metallic_specular = 0.15
	if color.a < 0.999:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	elif double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[key] = mat
	return mat


## Recolourable textured material. The mask's red and green channels select
## primary and secondary regions while the base texture keeps authored weave,
## wear, shading, and fine detail. Identical palettes share one material.
static func make_palette_masked_material(
		texture_path: String,
		mask_path: String,
		primary_color: Color,
		secondary_color: Color,
		tint: Color = Color.WHITE,
		roughness: float = 0.85,
		metallic: float = 0.0,
) -> Material:
	if texture_path.is_empty() or mask_path.is_empty():
		return make_textured_material(texture_path, tint, roughness, metallic, true)
	var key := "palette_mask:%s|%s|%s|%s|%s" % [
		texture_path,
		mask_path,
		_material_cache_key(primary_color, roughness, metallic, true),
		_material_cache_key(secondary_color, roughness, metallic, true),
		_material_cache_key(tint, roughness, metallic, true),
	]
	if _material_cache.has(key):
		return _material_cache[key] as Material
	var texture := _load_texture(texture_path)
	var mask := _load_texture(mask_path)
	if texture == null or mask == null:
		push_warning("MeshBuilder: could not load palette texture or mask `%s`, `%s`" % [texture_path, mask_path])
		return make_textured_material(texture_path, tint, roughness, metallic, true)
	var mat := ShaderMaterial.new()
	mat.shader = PALETTE_MASK_SHADER
	mat.set_shader_parameter("base_texture", texture)
	mat.set_shader_parameter("palette_mask", mask)
	mat.set_shader_parameter("primary_color", primary_color)
	mat.set_shader_parameter("secondary_color", secondary_color)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("surface_roughness", roughness)
	mat.set_shader_parameter("surface_metallic", metallic)
	_material_cache[key] = mat
	return mat


static func _load_texture(texture_path: String) -> Texture2D:
	if _texture_cache.has(texture_path):
		return _texture_cache[texture_path] as Texture2D
	var texture: Texture2D = null
	## Source-generated texture libraries can be present before Godot has written
	## their import metadata. ResourceLoader cannot see those files yet, but the
	## runtime still needs to render them in authoring showcases and first launch.
	## Prefer the imported resource when available so production builds keep the
	## normal compressed/mipmapped path; decode the source image only as a safe
	## fallback for newly generated assets.
	if ResourceLoader.exists(texture_path, "Texture2D"):
		texture = ResourceLoader.load(texture_path, "Texture2D") as Texture2D
	if texture == null:
		var absolute_path := ProjectSettings.globalize_path(texture_path)
		if FileAccess.file_exists(absolute_path):
			var image := Image.load_from_file(absolute_path)
			if image != null and not image.is_empty():
				texture = ImageTexture.create_from_image(image)
	if texture != null:
		_texture_cache[texture_path] = texture
	return texture


static func _material_cache_key(
		color: Color,
		roughness: float,
		metallic: float,
		double_sided: bool,
) -> String:
	return "%.4f,%.4f,%.4f,%.4f|%.3f|%.3f|%s" % [
		color.r,
		color.g,
		color.b,
		color.a,
		roughness,
		metallic,
		double_sided,
	]


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


## Append an axis-aligned box (12 triangles) into an active SurfaceTool pass.
static func append_axis_box(st: SurfaceTool, size: Vector3, center: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var faces: Array = [
		[Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)],
		[Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz)],
		[Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz)],
		[Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz)],
		[Vector3(hx, -hy, hz), Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz)],
		[Vector3(-hx, -hy, -hz), Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz)],
	]
	for face in faces:
		var quad: Array = face
		st.add_vertex(center + quad[0])
		st.add_vertex(center + quad[1])
		st.add_vertex(center + quad[2])
		st.add_vertex(center + quad[0])
		st.add_vertex(center + quad[2])
		st.add_vertex(center + quad[3])


static func merged_boxes(size_positions: Array, color: Color, roughness: float = 0.85, metallic: float = 0.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat := make_material(color, roughness, metallic)
	st.set_material(mat)
	for entry in size_positions:
		append_axis_box(st, entry["size"], entry["position"])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
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


## Low-poly shell lofted through HullStations. The station lattice is shared
## with buoyancy, so the rendered bilges, waterline, flare, and end taper agree
## with the physical hull.
##
## The shell's ceiling is `hull_stations.deck_y` and it must stay there. Everything
## the deck carries — `pointed_deck_plate` at [deck_y, deck_y + 0.1], the DeckGrid
## build plane at deck_y + 0.12, the plan's box colliders, BoatBody's walk slab —
## starts at that Y and goes up, and the player's mask has nothing above it. Plating
## that stands proud of a flat deck is a bulwark; it has to be drawn by whoever can
## also collide it. See the sheer note in `scripts/ship/hull_stations.gd`.
static func lofted_hull_shell(
	hull_stations: HullStations,
	color: Color = Color(0.12, 0.14, 0.16),
	roughness: float = 0.9,
	metallic: float = 0.05,
	double_sided: bool = false,
	keel_color: Color = Color(0.34, 0.055, 0.04),
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if hull_stations == null or hull_stations.stations.size() < 2:
		return mi
	var upper_faces: Array = []
	var keel_faces: Array = []
	var station_count := hull_stations.stations.size()
	for i in range(station_count - 1):
		var section_a: Array = hull_stations.stations[i]["section"]
		var section_b: Array = hull_stations.stations[i + 1]["section"]
		var level_count := mini(section_a.size(), section_b.size())
		if level_count < 2:
			continue
		var za := float(hull_stations.stations[i]["z"])
		var zb := float(hull_stations.stations[i + 1]["z"])
		for j in range(level_count - 1):
			var a0: Vector2 = section_a[j]
			var a1: Vector2 = section_a[j + 1]
			var b0: Vector2 = section_b[j]
			var b1: Vector2 = section_b[j + 1]
			var faces := (
				keel_faces
				if maxf(a1.x, b1.x) <= hull_stations.design_draft_m + 0.001
				else upper_faces
			)
			## Starboard side.
			faces.append([
				Vector3(a0.y, a0.x, za),
				Vector3(b0.y, b0.x, zb),
				Vector3(b1.y, b1.x, zb),
			])
			faces.append([
				Vector3(a0.y, a0.x, za),
				Vector3(b1.y, b1.x, zb),
				Vector3(a1.y, a1.x, za),
			])
			## Port side.
			faces.append([
				Vector3(-a0.y, a0.x, za),
				Vector3(-b1.y, b1.x, zb),
				Vector3(-b0.y, b0.x, zb),
			])
			faces.append([
				Vector3(-a0.y, a0.x, za),
				Vector3(-a1.y, a1.x, za),
				Vector3(-b1.y, b1.x, zb),
			])
		## Flat bottom between the lowest port/starboard rails.
		var low_a: Vector2 = section_a[0]
		var low_b: Vector2 = section_b[0]
		keel_faces.append([
			Vector3(-low_a.y, low_a.x, za),
			Vector3(-low_b.y, low_b.x, zb),
			Vector3(low_b.y, low_b.x, zb),
		])
		keel_faces.append([
			Vector3(-low_a.y, low_a.x, za),
			Vector3(low_b.y, low_b.x, zb),
			Vector3(low_a.y, low_a.x, za),
		])

	_append_loft_cap(
		upper_faces,
		keel_faces,
		hull_stations.stations[0] as Dictionary,
		hull_stations.design_draft_m
	)
	_append_loft_cap(
		upper_faces,
		keel_faces,
		hull_stations.stations[station_count - 1] as Dictionary,
		hull_stations.design_draft_m
	)
	var upper_mat := make_material(color, roughness, metallic, double_sided)
	upper_mat.resource_name = "Hull Topsides"
	var keel_mat := make_material(keel_color, 0.96, 0.0, double_sided)
	keel_mat.resource_name = "Anti-fouling Keel"
	var center := Vector3(0.0, hull_stations.height_m * 0.5, 0.0)
	var mesh := _commit_loft_surface(upper_faces, upper_mat, center)
	mesh = _commit_loft_surface(keel_faces, keel_mat, center, mesh)
	mi.mesh = mesh
	return mi


static func _commit_loft_surface(
	faces: Array,
	material: Material,
	hull_center: Vector3,
	existing_mesh: ArrayMesh = null,
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	st.set_material(material)
	for face in faces:
		_add_clockwise_outward_face(st, face as Array, hull_center)
	st.generate_normals()
	return st.commit(existing_mesh)


## Convex point clouds for a bounded longitudinal decomposition. Jolt computes
## one convex hull per cloud; no concave trimesh is attached to a dynamic boat.
static func lofted_collision_slices(
	hull_stations: HullStations,
	max_slices: int = 10,
) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	if hull_stations == null or hull_stations.stations.size() < 2:
		return result
	var segment_count := hull_stations.stations.size() - 1
	var slice_count := clampi(max_slices, 1, segment_count)
	for slice_idx in range(slice_count):
		var first := floori(float(slice_idx) * float(segment_count) / float(slice_count))
		var last := ceili(
			float(slice_idx + 1) * float(segment_count) / float(slice_count)
		)
		last = clampi(last, first + 1, segment_count)
		var points := PackedVector3Array()
		for station_idx in range(first, last + 1):
			var station: Dictionary = hull_stations.stations[station_idx]
			var z := float(station["z"])
			var section: Array = station["section"]
			for raw_point in section:
				var point := raw_point as Vector2
				points.append(Vector3(-point.y, point.x, z))
				points.append(Vector3(point.y, point.x, z))
		if points.size() >= 4:
			result.append(points)
	return result


static func _append_loft_cap(
	upper_faces: Array,
	keel_faces: Array,
	station: Dictionary,
	design_draft_m: float,
) -> void:
	var section: Array = station["section"]
	if section.size() < 2:
		return
	var z := float(station["z"])
	var outline: Array[Vector3] = []
	for raw_point in section:
		var point := raw_point as Vector2
		outline.append(Vector3(-point.y, point.x, z))
	for j in range(section.size() - 1, -1, -1):
		var point := section[j] as Vector2
		outline.append(Vector3(point.y, point.x, z))
	var center := Vector3.ZERO
	for point in outline:
		center += point
	center /= float(outline.size())
	for j in range(outline.size()):
		var face := [center, outline[j], outline[(j + 1) % outline.size()]]
		var average_y := (
			center.y + outline[j].y + outline[(j + 1) % outline.size()].y
		) / 3.0
		if average_y <= design_draft_m:
			keel_faces.append(face)
		else:
			upper_faces.append(face)


static func _add_clockwise_outward_face(
	st: SurfaceTool,
	face: Array,
	hull_center: Vector3,
) -> void:
	var a := face[0] as Vector3
	var b := face[1] as Vector3
	var c := face[2] as Vector3
	var geometric_normal := (b - a).cross(c - a)
	if geometric_normal.length_squared() <= 0.0000000001:
		return
	var face_center := (a + b + c) / 3.0
	## Godot's visible front face is clockwise, opposite the geometric
	## cross-product winding used to decide which direction is outward.
	if geometric_normal.dot(face_center - hull_center) > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)


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


## Builds a custom JSON mesh from flat vertex/index arrays. Geometry is cached
## independently from appearance, so differently coloured or textured instances
## share one ArrayMesh. UVs are optional and contain one Vector2 per vertex.
##
## `geometry_cache_id` is the fast production path for data-authored assets. It
## must remain stable for a specific authored mesh. Callers without a stable id
## fall back to a content hash, which is safe but costs O(vertex count) at spawn.
static func from_data(
	vertices: Array,
	indices: Array,
	color: Color,
	roughness: float = 0.55,
	metallic: float = 0.05,
	uvs: Array = [],
	texture_path: String = "",
	texture_mask_path: String = "",
	primary_color: Color = Color.WHITE,
	secondary_color: Color = Color.WHITE,
	geometry_cache_id: String = "",
) -> MeshInstance3D:
	var geometry_key := _geometry_cache_key(vertices, indices, uvs, geometry_cache_id)
	var mesh := _geometry_cache.get(geometry_key, null) as ArrayMesh
	if mesh == null:
		var built := _from_data_uncached(vertices, indices, uvs)
		mesh = built.mesh as ArrayMesh
		if mesh != null:
			_geometry_cache[geometry_key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = (
		make_palette_masked_material(
			texture_path,
			texture_mask_path,
			primary_color,
			secondary_color,
			color,
			roughness,
			metallic,
		)
		if not texture_mask_path.is_empty()
		else make_textured_material(texture_path, color, roughness, metallic, true)
		if not texture_path.is_empty()
		else make_material(color, roughness, metallic, true)
	)
	return mi


static func _geometry_cache_key(
		vertices: Array,
		indices: Array,
		uvs: Array,
		geometry_cache_id: String,
) -> String:
	if not geometry_cache_id.is_empty():
		return "asset:" + geometry_cache_id
	return "%d:%d:%d|%d|%d" % [
		vertices.size(),
		indices.size(),
		uvs.size(),
		hash(vertices),
		hash([indices, uvs]),
	]


static func _from_data_uncached(
	vertices: Array,
	indices: Array,
	uvs: Array = [],
) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var v3_array: Array[Vector3] = []
	for i in range(0, vertices.size(), 3):
		v3_array.append(Vector3(vertices[i], vertices[i+1], vertices[i+2]))
	var uv_array: Array[Vector2] = []
	if uvs.size() == v3_array.size() * 2:
		for i in range(0, uvs.size(), 2):
			uv_array.append(Vector2(float(uvs[i]), float(uvs[i + 1])))

	# JSON authoring uses CW winding; Godot expects CCW — swap the last two indices.
	# Each triangle emits 3 unique vertices so generate_normals() gives flat shading.
	for i in range(0, indices.size(), 3):
		for raw_index in [indices[i], indices[i + 2], indices[i + 1]]:
			var vertex_index := int(raw_index)
			if not uv_array.is_empty():
				st.set_uv(uv_array[vertex_index])
			st.add_vertex(v3_array[vertex_index])

	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi
