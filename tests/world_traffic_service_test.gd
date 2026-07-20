extends SceneTree

const FIXED_SEED := 77127
const PORT_COUNT := 8
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const SERVICE := preload("res://scripts/traffic/world_traffic_service.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var layout := GENERATOR.generate(FIXED_SEED) as WorldLayout
	var names := PackedStringArray()
	for index in range(PORT_COUNT):
		names.append("Traffic Runtime %02d" % index)
	var definitions: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT, names)
	var ports: Array[PortData] = []
	for definition in definitions:
		ports.append(PortExpander.expand(definition, FIXED_SEED, layout))
	var network := ShippingLaneNetworkBuilder.new().build(layout, ports)
	var service := SERVICE.new() as WorldTrafficService
	service.configure(network, layout, FIXED_SEED)
	root.add_child(service)
	var result := service.spawn_debug_fleet(50)
	assert(bool(result.get("ok", false)))
	assert(int(result.get("vessel_count", 0)) == 50)
	assert(service.map_contacts().size() == 50)
	var summary := service.presentation_summary()
	assert(int(summary.get("record_count", 0)) == 50)
	assert(int(summary.get("materialized", 0)) <= 200)
	service.clear_debug_fleet()
	assert(service.map_contacts().is_empty())
	await process_frame
	service.free()
	TrafficVesselProxyCache.clear()
	print("World traffic service: 50 authoritative contacts and bounded presentation PASS")
	quit(0)
