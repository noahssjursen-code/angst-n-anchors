extends "res://scripts/port/port_showcase.gd"

func _ready() -> void:
	super._ready()
	call_deferred("review_materials")

func review_materials() -> void:
	assert(ShipyardPlaytestMode.active())
	for frame in 120: await get_tree().process_frame
	get_node("HudLayer").hide()
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(.54)
	WeatherLighting.time_of_day = .54
	WeatherLighting.cloud_cover = .2
	WeatherLighting.precipitation = 0
	WeatherLighting.convection_index = 0
	WeatherLighting.visibility = 1
	get_node("ShowcaseWorldRenderer")._apply_weather_lighting()
	var crane: Node3D
	for node in find_children("*", "Node3D", true, false):
		if (node is ProvisionCrane) if OS.get_cmdline_user_args().has("--provision-review") else (node is BulkCrane):
			crane = node
			break
	assert(crane != null)
	var directory := "C:/Users/noahs/Pictures/machinescreenshots/port-material-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(directory)
	var views := [
		["cabin", Vector3(7, 6, -8), Vector3(-.7, 3, 0)],
		["service", Vector3(-7, 7, 7), Vector3(-.7, 3.4, 0)],
		["quay", Vector3(22, 15, 24), Vector3(0, 7, -13)],
	]
	if OS.get_cmdline_user_args().has("--provision-review"):
		var hook := crane.to_local(crane.get_hook_global())
		views = [
			["provision-cab", Vector3(5,34,-6), Vector3(0,32.5,0)],
			["provision-station", Vector3(-7,36,9), Vector3(-.5,32.5,0)],
			["provision-quay", Vector3(55,48,50), Vector3(0,22,-15)],
			["provision-hook", hook+Vector3(3,2,4), hook+Vector3(0,.5,0)],
			["provision-trolley", crane.to_local(crane.get_talje_global())+Vector3(3,-1,4), crane.to_local(crane.get_talje_global())],
		]
	for view in views:
		_camera.global_position = crane.to_global(view[1])
		_camera.look_at(crane.to_global(view[2]))
		for frame in 45: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join(view[0]+".png")
		assert(get_viewport().get_texture().get_image().save_png(path) == OK)
		print("CAPTURE ", path)
	get_tree().quit()
