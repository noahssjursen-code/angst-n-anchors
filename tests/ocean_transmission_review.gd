extends Node3D

var renderer: WorldRenderer
var camera: Camera3D
var output: String

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
