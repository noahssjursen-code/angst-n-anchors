extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const WORLD_CONTEXT := preload("res://scripts/world/world_generation_context.gd")
const PORT_DEFINITION := preload("res://scripts/port/port_definition.gd")


func _initialize() -> void:
	var t := TestReport.new("world_context_test")
	t.check("legacy saves adopt current world", WORLD_CONTEXT.matches({}, {"seed": 42}))
	var current := {"seed": 42, "generation_version": 1, "layout_checksum": "abc"}
	t.check("identical world contexts match", WORLD_CONTEXT.matches(current, current))
	t.check("different world seed rejects coordinate restore", not WORLD_CONTEXT.matches(
		{"seed": 43, "generation_version": 1, "layout_checksum": "def"}, current
	))
	t.check("different generation version rejects coordinate restore", not WORLD_CONTEXT.matches(
		{"seed": 42, "generation_version": 2, "layout_checksum": "abc"}, current
	))
	t.check("different layout checksum rejects coordinate restore", not WORLD_CONTEXT.matches(
		{"seed": 42, "generation_version": 1, "layout_checksum": "def"}, current
	))
	t.check("pre-checksum world context remains forward compatible", WORLD_CONTEXT.matches(
		{"seed": 42, "generation_version": 1, "layout_checksum": ""}, current
	))

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
	t.check("restored port keeps its explicit rotation flag", restored.has_explicit_rotation)
	t.check("restored rotation_y round trips", is_equal_approx(restored.rotation_y, 1.25))
	t.equal("restored size round trips", restored.size, 2)
	t.equal("restored site_id round trips", restored.site_id, "coast-segment-00042")
	t.equal("restored site_seed round trips", restored.site_seed, 123456)
	t.equal("restored region_kind round trips", restored.region_kind, PORT_DEFINITION.RegionKind.FJORD)
	t.equal(
		"restored ground_mode round trips",
		restored.ground_mode,
		PORT_DEFINITION.GroundMode.WORLD_TERRAIN,
	)

	t.finish(self)
