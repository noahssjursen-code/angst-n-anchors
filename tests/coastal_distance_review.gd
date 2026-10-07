extends "res://tests/live_lighting_review.gd"
func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(300).timeout.connect(func():get_tree().quit(1))
	output="C:/Users/noahs/Pictures/machinescreenshots/coastal-distance-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	GameSettings.map_generation_seed=424242
	GameSettings.map_layout_checksum=""
	GameSettings.map_world_size_m=40000
	PlayerSession.data.home_port_id="port-home"
	PlayerSession.data.tutorial_seen["welcome"]=true
	var start:=Time.get_ticks_msec()
	world=preload("res://scenes/world.tscn").instantiate();add_child(world)
	await world.boot_finished
	print("COAST BOOT MS ",Time.get_ticks_msec()-start)
	renderer=world.get_node("WorldRenderer")
	var player:=get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(false)
	camera=Camera3D.new();camera.far=16000;world.add_child(camera);camera.current=true
	var home:=world.get_node("HomePort") as Node3D
	camera.fov=40
	for distance in [350.0,900.0,1800.0]:
		if OS.get_cmdline_user_args().has("--forest-only"): break
		camera.position=home.to_global(Vector3(0,30,-distance))
		camera.look_at(home.global_position+Vector3(0,15,0))
		weather(.5,.25)
		await get_tree().create_timer(5).timeout
		await capture("day-"+str(int(distance)))
		weather(.08,.25)
		await get_tree().create_timer(2).timeout
		await capture("night-"+str(int(distance)))
	weather(.5,.35)
	var layout := world.get_world_layout() as WorldLayout
	var wooded := Vector2.ZERO
	var best := -1.0
	for z in range(-12000,12000,250):
		for x in range(-12000,12000,250):
			var p := Vector2(x,z)
			var inland := -layout.sample_signed_distance(p)
			if inland < 100 or inland > 500: continue
			var density := ForestField.sample(p)
			if density>best: best=density;wooded=p
	var target := Vector3(wooded.x,layout.sample_height(wooded),wooded.y)
	player.global_position = target + Vector3.UP * 2
	print("WOODLAND TARGET ",target," density ",best)
	var coverage := ForestField.coverage_texture().get_image()
	var uv := wooded / (ForestField.world_half_extent_m()*2.0) + Vector2(.5,.5)
	print("COVERAGE TARGET ",coverage.get_pixel(int(uv.x*coverage.get_width()),int(uv.y*coverage.get_height())), " BIND ",world.get_node("WorldTerrainStreamer")._near_material.get_shader_parameter("forest_map"))
	var views := [3.0,35.0,130.0]
	if OS.get_cmdline_user_args().has("--far-forest"): views = [1700.0,2100.0,2500.0,3500.0]
	if OS.get_cmdline_user_args().has("--coverage-debug"):
		views = [2500.0]
		var mat: ShaderMaterial = world.get_node("WorldTerrainStreamer")._near_material
		var debug := Shader.new()
		debug.code = mat.shader.code.replace("diffuse_burley;", "unshaded;").replace('"terrain_canopy.gdshaderinc"', '"res://resources/shaders/terrain_canopy.gdshaderinc"')
		debug.code = debug.code.insert(debug.code.rfind("}"), "ALBEDO=vec3(forest_w);\n")
		mat.shader = debug
	if OS.get_cmdline_user_args().has("--sea-level"): views = [2100.0,2500.0,3500.0]
	for height in views:
		camera.position=target+(Vector3(20,height,30) if height == 3 else Vector3(120,height,180))
		if OS.get_cmdline_user_args().has("--far-forest"):
			camera.position = target + Vector3(height,120,height*.25)
		if OS.get_cmdline_user_args().has("--sea-level"): camera.position.y = 8.0
		camera.look_at(target+Vector3(0,5,0))
		await get_tree().create_timer(8).timeout
		var terrain := world.get_node("WorldTerrainStreamer")
		for attempt in 180:
			if terrain.pending_near(camera.global_position, 1800) == 0 and int(world.get_node("WorldForestStreamer").get_debug_stats().pending) == 0: break
			await get_tree().create_timer(.25).timeout
		print("TERRAIN STATS ", terrain.get_debug_stats())
		await capture("woodland-"+str(int(height)))
	if OS.get_cmdline_user_args().has("--sea-level"):
		weather(.08,.35)
		await get_tree().create_timer(3).timeout
		await capture("sea-night")
	print("FOREST STATS ",world.get_node("WorldForestStreamer").get_debug_stats())
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var timings:Array[float]=[]
	for frame in 90:
		await RenderingServer.frame_post_draw
		if frame>30:timings.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	timings.sort()
	print("COAST GPU median_ms ",timings[timings.size()/2]," draws ",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)," triangles ",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	# Same camera, weather and terrain; hold forest streaming while comparing
	# its visible rendering cost against the identical scene with it hidden.
	var forest := world.get_node("WorldForestStreamer") as Node3D
	forest.set_process(false)
	forest.visible = false
	timings.clear()
	for frame in 90:
		await RenderingServer.frame_post_draw
		if frame>30:timings.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	timings.sort()
	print("COAST GPU forest_hidden median_ms ",timings[timings.size()/2])
	forest.visible = true
	print("COAST DISTANCE COMPLETE ",output)
	world.queue_free()
	for frame in 5:await get_tree().process_frame
	get_tree().quit()
