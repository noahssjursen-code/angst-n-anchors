extends SceneTree

const FIXED_SEED := 77127
const PORT_COUNT := 6
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("Shipping lane test: generating world")
	var layout := GENERATOR.generate(FIXED_SEED) as WorldLayout
	print("Shipping lane test: placing ports")
	var names := PackedStringArray()
	for index in range(PORT_COUNT):
		names.append("Traffic Test %02d" % index)
	var definitions: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT, names)
	var ports: Array[PortData] = []
	for definition in definitions:
		ports.append(PortExpander.expand(definition, FIXED_SEED, layout))

	print("Shipping lane test: building first network")
	var first := ShippingLaneNetworkBuilder.new().build(layout, ports)
	print("Shipping lane test: building deterministic comparison")
	var second := ShippingLaneNetworkBuilder.new().build(layout, ports)
	print("Shipping lane test: validating")
	_test_shape(first, ports)
	_test_connectivity(first)
	_test_determinism(first, second)
	_test_snapshot(first)
	_test_reservations(first)
	_finish(first)


func _test_shape(network: ShippingLaneNetwork, ports: Array[PortData]) -> void:
	_check(network.nodes.size() > 30, "network has useful node density")
	_check(network.edges.size() > 30, "network has useful edge density")
	_check(network.blocks.size() == network.edges.size(), "every directed edge owns one block")
	_check(network.signals.size() > 20, "block boundaries have signals")
	_check(network.port_gate_nodes.size() == ports.size(), "every port publishes traffic gates")
	_check(network.holding_slots.size() == ports.size() * 4, "every port has four holding slots")
	for port in ports:
		_check(network.port_gate_nodes.has(port.port_id), "%s has traffic gates" % port.port_id)
		var hold_count := 0
		var junction_count := 0
		for slot_value in network.holding_slots.values():
			var slot := slot_value as Dictionary
			if String(slot.get("port_id", "")) == port.port_id:
				hold_count += 1
		_check(hold_count == 4, "%s has a complete holding queue" % port.port_id)
		for node_value in network.nodes.values():
			var node := node_value as Dictionary
			if String(node.get("port_id", "")) == port.port_id \
					and String(node.get("kind", "")) == "quay_junction":
				junction_count += 1
		var plan := port.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary
		var expected_junctions := (plan.get("asphalt_stations", []) as Array).size() \
			+ (plan.get("quay_stations", []) as Array).size()
		_check(
			junction_count == expected_junctions,
			"%s has exactly one junction per physical quay" % port.port_id,
		)
		var published_gates := network.port_gate_nodes.get(port.port_id, []) as Array
		_check(
			published_gates.size() == expected_junctions,
			"%s publishes every physical quay junction independently" % port.port_id,
		)
		var unique_gates: Dictionary = {}
		for gate_value in published_gates:
			var gate_id := str(gate_value)
			unique_gates[gate_id] = true
			var gate := network.nodes.get(gate_id, {}) as Dictionary
			_check(
				str(gate.get("kind", "")) == "quay_junction",
				"%s publishes the physical quay junction itself as its gate" % gate_id,
			)
		_check(
			unique_gates.size() == expected_junctions,
			"%s does not collapse physical quays into a shared gate" % port.port_id,
		)
	for node_value in network.nodes.values():
		var node := node_value as Dictionary
		_check(
			str(node.get("kind", "")) != "port_gate",
			"network contains no legacy shared port-gate knot",
		)


