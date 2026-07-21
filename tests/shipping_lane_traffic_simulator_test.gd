extends SceneTree

const FIXED_SEED := 77127
const PORT_COUNT := 8
const SIMULATED_SECONDS := 12000.0
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("Traffic simulator test: generating deterministic world")
	var layout := GENERATOR.generate(FIXED_SEED) as WorldLayout
	var names := PackedStringArray()
	for index in range(PORT_COUNT):
		names.append("Traffic Simulation %02d" % index)
	var definitions: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT, names)
	var ports: Array[PortData] = []
	for definition in definitions:
		ports.append(PortExpander.expand(definition, FIXED_SEED, layout))
	var network := ShippingLaneNetworkBuilder.new().build(layout, ports)
	var first := ShippingLaneTrafficSimulator.new()
	first.configure(network, 24, FIXED_SEED, layout)
	var failures := PackedStringArray()
	_check_initial_staging(first, network, failures)
	first.advance(SIMULATED_SECONDS)
	var summary := first.summary()
	print(first.generate_report())
	_check(int(summary.get("trips_completed", 0)) > 0,
		"fleet completes port-to-port journeys", failures)
	_check(int(summary.get("vessel_count", 0)) == 24,
		"authority keeps vessels beyond the available starting berths", failures)
	_check(int(summary.get("route_failures", 0)) == 0,
		"all data ships have valid routes", failures)
	var modes := summary.get("passage_modes", {}) as Dictionary
	_check(int(modes.get("all_lane", 0)) > 0,
		"ordinary journeys prefer the authority-controlled lane graph", failures)
	_check(int(modes.get("hybrid", 0)) > 0,
		"unreasonable lane detours use a bounded A* lane transfer", failures)
	_check(first.generate_report().contains("open_water_sections"),
		"authority report exposes each vessel's passage composition", failures)
	_check(summary.has("collisions") and summary.has("deadlocks") \
		and summary.has("starved_vessels"),
		"safety failures are measured rather than hidden", failures)
	_check(str(summary.get("status", "FAIL")) == "PASS",
		"long replay passes every authority safety gate", failures)
	_check(int(summary.get("collisions", 0)) == 0,
		"open-water and controlled traffic remain collision-free", failures)
	_check(int(summary.get("deadlocks", 0)) == 0,
		"port queues and lane reservations remain globally live", failures)
	_check(int(summary.get("starved_vessels", 0)) == 0,
		"every prolonged wait has an explicit scheduled or FIFO cause", failures)
	_check(int(summary.get("queue_entries", 0)) > 0,
		"scenario exercises berth queues", failures)
	_check(int(summary.get("reservation_denials", 0)) > 0,
		"scenario exercises signal contention", failures)
	_check(first.generate_report().contains("MACHINE DATA"),
		"copyable report contains machine-readable authority data", failures)
	var second := ShippingLaneTrafficSimulator.new()
	second.configure(network, 24, FIXED_SEED, layout)
	second.advance(SIMULATED_SECONDS)
	_check(second.summary() == summary,
		"fixed-step traffic result is deterministic", failures)
	if failures.is_empty():
		print("Shipping lane traffic simulator tests: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("Traffic simulator test failed: %s" % failure)
		quit(1)


func _check_initial_staging(simulator: ShippingLaneTrafficSimulator,
		network: ShippingLaneNetwork, failures: PackedStringArray) -> void:
	for vessel in simulator.vessel_records():
		var route := vessel.get("route_steps", []) as Array
		var route_index := int(vessel.get("route_index", -1))
		_check(route_index >= 0 and route_index < route.size(),
			"%s is staged on its assigned contract route" % str(vessel.get("id", "")),
			failures)
		if route_index < 0 or route_index >= route.size():
			continue
		var step := route[route_index] as Dictionary
		var edge := step if str(step.get("kind", "")) == "open_water" \
			else network.edge(str(step.get("edge_id", "")))
		var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
		var distance := _distance_to_polyline(
			vessel.get("position", Vector2.ZERO) as Vector2, points)
		_check(distance <= absf(float(vessel.get("navigation_offset_m", 0.0))) + 1.0,
			"%s initial AIS position lies on its real route" % str(vessel.get("id", "")),
			failures)
		_check(str(vessel.get("source_token_id", "")) \
				!= str(vessel.get("destination_token_id", "")),
			"%s starts with a meaningful inter-port contract" % str(vessel.get("id", "")),
			failures)


static func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	if points.is_empty():
		return INF
	if points.size() == 1:
		return point.distance_to(points[0])
	var best := INF
	for index in range(points.size() - 1):
		var start := points[index]
		var finish := points[index + 1]
		var segment := finish - start
		var ratio := 0.0 if segment.length_squared() <= 0.0001 else clampf(
			(point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
		best = minf(best, point.distance_to(start + segment * ratio))
	return best


static func _check(condition: bool, label: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(label)
