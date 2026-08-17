extends SceneTree

const FIXED_SEED := 77127
const PORT_COUNT := 6
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const TestReport := preload("res://tests/support/test_report.gd")

## ── WHY THIS FILE COUNTS ITS CHECKS (REALITY.md §4f, standing order 1a) ─────
##
## It used to print `Shipping lane network tests: all checks passed - {…}` and
## no check count at all, which makes every failure mode in §4f invisible in it
## by construction: two runs of this unit cannot be diffed. That matters more
## here than almost anywhere, because 23 of its check sites sit INSIDE loops
## over collections it DISCOVERS from the generated world — `network.blocks`
## (5282), `network.nodes` (3911), `sorted_edge_ids()`, `passing_zones`,
## `port_ramps`, `portals`, `ports` — so a generator that quietly stops emitting
## a class of edge deletes hundreds of checks and this file said `all checks
## passed` either way.
##
## `TestReport` fails a run that executed zero checks by construction, and it
## prints the number, so a shrink is diffable.
##
## Verbose is OFF on purpose: at HEAD this unit runs tens of thousands of
## checks and one line each would bury the log it shares with the failures.
## Failures always print.
##
## The old `_check` also DEDUPLICATED by label — `if not _failures.has(label)` —
## so the 5282-block coverage check could only ever report ONE failure however
## many blocks were broken, and `results.tsv` would read `FAIL(1)` for a network
## in which every block had lost its passing zone. That is gone: every failure
## is now recorded, so the reported magnitude is the real magnitude.
var _t := TestReport.new("shipping_lane_network_test", false)


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
	_test_hybrid_passages(first, layout)
	_test_port_interchange_isolation(first, ports)
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
	_check(network.port_queue_slots.size() >= ports.size() * 2,
		"ports have block-based inbound queue capacity")
	_check(not network.passing_zones.is_empty(), "wide waterways publish passing zones")
	for block_value in network.blocks.values():
		var lane_block := block_value as Dictionary
		var lane_edge := network.edge(str(lane_block.get("edge_id", "")))
		if str(lane_edge.get("kind", "")) in ["main_lane", "regional_lane"]:
			_check(not str(lane_block.get("passing_zone_id", "")).is_empty(),
				"every shipping-lane block has continuous passing coverage")
	for zone_value in network.passing_zones.values():
		var zone := zone_value as Dictionary
		for direction in ["forward", "reverse"]:
			var bypass_ids := zone.get("%s_bypass_edge_ids" % direction,
				PackedStringArray()) as PackedStringArray
			_check(not bypass_ids.is_empty(),
				"%s publishes continuous %s access/overtaking edges" % [
					str(zone.get("id", "")), direction])
			for bypass_id in bypass_ids:
				_check(str(network.edge(bypass_id).get("kind", "")) == "passing_lane",
					"%s is a permanent outside access lane" % bypass_id)
			_check(network.edges.has(str(zone.get("%s_entry_edge_id" % direction, "")))
				and network.edges.has(str(zone.get("%s_exit_edge_id" % direction, ""))),
				"%s has deterministic through/access merge points" % str(zone.get("id", "")))
	var coastal_nodes: Array[Vector2] = []
	for node_value in network.nodes.values():
		var coastal_node := node_value as Dictionary
		if str(coastal_node.get("waterway_id", "")) == "coastal_main_bus":
			coastal_nodes.append(coastal_node.get("position", Vector2.ZERO) as Vector2)
	_check(coastal_nodes.size() >= 4, "mainland coast has a north-south shipping trunk")
	if coastal_nodes.size() >= 2:
		coastal_nodes.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
		_check(coastal_nodes[-1].y - coastal_nodes[0].y > 1000.0,
			"coastal shipping trunk spans multiple fjord mouths")
	for port in ports:
		_check(network.port_gate_nodes.has(port.port_id), "%s has traffic gates" % port.port_id)
		var queue_count := 0
		var junction_count := 0
		for slot_value in network.port_queue_slots.values():
			var slot := slot_value as Dictionary
			if String(slot.get("port_id", "")) == port.port_id:
				queue_count += 1
		_check(queue_count >= 2, "%s has inbound queue blocks" % port.port_id)
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
		var port_ramps := network.ramps_for_port(port.port_id)
		_check(port_ramps.size() == 4,
			"%s publishes four physical service ramps" % port.port_id)
		var ramp_shapes: Dictionary = {}
		for ramp in port_ramps:
			var lane_node := network.node(str(ramp.get("lane_node_id", "")))
			var ramp_node := network.node(str(ramp.get("ramp_node_id", "")))
			var shape := "%s:%s:%d" % [str(ramp.get("station", "")),
				str(ramp.get("ramp_kind", "")), int(ramp.get("direction_index", -1))]
			ramp_shapes[shape] = true
			_check(str(lane_node.get("kind", "")) in ["main_lane", "regional_lane"],
				"%s ramp attaches to the shipping highway" % port.port_id)
			_check(str(lane_node.get("lane_role", "")) == "access",
				"%s ramp attaches only to the outside access lane" % port.port_id)
			_check(str(ramp_node.get("kind", "")) == "shipping_ramp",
				"%s service ramp owns a physical ramp node" % port.port_id)
			_check(not unique_gates.has(str(ramp.get("ramp_node_id", ""))),
				"%s ramps are not quay approach junctions" % port.port_id)
			for gate_id in published_gates:
				var gate_node := network.node(str(gate_id))
				_check((ramp.get("position", Vector2.ZERO) as Vector2).distance_to(
					gate_node.get("position", Vector2.ZERO) as Vector2) >= 400.0,
					"%s ramps clear the local harbour envelope" % port.port_id)
		_check(ramp_shapes.size() == 4,
			"%s has no collapsed or duplicated service-ramp roles" % port.port_id)
		var portals := network.portals_for_port(port.port_id)
		_check(portals.size() == 4,
			"%s publishes four dedicated open-water join/leave portals" % port.port_id)
		var portal_shapes: Dictionary = {}
		for portal in portals:
			var lane_node := network.node(str(portal.get("lane_node_id", "")))
			var shape := "%s:%s:%d" % [str(portal.get("station", "")),
				str(portal.get("portal_kind", "")), int(portal.get("direction_index", -1))]
			portal_shapes[shape] = true
			_check(str(lane_node.get("lane_role", "")) == "access",
				"%s open-water portal attaches to an outside access lane" % port.port_id)
			for gate_id in published_gates:
				var gate_node := network.node(str(gate_id))
				_check((portal.get("position", Vector2.ZERO) as Vector2).distance_to(
					gate_node.get("position", Vector2.ZERO) as Vector2) >= 400.0,
					"%s open-water portals clear the harbour envelope" % port.port_id)
		_check(portal_shapes.size() == 4,
			"%s has no collapsed or duplicated open-water portal roles" % port.port_id)
		var berth_count := 0
		for token_value in network.berth_tokens.values():
			if str((token_value as Dictionary).get("port_id", "")) == port.port_id:
				berth_count += 1
		_check(berth_count >= expected_junctions, "%s publishes reservable berths" % port.port_id)
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


