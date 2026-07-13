class_name ForestTreeMesh
extends RefCounted

## Decorative spruce silhouettes for MultiMesh stamping.
## Built as flat-shaded ArrayMeshes — no CylinderMesh / cone stacks.

const CANOPY := Color(0.045, 0.085, 0.042)
const TRUNK := Color(0.12, 0.09, 0.06)

static var _near_mesh: ArrayMesh
static var _mid_mesh: ArrayMesh
static var _near_material: StandardMaterial3D
static var _mid_material: StandardMaterial3D


static func near_mesh() -> ArrayMesh:
	if _near_mesh == null:
		_near_mesh = build_near_spruce()
	return _near_mesh


static func mid_mesh() -> ArrayMesh:
	if _mid_mesh == null:
		_mid_mesh = build_mid_card()
	return _mid_mesh


static func near_material() -> StandardMaterial3D:
	if _near_material == null:
		_near_material = MeshBuilder.make_material(Color.WHITE, 0.92, 0.0)
		_near_material.vertex_color_use_as_albedo = true
	return _near_material


static func mid_material() -> StandardMaterial3D:
	if _mid_material == null:
		_mid_material = MeshBuilder.make_material(CANOPY, 0.95, 0.0, true)
		_mid_material.albedo_color = Color(CANOPY.r, CANOPY.g, CANOPY.b, 0.92)
		_mid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mid_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mid_material


## Low-poly spruce: box trunk + three diamond canopy tiers (triangle fans).
## Base mesh is ~12 m so Multimesh scale reads as a canopy mass from the sea.
static func build_near_spruce() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(near_material())

	_add_box(st, Vector3(0.0, 1.4, 0.0), Vector3(0.45, 3.2, 0.45), TRUNK)

	_add_canopy_tier(st, 3.4, 3.8, 5.2, CANOPY)
	_add_canopy_tier(st, 6.4, 2.6, 4.4, CANOPY.darkened(0.08))
	_add_canopy_tier(st, 8.9, 1.5, 3.4, CANOPY.darkened(0.16))
	_add_pyramid(st, Vector3(0.0, 11.6, 0.0), 0.55, 2.1, CANOPY.darkened(0.22))

	st.generate_normals()
	return st.commit()


## Crossed soft cards — cheap mid-distance massing without toy cones.
static func build_mid_card() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mid_material())
	var h := 12.0
	var half_w := 3.2
	_add_spruce_card(st, 0.0, half_w, h)
	_add_spruce_card(st, PI * 0.5, half_w, h)
	st.generate_normals()
	return st.commit()


static func _add_spruce_card(st: SurfaceTool, yaw: float, half_w: float, height: float) -> void:
	var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0))
	# Tapered hex outline: wide mid, narrow tip/base — reads as a spruce from afar.
	var local := PackedVector3Array([
		Vector3(0.0, 0.15, 0.0),
		Vector3(-half_w * 0.35, 0.85, 0.0),
		Vector3(-half_w, 1.9, 0.0),
		Vector3(-half_w * 0.55, 3.05, 0.0),
		Vector3(0.0, height, 0.0),
		Vector3(half_w * 0.55, 3.05, 0.0),
		Vector3(half_w, 1.9, 0.0),
		Vector3(half_w * 0.35, 0.85, 0.0),
	])
	var world := PackedVector3Array()
	for p in local:
		world.append(basis * p)
	# Fan from tip for a filled silhouette.
	for i in range(1, world.size() - 1):
		_tri(st, world[0], world[i], world[i + 1], CANOPY)
		_tri(st, world[0], world[i + 1], world[i], CANOPY) # backface


static func _add_canopy_tier(
		st: SurfaceTool,
		centre_y: float,
		radius: float,
		height: float,
		color: Color,
) -> void:
	var tip := Vector3(0.0, centre_y + height * 0.55, 0.0)
	var base_y := centre_y - height * 0.45
	var sides := 6
	var ring := PackedVector3Array()
	for i in range(sides):
		var a := TAU * float(i) / float(sides)
		ring.append(Vector3(cos(a) * radius, base_y, sin(a) * radius))
	for i in range(sides):
		var a := ring[i]
		var b := ring[(i + 1) % sides]
		_tri(st, tip, a, b, color)


static func _add_pyramid(
		st: SurfaceTool,
		tip: Vector3,
		radius: float,
		height: float,
		color: Color,
) -> void:
	var base_y := tip.y - height
	var ring := PackedVector3Array([
		Vector3(-radius, base_y, -radius),
		Vector3(radius, base_y, -radius),
		Vector3(radius, base_y, radius),
		Vector3(-radius, base_y, radius),
	])
	for i in range(4):
		_tri(st, tip, ring[i], ring[(i + 1) % 4], color)


static func _add_box(st: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var p := PackedVector3Array([
		centre + Vector3(-hx, -hy, -hz),
		centre + Vector3(hx, -hy, -hz),
		centre + Vector3(hx, -hy, hz),
		centre + Vector3(-hx, -hy, hz),
		centre + Vector3(-hx, hy, -hz),
		centre + Vector3(hx, hy, -hz),
		centre + Vector3(hx, hy, hz),
		centre + Vector3(-hx, hy, hz),
	])
	# Bottom, top, sides (CW for MeshBuilder convention / generate_normals).
	_quad(st, p[0], p[1], p[2], p[3], color)
	_quad(st, p[4], p[7], p[6], p[5], color)
	_quad(st, p[0], p[4], p[5], p[1], color)
	_quad(st, p[1], p[5], p[6], p[2], color)
	_quad(st, p[2], p[6], p[7], p[3], color)
	_quad(st, p[3], p[7], p[4], p[0], color)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
