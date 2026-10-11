extends "res://tests/ferry_world_test.gd"
## Real generated terminals, harbourmaster, terminal UI and world-installed
## component. Travel is teleported; production ramp/door/line checks stay live.
var operations: PassengerOperations
var agent: PassengerAgentNpc
var sailing := ""
var target_port := ""

func run() -> void:
	output = "C:/Users/noahs/Pictures/machinescreenshots/passenger-live-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	PlayerSaveStore.storage_root_override = output.path_join("scratch-save")
	var backend := LocalWorldBackend.new()
	WorldGateway.add_child(backend); WorldGateway._backend = backend
	backend.session_started.connect(WorldGateway._on_session_started)
	backend.session_ended.connect(WorldGateway._on_session_ended)
	backend.event_received.connect(WorldGateway._on_world_event)
	backend.command_finished.connect(WorldGateway._on_command_finished)
	backend.projections_received.connect(WorldGateway._on_projections_received)
	backend.start_session("passenger-live", "Ferry captain", "")
	GameSettings.map_generation_seed = 424242; GameSettings.map_layout_checksum = ""; GameSettings.map_world_size_m = 40000
	PlayerSession.data.home_port_id = "port-2"
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/coastal_express_recipe.json"))
	recipe.format = "imported_models"; recipe.hull_id = recipe.hull
	var owned := VesselSpawn.normalize_record({"uid": "live-ferry", "name": "Coastal Express", "hull_id": recipe.hull, "brick_layout": recipe})
	PlayerSession.data.upsert_owned_vessel(owned); PlayerSession.data.set_active_vessel(owned)
	if not await boot_world(): finish(); return
	check(operations.terminals.size() == 6, "data directory contains all six safe terminals without loading their models")
	await deploy_home(owned)
	if ship == null: finish(); return
	await open_agent()
	await photo("route-offers")
	var offers: Array = agent.snapshot().offers
	if not check(offers.size() == 3, "terminal offers the nearest three real passenger destinations"): finish(); return
	target_port = str(offers[0].destination)
	click_booking(str(offers[0].id))
	sailing = str(operations.service.active_for(ship).get("id", ""))
	if not check(not sailing.is_empty(), "actual booking button creates company sailing"): finish(); return
	check(operations.service.record(sailing).total == 240, "booking fills supported 240 seats")
	check(operations.service.record(sailing).destination_berth == target_port + "/passenger", "offer targets a registered terminal berth")
	await wait_until(func(): return int(operations.service.record(sailing).onboard) >= 8, 8)
	await photo("boarding-ui")
	var master := HarbourRegistry.controller("port-2").get_parent().find_child("HarbourMaster*", true, false) as HarbourMasterNpc
	# Find by type rather than relying on decorative node names.
	for npc in get_tree().get_nodes_in_group("port_service_npc"):
		if npc is HarbourMasterNpc and npc.port_id == "port-2": master = npc
	var storage_reply: Array = []
	master.deployment_finished.connect(func(ok: bool, message: String): storage_reply.assign([ok, message]))
	master.request_storage(ship)
	check(not storage_reply.is_empty() and not storage_reply[0] and is_instance_valid(ship), "harbourmaster refuses storage during active passenger sailing")
	check("passenger" in PortServiceDesk.storage_reason(master, ship), "harbourmaster panel explains why passenger ferry storage is disabled")
	master._deploy_fleet_vessel(owned)
	check(PlayerVessel.find_active_ship(get_tree()) == ship, "replacement cannot discard the passenger vessel")
	var panel := PassengerTerminalPanel.current(get_tree())
	(panel._buttons.cancel as Button).pressed.emit()
	await wait_until(func(): return operations.service.record(sailing).phase == "cancelled", 12)
	check(operations.service.record(sailing).phase == "cancelled", "cancel button returns partial boarding without payment")
	# Same open panel must issue a new booking reference after cancellation.
	await get_tree().create_timer(.5).timeout
	click_booking(str(offers[0].id))
	var second := str(operations.service.active_for(ship).get("id", ""))
	check(not second.is_empty() and second != sailing, "same panel can book a fresh sailing after cancellation")
	sailing = second
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame; await get_tree().process_frame
	check(PassengerTerminalPanel.current(get_tree()) == null and not GameMenu.is_modal_open(), "Escape closes the passenger panel without opening a second menu")
	Engine.time_scale = 8; Engine.physics_ticks_per_second = 240; Engine.max_physics_steps_per_frame = 64
	check(await wait_until(func(): return operations.service.record(sailing).phase == "ready", 20), "live component boards all passengers with UI closed")
	Engine.time_scale = 1; Engine.physics_ticks_per_second = 60
	check(absf(float(ship.get_mass_breakdown().categories.get("passengers", 0)) - 21600) < .1, "production passenger mass is 21.6 tonnes")
	check(PlayerSaveStore.save_player(PlayerSession.data), "partial voyage writes only to scratch captain save")
	var saved := PlayerSaveStore.load_player()
	world.queue_free(); ship = null
	await get_tree().process_frame; await get_tree().process_frame
	camera.queue_free()
	PlayerSession.data = saved; PlayerSession.company_service.bind(saved); PlayerSession.data_loaded.emit(saved)
	if not await boot_world(): finish(); return
	await deploy_home(saved.active_vessel)
	if ship == null: finish(); return
	check(operations.service.record(sailing).phase == "ready" and operations.service.record(sailing).onboard == 240,
		"new world restores the saved manifest on harbourmaster redeployment")
	var voyage := ship.get_node("PassengerVoyage") as PassengerVoyage
	check(voyage.cabin_visual.rendered_count == 240, "restored production vessel projects all seated passengers")
	var lines := ship.get_node("ShipGameplay/MooringComponent") as MooringComponent
	lines.release_mooring()
	await wait_until(func(): return ship.departure_block_reason().is_empty(), 10)
	lines.release_mooring()
	check(await wait_until(func(): return operations.service.record(sailing).phase == "underway", 5), "closing entrance and stowing ramp permits departure")
	check(not operations.service.begin_alighting(sailing, ship).ok, "arrival away from booked terminal rejected")
	var destination: Vector3 = operations.terminals[target_port].position
	player.global_position = destination + Vector3(0, 5, 0)
	camera.global_position = destination + Vector3(0, 40, -70); camera.look_at(destination)
	if not check(await wait_until(func(): return HarbourRegistry.controller(target_port) != null, 35), "destination streams on arrival"): finish(); return
	var harbour := HarbourRegistry.controller(target_port)
	terminal = harbour.get_parent().find_child("PassengerTerminal", true, false) as PassengerTerminal
	if not check(terminal != null, "offered destination has the actual generated terminal"): finish(); return
	ship.dock_at_berth(terminal.berth); ship.freeze = true
	lines.moor_to_nearest_of(terminal.berth.bollards())
	await wait_until(func(): return operations.service.secured_at(ship, terminal.berth.berth_id), 10)
	agent = terminal.get_node("PassengerAgent") as PassengerAgentNpc
	await open_agent()
	var before := PlayerSession.data.marks
	var fare: int = int(operations.service.record(sailing).fare_marks) * 240
	(PassengerTerminalPanel.current(get_tree())._buttons.arrive as Button).pressed.emit()
	check(operations.service.record(sailing).phase == "alighting", "destination agent starts disembarkation")
	await wait_until(func(): return operations.service.record(sailing).landed > 4, 8)
	await photo("arrival-ui")
	PassengerTerminalPanel.current(get_tree()).close()
	Engine.time_scale = 8; Engine.physics_ticks_per_second = 240
	check(await wait_until(func(): return operations.service.record(sailing).phase == "completed", 20), "full live ferry journey reaches paid completion")
	Engine.time_scale = 1; Engine.physics_ticks_per_second = 60
	check(PlayerSession.data.marks == before + fare, "company receives the exact quoted fare")
	check(PassengerOperations.storage_reason(ship).is_empty(), "completed sailing releases storage restriction")
	check((ship.get_node("PassengerVoyage") as PassengerVoyage).cabin_visual.rendered_count == 0, "alighted passengers disappear from saloon")
	check(not agent.snapshot().offers.is_empty(), "arrival terminal offers a return journey")
	operations.service.advance(sailing, ship)
	check(PlayerSession.data.marks == before + fare, "completed record replay cannot pay again")
	await photo("completed-terminal")
	await measure_runtime()
	report.sailings = operations.service.records()
	report.terminal_siting_ms = operations.siting_usec / 1000.0
	report.scope = "Actual world and terminal buttons. Accelerated transfer; teleport between terminals. Scratch captain save and whole-world rebuild; no underway ship-pose restoration claim."
	finish()

