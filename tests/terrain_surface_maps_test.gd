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
	_check_lichen(t, lichen)
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


## `bake_lichen_map` bakes an opaque RGB8 MAP_SIZE² image from three noise
## fields. Alpha alone is satisfied by a blank texture, so the spread of every
## channel is asserted too: a flat, black, or single-pixel image fails here.
func _check_lichen(t: RefCounted, lichen: ImageTexture) -> void:
	var image := lichen.get_image()
	if not t.check("lichen map has an image", image != null):
		return
	t.equal("lichen map width is MAP_SIZE", image.get_width(), MAPS.MAP_SIZE)
	t.equal("lichen map height is MAP_SIZE", image.get_height(), MAPS.MAP_SIZE)
	t.equal("lichen map is opaque RGB8", image.get_format(), Image.FORMAT_RGB8)
	t.equal("lichen map sample is fully opaque", image.get_pixel(10, 10).a, 1.0)
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var distinct := {}
	var samples := 0
	for y in range(0, MAPS.MAP_SIZE, 4):
		for x in range(0, MAPS.MAP_SIZE, 4):
			var pixel := image.get_pixel(x, y)
			low = Vector3(minf(low.x, pixel.r), minf(low.y, pixel.g), minf(low.z, pixel.b))
			high = Vector3(maxf(high.x, pixel.r), maxf(high.y, pixel.g), maxf(high.z, pixel.b))
			distinct[pixel] = true
			samples += 1
	# Measured on seed 42: every channel spans ~0.90 and all 4096 samples differ.
	var span := high - low
	t.check("lichen patch channel spans a real range (%.3f)" % span.x, span.x > 0.5)
	t.check("lichen edge channel spans a real range (%.3f)" % span.y, span.y > 0.5)
	t.check("lichen tone channel spans a real range (%.3f)" % span.z, span.z > 0.5)
	t.check(
		"lichen map is not flat paint (%d/%d distinct samples)" % [distinct.size(), samples],
		distinct.size() > samples / 2,
	)