func _test_hybrid_passages(network: ShippingLaneNetwork, layout: WorldLayout) -> void:
	var token_ids := network.sorted_berth_token_ids()
	var from_id := ""
	var to_id := ""
	var farthest := -1.0
	for a_index in range(token_ids.size()):
		var a := network.berth_tokens[token_ids[a_index]] as Dictionary
		var a_node := network.node(str(a.get("node_id", "")))
		for b_index in range(a_index + 1, token_ids.size()):
			var b := network.berth_tokens[token_ids[b_index]] as Dictionary
			if str(a.get("port_id", "")) == str(b.get("port_id", "")):
				continue
			var b_node := network.node(str(b.get("node_id", "")))
			var distance := (a_node.get("position", Vector2.ZERO) as Vector2).distance_squared_to(
				b_node.get("position", Vector2.ZERO) as Vector2)
			if distance > farthest:
				farthest = distance
				from_id = str(a.get("node_id", ""))
				to_id = str(b.get("node_id", ""))
	var planner := HybridShippingRoutePlanner.new()
	planner.configure(network, layout)
	var passage := planner.plan(from_id, to_id,
		{"draft_m": 4.0, "beam_m": 12.0, "length_m": 55.0})
	_check(not passage.is_empty(), "hybrid planner finds a berth-to-berth passage")
	_check(str(passage.get("mode", "")) in ["all_lane", "hybrid"],
		"voyage uses controlled lanes with only a justified A* transfer")
	for raw_step in passage.get("steps", []) as Array:
		var step := raw_step as Dictionary
		if str(step.get("kind", "")) != "open_water":
			continue
		var leave_portal := network.open_water_portals.get(
			str(step.get("from_portal_id", "")), {}) as Dictionary
		var join_portal := network.open_water_portals.get(
			str(step.get("to_portal_id", "")), {}) as Dictionary
		_check(str(leave_portal.get("portal_kind", "")) == "leave" \
			and str(join_portal.get("portal_kind", "")) == "join",
			"open-water passage travels only from a leave portal to a join portal")
	_test_route_choice_quality(network, planner)


