extends Node3D
var _camera: Camera3D
var _target := Vector3.ZERO
var _angle := 0.0
var _distance := 16.0
## Production imported mark at its generated shallow, viewed from boat height.
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func run() -> void:
	var seed_value := 1212599375
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
	var layout := WorldLayoutGenerator.generate(seed_value)
	var ports := CoastalPortPlacer.place_ports(layout,35,PackedStringArray(WorldPortNames.NAMES))
	var marks := CoastalSeamarks.plan(layout,ports)
	assert(not marks.is_empty())
	var record := marks[0]
	for candidate in marks:
		if absf(candidate.position.y) < 9000 and absf(candidate.position.x) < 10000 and layout.sample_signed_distance(candidate.position) < 500:
			record = candidate
			break
	var pole := Node3D.new()
	pole.position = Vector3(record.position.x,WaveSurface.WATER_LEVEL,record.position.y)
	add_child(pole)
	var seamarks := CoastalSeamarks.new()
	seamarks.configure(layout,ports)
	add_child(seamarks)
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day = .5
	WeatherLighting.wind_speed_ms = 2
	var camera := Camera3D.new()
	_camera = camera
	_target = pole.position + Vector3.UP*1.5
	camera.far = 15000
	add_child(camera)
	camera.current = true
	var direction: Vector2 = record.direction
	var forward := Vector3(direction.x,0,direction.y)
	var side := Vector3(-direction.y,0,direction.x)
	camera.position = pole.position + forward*5 + side*8 + Vector3.UP*2
	camera.look_at(pole.position + Vector3.UP*1.5)
	LandField.initialize(layout)
	var renderer := WorldRenderer.new()
	add_child(renderer)
	var streamer := WorldTerrainStreamer.new()
	streamer.visual_radius_m = 2000
	streamer.collision_radius_m = 0
	add_child(streamer)
	streamer.configure(layout,ports)
	var ui := CanvasLayer.new()
	add_child(ui)
	var label := Label.new()
	label.position = Vector2(20,20)
	label.text = "JERNSTANG MED VISER | Generated shallow %.1f m | Arm points toward deeper water | Arrows: orbit/zoom" % record.depth_m
	ui.add_child(label)
	if not OS.get_cmdline_user_args().has("--capture"): return
	var chart := preload("res://scripts/ui/map_overlay.gd").new()
	ui.add_child(chart)
	chart.set_data_snapshot(ChartDataSnapshot.for_preview(seed_value,35))
	chart.visible = false
	for view in ["close","approach","passage-forward","passage-return","aerial","seabed","chart"]:
		if view.begins_with("passage-"):
			var reverse := -1.0 if view == "passage-return" else 1.0
			for frame in 180:
				var along := lerpf(-180,180,float(frame)/179.0)*reverse
				camera.position = pole.position + forward*60 + side*along + Vector3.UP*3
				camera.look_at(pole.position + Vector3.UP*1.2)
				assert(layout.sample_water_depth(Vector2(camera.position.x,camera.position.z)) >= 6)
				await get_tree().process_frame
		if view == "seabed":
			renderer.set_ocean_hidden(true)
		if view == "chart":
			chart.visible = true
			chart.camera.center = Vector2(pole.position.x,pole.position.z)
			chart.camera.span = 4500
			chart.camera.user_moved = true
		if view == "aerial":
			camera.position = pole.position + forward*350 + side*250 + Vector3.UP*1200
			camera.look_at(pole.position)
		if view == "approach":
			camera.position = pole.position + forward*50 + side*25 + Vector3.UP*2
			camera.look_at(pole.position + Vector3.UP*1.2)
		for frame in 160: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var folder := "C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(folder)
		var path := folder.path_join("jernstang-%s-%d.png" % [view,int(Time.get_unix_time_from_system()*1000000)])
		var capture := get_viewport().get_texture().get_image()
		var task := WorkerThreadPool.add_task(func(): capture.save_png(path))
		while not WorkerThreadPool.is_task_completed(task): await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		print("CAPTURE ",path)
	get_tree().quit()

func _process(delta: float) -> void:
	if _camera == null or OS.get_cmdline_user_args().has("--capture"): return
	var turn := Input.get_axis("ui_left","ui_right")
	var zoom := Input.get_axis("ui_up","ui_down")
	if turn == 0 and zoom == 0: return
	_angle += turn*delta
	_distance = clampf(_distance+zoom*delta*10,3,100)
	_camera.position = _target + Vector3(cos(_angle)*_distance,.5,sin(_angle)*_distance)
	_camera.look_at(_target)
