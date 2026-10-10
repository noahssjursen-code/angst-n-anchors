class_name CoastalBuildingLibrary
extends RefCounted

## Shared authored shells; far meshes retain roof, openings and paint placement.
## No scene-node cache and no independent material allocations per house.
const ROOT := "res://resources/models/scenery/coastal_settlement/"
const WINDOW_SHADER := preload("res://resources/shaders/coastal_building.gdshader")
const COLOURS := [Color("dad7c8"), Color("893c30"), Color("bd9d59"), Color("d2d2c5"), Color("607373"), Color("746454")]
static var _cache := {}
static var _sources := {}
static var _window_materials: Array[ShaderMaterial] = []
static var _night_factor := 0.0

static func mesh(kind: String, near: bool, paint: int) -> ArrayMesh:
	paint = posmod(paint, COLOURS.size())
	var key := "%s:%s:%d" % [kind, near, paint]
	if _cache.has(key): return _cache[key]
	var id := kind + ("_near" if near else "_far")
	if not _sources.has(id):
		var root := (load(ROOT + id + ".glb") as PackedScene).instantiate()
		var node := root.find_child("*", true, false) as MeshInstance3D
		if node == null:
			for candidate in root.find_children("*", "MeshInstance3D", true, false): node = candidate; break
		assert(node != null)
		_sources[id] = node.mesh
		root.free()
	var source: ArrayMesh = _sources[id]
	var output := source.duplicate() as ArrayMesh
	for surface in output.get_surface_count():
		var original: StandardMaterial3D = source.surface_get_material(surface)
		var name := original.resource_name
		var color := original.albedo_color
		var profile := ""
		match name:
			"Coastal painted timber": profile = "painted_timber"; color = COLOURS[paint]
			"Coastal window trim": profile = "painted_timber"
			"Coastal standing seam roof": profile = "roof_sheet"
			"Coastal stone plinth": profile = "working_concrete"
			"Coastal timber door": profile = "painted_timber"
		if not profile.is_empty(): output.surface_set_material(surface, SurfaceMaterialLibrary.material(profile, color, name))
		else:
			var glass := ShaderMaterial.new();glass.shader=WINDOW_SHADER
			glass.set_shader_parameter("glass_colour",color)
			glass.set_shader_parameter("night_factor",_night_factor)
			glass.set_meta("coastal_glass",true)
			_window_materials.append(glass)
			output.surface_set_material(surface, glass)
	if not near: output = _merge_distant(output)
	_cache[key] = output
	return output

static func _merge_distant(source: ArrayMesh) -> ArrayMesh:
	# Subpixel finish detail belongs in mipmaps; a single draw retains the
	# physical geometry and averaged colours of the approved close materials.
	var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for surface in source.get_surface_count():
		var material := source.surface_get_material(surface)
		var color := SurfaceMaterialLibrary.colour_of(material)
		var glazing := material.has_meta("coastal_glass")
		if glazing: color=material.get_shader_parameter("glass_colour")
		color=color.srgb_to_linear();color.a=1.0 if glazing else 0.0
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in vertices.size(): indices.append(index)
		for index in indices:
			tool.set_color(color); tool.set_normal(normals[index]); tool.add_vertex(vertices[index])
	tool.index()
	var result := tool.commit()
	var finish := ShaderMaterial.new();finish.shader=WINDOW_SHADER
	finish.set_shader_parameter("distant_shell",true)
	finish.set_shader_parameter("night_factor",_night_factor)
	_window_materials.append(finish)
	result.surface_set_material(0, finish)
	return result

static func set_night_factor(value: float) -> void:
	if absf(value-_night_factor)<.001:return
	_night_factor=value
	for material in _window_materials:material.set_shader_parameter("night_factor",value)

static func clear() -> void:
	_cache.clear(); _sources.clear();_window_materials.clear()