func _test_route_choice_quality(
		network: ShippingLaneNetwork, planner: HybridShippingRoutePlanner,
) -> void:
	var token_by_port: Dictionary = {}
	for token_id in network.sorted_berth_token_ids():
		var token := network.berth_tokens[token_id] as Dictionary
		var port_id := str(token.get("port_id", ""))
		if not token_by_port.has(port_id):
			token_by_port[port_id] = token
	var ports := ShippingLaneNetwork._sorted_ids(token_by_port)
	var lane_routes := 0
	var hybrid_routes := 0
	for source_port in ports:
		for destination_port in ports:
			if source_port == destination_port:
				continue
			var source := token_by_port[source_port] as Dictionary
			var destination := token_by_port[destination_port] as Dictionary
			var route := planner.plan(str(source.get("node_id", "")),
				str(destination.get("node_id", "")),
				{"draft_m": 3.0, "beam_m": 10.0, "length_m": 28.0})
			_check(not route.is_empty(), "%s to %s has a voyage" % [
				source_port, destination_port])
			if route.is_empty():
				continue
			var mode := str(route.get("mode", ""))
			_check(mode != "open_water",
				"berth voyage never bypasses controlled port and lane transitions")
			var steps := route.get("steps", []) as Array
			_check(not steps.is_empty() \
				and str((steps.front() as Dictionary).get("kind", "")) == "controlled" \
				and str((steps.back() as Dictionary).get("kind", "")) == "controlled",
				"%s to %s starts and ends under controlled harbour authority" % [
					source_port, destination_port])
			if mode == "hybrid":
				hybrid_routes += 1
				_check(float(route.get("open_water_saving_s", 0.0)) > 0.0,
					"%s to %s leaves lanes only for a measured saving" % [
						source_port, destination_port])
				_check(str(route.get("route_choice_reason", "")) \
						== "material_network_detour",
					"%s to %s records why open water was selected" % [
						source_port, destination_port])
				for step_index in range(steps.size()):
					if str((steps[step_index] as Dictionary).get("kind", "")) \
							!= "open_water":
						continue
					_check(step_index > 0 and step_index + 1 < steps.size() \
							and str((steps[step_index - 1] as Dictionary).get(
								"kind", "")) == "controlled" \
							and str((steps[step_index + 1] as Dictionary).get(
								"kind", "")) == "controlled",
						"open water exists only between marked-lane portals")
			else:
				lane_routes += 1
	_check(lane_routes > 0, "route sample retains ordinary marked-lane voyages")
	_check(hybrid_routes > 0, "route sample contains justified open-water transfers")


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
	_check(restored.port_queue_slots.size() == network.port_queue_slots.size(),
		"authority snapshot preserves inbound queues")
	_check(restored.berth_tokens.size() == network.berth_tokens.size(),
		"authority snapshot preserves berth tokens")
	_check(restored.passing_zones.size() == network.passing_zones.size(),
		"authority snapshot preserves passing zones")
	_check(restored.port_ramps.size() == network.port_ramps.size(),
		"authority snapshot preserves physical service ramps")
	_check(restored.open_water_portals.size() == network.open_water_portals.size(),
		"authority snapshot preserves open-water portals")


