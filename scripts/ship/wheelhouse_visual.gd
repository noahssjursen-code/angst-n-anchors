@tool
class_name WheelhouseVisual
extends Node3D

## Procedural wheelhouse built from a deck footprint polygon (XZ) + box primitives.
## Drop on a superstructure scene root; tune exports in the inspector.

enum FootprintPreset {
	CUSTOM,
	FISHING_SMALL,
	FISHING_MEDIUM,
	FISHING_LARGE,
}

static func _fishing_small_footprint() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.644088, 1.09375),
		Vector2(-0.700112, 0.99975),
		Vector2(-1.185716, -0.17525),
		Vector2(-1.284228, -1.06825),
		Vector2(1.284228, -1.06825),
		Vector2(1.185716, -0.17525),
		Vector2(0.700112, 0.99975),
		Vector2(0.644088, 1.09375),
	])


static func _fishing_medium_footprint() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.8456, 1.3611),
		Vector2(-0.8752, 1.3094),
		Vector2(-1.4821, -0.2181),
		Vector2(-1.5998, -1.3273),
		Vector2(1.5998, -1.3273),
		Vector2(1.4821, -0.2181),
		Vector2(0.8752, 1.3094),
		Vector2(0.8456, 1.3611),
	])


static func _fishing_large_footprint() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-1.135, 1.886),
		Vector2(-1.1503, 1.8578),
		Vector2(-1.9479, -0.2573),
		Vector2(-2.1069, -1.8365),
		Vector2(2.1069, -1.8365),
		Vector2(1.9479, -0.2573),
		Vector2(1.1503, 1.8578),
		Vector2(1.135, 1.886),
	])


@export var footprint_preset: FootprintPreset = FootprintPreset.FISHING_SMALL:
	set(v):
		footprint_preset = v
		_apply_preset_defaults()
		if is_inside_tree():
			_rebuild()

@export var rebuild: bool = false:
	set(v):
		rebuild = false
		if v and is_inside_tree():
			_rebuild()

@export var deck_contact_y: float = 0.3
@export var base_thickness: float = 0.08
@export var wall_height: float = 2.24
@export var roof_thickness: float = 0.07
@export var roof_overhang: float = 0.025
@export var footprint: PackedVector2Array = PackedVector2Array()
@export var mast_height: float = 1.12
@export var mast_diameter: float = 0.1

@export_group("Windows")
@export var window_sill: float = 0.84
@export var window_head: float = 2.04
@export var glass_recess: float = 0.03


func _ready() -> void:
	_apply_preset_defaults()
	_rebuild()


func _apply_preset_defaults() -> void:
	match footprint_preset:
		FootprintPreset.FISHING_SMALL:
			deck_contact_y = 0.3
			wall_height = 2.24
			mast_height = 1.12
			mast_diameter = 0.1
		FootprintPreset.FISHING_MEDIUM:
			deck_contact_y = 0.4
			wall_height = 2.5
			mast_height = 1.24
			mast_diameter = 0.11
		FootprintPreset.FISHING_LARGE:
			deck_contact_y = 0.5
			wall_height = 2.9
			mast_height = 1.44
			mast_diameter = 0.12
		FootprintPreset.CUSTOM:
			pass


func _get_footprint() -> PackedVector2Array:
	if footprint.size() >= 3:
		return footprint
	match footprint_preset:
		FootprintPreset.FISHING_SMALL:
			return _fishing_small_footprint()
		FootprintPreset.FISHING_MEDIUM:
			return _fishing_medium_footprint()
		FootprintPreset.FISHING_LARGE:
			return _fishing_large_footprint()
		_:
			return PackedVector2Array()


func _rebuild() -> void:
	for child in get_children():
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()

	var poly := _get_footprint()
	if poly.size() < 3:
		return

	var y_base := deck_contact_y
	var y_floor := y_base + base_thickness
	var y_eave := y_floor + wall_height
	var y_roof := y_eave + roof_thickness

	_add_mesh("BasePlate", _extrude_cap(poly, y_base, y_floor), Palette.make(Palette.TIMBER))
	var walls_mesh := _extrude_sides(poly, y_floor, y_eave)
	_add_mesh("CabinWalls", walls_mesh, Palette.make(Palette.WHITE_PAINT))
	_add_mesh(
		"Roof",
		_extrude_cap(_expand_polygon(poly, roof_overhang), y_eave, y_roof),
		Palette.make(Palette.CLADDING)
	)
	_add_mast(y_roof)
	_add_windows(poly, y_floor)


func _add_mesh(node_name: String, mesh: Mesh, material: Material) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)
	if Engine.is_editor_hint() and is_inside_tree():
		mi.owner = get_tree().edited_scene_root


