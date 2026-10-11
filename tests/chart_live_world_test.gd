extends Node

class WorldFixture extends Node3D:
	var layout: WorldLayout
	func get_world_layout() -> WorldLayout: return layout
	func get_world_context() -> Dictionary:
		return {"seed": 73119, "generation_version": WorldLayoutGenerator.GENERATION_VERSION,
			"layout_checksum": layout.layout_checksum, "world_size_m": layout.world_size_m}

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	assert(ShipyardPlaytestMode.active())
	var world := WorldFixture.new()
	world.layout = WorldLayoutGenerator.generate(73119)
	world.add_to_group("world")
	add_child(world)
	var definitions := CoastalPortPlacer.place_ports(world.layout, 3, PackedStringArray(WorldPortNames.NAMES))
	var definition: PortDefinition = definitions[0]
	definition.development_facilities = true
	PortCatalog.clear()
	PortCatalog.register_port(definition.port_id, definition.display_name, definition.world_position,
		Vector3.INF, "provisions", [], 0, 140, definition.site_seed, 0, [], definition.rotation_y,
		1, definition.size, "coastal", "", [], definition.to_dict())
	# Later registration by a loaded plot must retain the generator definition.
	PortCatalog.register_port(definition.port_id, definition.display_name, definition.world_position)
	assert(PortCatalog.get_port_info(definition.port_id).port_definition.development_facilities)
	var preview := ChartDataSnapshot.for_preview(90210, 3)
	var chart := MapOverlay.new()
	add_child(chart)
	chart.set_data_snapshot(preview)
	chart.open_navigation()
	assert(not chart.data.preview and chart.data.world_seed == 73119)
	assert(chart.data.layout == world.layout and chart.data.matches_live_tree(get_tree()))
	var resolved := ChartHarbourPlan.resolve_port_data(definition.port_id, get_tree(), chart.data)
	assert(resolved.trade_profile.theme_id == DevelopmentHarbour.THEME)
	var actual := PortExpander.expand(definition, 73119, world.layout)
	assert(resolved.layout_graph == actual.layout_graph, "Chart uses identical development harbour geometry")
	var before: ChartDataSnapshot = chart.data
	PortCatalog.register_port("new-port", "New port", Vector3(50, 0, 50))
	assert(chart.ensure_live_data() and chart.data != before)
	assert(chart.data.port_ids().has("new-port"))
	before = chart.data
	world.remove_from_group("world")
	var replacement := WorldFixture.new()
	replacement.layout = world.layout
	replacement.add_to_group("world")
	add_child(replacement)
	assert(chart.ensure_live_data() and chart.data != before, "World switch invalidates chart even on same seed")
	chart.queue_free()
	world.queue_free()
	replacement.queue_free()
	for frame in 4: await get_tree().process_frame
	print("LIVE CHART PASS: preview handoff, world switch, registry refresh and exact development harbour geometry")
	get_tree().quit()
