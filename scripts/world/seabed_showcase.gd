extends Node3D
## F6 geological cutaway using production mesh, materials and chart.
## Space toggles chart; arrows orbit the exposed seabed. No captain I/O.
var camera: Camera3D
var chart: Control
var focus := Vector3.ZERO
var angle := 0.0

func _ready() -> void:
	var layout := WorldLayoutGenerator.generate(1212599375)
	var coord := Vector2i(0, 0)
	for z in range(-15, 15):
		for x in range(-15, 15):
			var at := Vector2(x * 1000 + 500, z * 1000 + 500)
			if layout.sample_signed_distance(at) > 400 and layout.sample_signed_distance(at) < 650:
				coord = Vector2i(x, z)
	focus = Vector3(coord.x * 1000 + 500, -70, coord.y * 1000 + 500)
	var streamer := WorldTerrainStreamer.new()
	add_child(streamer)
	streamer.set_process(false)
	streamer._layout = layout
	for z in range(coord.y - 1, coord.y + 2):
		for x in range(coord.x - 1, coord.x + 2):
			var data := WorldTerrainStreamer.build_chunk_mesh_data(layout, Vector2i(x,z), 25.0)
			var mesh := MeshInstance3D.new()
			mesh.mesh = streamer._array_mesh_from_data(data)
			mesh.material_override = streamer._terrain_material(0)
			add_child(mesh)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("172c3a")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9c9d0")
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	add_child(sun)
	camera = Camera3D.new()
	camera.far = 12000
	add_child(camera)
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	var label := Label.new()
	label.text = "SEABED CUTAWAY | Sea surface hidden | Arrows: orbit | Space: depth chart"
	label.position = Vector2(20,20)
	ui.add_child(label)
	chart = preload("res://scripts/ui/map_overlay.gd").new()
	ui.add_child(chart)
	chart.set_data_snapshot(ChartDataSnapshot.for_preview(1212599375,35))
	chart.visible = false
	chart.close_requested.connect(func(): chart.hide())
	if OS.get_cmdline_user_args().has("--capture"):
		capture_review.call_deferred()

func _process(delta: float) -> void:
	angle += (float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))) * delta
	camera.position = focus + Vector3(cos(angle)*1800,1200,sin(angle)*1800)
	camera.look_at(focus)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		chart.visible = not chart.visible

func capture_review() -> void:
	for view in ["bottom", "chart"]:
		chart.visible = view == "chart"
		if chart.visible:
			chart.camera.center = Vector2(focus.x,focus.z)
			chart.camera.span = 9000
			chart.camera.user_moved = true
		for frame in 40: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var folder := "C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(folder)
		var path := folder.path_join("seabed-%s-%d.png" % [view, int(Time.get_unix_time_from_system() * 1000000)])
		var capture := get_viewport().get_texture().get_image()
		var task := WorkerThreadPool.add_task(func(): capture.save_png(path))
		while not WorkerThreadPool.is_task_completed(task): await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		print("CAPTURE ",path)
	get_tree().quit()
