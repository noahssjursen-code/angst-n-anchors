extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout := WorldLayoutGenerator.generate(424242)
	var defs := CoastalPortPlacer.place_ports(layout,35,PackedStringArray())
	var counts: Dictionary = {}
	var ore_exports := 0
	var ore_imports := 0
	var ore_docks := 0
	for definition in defs:
		var data := PortExpander.expand(definition,424242,layout)
		var trade := data.trade_profile
		var plan: Dictionary = data.layout_graph.initial_attributes.get("berth_plan",{})
		if JSON.stringify(plan).contains('"iron_ore"'): ore_docks += 1
		for commodity in trade.all_slots(): counts[commodity] = int(counts.get(commodity,0))+1
		if trade.export_slots.has("iron_ore"): ore_exports += 1
		if trade.import_slots.has("iron_ore"): ore_imports += 1
	print("GENERATED PORT TRADE ",counts," ore exports=",ore_exports," imports=",ore_imports," built docks=",ore_docks)
	assert(not counts.has("grain") and not counts.has("lng"),"Unfinished commodities must not spawn")
	assert(ore_exports > 0 and ore_imports > 0,"Ore needs producers and consumers")
	assert(ore_docks == ore_exports+ore_imports,"Ore trading ports must actually build ore docks")
	print("PORT TRADE AVAILABILITY PASS")
	quit()
