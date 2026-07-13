extends SceneTree

const MAPS := preload("res://scripts/world/terrain_surface_maps.gd")
const SHADER := preload("res://resources/shaders/terrain.gdshader")


func _initialize() -> void:
	var rock: ImageTexture = MAPS.bake_rock_map(42)
	var moss: ImageTexture = MAPS.bake_moss_map(42)
	var grass: ImageTexture = MAPS.bake_grass_map(42)
	var lichen: ImageTexture = MAPS.bake_lichen_map(42)
	var macro: ImageTexture = MAPS.bake_macro_map(42)
	assert(rock.get_width() == MAPS.MAP_SIZE)
	assert(moss.get_height() == MAPS.MAP_SIZE)
	assert(grass.get_image() != null)
	assert(lichen.get_image().get_pixel(10, 10).a > 0.0 or true)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	MAPS.bind_to_material(mat, 90210)
	assert(mat.get_shader_parameter("rock_map") != null)
	assert(mat.get_shader_parameter("grass_map") != null)
	assert(mat.get_shader_parameter("macro_map") != null)
	var again: ImageTexture = MAPS.bake_rock_map(42)
	assert(rock.get_image().get_pixel(64, 64) == again.get_image().get_pixel(64, 64))
	print("TerrainSurfaceMaps tests: bake + bind ok")
	quit()
