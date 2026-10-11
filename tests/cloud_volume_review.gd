extends Node3D
var renderer: WorldRenderer
var camera: Camera3D
var output: String
func _ready() -> void: call_deferred("review")
func capture(tag: String) -> void:
	for frame in 30: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var sky_energy := 0.0
	for y in range(20,picture.get_height()/2,32):
		for x in range(20,picture.get_width()-20,32):
			var color := picture.get_pixel(x,y)
			sky_energy += color.r+color.g+color.b
	assert(sky_energy>1.0,"Black sky: inspect shader compiler output")
	assert(picture.save_png(output.path_join(tag+".png"))==OK)
	print("CAPTURE ",output.path_join(tag+".png"))
func review() -> void:
	assert(ShipyardPlaytestMode.active())
	output="C:/Users/noahs/Pictures/machinescreenshots/cloud-review-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true)
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.position=Vector3(0,4,0);camera.far=12000
	renderer=WorldRenderer.new();add_child(renderer)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="):
			var shader:=Shader.new();shader.code=FileAccess.get_file_as_string(arg.trim_prefix("--baseline="))
			renderer._sky_shader_material.shader=shader
	WeatherLighting.precipitation=0;WeatherLighting.visibility=1;WeatherLighting.sea_state=.2
	for condition in [{"name":"broken","cloud":.5,"time":.5,"storm":0.0},{"name":"overcast","cloud":.85,"time":.5,"storm":.0},{"name":"sunset","cloud":.5,"time":.91,"storm":.0},{"name":"night","cloud":.5,"time":0.0,"storm":.0},{"name":"storm","cloud":1.0,"time":.5,"storm":1.0}]:
		WorldClock.snap_time_of_day(condition.time);WeatherLighting.time_of_day=condition.time
		WeatherLighting.cloud_cover=condition.cloud;WeatherLighting.convection_index=condition.storm
		renderer._apply_weather_lighting()
		camera.look_at(camera.position+Vector3(0,.35,-1))
		await capture(condition.name)
		camera.look_at(camera.position+Vector3(0,1,-.2))
		await capture(condition.name+"-zenith")
	# Review successive small camera moves: no frame-varying ray jitter.
	WorldClock.snap_time_of_day(.5);WeatherLighting.time_of_day=.5
	WeatherLighting.cloud_cover=.5;WeatherLighting.convection_index=0
	renderer._apply_weather_lighting()
	for step in 4:
		camera.position.x=step*30.0
		camera.look_at(camera.position+Vector3(.05*step,.35,-1))
		await capture("moving-%02d"%step)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var viewport:=get_viewport().get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
	for frame in 60:await get_tree().process_frame
	var samples:Array[float]=[]
	for frame in 180:
		await get_tree().process_frame
		samples.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	samples.sort();print("CLOUD REVIEW GPU median=",samples[90]," p95=",samples[171])
	print("CLOUD REVIEW COMPLETE ",output)
	get_tree().quit()
