extends SceneTree

const WORLD_CONTEXT := preload("res://scripts/world/world_generation_context.gd")
const PORT_DEFINITION := preload("res://scripts/port/port_definition.gd")


func _initialize() -> void:
	assert(WORLD_CONTEXT.matches({}, {"seed": 42}), "legacy saves adopt current world")
	var current := {"seed": 42, "generation_version": 1, "layout_checksum": "abc"}
	var standard := {"seed": 42, "generation_version": 8, "layout_checksum": "", "world_size_m": 40000.0}
	var compact := standard.duplicate()
	compact.world_size_m = 30000.0
	assert(not WORLD_CONTEXT.matches(standard, compact), "dimensions reject mismatched coordinates before checksum is ready")
	assert(WORLD_CONTEXT.matches(compact, compact), "compact world matches itself")
	assert(WORLD_CONTEXT.matches(current, current), "identical world contexts match")
	assert(not WORLD_CONTEXT.matches(
		{"seed": 43, "generation_version": 1, "layout_checksum": "def"}, current
	), "different world seed rejects coordinate restore")
	assert(not WORLD_CONTEXT.matches(
		{"seed": 42, "generation_version": 2, "layout_checksum": "abc"}, current
	), "different generation version rejects coordinate restore")
	assert(not WORLD_CONTEXT.matches(
		{"seed": 42, "generation_version": 1, "layout_checksum": "def"}, current
	), "different layout checksum rejects coordinate restore")
	assert(WORLD_CONTEXT.matches(
		{"seed": 42, "generation_version": 1, "layout_checksum": ""}, current
	), "pre-checksum world context remains forward compatible")

	var definition := PORT_DEFINITION.new()
	definition.port_id = "coast-test"
	definition.rotation_y = 1.25
	definition.has_explicit_rotation = true
	definition.size = 2
	definition.site_id = "coast-segment-00042"
	definition.site_seed = 123456
	definition.region_kind = PORT_DEFINITION.RegionKind.FJORD
	definition.ground_mode = PORT_DEFINITION.GroundMode.WORLD_TERRAIN
	var restored = PORT_DEFINITION.from_dict(definition.to_dict())
	assert(restored.has_explicit_rotation)
	assert(is_equal_approx(restored.rotation_y, 1.25))
	assert(restored.size == 2)
	assert(restored.site_id == "coast-segment-00042")
	assert(restored.site_seed == 123456)
	assert(restored.region_kind == PORT_DEFINITION.RegionKind.FJORD)
	assert(restored.ground_mode == PORT_DEFINITION.GroundMode.WORLD_TERRAIN)

	print("World context tests: all checks passed")
	quit()
