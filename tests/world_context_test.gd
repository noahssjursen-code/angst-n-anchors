extends SceneTree

const WORLD_CONTEXT := preload("res://scripts/world/world_generation_context.gd")
const PORT_DEFINITION := preload("res://scripts/port/port_definition.gd")


func _initialize() -> void:
	assert(WORLD_CONTEXT.matches({}, {"seed": 42}), "legacy saves adopt current world")
	var current := {"seed": 42, "generation_version": 1, "layout_checksum": "abc"}
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
	definition.region_kind = PORT_DEFINITION.RegionKind.FJORD
	definition.ground_mode = PORT_DEFINITION.GroundMode.WORLD_TERRAIN
	var restored = PORT_DEFINITION.from_dict(definition.to_dict())
	assert(restored.has_explicit_rotation)
	assert(is_equal_approx(restored.rotation_y, 1.25))
	assert(restored.region_kind == PORT_DEFINITION.RegionKind.FJORD)
	assert(restored.ground_mode == PORT_DEFINITION.GroundMode.WORLD_TERRAIN)

	print("World context tests: all checks passed")
	quit()
