extends Node3D

var renderer: WorldRenderer
var camera: Camera3D
var output: String
var moving_boat: ImportedDraftVessel

func capture(tag: String) -> void:
	for frame in 15: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	assert(picture.save_png(output.path_join(tag+".png")) == OK)
	print("CAPTURE ", output.path_join(tag+".png"))

func _ready() -> void:
	call_deferred("review")

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	output="C:/Users/noahs/Pictures/machinescreenshots/ocean-transmission-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day=.5
	WeatherLighting.cloud_cover=.15
	WeatherLighting.precipitation=0
	WeatherLighting.convection_index=0
	WeatherLighting.visibility=1
	WeatherLighting.sea_state=.1
	camera=Camera3D.new()
	add_child(camera)
	camera.current=true
	camera.far=12000
	camera.position=Vector3(19,15,23)
	camera.look_at(Vector3(0,-2,0))
	renderer=WorldRenderer.new()
	add_child(renderer)
	if OS.get_cmdline_user_args().has("--drive-review"):
		await drive_review()
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--surface-review"):
		await surface_review()
		get_tree().quit()
		return
	var boat := VesselSpawn.instantiate_from_record(CompanyService.build_starter_vessel_record("fishing")) as ImportedDraftVessel
	boat.freeze=true
	add_child(boat)
	boat.position=Vector3(-6,WaveSurface.WATER_LEVEL-boat.draft_m,0)
	# Equal material targets at known submergence to judge absorption.
	for index in 4:
		var target := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size=Vector3(3,.2,5)
		target.mesh=box
		var material := StandardMaterial3D.new()
		material.albedo_color=Color(.75,.62,.35)
		target.material_override=material
		add_child(target)
		target.position=Vector3(2+index*4,WaveSurface.WATER_LEVEL-[.3,1.5,4.0,12.0][index]-.1,0)
	for frame in 90: await get_tree().process_frame
	renderer._fft_system.set_process(false)
	renderer._ocean_shader_material.set_shader_parameter("transmission_strength",0.0)
	await capture("opaque-before")
	renderer._ocean_shader_material.set_shader_parameter("transmission_strength",1.0)
	await capture("transmission-after")
	camera.position=Vector3(9,2,13)
	camera.look_at(Vector3(-5,-1.5,0))
	await capture("waterline-day")
	WorldClock.snap_time_of_day(0)
	WeatherLighting.time_of_day=0
	renderer._apply_weather_lighting()
	await capture("waterline-night")
	await spectrum_test()
	check_slope_mips()
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day=.5
	renderer._apply_weather_lighting()
	camera.position=Vector3(8,-3,12)
	camera.look_at(Vector3(-6,-3,0))
	await capture("underwater")
	camera.position=Vector3(9,2,13)
	camera.look_at(Vector3(-5,-1.5,0))
	var fft: FFTWaterSystem=renderer._fft_system
	fft.set_process(true)
	WeatherLighting.weather_drives_waves=false
	WaveSurface.set_wave_intensity(2.0)
	var previous := WaveSurface.get_applied_wave_intensity()
	for frame in 8:
		await capture("transition-%02d" % frame)
		var applied := WaveSurface.get_applied_wave_intensity()
		assert(applied >= previous and applied < 2.0)
		previous=applied
	WaveSurface.set_wave_intensity(.3)
	await capture("transition-retarget")
	assert(WaveSurface.get_applied_wave_intensity() > .3)
	await profile()
	await profile_slope_mips()
	print("OCEAN REVIEW PASS ",output)
	get_tree().quit()

func spectrum_test() -> void:
	var fft: FFTWaterSystem=renderer._fft_system
	var rd := fft.rd
	# Blocking readbacks are confined to this GPU regression, never gameplay.
	var before := rd.texture_get_data(fft.initial_spectrum_tex,0).to_float32_array()
	fft.sync_weather(.95,.8,.8,1.2)
	var target := rd.texture_get_data(fft.target_spectrum_tex,0).to_float32_array()
	var unchanged := rd.texture_get_data(fft.initial_spectrum_tex,0).to_float32_array()
	assert(before == unchanged, "Weather repack must not overwrite the active sea")
	fft._run_update_fft_assemble(1.0/60.0)
	var after := rd.texture_get_data(fft.initial_spectrum_tex,0).to_float32_array()
	var total_change := 0.0
	var total_target := 0.0
	var error := 0.0
	var blend := 1.0-exp(-(1.0/60.0)/FFTWaterSystem.SPECTRUM_RESPONSE_SECONDS)
	for i in range(0,before.size(),13):
		total_change+=absf(after[i]-before[i])
		total_target+=absf(target[i]-before[i])
		error+=absf(after[i]-lerpf(before[i],target[i],blend))
	assert(total_target>.001)
	assert(error/maxf(total_change,.000001)<.001)
	assert(total_change/total_target<.02)
	print("SPECTRUM first-frame fraction=",total_change/total_target," relative error=",error/maxf(total_change,.000001))

