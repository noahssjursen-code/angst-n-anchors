extends Node3D
## Isolated dev-captain world: actual generated facilities, NPC deployment and
## harbour clearance. --geometry-only skips rendering/fleet deployment.
var output := ""
var failures: Array[String] = []
var report := {"checks": [], "fleet": []}
var world: Node3D
var player: CharacterBody3D
var camera: Camera3D

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	report.checks.append({"ok": ok, "check": label})
	print("DEV HARBOUR ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func wait_until(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func run() -> void:
	output = "C:/Users/noahs/Pictures/machinescreenshots/development-harbour-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	LocalCaptainStore.root_override = output.path_join("scratch-captains")
	PlayerSaveStore.storage_root_override = output.path_join("scratch-save")
	LocalCaptainStore.clear_active()
	PlayerSession._persistent_io_enabled = true
	var service := CaptainService.new()
	service.configure_local()
	var dev := service.create_development_local()
	if not check(dev != null, "create real development captain in isolated save"): finish(); return
	var layout := WorldLayoutGenerator.generate(424242)
	var definitions := CoastalPortPlacer.place_ports(layout, 35, PackedStringArray(WorldPortNames.NAMES))
	var original: Array[Dictionary] = []
	for definition in definitions: original.append(definition.to_dict())
	DevelopmentFleet.configure_home_port(definitions, dev)
	for i in definitions.size():
		if definitions[i].port_id != dev.home_port_id:
			check(definitions[i].to_dict() == original[i], "ordinary port unchanged " + definitions[i].port_id)
	var home := definitions[0]
	var data := PortExpander.expand(home, 424242, layout)
	validate_geometry(data, layout)
	var ordinary := PortExpander.expand(PortDefinition.from_dict(original[0]), 424242, layout)
	check(ordinary != data and ordinary.trade_profile.theme_id != DevelopmentHarbour.THEME, "ordinary captain cannot receive cached development layout")
	check(not ordinary.trade_profile.all_slots().has("grain") and not ordinary.trade_profile.all_slots().has("lng"), "unfinished cargo remains absent from ordinary home")
	check(PortDefinition.from_dict(home.to_dict()).development_facilities, "development layout flag survives definition serialization")
	var loaded := service.create_development_local()
	check(loaded != null and loaded.account_id == dev.account_id, "existing development captain reloads without replacement")
	if OS.get_cmdline_user_args().has("--geometry-only"): finish(); return
	var backend := LocalWorldBackend.new()
	WorldGateway.add_child(backend); WorldGateway._backend = backend
	backend.session_started.connect(WorldGateway._on_session_started)
	backend.session_ended.connect(WorldGateway._on_session_ended)
	backend.event_received.connect(WorldGateway._on_world_event)
	backend.command_finished.connect(WorldGateway._on_command_finished)
	backend.projections_received.connect(WorldGateway._on_projections_received)
	backend.start_session(dev.account_id, "Development Captain", "")
	WorldBootstrap.apply_seed(424242, 8, "", 3, 40000)
	world = preload("res://scenes/world.tscn").instantiate()
	var booted := [false]
	world.boot_finished.connect(func(): booted[0] = true)
	var started := Time.get_ticks_msec()
	add_child(world)
	if not check(await wait_until(func(): return booted[0], 90), "actual development world boots"): finish(); return
	report.boot_seconds = (Time.get_ticks_msec() - started) / 1000.0
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(false)
	camera = Camera3D.new(); camera.far = 12000; add_child(camera); camera.make_current()
	GameMenu.set_gameplay_hud_visible(false)
	WorldWeather.set_blend_to_lighting_paused(true); WorldClock.set_process(false)
	WorldClock.snap_time_of_day(.5); WeatherLighting.time_of_day = .5; WeatherLighting.precipitation = 0
	var plot := world.get_node("HomePort") as PortPlot
	check(plot.port_data().trade_profile.theme_id == DevelopmentHarbour.THEME, "world uses development home automatically")
	var harbour := plot.harbour_controller()
	var terminal := plot.find_child("PassengerTerminal", true, false) as PassengerTerminal
	check(terminal != null, "passenger terminal is installed and registered at home")
	var live_commodities := PackedStringArray()
	for berth: QuayBerthSlot in harbour.berths():
		for commodity in berth.commodities:
			if not live_commodities.has(commodity): live_commodities.append(commodity)
	for commodity: Dictionary in CommodityCatalog.COMMODITIES:
		check(live_commodities.has(str(commodity.id)), "live berth exists for " + str(commodity.id))
	await capture("whole-harbour", plot.to_global(Vector3(250, 470, -840)), plot.to_global(Vector3(100, 0, -90)))
	var npc: HarbourMasterNpc
	for child in plot.get_children():
		if child is HarbourMasterNpc: npc = child
	if not check(npc != null, "live harbourmaster exists"): finish(); return
	for record: Dictionary in PlayerSession.data.owned_vessels.duplicate(true):
		# The local authority releases the old active ship's berth atomically;
		# it is available to its replacement even while still occupied locally.
		var candidates := HarbourDeploy.compatible_slots_for(harbour, record)
		if not check(not candidates.is_empty(), "compatible berth for " + str(record.name)): continue
		var slot: QuayBerthSlot = candidates[0]
		var done := [false, false, ""]
		var callback := func(ok: bool, message: String): done.assign([true, ok, message])
		npc.deployment_finished.connect(callback)
		npc._deploy_fleet_vessel(record)
		await wait_until(func(): return done[0], 15)
		npc.deployment_finished.disconnect(callback)
		if not check(done[0] and done[1], "harbourmaster deploys " + str(record.name) + ": " + str(done[2])): continue
		var ship := PlayerVessel.find_active_ship(get_tree())
		if not check(ship != null, "vessel actually instantiated"): continue
		check(ship.get_moored_berth_id() == slot.berth_id, "assigned berth matches service preference " + slot.family)
		check(slot.family == HarbourDeploy.terminal_families_for_record(record)[0], "preferred terminal available for " + str(record.name))
		var req := HarbourDeploy.ship_requirements(record)
		var wet := true
		for x in [-.5, 0.0, .5]:
			for z in [-.5, 0.0, .5]:
				var point := ship.to_global(Vector3(x * req.beam_world_m, 0, z * req.loa_world_m))
				wet = wet and layout.sample_height(Vector2(point.x, point.z)) < WaveSurface.WATER_LEVEL - 2.5
		check(wet, "hull has water clearance " + str(record.name))
		report.fleet.append({"vessel": record.name, "berth": slot.berth_id, "family": slot.family})
		if slot.family == "passenger":
			var ramp := PassengerAccommodation.ramp(ship)
			check(await wait_until(func(): return ramp.deployed, 12), "ferry bow ramp connects to home terminal")
			await capture("ferry-landing", terminal.to_global(Vector3(68, 32, 55)), terminal.to_global(Vector3(0, 1, -12)))
		elif float(req.loa_world_m) > 80:
			await capture("northline-quay", ship.to_global(Vector3(90, 65, -110)), ship.global_position)
	await capture("working-waterfront", plot.to_global(Vector3(-220, 75, -500)), plot.to_global(Vector3(300, 15, -80)))
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 180:
		await get_tree().process_frame
		var now := Time.get_ticks_usec(); samples.append((now - previous) / 1000.0); previous = now
	samples.sort()
	report.performance = {"frame_median_ms": samples[90], "frame_p95_ms": samples[171], "draw_calls": get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	finish()

func validate_geometry(data: PortData, layout: WorldLayout) -> void:
	var plan: Dictionary = data.layout_graph.initial_attributes.berth_plan
	var quays: Array = plan.quay_stations
	check(quays.size() == CommodityCatalog.COMMODITIES.size(), "one dedicated quay per commodity")
	var frame := Transform3D(Basis(Vector3.UP, data.rotation_y), data.world_position)
	for q: Dictionary in quays:
		check(PortBerthPlan._loading_face_gap(q, quays, q.berth_side) >= 29, "clear loading pocket " + str(q.id))
		var origin := Vector2(q.origin[0], q.origin[1])
		var sea := Vector2(q.direction[0], q.direction[1])
		var along := Vector2(sea.y, -sea.x)
		var wet := true
		# The opposite side can meet a natural headland. Only the signed loading
		# face is a registered vessel pocket; test it through the departure tail.
		for depth in [40.0, 90.0, float(q.length_m) + 28]:
			for side in [float(q.berth_side)]:
				var at: Vector2 = origin + sea * depth + along * side * (float(q.width_m) * .5 + 15)
				var p := frame * Vector3(at.x, 0, at.y)
				wet = wet and layout.sample_height(Vector2(p.x, p.z)) < WaveSurface.WATER_LEVEL - 2.5
		check(wet, "quay approaches clear natural land " + str(q.id))
	var ferry := PassengerPortSites.plan(data.layout_graph, frame, layout)
	check(not ferry.is_empty(), "reserved ferry site has full hull and departure clearance")
	report.quays = quays
	report.passenger_site = ferry

func capture(tag: String, eye: Vector3, target: Vector3) -> void:
	camera.global_position = eye; camera.look_at(target); camera.make_current()
	player.global_position = eye
	var terrain := world.get_node("WorldTerrainStreamer") as WorldTerrainStreamer
	await wait_until(func(): return terrain.is_ready_around(eye), 45)
	for frame in 90: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(tag + ".png"))

func finish() -> void:
	report.failures = failures; report.passed = failures.is_empty()
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("DEV HARBOUR REPORT ", output, " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