func _extrude_sides(poly: PackedVector2Array, y0: float, y1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in range(n):
		var p: Vector2 = poly[i]
		bottom.append(Vector3(p.x, y0, p.y))
		top.append(Vector3(p.x, y1, p.y))
	for i in range(n):
		var j := (i + 1) % n
		_add_quad(st, bottom[i], bottom[j], top[j], top[i])
	return _commit_mesh(st)


func _extrude_cap(poly: PackedVector2Array, y0: float, y1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in range(n):
		var p: Vector2 = poly[i]
		bottom.append(Vector3(p.x, y0, p.y))
		top.append(Vector3(p.x, y1, p.y))
	for i in range(1, n - 1):
		st.add_vertex(bottom[0])
		st.add_vertex(bottom[i])
		st.add_vertex(bottom[i + 1])
	for i in range(1, n - 1):
		st.add_vertex(top[0])
		st.add_vertex(top[i + 1])
		st.add_vertex(top[i])
	for i in range(n):
		var j := (i + 1) % n
		_add_quad(st, bottom[i], bottom[j], top[j], top[i])
	return _commit_mesh(st)


func _commit_mesh(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


func _expand_polygon(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	var cx := 0.0
	var cz := 0.0
	for p: Vector2 in poly:
		cx += p.x
		cz += p.y
	var inv_n := 1.0 / float(poly.size())
	cx *= inv_n
	cz *= inv_n
	var out := PackedVector2Array()
	for p: Vector2 in poly:
		var dx := p.x - cx
		var dz := p.y - cz
		var d := sqrt(dx * dx + dz * dz)
		if d < 0.0001:
			out.append(p)
			continue
		var scale := (d + amount) / d
		out.append(Vector2(cx + dx * scale, cz + dz * scale))
	return out


func _polygon_center(poly: PackedVector2Array) -> Vector2:
	var cx := 0.0
	var cz := 0.0
	for p: Vector2 in poly:
		cx += p.x
		cz += p.y
	var inv_n := 1.0 / float(poly.size())
	return Vector2(cx * inv_n, cz * inv_n)


func _edge_outward_normal(a: Vector2, b: Vector2, center: Vector2) -> Vector2:
	var mx := (a.x + b.x) * 0.5
	var mz := (a.y + b.y) * 0.5
	var ex := b.x - a.x
	var ez := b.y - a.y
	var el := maxf(sqrt(ex * ex + ez * ez), 0.0001)
	var nx := ez / el
	var nz := -ex / el
	if (mx - center.x) * nx + (mz - center.y) * nz < 0.0:
		nx = -nx
		nz = -nz
	return Vector2(nx, nz)


func _classify_face(n: Vector2) -> String:
	if n.y > 0.45:
		return "forward"
	if n.y < -0.45:
		return "aft"
	if n.x > 0.0:
		return "starboard"
	return "port"


func _lerp_edge(a: Vector2, b: Vector2, t: float) -> Vector2:
	return Vector2(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t))


func _add_glass(
	p0: Vector2,
	p1: Vector2,
	y0: float,
	y1: float,
	normal: Vector2,
	suffix: String
) -> void:
	var inset := glass_recess
	var o0 := Vector2(p0.x + normal.x * inset, p0.y + normal.y * inset)
	var o1 := Vector2(p1.x + normal.x * inset, p1.y + normal.y * inset)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(o0.x, y0, o0.y)
	var b := Vector3(o1.x, y0, o1.y)
	var c := Vector3(o1.x, y1, o1.y)
	var d := Vector3(o0.x, y1, o0.y)
	_add_quad(st, a, b, c, d)
	var mesh := _commit_mesh(st)
	var mat := Palette.make(Palette.GLASS_TINTED, true)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.72
	_add_mesh("Window_%s" % suffix, mesh, mat)


func _add_windows(poly: PackedVector2Array, y_floor: float) -> void:
	var center := _polygon_center(poly)
	var y0 := y_floor + window_sill
	var y1 := y_floor + window_head
	var n := poly.size()
	for i in range(n):
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % n]
		var normal := _edge_outward_normal(p0, p1, center)
		var face := _classify_face(normal)
		var el := p0.distance_to(p1)
		match face:
			"forward":
				if el > 0.55:
					var w0 := _lerp_edge(p0, p1, 0.12)
					var w1 := _lerp_edge(p0, p1, 0.88)
					_add_glass(w0, w1, y0, y1, normal, "fwd_%d" % i)
			"port", "starboard":
				if el > 0.75:
					var s0 := _lerp_edge(p0, p1, 0.22)
					var s1 := _lerp_edge(p0, p1, 0.78)
					_add_glass(s0, s1, y0 + 0.05, y1 - 0.08, normal, "side_%d" % i)
			"aft":
				if el > 1.0:
					var a0 := _lerp_edge(p0, p1, 0.08)
					var a1 := _lerp_edge(p0, p1, 0.32)
					_add_glass(a0, a1, y0 + 0.12, y1 - 0.05, normal, "aft_%d" % i)


func _add_mast(y_roof: float) -> void:
	var center := _polygon_center(_get_footprint())
	var bm := BoxMesh.new()
	bm.size = Vector3(mast_diameter, mast_height, mast_diameter)
	var mi := MeshInstance3D.new()
	mi.name = "Mast"
	mi.mesh = bm
	mi.material_override = Palette.make(Palette.EXHAUST_STEEL)
	mi.position = Vector3(center.x, y_roof + mast_height * 0.5, center.y + 0.35)
	add_child(mi)
	if Engine.is_editor_hint() and is_inside_tree():
		mi.owner = get_tree().edited_scene_root
