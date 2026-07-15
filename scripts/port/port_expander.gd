class_name PortExpander
extends RefCounted

## Deterministic converter: PortDefinition + world_seed → initial PortData.
## Pipeline: seeded attributes → trade profile → socketed layout graph.

const POPULATION_RANGE: Dictionary = {
	0: [50, 300],
	1: [300, 1500],
	2: [1500, 6000],
	3: [6000, 25000],
	4: [25000, 100000],
	5: [80000, 250000],
	6: [200000, 600000],
	7: [500000, 1200000],
	8: [1000000, 2500000],
}


static func expand(definition: PortDefinition, world_seed: int, world_layout: WorldLayout = null) -> PortData:
	assert(
		definition.port_generation_version == PortDefinition.CURRENT_PORT_GENERATION_VERSION,
		"PortExpander: incompatible port generation version %d" % definition.port_generation_version,
	)
	var data := PortData.new()
	data.port_id = definition.port_id
	data.display_name = definition.display_name
	data.world_position = definition.world_position
	data.site_id = definition.site_id
	data.port_generation_version = definition.port_generation_version
	data.size = PortSizing.normalized_size(definition.size)

	var site_seed := definition.site_seed if definition.site_seed != 0 \
			else world_seed ^ _hash_id(definition.port_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	data.trade_profile = PortTradeProfile.derive(definition, world_seed)
	data.has_fuel_point = true
	data.has_lighthouse = definition.has_lighthouse or (data.size >= 1 and rng.randf() < 0.3)
	data.has_fog_horn = definition.has_fog_horn or (data.size >= 0 and rng.randf() < 0.4)
	data.layout_graph = PortLayoutGenerator.generate(
		definition,
		data.trade_profile,
		site_seed,
		{
			"has_fuel_point": data.has_fuel_point,
			"has_lighthouse": data.has_lighthouse,
			"has_fog_horn": data.has_fog_horn,
			"world_layout": world_layout,
		},
	)

	var graph_bounds := data.layout_graph.bounds()
	var quay_pose := data.layout_graph.primary_quay_pose()
	data.dock_length = maxf(
		float(quay_pose.get("length_m", 0.0)),
		PortSizing.dock_length_m(data.size),
	)
	data.island_width = maxf(graph_bounds.size.x + 36.0, PortSizing.island_width_m(data.size))
	data.plot_depth = maxf(graph_bounds.size.z + 36.0, PortSizing.PLOT_DEPTH_M)
	data.max_ship_class = _ship_class_for_size(data.size)
	data.berth_count = _count_quay_modules(data.layout_graph)
	data.commodity_export = data.trade_profile.primary_export()
	data.commodity_imports = data.trade_profile.import_slots.duplicate()
	data.layout_seed = site_seed
	var legacy_rotation := rng.randf() * TAU
	data.rotation_y = definition.rotation_y if definition.has_explicit_rotation else legacy_rotation
	data.region_kind = definition.region_kind
	data.ground_mode = definition.ground_mode
	data.population = _population(rng, data.size)
	data.features = ["Terrain-traced Port Layout"]
	if data.has_lighthouse:
		data.features.append("Lighthouse")
	if data.has_fog_horn:
		data.features.append("Fog Horn")
	for commodity in data.trade_profile.export_slots:
		data.features.append("Export:%s" % commodity)
	return data


static func _population(rng: RandomNumberGenerator, size: int) -> int:
	var band: Array = POPULATION_RANGE.get(size, [100, 500])
	return rng.randi_range(int(band[0]), int(band[1]))


static func _hash_id(port_id: String) -> int:
	return port_id.hash()


static func _count_quay_modules(graph: PortLayoutGraph) -> int:
	var count := 0
	for instance_id in graph.module_ids():
		var placed := graph.modules[instance_id] as PortPlacedModule
		var definition := graph.module_definition(placed.module_id)
		if definition != null and definition.kind == "quay":
			count += 1
	return maxi(count, 1)


static func _ship_class_for_size(size: int) -> ShipClass.Type:
	return PortSizing.design_ship_class(size)