func finish() -> void:
	check(report.has("scope"), "journey reaches final verification checkpoint")
	super.finish()

func measure_runtime() -> void:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for frame in 30: await get_tree().process_frame
	var frames: Array[float] = []; var gpu: Array[float] = []
	var last := Time.get_ticks_usec()
	for frame in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec(); frames.append((now-last)/1000.0); last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	frames.sort(); gpu.sort()
	report.performance = {"resolution": str(get_viewport().get_visible_rect().size),
		"frame_median_ms": frames[60], "frame_p95_ms": frames[114], "gpu_median_ms": gpu[60],
		"draw_calls": get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	RenderingServer.viewport_set_measure_render_time(rid, false)

func boot_world() -> bool:
	world = preload("res://scenes/world.tscn").instantiate()
	var booted := [false]; world.boot_finished.connect(func(): booted[0] = true); add_child(world)
	if not check(await wait_until(func(): return booted[0], 90), "isolated production world boots"): return false
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D; player.set_physics_process(false)
	camera = Camera3D.new(); camera.far = 12000; add_child(camera); camera.make_current()
	GameMenu.set_gameplay_hud_visible(false)
	WorldWeather.set_blend_to_lighting_paused(true); WorldClock.set_process(false); WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day = .5; WeatherLighting.precipitation = 0
	operations = PassengerOperations.current(get_tree())
	return check(operations != null, "world installs passenger operations")

func deploy_home(record: Dictionary) -> void:
	var master: HarbourMasterNpc
	for npc in get_tree().get_nodes_in_group("port_service_npc"):
		if npc is HarbourMasterNpc and npc.port_id == "port-2": master = npc
	if not check(master != null, "home harbourmaster exists"): return
	master._deploy_fleet_vessel(record)
	await wait_until(func(): return PlayerVessel.find_active_ship(get_tree()) != null, 12)
	ship = PlayerVessel.find_active_ship(get_tree()) as ImportedDraftVessel
	if not check(ship != null, "actual harbourmaster deploys owned ferry"): return
	ship.freeze = true
	terminal = HarbourRegistry.controller("port-2").get_parent().find_child("PassengerTerminal", true, false) as PassengerTerminal
	agent = terminal.get_node("PassengerAgent") as PassengerAgentNpc
	await wait_until(func(): return ship.get_node_or_null("PassengerVoyage") != null, 8)
	check(ship.get_node_or_null("PassengerVoyage") != null, "owned ferry automatically receives passenger component")
	await wait_until(func(): return PassengerAccommodation.ramp(ship).deployed, 12)
	check(PassengerAccommodation.ramp(ship).deployed, "physical boarding ramp reaches generated landing")

func open_agent() -> void:
	player.global_position = agent.global_position + terminal.global_basis * Vector3(0, .1, -2.4)
	camera.global_position = player.global_position + Vector3(0, 1.65, 0)
	camera.look_at(agent.global_position + Vector3(0, 1.3, 0)); camera.make_current()
	(player.get_node("Camera3D") as Camera3D).global_transform = camera.global_transform
	check(agent._can_interact(), "normal player interaction ray reaches the terminal agent")
	agent._on_interact()
	await get_tree().process_frame
	check(is_instance_valid(PassengerTerminalPanel.current(get_tree())), "terminal interaction opens live passenger panel")

func click_booking(route_id: String) -> void:
	for button in PassengerTerminalPanel.current(get_tree())._routes.find_children("*", "Button", true, false):
		if button.get_meta("route_id", "") == route_id:
			button.pressed.emit(); return
	check(false, "booking button exists for " + route_id)

func photo(tag: String) -> void:
	for frame in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(tag + ".png"))
