extends SceneTree

## Smoke: WorldConfig presets + layout generate at small/standard/large sizes.

const WORLD_CONFIG := preload("res://scripts/world/world_config.gd")
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")


func _initialize() -> void:
	GENERATOR.clear_cache()
	assert(is_equal_approx(WORLD_CONFIG.preset_size_m("small"), 15000.0), "small preset")
	assert(is_equal_approx(WORLD_CONFIG.preset_size_m("standard"), 40000.0), "standard preset")
	assert(is_equal_approx(WORLD_CONFIG.preset_size_m("large"), 100000.0), "large preset")
	assert(WORLD_CONFIG.validate_size_m(5000.0) >= WORLD_CONFIG.MIN_SIZE_M, "clamp min")
	assert(WORLD_CONFIG.validate_size_m(200000.0) <= WORLD_CONFIG.MAX_SIZE_M, "clamp max")

	## Full bake for small + standard; large only resolves config (513² is heavy for CI).
	for size in [15000.0, 40000.0]:
		var layout: WorldLayout = GENERATOR.generate(42, WORLD_CONFIG.ARCHETYPE_PATH, size)
		assert(layout != null, "layout for %.0f" % size)
		assert(is_equal_approx(layout.world_size_m, size), "size stamped %.0f" % size)
		assert(not layout.layout_checksum.is_empty(), "checksum %.0f" % size)

	var large_cfg: Dictionary = WORLD_CONFIG.resolve(100000.0)
	assert(is_equal_approx(float(large_cfg["world_size_m"]), 100000.0), "large resolve size")
	assert(int(large_cfg["raster_resolution"]) <= WORLD_CONFIG.MAX_RASTER, "large raster capped")

	for step in [25.0, 50.0, 100.0, 200.0]:
		assert(is_equal_approx(fmod(1000.0, step), 0.0), "step %.0f divides chunk" % step)

	var a: WorldLayout = GENERATOR.generate(7, WORLD_CONFIG.ARCHETYPE_PATH, 40000.0)
	var b: WorldLayout = GENERATOR.generate(7, WORLD_CONFIG.ARCHETYPE_PATH, 15000.0)
	assert(a.layout_checksum != b.layout_checksum, "size changes identity")
	print("world_config_size_test: PASS")
	quit(0)
