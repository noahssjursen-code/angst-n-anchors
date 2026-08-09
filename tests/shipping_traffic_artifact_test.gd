extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const SEED := 77127
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const RENDERER := preload("res://scripts/traffic/shipping_traffic_snapshot_renderer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("shipping_traffic_artifact_test")
	var layout := GENERATOR.generate(SEED) as WorldLayout
	var names := PackedStringArray()
	for index in range(8):
		names.append("Artifact Port %02d" % index)
	var definitions: Array[PortDefinition] = PLACER.place_ports(layout, 8, names)
	var ports: Array[PortData] = []
	for definition in definitions:
		ports.append(PortExpander.expand(definition, SEED, layout))
	var network := ShippingLaneNetworkBuilder.new().build(layout, ports)
	var simulator := ShippingLaneTrafficSimulator.new()
	simulator.configure(network, 24, SEED, layout)
	var started := Time.get_ticks_usec()
	simulator.advance(4000.0)
	var summary := simulator.summary()
	summary["wall_clock_simulation_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	var artifact: Dictionary = RENDERER.save_artifacts(
		"user://traffic_lab_artifacts", network, simulator.vessel_records(), summary)
	t.check("artifacts saved", bool(artifact.get("ok", false)))
	print("Traffic artifact: %s" % JSON.stringify(artifact))
	t.finish(self)
