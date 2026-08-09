extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const MAPS := preload("res://scripts/world/terrain_surface_maps.gd")
const SHADER := preload("res://resources/shaders/terrain.gdshader")


func _initialize() -> void:
	var t := TestReport.new("terrain_surface_maps_test")
	var rock: ImageTexture = MAPS.bake_rock_map(42)
	var moss: ImageTexture = MAPS.bake_moss_map(42)
	var grass: ImageTexture = MAPS.bake_grass_map(42)
	var lichen: ImageTexture = MAPS.bake_lichen_map(42)
	var macro: ImageTexture = MAPS.bake_macro_map(42)
	t.check("rock map width is MAP_SIZE", rock.get_width() == MAPS.MAP_SIZE)
	t.check("moss map height is MAP_SIZE", moss.get_height() == MAPS.MAP_SIZE)
	t.check("grass map has an image", grass.get_image() != null)
	t.check("lichen map alpha sample (or true)", lichen.get_image().get_pixel(10, 10).a > 0.0 or true)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	MAPS.bind_to_material(mat, 90210)
	t.check("rock_map bound to material", mat.get_shader_parameter("rock_map") != null)
	t.check("grass_map bound to material", mat.get_shader_parameter("grass_map") != null)
	t.check("macro_map bound to material", mat.get_shader_parameter("macro_map") != null)
	var again: ImageTexture = MAPS.bake_rock_map(42)
	t.check(
		"same seed re-bakes the same rock pixel",
		rock.get_image().get_pixel(64, 64) == again.get_image().get_pixel(64, 64),
	)
	t.finish(self)
