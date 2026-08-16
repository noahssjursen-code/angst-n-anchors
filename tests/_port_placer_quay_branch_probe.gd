extends SceneTree

## SCRATCH PROBE — leading underscore, the gate must not score it.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_port_placer_quay_branch_probe.gd
##
## `coastal_port_placer_test.gd:123` looks for a quay in `layout_graph.modules`
## and, failing that, scans `module_ids()` for a `kind == "quay"` module. Both
## come back null on every port today, so its "quay carve keeps berth water
## open" check never runs. Measure what the same property says when it is
## pointed at the berth plan instead — BEFORE editing the test, so nobody
## "fixes" a vacuous branch into a red one by accident (REALITY.md §7).

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const FIXED_SEED := 90210
const PORT_COUNT := 35


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	var layout: WorldLayout = GENERATOR.generate(FIXED_SEED)
	var ports: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT)
	## Both expansions: the one `world.gd` runs, and the one the test ran.
	_sweep(layout, ports, false)
	_sweep(layout, ports, true)
	quit(0)


func _sweep(layout: WorldLayout, ports: Array[PortDefinition], no_layout: bool) -> void:
	print("\n== expansion: %s ==" % ("PortExpander.expand(port, seed)  [what coastal_port_placer_test did]" if no_layout else "PortExpander.expand(port, seed, layout)  [what world.gd does]"))
	var module_quays := 0
	var plan_stations := 0
	var origin_water := 0
	var origin_land := 0
	var tip_water := 0
	var tip_land := 0
	var worst_origin := INF
	var worst_tip := INF
	for port in ports:
		var expanded := PortExpander.expand(port, layout.seed) if no_layout \
				else PortExpander.expand(port, layout.seed, layout)
		var graph := expanded.layout_graph
		if graph.modules.get("arm_general") != null:
			module_quays += 1
		for instance_id in graph.module_ids():
			var placed := graph.modules[instance_id] as PortPlacedModule
			var definition := graph.module_definition(placed.module_id)
			if definition != null and definition.kind == "quay":
				module_quays += 1
		var zones := expanded.flatten_zone_records()
		var basis := Basis(Vector3.UP, port.rotation_y)
		var stations: Array = (graph.initial_attributes.get("berth_plan", {}) as Dictionary) \
				.get("quay_stations", []) as Array
		for raw in stations:
			var station := raw as Dictionary
			plan_stations += 1
			var origin := _xz(station.get("origin", []))
			var tip := _xz(station.get("tip", []))
			var origin_world := port.world_position + basis * Vector3(origin.x, 0.0, origin.y)
			var tip_world := port.world_position + basis * Vector3(tip.x, 0.0, tip.y)
			var d_origin := WorldTerrainStreamer.sample_effective_signed_distance(
				layout, Vector2(origin_world.x, origin_world.z), zones)
			var d_tip := WorldTerrainStreamer.sample_effective_signed_distance(
				layout, Vector2(tip_world.x, tip_world.z), zones)
			worst_origin = minf(worst_origin, d_origin)
			worst_tip = minf(worst_tip, d_tip)
			if d_origin >= 0.0:
				origin_water += 1
			else:
				origin_land += 1
			if d_tip >= 0.0:
				tip_water += 1
			else:
				tip_land += 1
	print("ports=%d  quay-kind MODULES found by the shipped selector = %d  (the branch is dead)"
		% [ports.size(), module_quays])
	print("berth-plan quay stations = %d" % plan_stations)
	print("station ORIGIN effective signed distance >= 0 (water): %d, < 0 (land): %d, worst %.2f m"
		% [origin_water, origin_land, worst_origin])
	print("station TIP    effective signed distance >= 0 (water): %d, < 0 (land): %d, worst %.2f m"
		% [tip_water, tip_land, worst_tip])


func _xz(raw: Variant) -> Vector2:
	var arr := raw as Array
	if arr == null or arr.size() < 2:
		return Vector2.ZERO
	return Vector2(float(arr[0]), float(arr[1]))
