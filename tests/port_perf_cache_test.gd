extends Node

## LANE B. This file reaches `BuildingCache`, which preloads
## `scripts/port/building_fitout.gd` -> `scripts/ship/brick_door.gd`, and
## `brick_door.gd:96` names the `WorldGateway` autoload as a bare compile-time
## identifier. Under `--script` that is `Identifier not found`, the failure
## cascades to the test itself, and Godot then loads and runs it anyway — so the
## unit reported `FAIL(2)` in the results table with no way to tell a compile
## failure from an assertion failure. `REALITY.md` §4a: fix the compile before
## trusting one word of what a unit asserts. Booted as a scene the autoloads
## exist and the cascade is gone.

const TestReport := preload("res://tests/support/test_report.gd")


func _ready() -> void:
	var t := TestReport.new("port_perf_cache_test")
	var layout := WorldLayoutGenerator.generate(424242)
	var definition := PortDefinition.new()
	definition.port_id = "perf-cache-test"
	definition.display_name = "Cache Test"
	definition.world_position = Vector3(1200.0, 0.0, -800.0)
	definition.size = 2
	definition.site_seed = 9911
	definition.rotation_y = 0.4
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION

	PortDataCache.clear()
	var first := PortExpander.expand(definition, 424242, layout)
	var second := PortExpander.expand(definition, 424242, layout)
	t.check("PortDataCache should return the same PortData instance", first == second)
	t.check("cached PortData must retain layout graph", first.layout_graph != null)
	t.equal("cached PortData must retain port id", first.port_id, "perf-cache-test")

	## `resources/data/buildings/` has held only `.gitkeep` since `aabdf198`
	## wiped `BrickCatalog.BRICKS` to `{}`, so this is red on a product blocker
	## and stays red until the parts vocabulary can author a blueprint again.
	## It used to `return` here, which buried the six unrelated checks below
	## behind a catalogue that has nothing to do with land decor or materials.
	## Record it and carry on: the failure still reddens the unit.
	BuildingCache.clear()
	var warehouse := BuildingBlueprintCatalog.by_id("warehouse")
	if t.check("warehouse blueprint must load", warehouse != null):
		var building_a := BuildingCache.instance(warehouse, true)
		var building_b := BuildingCache.instance(warehouse, true)
		t.check("building cache must stamp children", building_a.get_child_count() > 0)
		t.check("building cache must stamp children", building_b.get_child_count() > 0)

	LandDecorCache.clear()
	var house_a := LandDecorCache.house_instance(3, 0.2, 0.5)
	var house_b := LandDecorCache.house_instance(3, 0.2, 0.5)
	t.check("land decor cache must stamp house meshes", house_a.get_child_count() > 0)
	t.equal(
		"same variant should match child count",
		house_b.get_child_count(),
		house_a.get_child_count(),
	)

	MeshBuilder.clear_material_cache()
	var mat_a := MeshBuilder.make_material(Color(0.2, 0.3, 0.4))
	var mat_b := MeshBuilder.make_material(Color(0.2, 0.3, 0.4))
	t.check("MeshBuilder material cache should reuse materials", mat_a == mat_b)

	t.finish(get_tree())
