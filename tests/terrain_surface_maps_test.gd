extends SceneTree
const MAPS := preload("res://scripts/world/terrain_surface_maps.gd")
const SHADER := preload("res://resources/shaders/terrain.gdshader")

func _initialize() -> void:
	var start := Time.get_ticks_msec()
	var maps := [MAPS.bake_macro_map(42)]
	for texture in maps:
		var img: Image = texture.get_image()
		assert(img.get_width() == MAPS.MAP_SIZE and img.has_mipmaps())
		# Across a periodic boundary, adjacent texels must be as continuous as
		# adjacent interior texels. Do not demand duplicate edge texels.
		for horizontal in [true, false]:
			var seam := 0.0
			var interior := 0.0
			for i in MAPS.MAP_SIZE:
				seam += difference(img.get_pixel(0,i) if horizontal else img.get_pixel(i,0), img.get_pixel(255,i) if horizontal else img.get_pixel(i,255))
				for j in [1,2,253,254]:
					interior += difference(img.get_pixel(j,i) if horizontal else img.get_pixel(i,j),img.get_pixel(j-1,i) if horizontal else img.get_pixel(i,j-1)) / 4.0
			assert(seam < interior * 1.8 + .02, "Texture seam exceeds local gradient")
	assert(maps[0].get_image().get_data() == MAPS.bake_macro_map(42).get_image().get_data())
	var first := ShaderMaterial.new(); first.shader = SHADER
	var second := ShaderMaterial.new(); second.shader = preload("res://resources/shaders/terrain_far.gdshader")
	MAPS.bind_to_material(first,42); MAPS.bind_to_material(second,42)
	for name in ["stone_color","heath_color","soil_color","stone_normal","heath_normal","soil_normal","stone_roughness","heath_roughness","soil_roughness","macro_map"]:
		assert(first.get_shader_parameter(name) != null)
		assert(first.get_shader_parameter(name) == second.get_shader_parameter(name), "Repeated seed rebaked maps")
	var original: ImageTexture = first.get_shader_parameter("macro_map")
	MAPS.bind_to_material(second,43)
	assert(original != second.get_shader_parameter("macro_map"))
	assert(original.get_image().get_data() != second.get_shader_parameter("macro_map").get_image().get_data())
	assert(first.get_shader_parameter("macro_map") == original, "New seed changed existing world material")
	print("TerrainSurfaceMaps PASS: periodic edges, mipmaps, deterministic data, shared cache and seed isolation; ms=",Time.get_ticks_msec()-start)
	quit()

func difference(a: Color,b: Color) -> float:
	return absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
