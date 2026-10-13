extends Node3D
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	WorldWeather.set_blend_to_lighting_paused(true)
	var renderer := WorldRenderer.new()
	add_child(renderer)
	await get_tree().process_frame
	renderer.set_process(false)
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day=.5
	WeatherLighting.cloud_cover=.5
	WeatherLighting.precipitation=0
	WeatherLighting.visibility=1
	renderer._apply_weather_lighting()
	var camera := Camera3D.new()
	add_child(camera)
	camera.current=true
	camera.position=Vector3(0,4,0)
	camera.look_at(camera.position+Vector3(0,.8,-1))
	var stamp := 1791907200.0
	renderer._sync_sky_animation(stamp)
	var before: Vector3 = renderer._sky_shader_material.get_shader_parameter("cloud_drift")
	renderer._sync_sky_animation(stamp + 1.0/60.0)
	var after: Vector3 = renderer._sky_shader_material.get_shader_parameter("cloud_drift")
	assert(before.x>=0 and before.x<1 and before.z>=0 and before.z<1)
	assert(before.distance_to(after)>0 and before.distance_to(after)<.001,"Cloud animation preserves sub-frame precision at Unix-scale times")
	for frame in 45: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "C:/Users/noahs/Pictures/machinescreenshots/cloud-clock-fixed-%d.png" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert(get_viewport().get_texture().get_image().save_png(path)==OK)
	print("CLOUD CLOCK PRECISION PASS ",path)
	get_tree().quit()
