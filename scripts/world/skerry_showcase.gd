extends Node3D
var _camera: Camera3D
var _target := Vector3.ZERO
var _angle := 0.0
var _distance := 650.0
var _renderer: WorldRenderer
var _chart: MapOverlay
var _ocean_hidden := false
## Production coastal detail, moving sea-level review, chart and submerged views.
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func run() -> void:
	var seed_value := int(get_tree().get_meta("skerry_review_seed",1212599375))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
	var layout := WorldLayoutGenerator.generate(seed_value)
	var ports := CoastalPortPlacer.place_ports(layout,35,PackedStringArray(WorldPortNames.NAMES))
	var marks := CoastalSeamarks.plan(layout,ports)
	assert(not marks.is_empty())
	var record := marks[0]
	var skerries := layout.skerry_features()
	assert(not skerries.is_empty())
	for candidate in skerries:
		if absf(candidate.position.y) < 8000 and candidate.position.x > -3000 and candidate.position.x < 12000 and candidate.radius > 100:
			record = {"position":candidate.position,"direction":candidate.axis.orthogonal(),"depth_m":0}
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
	camera.position = pole.position + forward*500 + side*350 + Vector3.UP*380
	camera.look_at(pole.position + Vector3.UP*1.5)
	LandField.initialize(layout)
	var renderer := WorldRenderer.new()
	_renderer = renderer
	add_child(renderer)
	var streamer := WorldTerrainStreamer.new()
	streamer.visual_radius_m = 6500
	streamer.collision_radius_m = 0
	add_child(streamer)
	streamer.configure(layout,ports)
	var ui := CanvasLayer.new()
	add_child(ui)
	var label := Label.new()
	label.position = Vector2(20,20)
	label.text = "COASTAL SKERRIES | seed %d | %d exposed rocks and islets | streamed production terrain | arrows: orbit/zoom | 1/2/3: seed | M: chart | O: ocean" % [seed_value,skerries.size()]
	ui.add_child(label)
	var chart := preload("res://scripts/ui/map_overlay.gd").new()
	_chart = chart
	ui.add_child(chart)
	chart.set_data_snapshot(ChartDataSnapshot.for_preview(seed_value,35))
	chart.mode = MapOverlay.Mode.HOME_PORT_PICK
	chart.first_visible_frame = false
	chart.visible = false
	if not OS.get_cmdline_user_args().has("--capture"): return
	for view in ["regional","local","boat-east","boat-west","boat-close","seabed","chart-wide","chart-local"]:
		if OS.get_cmdline_user_args().has("--chart-only") and not view.begins_with("chart-"): continue
		chart.visible = false
		renderer.set_ocean_hidden(view == "seabed")
		if view == "regional":
			camera.position = pole.position + forward*1300 + side*1100 + Vector3.UP*1600
			camera.look_at(pole.position)
		if view == "local" or view == "seabed":
			camera.position = pole.position + forward*500 + side*350 + Vector3.UP*380
			camera.look_at(pole.position)
		if view.begins_with("boat-") and view != "boat-close":
			var sign_value := 1.0 if view == "boat-east" else -1.0
			# Translate and turn while streaming; skip any position over land.
			for frame in 240:
				var angle := sign_value*lerpf(-1.0,1.0,float(frame)/239)
				var position_xz := Vector2(pole.position.x,pole.position.z)+Vector2(cos(angle),sin(angle))*600
				if layout.sample_water_depth(position_xz) < 10: continue
				camera.position = Vector3(position_xz.x,WaveSurface.WATER_LEVEL+4,position_xz.y)
				camera.look_at(pole.position + Vector3.UP*4)
				await get_tree().process_frame
		if view == "boat-close":
			var center := Vector2(pole.position.x,pole.position.z)
			for angle in 32:
				var at := center + Vector2.from_angle(angle*TAU/32.0)*220
				if layout.sample_water_depth(at) < 12: continue
				camera.position = Vector3(at.x,WaveSurface.WATER_LEVEL+3,at.y)
				camera.look_at(pole.position + Vector3.UP*5)
				break
		if view.begins_with("chart-"):
			chart.visible = true
			chart.camera.center = Vector2(pole.position.x,pole.position.z)
			chart.camera.span = 13000 if view == "chart-wide" else 1100
			chart.camera.user_moved = true
			chart.queue_redraw()
		for frame in 320: await get_tree().process_frame
		for frame in 3000:
			if streamer.is_ready_around(camera.position,2500): break
			await get_tree().process_frame
		if view.begins_with("chart-"):
			for frame in 3000:
				if ChartBaseRaster._pending_detail.is_empty(): break
				await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var folder := "C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(folder)
		var path := folder.path_join("skerries-%d-%s-%d.png" % [seed_value,view,int(Time.get_unix_time_from_system()*1000000)])
		var capture := get_viewport().get_texture().get_image()
		var task := WorkerThreadPool.add_task(func(): capture.save_png(path))
		while not WorkerThreadPool.is_task_completed(task): await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		print("CAPTURE ",path)
		print("STREAM ",streamer.get_debug_stats())
	get_tree().quit()

func _process(delta: float) -> void:
	if _camera == null or OS.get_cmdline_user_args().has("--capture"): return
	var turn := Input.get_axis("ui_left","ui_right")
	var zoom := Input.get_axis("ui_up","ui_down")
	if turn == 0 and zoom == 0: return
	_angle += turn*delta
	_distance = clampf(_distance+zoom*delta*150,30,2500)
	_camera.position = _target + Vector3(cos(_angle)*_distance,_distance*.55,sin(_angle)*_distance)
	_camera.look_at(_target)

func _unhandled_key_input(event: InputEvent) -> void:
	if OS.get_cmdline_user_args().has("--capture") or not event is InputEventKey: return
	if not event.pressed or event.echo: return
	if event.keycode in [KEY_1,KEY_2,KEY_3]:
		get_tree().set_meta("skerry_review_seed",[42,1212599375,77127][event.keycode-KEY_1])
		get_tree().reload_current_scene()
	if event.keycode == KEY_O and _renderer != null:
		_ocean_hidden = not _ocean_hidden
		_renderer.set_ocean_hidden(_ocean_hidden)
	if event.keycode == KEY_M and _chart != null:
		_chart.visible = not _chart.visible
		_chart.camera.center = Vector2(_target.x,_target.z)
		_chart.camera.span = 1600
		_chart.camera.user_moved = true
