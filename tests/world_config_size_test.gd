extends SceneTree

## Smoke: WorldConfig presets + layout generate at small/standard/large sizes.

const TestReport := preload("res://tests/support/test_report.gd")
const WORLD_CONFIG := preload("res://scripts/world/world_config.gd")
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")


func _initialize() -> void:
	var t := TestReport.new("world_config_size_test")
	GENERATOR.clear_cache()
	t.check("small preset", is_equal_approx(WORLD_CONFIG.preset_size_m("small"), 15000.0))
	t.check("standard preset", is_equal_approx(WORLD_CONFIG.preset_size_m("standard"), 40000.0))
	t.check("large preset", is_equal_approx(WORLD_CONFIG.preset_size_m("large"), 100000.0))
	t.check("clamp min", WORLD_CONFIG.validate_size_m(5000.0) >= WORLD_CONFIG.MIN_SIZE_M)
	t.check("clamp max", WORLD_CONFIG.validate_size_m(200000.0) <= WORLD_CONFIG.MAX_SIZE_M)

	## Full bake for small + standard; large only resolves config (513² is heavy for CI).
	for size in [15000.0, 40000.0]:
		var layout: WorldLayout = GENERATOR.generate(42, WORLD_CONFIG.ARCHETYPE_PATH, size)
		if not t.check("layout for %.0f" % size, layout != null):
			continue
		t.check("size stamped %.0f" % size, is_equal_approx(layout.world_size_m, size))
		t.check("checksum %.0f" % size, not layout.layout_checksum.is_empty())

	var large_cfg: Dictionary = WORLD_CONFIG.resolve(100000.0)
	t.check("large resolve size", is_equal_approx(float(large_cfg["world_size_m"]), 100000.0))
	t.check("large raster capped", int(large_cfg["raster_resolution"]) <= WORLD_CONFIG.MAX_RASTER)

	for step in [25.0, 50.0, 100.0, 200.0]:
		t.check("step %.0f divides chunk" % step, is_equal_approx(fmod(1000.0, step), 0.0))

	var a: WorldLayout = GENERATOR.generate(7, WORLD_CONFIG.ARCHETYPE_PATH, 40000.0)
	var b: WorldLayout = GENERATOR.generate(7, WORLD_CONFIG.ARCHETYPE_PATH, 15000.0)
	t.not_equal("size changes identity", a.layout_checksum, b.layout_checksum)
	t.finish(self)
