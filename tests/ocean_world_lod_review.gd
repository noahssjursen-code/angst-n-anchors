extends "res://tests/live_lighting_review.gd"

func review() -> void:
	get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(1))
	output="C:/Users/noahs/Pictures/machinescreenshots/ocean-world-lod-"+str(Time.get_unix_time_from_system()).replace(".","-")
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
	print("WORLD BOOT MS ",Time.get_ticks_msec()-start)
	renderer=world.get_node("WorldRenderer")
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(false)
	camera=Camera3D.new()
	camera.far=12000
	world.add_child(camera)
	camera.current=true
	weather(.5,.65)
	WeatherLighting.sea_state=.8
	WeatherLighting.wind_force=.7
	var home := world.get_node("HomePort") as Node3D
	var sea := home.to_global(Vector3(0,0,-650))
	sea.y=WaveSurface.WATER_LEVEL
	camera.position=sea+Vector3(0,40,0)
	camera.look_at(sea+Vector3(0,0,-80))
	await get_tree().create_timer(8).timeout
	renderer._fft_system.set_process(false)
	var foam_strength: float = renderer._ocean_shader_material.get_shader_parameter("foam_strength")
	assert(is_equal_approx(foam_strength,float(renderer._ocean_mid_material.get_shader_parameter("foam_strength"))))
	assert(is_equal_approx(foam_strength,float(renderer._ocean_far_material.get_shader_parameter("foam_strength"))))
	for height in [6.0,40.0,180.0,600.0]:
		camera.position=sea+Vector3(0,height,0)
		camera.look_at(sea+Vector3(0,0,-height*.6))
		await capture("height-"+str(height))
		if height == 600.0:await profile("current-600m")
		renderer.set_ocean_ring_debug(true)
		await capture("tiers-"+str(height))
		renderer.set_ocean_ring_debug(false)
	camera.position=sea+Vector3(0,40,0)
	camera.look_at(sea+Vector3(0,0,-80))
	for step in 4:
		camera.position.x+=.25
		await capture("snap-"+str(step))
	# Freeze the same presentation work for both timings, including sky updates.
	renderer.set_process(false)
	await profile("current-40m")
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--baseline-dir="):continue
		var folder := arg.trim_prefix("--baseline-dir=")
		var include := FileAccess.get_file_as_string(folder.path_join("lod-before-ocean_lod_surface.gdshaderinc"))
		assert(not include.is_empty())
		for spec in [[renderer._ocean_shader_material,"ocean_waves.gdshader"],[renderer._ocean_mid_material,"ocean_waves_mid.gdshader"],[renderer._ocean_far_material,"ocean_waves_far.gdshader"]]:
			var source := FileAccess.get_file_as_string(folder.path_join("lod-before-"+spec[1]))
			assert(not source.is_empty())
			var shader := Shader.new()
			shader.code=source.replace('#include "res://resources/shaders/ocean_lod_surface.gdshaderinc"',include)
			spec[0].shader=shader
		renderer._ocean_mid_material.set_shader_parameter("foam_strength",foam_strength*.72)
		# Freeze presentation updates so the baseline's original gain stays intact.
		renderer.set_process(false)
		for height in [40.0,180.0,600.0]:
			camera.position=sea+Vector3(0,height,0)
			camera.look_at(sea+Vector3(0,0,-height*.6))
			renderer._follow_camera_xz()
			await capture("matched-baseline-"+str(height))
			if height == 600.0:await profile("baseline-600m")
		camera.position=sea+Vector3(1,40,0)
		camera.look_at(sea+Vector3(1,0,-80))
		renderer._follow_camera_xz()
		await capture("baseline-profile-camera")
		await profile("baseline-40m")
	print("OCEAN WORLD LOD REVIEW COMPLETE ",output)
	world.queue_free()
	for frame in 5:await get_tree().process_frame
	get_tree().quit()


func profile(tag:String) -> void:
	var was_processing := renderer.is_processing()
	renderer.set_process(false)
	for frame in 45:await RenderingServer.frame_post_draw
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var samples:Array[float]=[]
	for frame in 120:
		await RenderingServer.frame_post_draw
		samples.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	samples.sort()
	print("WORLD STATIC GPU ",tag," median=",samples[60]," p95=",samples[114])
	renderer.set_process(was_processing)