func _test_connectivity(network: ShippingLaneNetwork) -> void:
	var quays := PackedStringArray()
	for node_id in network.sorted_node_ids():
		var node := network.node(node_id)
		if String(node.get("kind", "")) != "quay":
			continue
		quays.append(node_id)
		var junction_id := String(node.get("junction_node_id", ""))
		_check(network.nodes.has(junction_id), "quay %s has its own clear-water junction" % node_id)
		if network.nodes.has(junction_id):
			var quay_tip := node.get("quay_tip_position", Vector2.ZERO) as Vector2
			var junction := network.node(junction_id)
			var junction_position := junction.get("position", quay_tip) as Vector2
			_check(
				quay_tip.distance_to(junction_position) >= 75.0,
				"quay %s junction lies beyond its physical tip" % node_id,
			)
			var outbound := junction.get("outbound_vector", Vector2.ZERO) as Vector2
			_check(
				outbound.length_squared() > 0.5 \
					and (junction_position - quay_tip).normalized().dot(outbound.normalized()) > 0.995,
				"quay %s junction is straight out from its physical tip" % node_id,
			)
		_check(
			network.can_reach_kind(node_id, PackedStringArray(["main_lane", "regional_lane"])),
			"quay %s can depart for the shipping highway" % node_id,
		)
	for edge_id in network.sorted_edge_ids():
		var edge := network.edge(edge_id)
		_check(float(edge.get("length_m", 0.0)) > 1.0, "%s has positive length" % edge_id)
		var block_ids := edge.get("block_ids", PackedStringArray()) as PackedStringArray
		_check(not block_ids.is_empty(), "%s references a block" % edge_id)
		for block_id in block_ids:
			_check(network.blocks.has(block_id), "%s references a known block" % edge_id)
	if quays.size() >= 2:
		var route := network.route_edge_ids(quays[0], quays[-1],
			{"draft_m": 6.0, "beam_m": 24.0, "length_m": 90.0})
		_check(not route.is_empty(), "directed blocks provide a port-to-port authority route")
		var uses_highway := false
		for edge_id in route:
			var kind := String(network.edge(edge_id).get("kind", ""))
			if kind in ["main_lane", "regional_lane"]:
				uses_highway = true
		_check(uses_highway, "port-to-port route joins the shipping highway")
	var gates := PackedStringArray()
	for port_id in ShippingLaneNetwork._sorted_ids(network.port_gate_nodes):
		for gate_id in network.port_gate_nodes[port_id] as Array:
			gates.append(str(gate_id))
	for from_index in range(gates.size()):
		for to_index in range(gates.size()):
			if from_index == to_index:
				continue
			_check(
				not network.route_edge_ids(gates[from_index], gates[to_index]).is_empty(),
				"port gate %d reaches port gate %d" % [from_index, to_index],
			)


func _test_determinism(first: ShippingLaneNetwork, second: ShippingLaneNetwork) -> void:
	_check(not first.network_checksum.is_empty(), "network has an identity checksum")
	_check(first.network_checksum == second.network_checksum, "same layout produces identical network")
	_check(first.summary() == second.summary(), "same layout produces identical counts")


func _test_snapshot(network: ShippingLaneNetwork) -> void:
	var encoded := JSON.stringify(network.to_snapshot())
	_check(not encoded.is_empty(), "authority snapshot is JSON-safe for a non-Godot server")
	var decoded := JSON.parse_string(encoded) as Dictionary
	var restored := ShippingLaneNetwork.from_snapshot(decoded)
	_check(restored.network_checksum == network.network_checksum, "authority snapshot preserves network identity")
	_check(restored.summary().get("errors", 0) == 0, "valid authority snapshot restores without errors")
	_check(restored.nodes.size() == network.nodes.size(), "authority snapshot preserves nodes")
	_check(restored.blocks.size() == network.blocks.size(), "authority snapshot preserves blocks")


func _test_reservations(network: ShippingLaneNetwork) -> void:
	var service := ShippingLaneReservationService.new(network)
	var block_ids := network.sorted_block_ids()
	_check(not block_ids.is_empty(), "reservation test has blocks")
	if block_ids.is_empty():
		return
	var first_id := block_ids[0]
	_check(service.block_state(first_id) == "green", "unreserved block is green")
	_check(bool(service.try_reserve("vessel-a", PackedStringArray([first_id])).get("ok", false)), "first reservation succeeds")
	_check(service.block_state(first_id) == "yellow", "reserved block is yellow")
	_check(not bool(service.try_reserve("vessel-b", PackedStringArray([first_id])).get("ok", false)), "second owner cannot reserve block")
	_check(service.occupy("vessel-a", first_id), "reservation owner may occupy block")
	_check(service.block_state(first_id) == "red", "occupied block is red")
	service.release_vessel("vessel-a")
	_check(service.block_state(first_id) == "green", "release restores green state")
	var conflicts := (network.block(first_id).get("conflicts", PackedStringArray()) as PackedStringArray)
	if not conflicts.is_empty():
		_check(bool(service.try_reserve("vessel-a", PackedStringArray([first_id])).get("ok", false)), "conflict setup reservation succeeds")
		_check(
			not bool(service.try_reserve("vessel-b", PackedStringArray([conflicts[0]])).get("ok", false)),
			"crossing or opposing block conflict is exclusive",
		)
	var snapshot := service.snapshot()
	var replica := ShippingLaneReservationService.new(network)
	_check(replica.apply_authority_snapshot(snapshot), "reservation authority snapshot applies to replica")
	_check(replica.snapshot() == snapshot, "reservation replica matches authority state")


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)


func _finish(network: ShippingLaneNetwork) -> void:
	var errors := 0
	for issue_value in network.validation_issues:
		var issue := issue_value as Dictionary
		if String(issue.get("severity", "warning")) == "error":
			errors += 1
	_check(errors == 0, "network validator reports no structural errors")
	if _failures.is_empty():
		print("Shipping lane network tests: all checks passed — %s" % network.summary())
		quit()
		return
	for failure in _failures:
		push_error("Shipping lane network test: " + failure)
	print("Shipping lane validation issues: %s" % [network.validation_issues])
	quit(1)
