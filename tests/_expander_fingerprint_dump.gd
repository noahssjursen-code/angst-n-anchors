extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
## Prints one SHA-256 per port over the FULL expansion result (chart dict +
## serialized layout graph + trade profile destiny lists). Run before and after a
## refactor of `expand_uncached` and diff the two outputs: a behaviour-preserving
## change must print identical lines.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817]


func _initialize() -> void:
	for world_seed in SEEDS:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		var ports: Array[PortDefinition] = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
		LandField.initialize(layout)
		FishingField.initialize(int(world_seed))
		for port in ports:
			PortDataCache.clear()
			var data := PortExpander.expand_uncached(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), layout)
			var attrs := (data.layout_graph.to_dict() as Dictionary)
			(attrs.get("initial_attributes", {}) as Dictionary).erase("world_layout")
			var blob := "%s|%s|%s|%s|%.4f|%.4f|%.4f|%s" % [
				str(data.to_chart_dict()),
				str(attrs),
				str(data.trade_profile.destiny_import_slots),
				str(data.trade_profile.destiny_export_slots),
				data.dock_length, data.island_width, data.plot_depth,
				str(data.trade_profile.import_slots),
			]
			print("FP %d %-12s %s" % [
				int(world_seed), port.port_id,
				blob.sha256_text(),
			])
			## Second producer, same port, same layout.
			PortDataCache.clear()
			var summary := PortExpander.chart_summary(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), layout)
			print("SU %d %-12s %s" % [
				int(world_seed), port.port_id, str(summary).sha256_text()])
	quit(0)
