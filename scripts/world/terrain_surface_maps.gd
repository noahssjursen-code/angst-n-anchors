class_name TerrainSurfaceMaps
extends RefCounted

## Runtime-baked detail maps for the mainland terrain shader.
## No imported texture files — images are synthesised from FastNoiseLite so
## MP clients stay deterministic for a given bake seed.

const MAP_SIZE := 256


static func bind_to_material(material: ShaderMaterial, bake_seed: int = 90210) -> void:
	material.set_shader_parameter("rock_map", bake_rock_map(bake_seed))
	material.set_shader_parameter("moss_map", bake_moss_map(bake_seed ^ 0x4d4f5353))
	material.set_shader_parameter("grass_map", bake_grass_map(bake_seed ^ 0x47525353))
	material.set_shader_parameter("lichen_map", bake_lichen_map(bake_seed ^ 0x4c494348))
	material.set_shader_parameter("macro_map", bake_macro_map(bake_seed ^ 0x4d414352))


static func bake_rock_map(bake_seed: int) -> ImageTexture:
	# RGB: base grain, crack mask, wet/speckle variation.
	var n_base := _noise(bake_seed, 0.045, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4, 0.48)
	var n_crack := _noise(bake_seed + 17, 0.11, FastNoiseLite.TYPE_CELLULAR, 2, 0.55)
	n_crack.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var n_speck := _noise(bake_seed + 41, 0.22, FastNoiseLite.TYPE_SIMPLEX, 3, 0.5)
	return _bake_rgb(n_base, n_crack, n_speck, true)


static func bake_moss_map(bake_seed: int) -> ImageTexture:
	var n_cov := _noise(bake_seed, 0.035, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4, 0.52)
	var n_tuft := _noise(bake_seed + 9, 0.16, FastNoiseLite.TYPE_SIMPLEX, 3, 0.55)
	var n_dark := _noise(bake_seed + 23, 0.08, FastNoiseLite.TYPE_VALUE_CUBIC, 2, 0.45)
	return _bake_rgb(n_cov, n_tuft, n_dark, false)


static func bake_grass_map(bake_seed: int) -> ImageTexture:
	var n_blade := _noise(bake_seed, 0.20, FastNoiseLite.TYPE_SIMPLEX, 5, 0.55)
	var n_clump := _noise(bake_seed + 5, 0.05, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3, 0.5)
	var n_dry := _noise(bake_seed + 29, 0.09, FastNoiseLite.TYPE_VALUE, 2, 0.5)
	return _bake_rgb(n_blade, n_clump, n_dry, false)


static func bake_lichen_map(bake_seed: int) -> ImageTexture:
	var n_patch := _noise(bake_seed, 0.07, FastNoiseLite.TYPE_CELLULAR, 3, 0.6)
	n_patch.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var n_edge := _noise(bake_seed + 11, 0.14, FastNoiseLite.TYPE_SIMPLEX, 2, 0.5)
	var n_tone := _noise(bake_seed + 37, 0.03, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2, 0.45)
	return _bake_rgb(n_patch, n_edge, n_tone, false)


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
	for y in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			var u := float(x) / denom
			var v := float(y) / denom
			# Seamless-ish sample: noise is not toroidal, but high-res tiling is
			# broken up further in-shader by macro UV offsets.
			var r := clampf(r_noise.get_noise_2d(u * 512.0, v * 512.0) * 0.5 + 0.5, 0.0, 1.0)
			var g := clampf(g_noise.get_noise_2d(u * 512.0, v * 512.0) * 0.5 + 0.5, 0.0, 1.0)
			var b := clampf(b_noise.get_noise_2d(u * 512.0, v * 512.0) * 0.5 + 0.5, 0.0, 1.0)
			if invert_g:
				g = 1.0 - g
			image.set_pixel(x, y, Color(r, g, b))
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	return tex
