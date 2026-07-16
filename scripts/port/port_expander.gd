class_name PortExpander
extends RefCounted

## Deterministic converter: PortDefinition + world_seed → initial PortData.
## Pipeline: trade profile → coast-traced foundation + berth_plan → PortData.

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


## Chart / menu summary without coast tracing or PortLayoutGraph generation.
## Same trade + size rules as `expand`, cheap enough for dozens of ports.
static func chart_summary(definition: PortDefinition, world_seed: int) -> Dictionary:
	assert(
		definition.port_generation_version == PortDefinition.CURRENT_PORT_GENERATION_VERSION,
		"PortExpander: incompatible port generation version %d" % definition.port_generation_version,
	)
	var site_max := clampi(
		definition.site_max_size if definition.site_max_size > 0 else PortSizing.MAX_SIZE,
		PortSizing.MIN_SIZE,
		PortSizing.MAX_SIZE,
	)
	var size := mini(PortSizing.normalized_size(definition.size), site_max)
	var site_seed := definition.site_seed if definition.site_seed != 0 \
			else world_seed ^ _hash_id(definition.port_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	## Clone definition fields the trade profile may read without mutating caller size forever.
	var def_size := definition.size
	definition.size = size
	var trade := PortTradeProfile.derive(definition, world_seed)
	var trade_max := PortTradeProfile.max_size_for_profile(trade)
	site_max = mini(site_max, trade_max)
	if size > site_max:
		size = site_max
		definition.size = size
		PortTradeProfile.resync_for_size(trade, size)
	definition.size = def_size

	var has_lighthouse := definition.has_lighthouse or (size >= 1 and rng.randf() < 0.3)
	var has_fog_horn := definition.has_fog_horn or (size >= 0 and rng.randf() < 0.4)
	var features: Array[String] = []
	if has_lighthouse:
		features.append("Lighthouse")
	if has_fog_horn:
		features.append("Fog Horn")
	for commodity in trade.export_slots:
		features.append("Export:%s" % commodity)

	var region := "coastal"
	match definition.region_kind:
		PortDefinition.RegionKind.MAINLAND:
			region = "mainland"
		PortDefinition.RegionKind.FJORD:
			region = "fjord"
		PortDefinition.RegionKind.ARCHIPELAGO:
			region = "archipelago"
		_:
			region = "coastal"

	var berths := maxi(PortSizing.berth_count(size), 1)

	return {
		"id": definition.port_id,
		"display_name": definition.display_name,
		"position": definition.world_position,
		## Chart harbour silhouettes expand from this summary — yaw + site seed
		## must match the placer or every quay faces world −Z (north-up).
		"rotation_y": definition.rotation_y,
		"layout_seed": site_seed,
		"site_max_size": site_max,
		"size": size,
		"region": region,
		"commodity_export": trade.primary_export(),
		"commodity_imports": trade.import_slots.duplicate(),
		"export_slots": trade.export_slots.duplicate(),
		"population": _population(rng, size),
		"berth_count": berths,
		"features": features,
		"max_ship_class": int(_ship_class_for_size(size)),
		"max_ship_class_name": str(ShipClass.DISPLAY_NAME.get(_ship_class_for_size(size), "Vessel")),
		"has_lighthouse": has_lighthouse,
		"has_fog_horn": has_fog_horn,
	}


static func expand(
		definition: PortDefinition,
		world_seed: int,
		world_layout: WorldLayout = null,
		extra_attributes: Dictionary = {},
) -> PortData:
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
	## Geography ceiling first — trade unlocks follow the allowed size.
	definition.site_max_size = clampi(
		definition.site_max_size if definition.site_max_size > 0 else PortSizing.MAX_SIZE,
		PortSizing.MIN_SIZE,
		PortSizing.MAX_SIZE,
	)
	data.size = mini(
		PortSizing.normalized_size(definition.size),
		definition.site_max_size,
	)
	definition.size = data.size

	var site_seed := definition.site_seed if definition.site_seed != 0 \
			else world_seed ^ _hash_id(definition.port_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	data.trade_profile = PortTradeProfile.derive(definition, world_seed)
	## Economy volume caps growth: sparse destinies cannot inflate into hubs.
	var trade_max := PortTradeProfile.max_size_for_profile(data.trade_profile)
	definition.site_max_size = mini(definition.site_max_size, trade_max)
	if data.size > definition.site_max_size:
		data.size = definition.site_max_size
		definition.size = data.size
		PortTradeProfile.resync_for_size(data.trade_profile, data.size)
	data.has_fuel_point = true
	data.has_lighthouse = definition.has_lighthouse or (data.size >= 1 and rng.randf() < 0.3)
	data.has_fog_horn = definition.has_fog_horn or (data.size >= 0 and rng.randf() < 0.4)
	var layout_attrs := {
		"has_fuel_point": data.has_fuel_point,
		"has_lighthouse": data.has_lighthouse,
		"has_fog_horn": data.has_fog_horn,
		"world_layout": world_layout,
		"trade_max_size": trade_max,
	}
	layout_attrs.merge(extra_attributes, true)
	data.layout_graph = PortLayoutGenerator.generate(
		definition,
		data.trade_profile,
		site_seed,
		layout_attrs,
	)
	## Basin may record a water hint; live size stays whatever Expander clamped.
	data.size = PortSizing.normalized_size(definition.size)

	var graph_bounds := data.layout_graph.bounds()
	var quay_pose := data.layout_graph.primary_quay_pose()
	data.dock_length = maxf(
		float(quay_pose.get("length_m", 0.0)),
		PortSizing.dock_length_m(data.size),
	)
	data.island_width = maxf(graph_bounds.size.x + 36.0, PortSizing.island_width_m(data.size))
	data.plot_depth = maxf(graph_bounds.size.z + 36.0, PortSizing.PLOT_DEPTH_M)
	data.max_ship_class = _ship_class_for_size(data.size)
	data.berth_count = _count_berths(data.layout_graph)
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


static func _count_berths(graph: PortLayoutGraph) -> int:
	var plan := graph.initial_attributes.get("berth_plan", {}) as Dictionary
	var planned := int(plan.get("quay_count", 0)) + int(plan.get("asphalt_slot_count", 0))
	if planned > 0:
		return planned
	var count := 0
	for instance_id in graph.module_ids():
		var placed := graph.modules[instance_id] as PortPlacedModule
		var definition := graph.module_definition(placed.module_id)
		if definition != null and definition.kind == "quay":
			count += 1
	return maxi(count, 1)


static func _ship_class_for_size(size: int) -> ShipClass.Type:
	return PortSizing.design_ship_class(size)