func _test_port_interchange_isolation(network: ShippingLaneNetwork,
		ports: Array[PortData]) -> void:
	# A port queue is a siding, not a motorway tailback. Its blocks must stay on
	# the port feeder while through blocks retain a continuous center-lane route.
	# OFF ramps that cross other carriageways publish explicit signal conflicts;
	# ON ramps merge onto the outside lane without reserving unrelated highway.
	for port in ports:
		var ramps := network.ramps_for_port(port.port_id)
		var crossing_off_ramps := 0
		for ramp in ramps:
			var ramp_kind := str(ramp.get("ramp_kind", ""))
			var transition_edges := ramp.get("transition_edge_ids",
				PackedStringArray()) as PackedStringArray
			var feeder_edges := ramp.get("port_feeder_edge_ids",
				PackedStringArray()) as PackedStringArray
			_check(not transition_edges.is_empty(),
				"%s %s owns a highway transition" % [port.port_id, ramp_kind])
			_check(not feeder_edges.is_empty(),
				"%s %s owns an isolated port feeder" % [port.port_id, ramp_kind])
			for edge_id in feeder_edges:
				var edge := network.edge(edge_id)
				_check(str(edge.get("kind", "")) == "port_feeder",
					"%s queue remains off the shipping highway" % port.port_id)
			for edge_id in transition_edges:
				var edge := network.edge(edge_id)
				_check(str(edge.get("kind", "")) == "shipping_ramp",
					"%s transition remains a signal-controlled ramp" % port.port_id)
			if ramp_kind != "off_ramp":
				continue
			var crossing_blocks := ramp.get("crossing_block_ids",
				PackedStringArray()) as PackedStringArray
			if not crossing_blocks.is_empty():
				crossing_off_ramps += 1
			for crossed_block_id in crossing_blocks:
				var crossed_edge := network.edge(str(network.block(
					crossed_block_id).get("edge_id", "")))
				_check(str(crossed_edge.get("kind", "")) in [
					"main_lane", "regional_lane", "passing_lane"],
					"%s OFF-ramp interlock references a real carriageway" % port.port_id)
				var reciprocal_found := false
				for transition_edge_id in transition_edges:
					var transition := network.edge(transition_edge_id)
					for transition_block_id in transition.get("block_ids",
							PackedStringArray()) as PackedStringArray:
						if (network.block(transition_block_id).get("conflicts",
								PackedStringArray()) as PackedStringArray).has(crossed_block_id):
							reciprocal_found = true
				_check(reciprocal_found,
					"%s crossing light protects its OFF-ramp movement" % port.port_id)
		_check(crossing_off_ramps >= 1,
			"%s has a signalled cross-carriageway OFF-ramp" % port.port_id)
		for slot_value in network.port_queue_slots.values():
			var slot := slot_value as Dictionary
			if str(slot.get("port_id", "")) != port.port_id:
				continue
			var queue_block := network.block(str(slot.get("block_id", "")))
			var queue_edge := network.edge(str(queue_block.get("edge_id", "")))
			_check(str(queue_edge.get("kind", "")) == "port_feeder",
				"%s berth queue never occupies a through/overtake lane" % port.port_id)


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
	_test_berth_queue_authority(network)
	_test_passing_authority(network)


