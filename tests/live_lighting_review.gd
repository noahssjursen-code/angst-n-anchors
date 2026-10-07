extends Node

var world: Node3D
var camera: Camera3D
var renderer: Node3D
var output: String

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("review")

func capture(tag: String) -> void:
	for frame in 45: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(tag+".png")
	assert(get_viewport().get_texture().get_image().save_png(path)==OK)
	print("CAPTURE ",path)

func weather(time: float, cloud: float = .2) -> void:
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(time)
	WeatherLighting.time_of_day=time
	WeatherLighting.cloud_cover=cloud
	WeatherLighting.precipitation=0
	WeatherLighting.convection_index=0
	WeatherLighting.visibility=1
	WeatherLighting.wind_force=.15
	WeatherLighting.sea_state=.2
	assert(is_zero_approx(WeatherLighting.rain_amount))
	renderer._apply_weather_lighting()
	for node in world.find_children("*","SpotLight3D",true,false):
		if node.get_script()==preload("res://scripts/port/harbour_area_light.gd"): node._update()

func review() -> void:
	output="C:/Users/noahs/Pictures/machinescreenshots/live-lighting-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	GameSettings.map_generation_seed=424242
	GameSettings.map_layout_checksum=""
	GameSettings.map_world_size_m=40000
	PlayerSession.data.home_port_id="port-home"
	PlayerSession.data.tutorial_seen["welcome"]=true
	var start := Time.get_ticks_msec()
	world=preload("res://scenes/world.tscn").instantiate()
	add_child(world)
	await world.boot_finished
	print("LIVE BOOT MS ",Time.get_ticks_msec()-start)
	renderer=world.get_node("WorldRenderer")
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	assert(player != null)
	player.set_physics_process(false)
	camera=Camera3D.new()
	camera.far=12000
	world.add_child(camera)
	camera.global_transform=player.get_node("Camera3D").global_transform
	camera.current=true
	if OS.get_cmdline_user_args().has("--solar-performance"):
		await solar_performance()
		get_tree().quit()
		return
	weather(0.0)
	await get_tree().create_timer(1.3).timeout # Let pre-boot rain particles expire.
	if OS.get_cmdline_user_args().has("--shadow-review"):
		await shadow_review()
		get_tree().quit()
		return
	var origin := camera.global_position
	for time in [0.0,.23,.5]:
		weather(time)
		camera.global_position=origin
		camera.rotation=Vector3(0,player.rotation.y,0)
		await capture("public-spawn-"+str(time))
	weather(0.0)
	var solar := SolarCycle.sample(0.0)
	camera.look_at(camera.global_position+solar.moon_direction*100)
	await capture("moon-clear")
	weather(0.0,.65)
	await capture("moon-cloud")
	weather(.5)
	solar=SolarCycle.sample(.5)
	camera.look_at(camera.global_position+solar.sun_direction*100)
	await capture("sun-clear")
	# Use owned deployment entry point, not direct editor-only construction.
	var record := CompanyService.build_starter_vessel_record("fishing")
	var boat := VesselSpawn.instantiate_from_record(record) as ImportedDraftVessel
	assert(boat != null and boat.get_node_or_null("DoorInteraction") != null)
	boat.freeze=true
	world.add_child(boat)
	boat.global_position=Vector3(origin.x,WaveSurface.WATER_LEVEL-boat.draft_m,origin.z)
	# Move to a known ocean location outside the port foundation for a deck view.
	var home := world.get_node("HomePort") as Node3D
	boat.global_position=home.to_global(Vector3(0,0,-350))
	boat.global_position.y=WaveSurface.WATER_LEVEL-boat.draft_m
	var lights := boat.get_node("ShipLighting") as ShipLighting
	lights._preset=ShipLighting.Preset.ALL
	lights._apply_preset()
	for time in [0.0,.23,.5]:
		weather(time)
		lights._apply_day_scales()
		camera.global_position=boat.to_global(Vector3(0,boat.depth_m+1.7,4))
		camera.look_at(boat.to_global(Vector3(0,boat.depth_m+1.3,-3)))
		await capture("owned-deck-"+str(time))
	print("LIVE LIGHTING REVIEW COMPLETE ",output)
	world.queue_free()
	for frame in 5: await get_tree().process_frame
	get_tree().quit()

func shadow_review() -> void:
	var lamps := []
	for node in world.find_children("*","SpotLight3D",true,false):
		if node.get_script()==preload("res://scripts/port/harbour_area_light.gd"): lamps.append(node)
	print("SHADOW FILTER ",ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality"))
	for variant in ["current","large-emitter","high-filter","low-bias"]:
		for lamp in lamps:
			lamp.light_size=2.0 if variant=="large-emitter" else .65
			lamp.shadow_normal_bias=.02 if variant=="low-bias" else .25
			lamp.shadow_bias=.005 if variant=="low-bias" else .03
		RenderingServer.positional_soft_shadow_filter_set_quality(4 if variant=="high-filter" else 2)
		await capture("shadow-"+variant)

func solar_performance() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	WorldClock.set_process(false)
	weather(.24, 0.0)
	var sun := renderer._sun as DirectionalLight3D
	for long_range in [false, true]:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if long_range else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 6000.0 if long_range else 180.0
		for frame in 60: await get_tree().process_frame
		var start := Time.get_ticks_usec()
		for frame in 180: await get_tree().process_frame
		print("SOLAR FRAME MS range=",sun.directional_shadow_max_distance," mean=",float(Time.get_ticks_usec()-start)/180000.0,
			" draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		await capture("solar-range-"+str(sun.directional_shadow_max_distance))
