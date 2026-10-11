extends "res://tests/compact_world_review.gd"
## Production terrain, harbour, forest and vessel draw cost of local rain shelter.
var boat: ImportedDraftVessel
var rain: RainField

func capture(label: String, eye: Vector3, target: Vector3) -> void:
	var home := world.get_node("HomePort") as Node3D
	if boat == null:
		var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/container_feeder_40.json"))
		boat = VesselSpawn.instantiate_from_record(VesselSpawn.normalize_record({"uid":"world-rain-review","name":stock.name,"hull_id":stock.hull_id,"brick_layout":stock.brick_layout}))
		boat.freeze = true; world.add_child(boat)
		boat.global_transform = home.global_transform
		boat.global_position = home.to_global(Vector3(0,0,-350))
		boat.global_position.y = WaveSurface.WATER_LEVEL - boat.draft_m
		rain = world.find_child("RainField",true,false) as RainField
		check(rain != null,"actual world owns rain field")
	var state := WeatherState.new()
	state.cloud_cover = .94; state.precipitation = .8
	state.wind_speed_ms = 8; state.wind_force = .36
	state.visibility = .90; state.wind_direction = Vector3(.8,0,.6)
	WeatherLighting.apply_weather_state(state)
	if label == "harbour":
		eye = boat.to_global(Vector3(2,11.65,41)); target = boat.to_global(Vector3(-.5,10.7,35.2))
	elif label == "channel":
		eye = boat.to_global(Vector3(0,7.3,16)); target = boat.to_global(Vector3(0,7.3,-12))
	else:
		eye = home.get_spawn_position() + Vector3.UP * 1.65
		target = eye + home.global_basis * Vector3(25,1,-90)
	camera.global_position = eye; camera.look_at(target)
	player.global_position = eye
	var forest := world.get_node("WorldForestStreamer") as WorldForestStreamer
	for tick in 12: await get_tree().process_frame
	check(await wait_until(func():var s:=forest.get_debug_stats();return s.pending==0 and s.world_canopy_pending==0,120),label+" full woodland ready")
	await super.capture(label,eye,target)
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	for collision in [true,false,true]:
		rain.set_process(collision); rain._shelter.visible = collision
		var gpu: Array[float] = []; var wall: Array[float] = []
		var previous := Time.get_ticks_usec()
		for frame in 150:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			if frame>=30:
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
				wall.append((now-previous)/1000.0)
			previous = now
		gpu.sort(); wall.sort()
		var stats := {"view":label,"shelter":collision,"gpu_median_ms":gpu[60],"gpu_p95_ms":gpu[114],
			"frame_p95_ms":wall[114],"frame_max_ms":wall[-1]}
		report.get_or_add("collision_cost",[]).append(stats)
		print("RAIN_WORLD_COST ",stats)
	RenderingServer.viewport_set_measure_render_time(rid,false)