func _test_berth_queue_authority(network: ShippingLaneNetwork) -> void:
	var service := ShippingLaneReservationService.new(network)
	var first_token := network.berth_tokens[network.sorted_berth_token_ids()[0]] as Dictionary
	var port_id := str(first_token.get("port_id", ""))
	var port_tokens := PackedStringArray()
	for token_id in network.sorted_berth_token_ids():
		if str((network.berth_tokens[token_id] as Dictionary).get("port_id", "")) == port_id:
			port_tokens.append(token_id)
	for index in range(port_tokens.size()):
		var result := service.request_berth("berth-vessel-%d" % index, port_id)
		_check(str(result.get("status", "")) == "assigned", "free quay assigns immediately")
	var queued_id := "berth-vessel-queued"
	var queued := service.request_berth(queued_id, port_id,
		PackedStringArray([port_tokens[0]]))
	_check(str(queued.get("status", "")) == "queued", "full port creates FIFO lane queue")
	var second_queued_id := "berth-vessel-queued-second"
	var second_queued := service.request_berth(second_queued_id, port_id,
		PackedStringArray([port_tokens[0]]))
	_check(str(second_queued.get("status", "")) == "queued", "queue accepts a second vessel")
	var front_slot := service.assigned_queue_slot(queued_id, 0)
	var second_slot := service.assigned_queue_slot(second_queued_id, 0)
	_check(int(front_slot.get("queue_index", -1)) == 0, "FIFO head receives the front lane block")
	_check(int(second_slot.get("queue_index", -1)) == 1, "next vessel receives the following lane block")
	var queue_block_id := ""
	var vessel_slots := service.queue_slots_for_vessel(queued_id)
	if not vessel_slots.is_empty():
		queue_block_id = str(vessel_slots[0].get("block_id", ""))
	_check(not queue_block_id.is_empty(), "queued port has an inbound block")
	if not queue_block_id.is_empty():
		_check(not bool(service.try_reserve("unannounced-vessel",
			PackedStringArray([queue_block_id])).get("ok", false)),
			"vessel cannot enter port queue before requesting a berth")
		_check(not service.occupy("unannounced-vessel", queue_block_id),
			"direct occupancy cannot bypass berth queue authority")
		_check(not bool(service.try_reserve(second_queued_id,
			PackedStringArray([queue_block_id])).get("ok", false)),
			"queued vessel cannot skip the FIFO lane position ahead of it")
		_check(bool(service.try_reserve(queued_id,
			PackedStringArray([queue_block_id])).get("ok", false)),
			"FIFO head may occupy its isolated port-feeder queue slot")
	var second_block_id := str(second_slot.get("block_id", ""))
	if not second_block_id.is_empty():
		var second_reservation := service.try_reserve(second_queued_id,
			PackedStringArray([second_block_id]))
		_check(bool(second_reservation.get("ok", false)),
			"later queued vessel may occupy only its own feeder slot")
	var promoted := service.release_berth("berth-vessel-0")
	_check(str(promoted.get("vessel_id", "")) == queued_id, "berth release promotes FIFO head")
	_check(not service.berth_assignment(queued_id).is_empty(), "promoted vessel owns the berth")
	if not queue_block_id.is_empty():
		_check(bool(service.try_reserve(queued_id,
			PackedStringArray([queue_block_id])).get("ok", false)),
			"promoted vessel may enter its interlocked connector")
	var advanced_slot := service.assigned_queue_slot(second_queued_id, 0)
	_check(int(advanced_slot.get("queue_index", -1)) == 0,
		"remaining vessel advances to the front queue block")
	var authority_snapshot := service.snapshot()
	var replica := ShippingLaneReservationService.new(network)
	var authority_wire := JSON.parse_string(JSON.stringify(authority_snapshot)) as Dictionary
	_check(replica.apply_authority_snapshot(authority_wire),
		"berth and FIFO authority state replicates")
	var replica_wire := JSON.parse_string(JSON.stringify(replica.snapshot())) as Dictionary
	_check(replica_wire == authority_wire,
		"berth queue replica is exact after JSON transport")


func _test_passing_authority(network: ShippingLaneNetwork) -> void:
	var service := ShippingLaneReservationService.new(network)
	var zone_id := network.sorted_passing_zone_ids()[0]
	_check(str(service.try_reserve_passing("invalid-vessel", zone_id, "sideways").get(
		"reason", "")) == "invalid_travel_direction", "passing rejects an invalid direction")
	var first := service.try_reserve_passing("passing-vessel", zone_id, "forward")
	_check(bool(first.get("ok", false)), "passing vessel may reserve its outside access lane")
	var blocked := service.try_reserve_passing("opposing-vessel", zone_id, "forward")
	_check(not bool(blocked.get("ok", false)), "passing authority excludes conflicting same-direction traffic")


## Argument order is (condition, label) here and (label, ok) in `TestReport`;
## the local signature is kept so the 108 call sites below are untouched.
func _check(condition: bool, label: String) -> void:
	_t.check(label, condition)


func _finish(network: ShippingLaneNetwork) -> void:
	var errors := 0
	for issue_value in network.validation_issues:
		var issue := issue_value as Dictionary
		if String(issue.get("severity", "warning")) == "error":
			errors += 1
	_check(errors == 0, "network validator reports no structural errors")
	print("Shipping lane network: %s" % network.summary())
	if not _t.ok():
		print("Shipping lane validation issues: %s" % [network.validation_issues])
	_t.finish(self)
