extends Node3D

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	WorldWeather.set_blend_to_lighting_paused(true); WorldClock.set_process(false)
	WeatherLighting.time_of_day = .46; WeatherLighting.precipitation = 0
	WeatherLighting.cloud_cover = .25; WeatherLighting.visibility = 1
	var renderer := WorldRenderer.new(); add_child(renderer)
	var platform := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3(140,2,100)
	platform.mesh = box; platform.position.y = 1
	platform.material_override = SurfaceMaterialLibrary.material("crushed_aggregate", Color(.44,.45,.36))
	add_child(platform)
	for i in 6:
		var model := MeshInstance3D.new()
		model.mesh = CoastalBuildingLibrary.mesh(["cottage","house","boathouse"][i%3], i<3, [0,1,4][i%3])
		model.position = Vector3((i%3)*17-17,2,(-int(i/3))*26)
		add_child(model)
	var camera := Camera3D.new(); camera.far = 12000; add_child(camera); camera.make_current()
	var folder := "C:/Users/noahs/Pictures/machinescreenshots/coastal-building-" + str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(folder)
	for view in [{"id":"kit", "eye":Vector3(35,21,40), "target":Vector3(0,4,-10)},
		{"id":"cottage", "eye":Vector3(-5,6,12), "target":Vector3(-17,4,0)},
		{"id":"boathouse", "eye":Vector3(26,5,12), "target":Vector3(17,4,0)}]:
		camera.position = view.eye; camera.look_at(view.target)
		for frame in 60: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join(view.id+".png"))
	print("COASTAL BUILDING REVIEW ",folder)
	if OS.get_cmdline_user_args().has("--capture"): get_tree().quit()
