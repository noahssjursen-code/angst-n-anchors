extends Node3D
## --metrics compares generated terrain, full-sized sites and real passage routes.
## Otherwise boots the actual world and captures daytime terrain/harbour views.
## --menu exercises compact selection, captain creation and disk reload first.
## Always run with --shipyard-playtest; all saves are isolated in the report folder.

var output := ""
var report := {"checks": [], "worlds": []}
var failures: Array[String] = []
var world: Node3D
var camera: Camera3D
var player: CharacterBody3D
var world_size := 30000.0
var seed_value := 424242

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	report.checks.append({"ok": ok, "check": label})
	print("COMPACT ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func wait_until(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func run() -> void:
	output = "C:/Users/noahs/Pictures/machinescreenshots/compact-world-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	PlayerSaveStore.storage_root_override = output.path_join("scratch-save")
	LocalCaptainStore.root_override = output.path_join("scratch-captains")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="): world_size = float(arg.trim_prefix("--size="))
		if arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
	if OS.get_cmdline_user_args().has("--metrics"):
		for sample_seed in [424242, 42, 8675309]:
			for size in [40000.0, 30000.0]:
				report.worlds.append(measure_layout(sample_seed, size))
		finish(); return
	GameSettings.apply_world_size_preset("compact" if world_size == 30000 else "standard")
	WorldBootstrap.apply_seed(seed_value, 8, "", 3, world_size)
	if OS.get_cmdline_user_args().has("--menu"):
		await menu_and_save()
	else:
		PlayerSession.data.home_port_id = "port-home"
		world = preload("res://scenes/world.tscn").instantiate()
		var booted := [false]
		world.boot_finished.connect(func(): booted[0] = true)
		add_child(world)
		check(await wait_until(func(): return booted[0], 90), "world boots")
	if world == null: finish(); return
	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if not check(player != null, "player spawns in actual world"): finish(); return
	player.set_physics_process(false)
	camera = Camera3D.new(); camera.far = 40000; add_child(camera); camera.make_current()
	GameMenu.set_gameplay_hud_visible(false)
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.set_process(false); WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day = .5; WeatherLighting.precipitation = 0
	var layout := world.get_world_layout() as WorldLayout
	check(is_equal_approx(layout.world_size_m, world_size), "live terrain uses selected dimensions")
	check(is_equal_approx(ForestField.world_half_extent_m(), world_size * .5), "forest follows terrain dimensions")
	report.context = world.get_world_context()
	var definitions: Array = world._generate_definitions()
	report.port_count = definitions.size()
	check(definitions.size() == 35, "all 35 ports generated")
	var home: PortDefinition = definitions[0]
	var frame := Transform3D(Basis(Vector3.UP, home.rotation_y), home.world_position)
	player.global_position = home.world_position + Vector3(0, 5, 0)
	var terrain := world.get_node("WorldTerrainStreamer") as WorldTerrainStreamer
	camera.global_position = frame * Vector3(200, 140, -400)
	camera.look_at(frame * Vector3(0, 0, -35))
	check(await wait_until(func(): return terrain.is_ready_around(player.global_position), 60), "home terrain and collision ready")
	check(await wait_until(func(): return HarbourRegistry.controller(home.port_id) != null, 30), "full-size home harbour streams")
	for tick in 240: await get_tree().process_frame
	await capture("harbour", frame * Vector3(300, 180, -500), frame * Vector3(0, 10, 80))
	await capture("channel", frame * Vector3(0, 7, -850), frame * Vector3(0, 70, 1000))
	await capture("coast", frame * Vector3(900, 650, -1400), frame * Vector3(0, 160, 1800))
	report.terrain = terrain.get_debug_stats()
	finish()

func measure_layout(seed_number: int, size: float) -> Dictionary:
	var started := Time.get_ticks_msec()
	var layout := WorldLayoutGenerator.generate(seed_number, WorldConfig.ARCHETYPE_PATH, size)
	var definitions := CoastalPortPlacer.place_ports(layout, 35)
	var label := "%d:%d" % [seed_number, size]
	check(definitions.size() == 35, label + " retains 35 ports")
	var ports: Array[Dictionary] = []
	for site in definitions:
		var point := Vector2(site.world_position.x, site.world_position.z)
		var forward3 := Basis(Vector3.UP, site.rotation_y) * Vector3.FORWARD
		var seaward := Vector2(forward3.x, forward3.z)
		check(CoastalPortPlacer.has_seaward_clearance(layout, point, seaward), label + " full-size approach " + site.port_id)
		check(CoastalPortPlacer.is_size_footprint_valid(layout, point, seaward, site.size), label + " full-size land footprint " + site.port_id)
		ports.append({"id": site.port_id, "x": point.x, "z": point.y, "size": site.size})
	var planner := MarineRoutePlanner.new(layout)
	var nearest: Array[float] = []
	var from_home: Array[float] = []
	for i in definitions.size():
		var a := Vector2(definitions[i].world_position.x, definitions[i].world_position.z)
		var closest := -1; var distance := INF
		for j in definitions.size():
			if i == j: continue
			var b := Vector2(definitions[j].world_position.x, definitions[j].world_position.z)
			if a.distance_squared_to(b) < distance:
				distance = a.distance_squared_to(b); closest = j
		var destination := Vector2(definitions[closest].world_position.x, definitions[closest].world_position.z)
		var route := planner.plan(a, destination)
		check(route.is_valid(), label + " nearest route " + definitions[i].port_id)
		if route.is_valid(): nearest.append(route.total_distance_m())
		if i > 0:
			var home := Vector2(definitions[0].world_position.x, definitions[0].world_position.z)
			var home_route := planner.plan(home, a)
			check(home_route.is_valid(), label + " home route " + definitions[i].port_id)
			if home_route.is_valid(): from_home.append(home_route.total_distance_m())
	var heights := []
	for point in [Vector2(.2, .2), Vector2(.35, -.2), Vector2(.42, .4)]:
		heights.append(layout.sample_height(point * size))
	var data := {"seed": seed_number, "size_m": size, "checksum": layout.layout_checksum,
		"raster": layout.raster_resolution, "cell_m": layout.cell_size_m, "ports": ports,
		"nearest_routes": summarize(nearest), "home_routes": summarize(from_home),
		"terrain_heights_m": heights, "elapsed_ms": Time.get_ticks_msec() - started}
	print("COMPACT METRICS ", JSON.stringify(data))
	return data

func summarize(values: Array[float]) -> Dictionary:
	values.sort()
	if values.is_empty(): return {}
	return {"count": values.size(), "median_m": values[values.size() / 2],
		"minimum_m": values[0], "maximum_m": values[-1],
		"median_minutes_15kn": values[values.size() / 2] / (15 * .514444 * 60)}

func menu_and_save() -> void:
	# Verify legacy loading cannot inherit the last preview's compact settings.
	var legacy := PlayerData.new()
	legacy.world_context = {"seed": seed_value, "generation_version": 8}
	WorldBootstrap.apply_player_world_context(legacy)
	check(GameSettings.map_world_size_m == 40000, "legacy captain retains 40 km after compact preview")
	var menu := preload("res://scripts/ui/main_menu.gd").new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.show_backdrop = false
	add_child(menu)
	menu._pending_seed = seed_value
	menu._creating_new = true
	menu._on_creator_confirmed("Compact review", CharacterAppearance.default_appearance())
	menu._company_setup._world_size.select(1)
	for tick in 4: await get_tree().process_frame
	await save_capture("new-company-selection")
	menu._on_company_confirmed("Compact Review Maritime", Color("2f7f83"), "general_cargo")
	var context: Dictionary = menu._chart_bootstrap.snapshot.world_context()
	check(float(context.world_size_m) == 30000, "company selection generates compact home-port chart")
	for tick in 8: await get_tree().process_frame
	await save_capture("home-port-chart")
	PlayerSession._persistent_io_enabled = true
	# Keep the review runner alive while the real menu performs its scene switch.
	get_tree().current_scene = null
	menu._on_home_port_confirmed("port-home")
	await get_tree().scene_changed
	menu.queue_free()
	world = get_tree().current_scene as Node3D
	if not check(world != null, "normal home-port confirmation starts world"): return
	check(await wait_until(func(): return get_tree().get_first_node_in_group("player") != null, 90), "compact captain enters world")
	check(str(world.get_world_context().layout_checksum) == str(context.layout_checksum), "preview and actual terrain checksums match")
	PlayerSession.save_now()
	var saved := PlayerSaveStore.load_player()
	check(saved != null and float(saved.world_context.get("world_size_m", 0)) == 30000, "compact size survives captain save/reload")
	if saved != null:
		GameSettings.apply_world_size_preset("standard")
		WorldBootstrap.apply_player_world_context(saved)
		check(GameSettings.map_world_size_m == 30000, "saved compact captain restores its own dimensions")
	PlayerSession._persistent_io_enabled = false

func capture(label: String, eye: Vector3, target: Vector3) -> void:
	camera.global_position = eye; camera.look_at(target)
	player.global_position = Vector3(eye.x, 5, eye.z)
	var terrain := world.get_node("WorldTerrainStreamer") as WorldTerrainStreamer
	for tick in 10: await get_tree().process_frame
	check(await wait_until(func(): return int(terrain.get_debug_stats().pending) == 0, 60), label + " complete terrain streaming")
	for tick in 180: await get_tree().process_frame
	await save_capture(label)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var gpu: Array[float] = []; var wall: Array[float] = []
	var last := Time.get_ticks_usec()
	for tick in 150:
		await get_tree().process_frame
		if tick >= 30:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			wall.append((Time.get_ticks_usec() - last) / 1000.0)
		last = Time.get_ticks_usec()
	gpu.sort(); wall.sort()
	report.get_or_add("performance", {})[label] = {"gpu_median_ms": gpu[60], "frame_median_ms": wall[60], "frame_p95_ms": wall[114],
		"draw_calls": get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	RenderingServer.viewport_set_measure_render_time(rid, false)

func save_capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label + "-%d.png" % world_size))

func finish() -> void:
	PlayerSession._persistent_io_enabled = false
	report.failures = failures
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("COMPACT REPORT ", output, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
