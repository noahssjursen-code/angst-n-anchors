extends SceneTree

const FIXED_SEED := 42
const PORT_COUNT := 35
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const SERVICE := preload("res://scripts/traffic/world_traffic_service.gd")
const WORLD_PORT_NAMES := preload("res://scripts/world/world_port_names.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("World traffic service test: generating world")
	var layout := GENERATOR.generate(FIXED_SEED) as WorldLayout
	var names := PackedStringArray(WORLD_PORT_NAMES.NAMES)
	var definitions: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT, names)
	var ports: Array[PortData] = []
	for definition in definitions:
		ports.append(PortExpander.expand(definition, FIXED_SEED, layout))
	var network := ShippingLaneNetworkBuilder.new().build(layout, ports)
	print("World traffic service test: network ready")
	var service := SERVICE.new() as WorldTrafficService
	service.configure(network, layout, FIXED_SEED)
	root.add_child(service)
	var failures := PackedStringArray()
	var result := service.spawn_debug_fleet(250)
	print("World traffic service test: fleet spawned")
	_check(bool(result.get("ok", false)), "debug fleet configures", failures)
	_check(int(result.get("vessel_count", 0)) == 250, "all authority records exist", failures)
	_check(service.map_contacts().size() == 250, "all chart contacts publish", failures)
	var route_pairs: Dictionary = {}
	var staged_on_western_boundary := 0
	var scheduled_strategic := 0
	var exact_authority := 0
	var strategic_interest := Vector2.ZERO
	var strategic_interest_id := ""
	var has_strategic_interest := false
	for contact in service.map_contacts():
		route_pairs["%s>%s" % [str(contact.get("source_token_id", "")),
			str(contact.get("destination_token_id", ""))]] = true
		if str(contact.get("state", "")) == "traveling" \
				and not str(contact.get("current_block_id", "")).is_empty():
			var block := network.block(str(contact.get("current_block_id", "")))
			var edge := network.edge(str(block.get("edge_id", "")))
			var node := network.node(str(edge.get("from_node_id", "")))
			if str(node.get("waterway_id", "")) == "open_ocean_bus":
				staged_on_western_boundary += 1
		if str(contact.get("state", "")) == "scheduled_strategic":
			scheduled_strategic += 1
			if not has_strategic_interest:
				strategic_interest = contact.get("position", Vector2.ZERO) as Vector2
				strategic_interest_id = str(contact.get("id", ""))
				has_strategic_interest = true
		if str(contact.get("route_mode", "")) != "pending":
			exact_authority += 1
	_check(route_pairs.size() >= 20, "debug voyages are distributed", failures)
	_check(exact_authority == 24, "only the eager authority budget plans initially", failures)
	_check(staged_on_western_boundary == 0, "exact vessels avoid the empty western bus", failures)
	# The authority deliberately stages deterministic voyage phases on both lane
	# and open-water legs. Routes outside the eager local budget remain cheap
	# strategic contacts until the background planner promotes them.
	_check(scheduled_strategic > 0, "remote records remain strategic", failures)
	_check(has_strategic_interest, "a remote interest target exists", failures)
	service.set_authority_interest_centers(PackedVector2Array([strategic_interest]))
	service.call("_process", 2.1)
	var promoted_exact := 0
	var promoted_position := strategic_interest
	for contact in service.map_contacts():
		if str(contact.get("route_mode", "pending")) != "pending":
			promoted_exact += 1
		if str(contact.get("id", "")) == strategic_interest_id:
			promoted_position = contact.get("position", strategic_interest) as Vector2
	_check(promoted_exact > exact_authority, "interest promotes remote authority", failures)
	_check(promoted_position.distance_to(strategic_interest) <= 500.0,
		"interest promotion preserves the published AIS position", failures)
	var summary := service.presentation_summary()
	_check(int(summary.get("record_count", 0)) == 250, "presentation sees every record", failures)
	_check(int(summary.get("materialized", 0)) <= 200, "presentation stays bounded", failures)
	service.clear_debug_fleet()
	print("World traffic service test: fleet cleared")
	_check(service.map_contacts().is_empty(), "fleet clears cleanly", failures)
	await process_frame
	service.free()
	TrafficVesselProxyCache.clear()
	if failures.is_empty():
		print("World traffic service: 250 authoritative contacts and bounded presentation PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("World traffic service test failed: %s" % failure)
		quit(1)


static func _check(condition: bool, label: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(label)