func check_slope_mips() -> void:
	var fft: FFTWaterSystem = renderer._fft_system
	# Blocking GPU readback is confined to this paused regression fixture.
	for layer in 4:
		var data := fft.rd.texture_get_data(fft.slope_tex, layer).to_float32_array()
		assert(data.size() == 699050, "512-to-1 RG32F mip chain must exist")
		var source_offset := 0
		var source_size := 512
		for level in range(1, 10):
			var target_offset := source_offset + source_size * source_size * 2
			var target_size := source_size / 2
			for sample_index in mini(31, target_size * target_size):
				var pixel := (sample_index * 719) % (target_size * target_size)
				var x := pixel % target_size
				var y := pixel / target_size
				for channel in 2:
					var source := source_offset + (y*2*source_size+x*2)*2+channel
					var expected := (data[source]+data[source+2]+data[source+source_size*2]+data[source+source_size*2+2])*.25
					var actual := data[target_offset+pixel*2+channel]
					assert(is_finite(actual) and absf(expected-actual)<.00001, "Slope mip must average its four children")
			source_offset = target_offset
			source_size = target_size
	print("SLOPE MIP PASS: all four cascades, nine levels, exact filtered samples")

func profile_slope_mips() -> void:
	var fft: FFTWaterSystem = renderer._fft_system
	fft.set_process(false)
	var samples: Array[float] = []
	for frame in 150:
		fft.rd.capture_timestamp("SlopeMip.Begin")
		fft._run_slope_mips()
		fft.rd.capture_timestamp("SlopeMip.End")
		await get_tree().process_frame
		var begin := -1
		var end := -1
		for index in fft.rd.get_captured_timestamps_count():
			var tag := fft.rd.get_captured_timestamp_name(index)
			if tag == "SlopeMip.Begin": begin = fft.rd.get_captured_timestamp_gpu_time(index)
			if tag == "SlopeMip.End": end = fft.rd.get_captured_timestamp_gpu_time(index)
		if frame > 20 and begin >= 0 and end >= begin:
			samples.append(float(end-begin)/1000000.0)
	assert(not samples.is_empty())
	samples.sort()
	print("SLOPE MIP GPU median ms=",samples[samples.size()/2]," extra memory=2.667MiB")

func profile() -> void:
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	var current := renderer._ocean_shader_material.shader
	var baseline: Shader
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--compare-shader="):
			baseline=Shader.new()
			baseline.code=FileAccess.get_file_as_string(arg.trim_prefix("--compare-shader="))
	for variant in ["current","baseline","current-again"]:
		if variant=="baseline" and baseline==null: continue
		renderer._ocean_shader_material.shader=baseline if variant=="baseline" else current
		for frame in 30: await get_tree().process_frame
		var samples: Array[float]=[]
		for frame in 120:
			await get_tree().process_frame
			samples.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		samples.sort()
		print("OCEAN GPU ",variant," median ms=",samples[60])

func surface_review() -> void:
	for condition in [{"name":"clear","time":.5,"cloud":.05,"sea":.2},{"name":"cloudy","time":.5,"cloud":.65,"sea":.35},{"name":"sunset","time":.91,"cloud":.35,"sea":.2},{"name":"rough","time":.5,"cloud":.8,"sea":.8}]:
		WorldClock.snap_time_of_day(condition.time)
		WeatherLighting.time_of_day=condition.time
		WeatherLighting.cloud_cover=condition.cloud
		WeatherLighting.sea_state=condition.sea
		renderer._apply_weather_lighting()
		camera.position=Vector3(0,4,0)
		var solar := SolarCycle.sample(condition.time)
		var bearing: Vector3=solar.sun_direction
		camera.look_at(camera.position+Vector3(bearing.x*70,-4,bearing.z*70))
		await get_tree().create_timer(5.0).timeout
		await capture("surface-"+condition.name)
		camera.look_at(Vector3(15,-2,-15))
		await capture("close-"+condition.name)
	await profile()

func _process(_delta: float) -> void:
	if is_instance_valid(moving_boat):
		camera.global_position=moving_boat.global_position+moving_boat.global_basis*Vector3(17,10,23)
		camera.look_at(moving_boat.global_position+Vector3(0,1,0))

func drive_review() -> void:
	WeatherLighting.cloud_cover=.5
	WeatherLighting.sea_state=.25
	renderer._apply_weather_lighting()
	moving_boat=VesselSpawn.instantiate_from_record(CompanyService.build_starter_vessel_record("fishing")) as ImportedDraftVessel
	add_child(moving_boat)
	moving_boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	moving_boat.get_node("BoatController").set_physics_process(false)
	WaveSurface.set_local_visual_vessel(moving_boat)
	await get_tree().create_timer(5).timeout
	await capture("drive-settled")
	moving_boat.get_node("PropulsionComponent").throttle=-1
	for step in 5:
		await get_tree().create_timer(6).timeout
		assert(moving_boat.global_position.is_finite())
		assert(absf(moving_boat.global_position.y-WaveSurface.WATER_LEVEL)<6)
		await capture("drive-ahead-%02d" % step)
	print("DRIVE speed knots=",moving_boat.linear_velocity.length()*1.94384)
	assert(moving_boat.linear_velocity.length()>2)
	var start_heading := moving_boat.rotation.y
	moving_boat.get_node("RudderComponent").rudder_input=.65
	await get_tree().create_timer(8).timeout
	await capture("drive-turn")
	print("DRIVE turn radians=",wrapf(moving_boat.rotation.y-start_heading,-PI,PI))
	assert(absf(wrapf(moving_boat.rotation.y-start_heading,-PI,PI))>.03)
	WorldClock.snap_time_of_day(0)
	WeatherLighting.time_of_day=0
	renderer._apply_weather_lighting()
	var lights := moving_boat.get_node("ShipLighting") as ShipLighting
	lights._preset=ShipLighting.Preset.ALL
	lights._apply_preset()
	await capture("drive-night")
	print("DRIVE REVIEW PASS")
