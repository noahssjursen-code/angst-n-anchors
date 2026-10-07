class_name TerrainSurfaceMaps
extends RefCounted

## Original ambientCG surface maps; procedural data only controls habitat masks.
## Source/license/hash records live in resources/textures/marine/sources.json.
const MAP_SIZE := 256
static var _cached_seed := -2147483648
static var _cached_maps: Dictionary = {}


static func bind_to_material(material: ShaderMaterial, bake_seed: int = 90210) -> void:
	if _cached_maps.is_empty() or _cached_seed != bake_seed:
		_cached_seed = bake_seed
		_cached_maps = {"macro_map": bake_macro_map(bake_seed ^ 0x4d414352)}
		for pair in [["stone", "Rock030"], ["heath", "Ground037"], ["soil", "Ground048"]]:
			for channel in [["color", "Color"], ["normal", "NormalGL"], ["roughness", "Roughness"]]:
				var path := "res://resources/textures/marine/%s/%s_1K-PNG_%s.png" % [pair[1], pair[1], channel[1]]
				_cached_maps[pair[0] + "_" + channel[0]] = load(path)
	for name in _cached_maps: material.set_shader_parameter(name, _cached_maps[name])


static func bake_macro_map(bake_seed: int) -> ImageTexture:
	# Large coastal / hillside breakup so 1 km chunks do not read as flat paint.
	var n_a := _noise(bake_seed, 0.008, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4, 0.5)
	var n_b := _noise(bake_seed + 7, 0.018, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3, 0.5)
	var n_c := _noise(bake_seed + 19, 0.004, FastNoiseLite.TYPE_VALUE_CUBIC, 2, 0.5)
	return _bake_rgb(n_a, n_b, n_c, false)


static func _noise(
		bake_seed: int,
		frequency: float,
		noise_type: int,
		octaves: int,
		gain: float,
) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = bake_seed
	noise.noise_type = noise_type
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.1
	return noise


static func _bake_rgb(
		r_noise: FastNoiseLite,
		g_noise: FastNoiseLite,
		b_noise: FastNoiseLite,
		invert_g: bool,
) -> ImageTexture:
	var image := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var denom := float(MAP_SIZE)
	var circle := PackedVector2Array()
	for i in MAP_SIZE:
		var angle := TAU * float(i) / denom
		circle.append(Vector2(cos(angle), sin(angle)))
	for y in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			# A 3D torus is periodic in both texture axes, including derivatives.
			# No cross-faded tile borders or world-visible noise discontinuity.
			var radius := 150.0 + 81.0 * circle[y].x
			var p := Vector3(radius * circle[x].x, radius * circle[x].y, 81.0 * circle[y].y)
			var r := clampf(r_noise.get_noise_3d(p.x,p.y,p.z) * 0.5 + 0.5, 0.0, 1.0)
			var g := clampf(g_noise.get_noise_3d(p.x,p.y,p.z) * 0.5 + 0.5, 0.0, 1.0)
			var b := clampf(b_noise.get_noise_3d(p.x,p.y,p.z) * 0.5 + 0.5, 0.0, 1.0)
			if invert_g:
				g = 1.0 - g
			image.set_pixel(x, y, Color(r, g, b))
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	return tex
