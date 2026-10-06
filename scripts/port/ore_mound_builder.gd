class_name OreMoundBuilder
extends RefCounted

## Procedural bulk stockpiles — lumpy heap mesh + triplanar grain shader (iron ore / coal).

const ORE_PILE_SHADER := preload("res://resources/shaders/ore_pile.gdshader")

static var _material_cache: Dictionary = {}


static func resolve_commodity(commodity_id: String) -> String:
	return "coal" if commodity_id == "coal" else "iron_ore"


## Root node with one main pile and two satellite lobes. Sits on parent Y=0.
static func build_mound(commodity_id: String, size: Vector3, seed: int = 0) -> Node3D:
	var resolved := resolve_commodity(commodity_id)
	var root := Node3D.new()
	root.name = "OreMound_%s" % resolved

	var main := _build_pile_mesh(size, resolved, seed)
	main.name = "Main"
	root.add_child(main)

	var sat_a := _build_pile_mesh(
		size * Vector3(0.58, 0.48, 0.52),
		resolved,
		seed + 17,
	)
	sat_a.name = "LobeA"
	sat_a.position = Vector3(size.x * 0.20, 0.0, size.z * 0.14)
	root.add_child(sat_a)

	var sat_b := _build_pile_mesh(
		size * Vector3(0.44, 0.38, 0.40),
		resolved,
		seed + 41,
	)
	sat_b.name = "LobeB"
	sat_b.position = Vector3(-size.x * 0.16, 0.0, -size.z * 0.10)
	root.add_child(sat_b)

	return root


static func _build_pile_mesh(size: Vector3, commodity_id: String, seed: int) -> MeshInstance3D:
	var rx := maxf(size.x * 0.5, 0.5)
	var rz := maxf(size.z * 0.5, 0.5)
	var max_h := maxf(size.y, 0.5)
	var res := clampi(int(maxf(rx, rz) * 1.4), 10, 24)

	var heights: Array = []
	for iz in range(res + 1):
		var row: Array = []
		for ix in range(res + 1):
			var fx := float(ix) / float(res)
			var fz := float(iz) / float(res)
			var lx := (fx - 0.5) * 2.0 * rx
			var lz := (fz - 0.5) * 2.0 * rz
			var nx := lx / rx
			var nz := lz / rz
			var dome := maxf(0.0, 1.0 - nx * nx - nz * nz)
			dome = pow(dome, 0.78)
			var lump_a := sin(lx * 0.85 + float(seed) * 0.11) * cos(lz * 0.72 + float(seed) * 0.07)
			var lump_b := sin(lx * 2.15 + lz * 1.65 + float(seed) * 0.23)
			var lump := (lump_a * 0.5 + lump_b * 0.5) * 0.5 + 0.5
			var h := max_h * dome * lerpf(0.72, 1.10, lump)
			row.append(h)
		heights.append(row)

	var mat := _material_for(commodity_id)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	for iz in range(res):
		for ix in range(res):
			var x0 := (float(ix) / float(res) - 0.5) * 2.0 * rx
			var x1 := (float(ix + 1) / float(res) - 0.5) * 2.0 * rx
			var z0 := (float(iz) / float(res) - 0.5) * 2.0 * rz
			var z1 := (float(iz + 1) / float(res) - 0.5) * 2.0 * rz
			var p00 := Vector3(x0, heights[iz][ix], z0)
			var p10 := Vector3(x1, heights[iz][ix + 1], z0)
			var p01 := Vector3(x0, heights[iz + 1][ix], z1)
			var p11 := Vector3(x1, heights[iz + 1][ix + 1], z1)
			_add_mound_triangle(st, p00, p10, p11)
			_add_mound_triangle(st, p00, p01, p11)

	st.set_smooth_group(-1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


## Height fields face upward, including flat perimeter triangles at y=0.
static func _add_mound_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Empty corners of the height-field grid are pavement, not a square plate of
	# ore. Omitting them also avoids coplanar flicker against the asphalt below.
	if maxf(a.y, maxf(b.y, c.y)) <= 0.0001:
		return
	var n := (b - a).cross(c - a)
	if n.y > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)


static func _material_for(commodity_id: String) -> ShaderMaterial:
	var key := resolve_commodity(commodity_id)
	if _material_cache.has(key):
		return (_material_cache[key] as ShaderMaterial).duplicate()
	var mat := ShaderMaterial.new()
	mat.shader = ORE_PILE_SHADER
	mat.set_shader_parameter("pile_kind", 1 if key == "coal" else 0)
	if key == "iron_ore":
		var catalog := CommodityCatalog.commodity_color("iron_ore")
		mat.set_shader_parameter("iron_base", Vector3(catalog.r, catalog.g, catalog.b))
		mat.set_shader_parameter("iron_rust", Vector3(
			catalog.r * 1.05,
			catalog.g * 1.08,
			catalog.b * 1.02,
		))
		mat.set_shader_parameter("iron_dark", Vector3(
			catalog.r * 0.45,
			catalog.g * 0.42,
			catalog.b * 0.40,
		))
	else:
		var catalog := CommodityCatalog.commodity_color("coal")
		mat.set_shader_parameter("coal_base", Vector3(
			catalog.r * 0.55,
			catalog.g * 0.55,
			catalog.b * 0.55,
		))
		mat.set_shader_parameter("coal_fleck", Vector3(catalog.r, catalog.g, catalog.b))
		mat.set_shader_parameter("coal_highlight", Vector3(
			catalog.r * 1.6,
			catalog.g * 1.65,
			catalog.b * 1.7,
		))
	_material_cache[key] = mat
	return mat.duplicate()


static func material_for(commodity_id: String) -> Material:
	return _material_for(resolve_commodity(commodity_id))
