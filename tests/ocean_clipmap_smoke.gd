extends SceneTree

const CLIPMAP := preload("res://scripts/ocean/ocean_clipmap.gd")
const NEAR_SHADER := preload("res://resources/shaders/ocean_waves.gdshader")
const MID_SHADER := preload("res://resources/shaders/ocean_waves_mid.gdshader")
const FAR_SHADER := preload("res://resources/shaders/ocean_waves_far.gdshader")
const HORIZON_SHADER := preload("res://resources/shaders/ocean_horizon.gdshader")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var clipmap := CLIPMAP.new()
	root.add_child(clipmap)
	var materials: Array[ShaderMaterial] = []
	for shader in [NEAR_SHADER, MID_SHADER, FAR_SHADER, HORIZON_SHADER]:
		var material := ShaderMaterial.new()
		material.shader = shader
		materials.append(material)
	clipmap.build(materials)

	var stats: Dictionary = clipmap.get_debug_stats()
	assert(int(stats["active_rings"]) == 9)
	assert(int(stats["vertices"]) >= 90000)
	assert(int(stats["vertices"]) <= 120000)
	assert(int(stats["triangles"]) >= 170000)
	assert(clipmap.get_child_count() == 9)
	for child in clipmap.get_children():
		_assert_clockwise_surface(child)
	for level in range(7):
		var boundary_extent := 48.0 * pow(2.0, level)
		var inner_edge := _boundary_points(clipmap.get_child(level), boundary_extent)
		var outer_edge := _boundary_points(clipmap.get_child(level + 1), boundary_extent)
		assert(inner_edge == outer_edge, "LOD %d/%d boundary is not watertight" % [level, level + 1])
	print("OceanClipmap smoke: %d vertices, %d triangles" % [
		int(stats["vertices"]),
		int(stats["triangles"]),
	])
	quit()


func _assert_clockwise_surface(instance: MeshInstance3D) -> void:
	var arrays := instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var a := vertices[indices[0]]
	var b := vertices[indices[1]]
	var c := vertices[indices[2]]
	assert((b - a).cross(c - a).y < 0.0, "%s is back-face culled from above" % instance.name)


func _boundary_points(instance: MeshInstance3D, extent: float) -> Dictionary:
	var arrays := instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var morph_targets: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var points: Dictionary = {}
	for i in range(vertices.size()):
		var p := morph_targets[i]
		if is_equal_approx(maxf(absf(vertices[i].x), absf(vertices[i].z)), extent):
			points["%.3f:%.3f" % [p.x, p.y]] = true
	return points
