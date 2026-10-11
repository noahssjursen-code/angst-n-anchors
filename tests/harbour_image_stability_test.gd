extends Node3D

## Production harbour assets and lighting, viewed across subpixel fence wires.
## Run with --shipyard-playtest --capture; --legacy-grade recreates the prior pass.
var camera: Camera3D
var renderer: WorldRenderer

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest to isolate captain saves")
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day = .5
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(43, 2.6, -47)
	camera.look_at(Vector3(0, 3.3, 0))
	camera.current = true
	renderer = WorldRenderer.new()
	renderer.enable_ocean_system = false
	add_child(renderer)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	floor_mesh.mesh = plane
	floor_mesh.material_override = HarbourEnvironmentKit.paving()
	add_child(floor_mesh)
	PortFacilityVisual.build(self, {"id":"review_fishing", "kind":"fishing", "origin":[0,0], "size_m":[64,56], "commodity_ids":[]}, .025)
	PortFacilityVisual.build(self, {"id":"review_office", "kind":"office", "origin":[-50,40], "size_m":[48,48], "commodity_ids":[]}, .025)
	call_deferred("review")

func review() -> void:
	for frame in 90: await get_tree().process_frame
	var legacy := OS.get_cmdline_user_args().has("--legacy-grade")
	renderer.set_process(false)
	if legacy:
		get_viewport().use_taa = false
		renderer._environment.adjustment_contrast = 1.045
		renderer._screen_material.set_shader_parameter("outline_strength", .04)
		renderer._screen_material.set_shader_parameter("grain_strength", .012)
		renderer._screen_material.set_shader_parameter("weather_contrast", .018)
	else:
		assert(not get_viewport().use_taa, "Preserve clarity without temporal smoothing")
		assert(get_viewport().msaa_3d == Viewport.MSAA_4X, "Retain spatial edge anti-aliasing")
		assert(is_equal_approx(renderer._environment.adjustment_contrast, 1.0))
		assert(is_zero_approx(float(renderer._screen_material.get_shader_parameter("grain_strength"))))
		assert(is_zero_approx(float(renderer._screen_material.get_shader_parameter("outline_strength"))))
	for view in ["standing", "moving", "close"]:
		for frame in 60:
			if view == "moving": camera.position.x -= .015
			if view == "close":
				camera.position = Vector3(35, 2.3, -17)
				camera.look_at(Vector3(25, 1.5, 0))
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if OS.get_cmdline_user_args().has("--capture"):
			var folder := "C:/Users/noahs/Pictures/machinescreenshots"
			DirAccess.make_dir_recursive_absolute(folder)
			var path := folder.path_join("harbour-stability-%s-%s-%d.png" % ["before" if legacy else "after", view, Time.get_ticks_usec()])
			assert(get_viewport().get_texture().get_image().save_png(path) == OK)
			print("CAPTURE ", path)
	print("HARBOUR IMAGE STABILITY PASS: production assets, standing/moving/close views, isolated saves")
	get_tree().quit()
