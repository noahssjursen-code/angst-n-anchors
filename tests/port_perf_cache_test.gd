extends Node


func _ready() -> void:
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
	# Expansion normalizes its input definition. Compare identical input records
	# rather than comparing the original cache key with the normalized key.
	var first := PortExpander.expand(PortDefinition.from_dict(definition.to_dict()), 424242, layout)
	var second := PortExpander.expand(PortDefinition.from_dict(definition.to_dict()), 424242, layout)
	assert(first == second, "PortDataCache should return the same PortData instance")
	assert(first.layout_graph != null, "cached PortData must retain layout graph")
	assert(first.port_id == "perf-cache-test", "cached PortData must retain port id")

	BuildingCache.clear()
	# The old warehouse is archived pending a replacement land model library.
	# Cache any active blueprints, rather than requiring a removed asset.
	for blueprint in BuildingBlueprintCatalog.all():
		var building_a := BuildingCache.instance(blueprint, true)
		var building_b := BuildingCache.instance(blueprint, true)
		assert(building_a.get_child_count() > 0, "building cache must stamp children")
		assert(building_b.get_child_count() > 0, "building cache must stamp children")
		building_a.free()
		building_b.free()
	BuildingCache.clear()

	LandDecorCache.clear()
	var house_a := LandDecorCache.house_instance(3, 0.2, 0.5)
	var house_b := LandDecorCache.house_instance(3, 0.2, 0.5)
	assert(house_a.get_child_count() > 0, "land decor cache must stamp house meshes")
	assert(house_b.get_child_count() == house_a.get_child_count(), "same variant should match child count")
	house_a.free()
	house_b.free()
	LandDecorCache.clear()

	MeshBuilder.clear_material_cache()
	var mat_a := MeshBuilder.make_material(Color(0.2, 0.3, 0.4))
	var mat_b := MeshBuilder.make_material(Color(0.2, 0.3, 0.4))
	assert(mat_a == mat_b, "MeshBuilder material cache should reuse materials")

	print("port_perf_cache_test: PASS")
	get_tree().quit(0)
