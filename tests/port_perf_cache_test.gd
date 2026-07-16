extends SceneTree


func _initialize() -> void:
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
	assert(first == second, "PortDataCache should return the same PortData instance")
	assert(first.layout_graph != null, "cached PortData must retain layout graph")
	assert(first.port_id == "perf-cache-test", "cached PortData must retain port id")

	BuildingCache.clear()
	var warehouse := BuildingBlueprintCatalog.by_id("warehouse")
	assert(warehouse != null, "warehouse blueprint must load")
	var building_a := BuildingCache.instance(warehouse, true)
	var building_b := BuildingCache.instance(warehouse, true)
	assert(building_a.get_child_count() > 0, "building cache must stamp children")
	assert(building_b.get_child_count() > 0, "building cache must stamp children")

	LandDecorCache.clear()
	var house_a := LandDecorCache.house_instance(3, 0.2, 0.5)
	var house_b := LandDecorCache.house_instance(3, 0.2, 0.5)
	assert(house_a.get_child_count() > 0, "land decor cache must stamp house meshes")
	assert(house_b.get_child_count() == house_a.get_child_count(), "same variant should match child count")

	MeshBuilder.clear_material_cache()
	var mat_a := MeshBuilder.make_material(Color(0.2, 0.3, 0.4))
	var mat_b := MeshBuilder.make_material(Color(0.2, 0.3, 0.4))
	assert(mat_a == mat_b, "MeshBuilder material cache should reuse materials")

	print("port_perf_cache_test: PASS")
	quit(0)
