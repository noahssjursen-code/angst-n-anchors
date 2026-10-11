extends "res://tests/world_gateway_lifecycle_test.gd"

func _test_deployed_door(ship: ImportedDraftVessel) -> void:
	await super._test_deployed_door(ship)
	var mc := ship.find_child("MooringComponent", true, false) as MooringComponent
	var vessel_id := HarbourController.ship_id_of(ship)
	var origin := ship.get_parent() as PortPlot
	var old_front := mc._front_post
	var old_rear := mc._rear_post
	mc.toggle_line_from_post(old_front)
	mc.toggle_line_from_post(old_rear)
	check(not mc.is_moored, "Individual cast-off releases vessel")
	check(WorldGateway.projection("vessel_berth", vessel_id).state.status == "released", "Cast-off reaches authority")
	var destination := TestPortPlot.new()
	destination.port_id = "arrival-test"
	add_child(destination)
	var controller := HarbourController.new()
	controller.setup(destination.port_id)
	destination.add_child(controller)
	var slot := QuayBerthSlot.new()
	slot.setup("arrival-test/quay", "quay", "general", [], 100, 20)
	destination.add_child(slot)
	var posts: Array[Node] = []
	for z in [-5.0, 5.0]:
		var post := MooringPost.new()
		destination.add_child(post)
		post.global_position = ship.to_global(Vector3(-ship.beam_m * .5 - 2, ship.depth_m, z))
		slot.add_bollard(post)
		posts.append(post)
	controller.register_berth(slot)
	controller.activate()
	var before := ship.global_transform
	check(mc.toggle_line_from_post(posts[0]), "First destination line attaches")
	var state: Dictionary = WorldGateway.projection("vessel_berth", vessel_id).state
	check(state.port_id == "arrival-test" and state.status == "assigned", "Arrival claims destination through authority")
	check(bool(state.bow_line) != bool(state.stern_line), "First tie must preserve single-line state")
	check(ship.global_transform.is_equal_approx(before), "Arrival claim must not respawn or teleport the vessel")
	# Old-port released projections may be replayed while both ports are loaded.
	origin.harbour_controller()._authority_bridge._apply_berth_projection({"id": vessel_id, "state": {
		"vessel_id": vessel_id, "port_id": origin.port_id, "berth_id": "master-deploy-test/quay", "status": "released"}})
	check(mc.is_moored, "Old port replay must not cast off destination line")
	check(mc.toggle_line_from_post(posts[1]), "Second destination line attaches")
	state = WorldGateway.projection("vessel_berth", vessel_id).state
	check(state.bow_line and state.stern_line, "Both destination lines reach authority")
	mc.toggle_line_from_post(posts[0])
	mc.toggle_line_from_post(posts[1])
	check(not mc.is_moored, "Destination lines also cast off normally")
	check(WorldGateway.projection("vessel_berth", vessel_id).state.status == "released", "Destination cast-off releases its authority assignment")
	WorldGateway.send_command(WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body("occupied-" + vessel_id, "arrival-test", [slot.berth_id]), "occupy-" + vessel_id)
	# Return to home then try the now-occupied destination. Arrival must never
	# bypass the existing authority occupancy check or leave a phantom line.
	WorldGateway.send_command(WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body(vessel_id, origin.port_id, ["master-deploy-test/quay"]), "return-" + vessel_id)
	mc.release_mooring()
	mc.toggle_line_from_post(posts[0])
	check(not mc.is_moored and not mc.last_mooring_reject.is_empty(), "Occupied destination rejects and rolls back the provisional line")
	WorldGateway.send_command(WorldContracts.COMMAND_VESSEL_BERTH_RELEASE,
		{"vessel_id": "occupied-" + vessel_id}, "clear-occupied-" + vessel_id)
	destination.queue_free()
	await get_tree().process_frame
	print("MOORING AUTHORITY ARRIVAL checked ", vessel_id)
