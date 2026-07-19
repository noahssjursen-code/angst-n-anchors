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
	first.advance(SIMULATED_SECONDS)
	var summary := first.summary()
	print(first.generate_report())
	var failures := PackedStringArray()
	_check(int(summary.get("trips_completed", 0)) > 0,
		"fleet completes port-to-port journeys", failures)
	_check(int(summary.get("route_failures", 0)) == 0,
		"all data ships have valid routes", failures)
	_check(int((summary.get("passage_modes", {}) as Dictionary).get("hybrid", 0)) > 0,
		"scenario exercises lane-to-open-water breakoff passages", failures)
	_check(first.generate_report().contains("open_water_sections"),
		"authority report exposes each vessel's passage composition", failures)
	_check(summary.has("collisions") and summary.has("deadlocks") \
		and summary.has("starved_vessels"),
		"safety failures are measured rather than hidden", failures)
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


static func _check(condition: bool, label: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(label)
