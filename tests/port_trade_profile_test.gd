extends SceneTree

## Determinism: same seed + definition → identical trade profile + layout.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := PortDefinition.new()
	definition.port_id = "port-home"
	definition.display_name = "Haugsvik"
	definition.size = 2
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	definition.site_seed = 991122

	var a := PortExpander.expand(definition, 424242)
	var b := PortExpander.expand(definition, 424242)
	assert(a.trade_profile != null and b.trade_profile != null)
	assert(a.trade_profile.export_slots == b.trade_profile.export_slots)
	assert(a.trade_profile.import_slots == b.trade_profile.import_slots)
	assert(a.layout_graph != null and b.layout_graph != null)
	assert(JSON.stringify(a.layout_graph.to_dict()) == JSON.stringify(b.layout_graph.to_dict()))
	assert(not a.trade_profile.export_slots.is_empty())
	assert(not a.trade_profile.import_slots.is_empty())
	assert(a.layout_graph.local_footprints().size() >= 1)
	assert(a.layout_seed == b.layout_seed)

	print("Port trade profile tests: all checks passed")
	quit()
