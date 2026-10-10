extends "res://tests/passenger_live_loop_test.gd"
## Single-player purchase and actual passage controls. Boarding cadence and
## payment are covered by the live-loop test; here transfers are accelerated.

class ContractView extends Node:
	var contracts: Array = []
	func get_active_contracts() -> Array: return contracts

func run() -> void:
	output = "C:/Users/noahs/Pictures/machinescreenshots/passenger-passage-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	PlayerSaveStore.storage_root_override = output.path_join("scratch-save")
	var backend := LocalWorldBackend.new()
	WorldGateway.add_child(backend); WorldGateway._backend = backend
	backend.session_started.connect(WorldGateway._on_session_started)
	backend.session_ended.connect(WorldGateway._on_session_ended)
	backend.event_received.connect(WorldGateway._on_world_event)
	backend.command_finished.connect(WorldGateway._on_command_finished)
	backend.projections_received.connect(WorldGateway._on_projections_received)
	backend.start_session("passenger-passage", "Ferry captain", "")
	GameSettings.map_generation_seed = 424242; GameSettings.map_layout_checksum = ""; GameSettings.map_world_size_m = 40000
	PlayerSession.data.home_port_id = "port-2"
	if not await boot_world(): finish(); return
	var stock: Dictionary = {}
	for entry in PrebuiltVesselCatalog.for_sale_entries():
		if entry.prebuilt_id == "coastal_express": stock = entry
	if not check(not stock.is_empty(), "completed ferry is normal yard stock"): finish(); return
	var ids := {}
	for entry in DevelopmentFleet.catalog_entries(): ids[entry.prebuilt_id] = int(ids.get(entry.prebuilt_id, 0)) + 1
	check(int(ids.get("coastal_express", 0)) == 1, "stock promotion does not duplicate development ferry")
	var shipwright: ShipwrightNpc
	for npc in get_tree().get_nodes_in_group("port_service_npc"):
		if npc is ShipwrightNpc: shipwright = npc; break
	if not check(shipwright != null, "actual shipwright available"): finish(); return
	player.global_position = shipwright.global_position + Vector3(0, .1, 2)
	PlayerSession.data.company.onboarding_complete = true
	PlayerSession.company_service.post_transaction({"request_id": "test-funds", "amount_marks": 200000, "category": "test"})
	var balance := PlayerSession.data.marks
	var purchase := PortServiceDesk.request(shipwright, "buy", {"stock_id": "coastal_express", "vessel_name": "Coastal Passage", "request_id": "buy-ferry"})
	if not check(bool(purchase.get("ok", false)), "shipwright purchases ferry through company authority"): finish(); return
	check(PlayerSession.data.marks == balance - int(stock.price_marks), "purchase charges published price once")
	var owned: Dictionary = purchase.data.vessel
	PortServiceDesk.request(shipwright, "buy", {"stock_id": "coastal_express", "vessel_name": "Coastal Passage", "request_id": "buy-ferry"})
	check(PlayerSession.data.marks == balance - int(stock.price_marks), "purchase retry does not charge twice")
	PlayerSession.data.set_active_vessel(owned)
	await deploy_home(owned)
	if ship == null: finish(); return
	var id := terminal.berth.berth_id
	var planned := BerthApproachLanes.target_world_position("port-2", id)
	var live := terminal.berth.to_global(terminal.berth.ship_dock_local(5.5).origin)
	check(Vector2(planned.x-live.x, planned.z-live.z).length() < .02, "unloaded terminal navigation matches actual bow-in berth")
	for port_id: String in operations.terminals:
		check(BerthApproachLanes.best_target_id(port_id, "passenger") == port_id + "/passenger", "navigation includes passenger terminal " + port_id)
	var offers := operations.offers("port-2", ship)
	if not check(not offers.is_empty(), "ferry has available passenger routes"): finish(); return
	target_port = offers[0].destination
	check(HarbourRegistry.controller(target_port) == null, "destination navigation exists without loading destination models")
	player.global_position = agent.global_position + Vector3(0, .1, 2)
	var booking := agent.request("book", offers[0].id, "passage-booking")
	if not check(booking.ok, "purchased vessel books the actual route"): finish(); return
	sailing = booking.data.id
	check("Boarding" in LocalPlayerView.get_voyage_snapshot().objective, "company guidance shows passenger boarding instead of cargo")
	await wait_until(func(): return PassengerAccommodation.boarding_door(ship).current_door > .95, 8)
	for count in 240: operations.service.advance(sailing, ship)
	check(operations.service.record(sailing).phase == "ready", "supported seats fill for passage")
	var controller := ship.get_node("BoatController") as BoatController
	# The isolated editor-playtest mode suppresses automatic pilot creation.
	# Install the ordinary component without changing the isolation/save mode.
	var component := VesselAutopilot.new(); component.name = "VesselAutopilot"
	ship.add_child(component); controller._autopilot = component
	controller._toggle_autopilot()
	check(not controller.get_autopilot().is_engaged(), "autopilot cannot depart through open ramp or tied lines")
	var lines := ship.get_node("ShipGameplay/MooringComponent") as MooringComponent
	lines.release_mooring()
	await wait_until(func(): return ship.departure_block_reason().is_empty(), 10)
	lines.release_mooring()
	await wait_until(func(): return operations.service.record(sailing).phase == "underway", 5)
	controller._toggle_autopilot()
	check(not controller.get_autopilot().is_engaged(), "bow-in ferry must clear its pier manually")
	var position := terminal.global_position + terminal.global_basis.z * 360
	position.y = ship.global_position.y
	ship.global_position = position
	ship.linear_velocity = Vector3.ZERO
	var order := operations.navigation_order(ship)
	var endpoint := BerthApproachLanes.target_world_position(target_port, target_port + "/passenger")
	var preview := MarineRoutePlanner.new(LandField.get_layout()).plan_berth_to_berth(
		Vector2(position.x,position.z), Vector2(endpoint.x,endpoint.z), "port-2", "", target_port, order.destination_berth_id)
	var outgoing := preview.point_at_distance(85)
	ship.look_at(Vector3(2*position.x-outgoing.x,position.y,2*position.z-outgoing.y))
	controller._toggle_autopilot()
	check(not controller.get_autopilot().is_engaged(), "pilot will not turn the ferry through its pier when facing inland")
	ship.look_at(Vector3(outgoing.x,position.y,outgoing.y))
	controller._toggle_autopilot()
	var pilot := controller.get_autopilot()
	if not check(pilot.is_engaged(), "passage control engages for passenger booking without freight"): finish(); return
	check(pilot.route.destination_port_id == target_port and pilot.arrival_stop_m == 200, "route targets booked terminal with manual berthing handover")
	var end := BerthApproachLanes.target_world_position(target_port, target_port + "/passenger")
	check(pilot.route.waypoints[-1].distance_to(Vector2(end.x,end.z)) < .1, "route ends at correct passenger approach")
	var layout := LandField.get_layout()
	var worst := INF
	for distance in range(0, ceili(pilot.route.total_distance_m()), 12):
		worst = minf(worst, layout.sample_signed_distance(pilot.route.point_at_distance(distance)))
	check(worst > 3.0, "sampled passage stays in water including terminal approaches")
	report.route = {"destination": target_port, "distance_m": pilot.route.total_distance_m(), "minimum_land_clearance": worst}
	ship.look_at(Vector3(pilot.route.waypoints[1].x, ship.global_position.y, pilot.route.waypoints[1].y))
	var start := ship.global_position
	ship.freeze = false
	Engine.time_scale = 4; Engine.physics_ticks_per_second = 240; Engine.max_physics_steps_per_frame = 64
	var until := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < until and pilot.is_engaged():
		player.global_position = ship.global_position + Vector3(0, 5, 0)
		camera.global_position = ship.global_position + ship.global_basis * Vector3(30, 20, 45)
		camera.look_at(ship.global_position + Vector3(0, 2, 0))
		await get_tree().process_frame
	Engine.time_scale = 1; Engine.physics_ticks_per_second = 60
	check(ship.global_position.distance_to(start) > 15 and pilot.is_engaged(), "ordinary propulsion and rudder advance the purchased ferry on passage")
	report.route["observed_travel_m"] = ship.global_position.distance_to(start)
	check(target_port in operations.navigation_order(ship).destination_port_id, "moving vessel retains passenger itinerary")
	ship.freeze = true; pilot.set_physics_process(false)
	var terrain := world.get_node("WorldTerrainStreamer") as WorldTerrainStreamer
	check(await wait_until(func(): return int(terrain.get_debug_stats().pending) == 0, 90), "review waits for terrain around the moving camera")
	await photo("ferry-underway")
	var canvas := CanvasLayer.new(); add_child(canvas)
	var tablet := VoyagePanel.new(); canvas.add_child(tablet); tablet.show_tablet("Today")
	await photo("passenger-itinerary")
	canvas.queue_free()
	await measure_runtime()
	controller._toggle_autopilot()
	check(not pilot.is_engaged(), "same helm control disengages passenger autopilot")
	# Empty ferry must not inherit an unrelated vessel's freight destination.
	operations.service._player.company.passenger_sailings[0].phase = "completed"
	check(controller._navigation_order(LocalPlayerView).is_empty(), "finished sailing stops supplying a navigation order")
	var view := ContractView.new(); add_child(view)
	view.contracts = [{"vessel_uid": "another-vessel", "destination_port_id": "wrong-port"}]
	check(controller._navigation_order(view).is_empty(), "another vessel's freight cannot steer this ferry")
	view.contracts.append({"vessel_uid": str(ship.get_meta("vessel_uid")), "destination_port_id": "correct-port"})
	check(controller._navigation_order(view).destination_port_id == "correct-port", "freight navigation still selects this vessel's contract")
	view.queue_free()
	report.scope = "Actual stock purchase, harbour deployment and passenger passage controls; accelerated boarding, departure positioned clear of pier, 32 simulation seconds of actual sailing. Full route/payment separately covered by live-loop test."
	finish()
