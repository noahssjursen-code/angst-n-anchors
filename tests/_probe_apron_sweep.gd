extends SceneTree

## Scratch probe (not a test). Strip test for apron_decor: does the feature
## produce ANY output at ANY port as shipped?

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var total := 0
	var zero := 0
	var ports := 0
	var worst := 0
	var counts: Array[int] = []
	for size in range(0, 5):
		for seed_index in range(12):
			var definition := PortDefinition.new()
			definition.port_id = "sweep-%d-%d" % [size, seed_index]
			definition.display_name = "Sweep"
			definition.size = size
			definition.region_kind = PortDefinition.RegionKind.MAINLAND
			definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
			definition.site_seed = 100000 + size * 977 + seed_index * 31
			var data := PortExpander.expand(definition, 424242)
			var land: Dictionary = data.layout_graph.initial_attributes.get(
				"land_plan", {}
			) as Dictionary
			var n := int((land.get("apron_decor", {}) as Dictionary).get("point_count", 0))
			ports += 1
			total += n
			worst = maxi(worst, n)
			counts.append(n)
			if n == 0:
				zero += 1
	print("apron_decor sweep: %d ports, %d total props, %d ports with ZERO, max at one port = %d" % [
		ports, total, zero, worst,
	])
	counts.sort()
	var under3 := 0
	for n in counts:
		if n < 3:
			under3 += 1
	print("  ports with fewer than 3 props: %d of %d" % [under3, counts.size()])
	print("  counts: %s" % [counts])
	quit()
