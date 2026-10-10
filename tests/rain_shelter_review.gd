extends Node3D
## Actual rain shader under static/moving shelter, then the imported feeder bridge.
var camera: Camera3D
var rain: RainField
var roof: MeshInstance3D
var boat: ImportedDraftVessel
var directory: String
var results: Array[Dictionary] = []
var moving := false
var elapsed := 0.0
var reproduce := false
var failures: Array[String] = []

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.set_process(false)
	WeatherLighting.time_of_day = .5
	var state := WeatherState.new()
	state.cloud_cover = .95; state.precipitation = .85
	state.wind_speed_ms = 1; state.wind_force = .05; state.visibility = .90
	WeatherLighting.apply_weather_state(state)
	var renderer := WorldRenderer.new()
	renderer.enable_ocean_system = false
	add_child(renderer)
	camera = Camera3D.new(); camera.fov = 65; camera.far = 500
	add_child(camera); camera.make_current()
	rain = RainField.new()
	reproduce = OS.get_cmdline_user_args().has("--reproduce-roof-leak")
	if reproduce:
		rain.field_extents.y = 8; rain.height_above_camera = 6
	add_child(rain)
	if reproduce:
		rain.set_process(false); rain._shelter.hide()
		rain._process_material.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	_box("Floor", Vector3(80,.3,80), Vector3(0,-.15,0), "crushed_aggregate")
	_box("Backdrop", Vector3(30,6,.3), Vector3(0,3,-6), "roof_enamel")
	roof = _box("Canopy", Vector3(10,.3,12), Vector3(0,3.1,0), "roof_enamel")
	for x in [-4.7,4.7]:
		_box("Support",Vector3(.18,3,.18),Vector3(x,1.5,3),"roof_enamel")
	directory = "C:/Users/noahs/Pictures/machinescreenshots/rain-shelter-" + str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(directory)
	call_deferred("_review")

func _box(label: String, size: Vector3, point: Vector3, finish: String) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name = label
	var mesh := BoxMesh.new(); mesh.size = size; node.mesh = mesh
	node.material_override = SurfaceMaterialLibrary.material(finish, Color(.16,.20,.22))
	node.position = point; add_child(node)
	return node

func _process(delta: float) -> void:
	if reproduce and rain:
		rain.global_position = camera.global_position + Vector3.UP * rain.height_above_camera
	if moving and boat:
		elapsed += delta
		boat.position.x = 100 + elapsed * 7.5
		boat.rotation.z = sin(elapsed*.7)*.06
		camera.global_position = boat.to_global(Vector3(2,11.65,41))
		camera.look_at(boat.to_global(Vector3(-.5,10.7,35.2)),boat.global_basis.y)

func _review() -> void:
	camera.position = Vector3(0,1.65,2)
	camera.look_at(Vector3(0,1.65,-6))
	await _capture("covered-canopy", Rect2(.22,.30,.56,.50))
	roof.position.x = 30
	await _capture("roof-moved-away", Rect2(.22,.30,.56,.50))
	roof.position.x = 0
	await _capture("roof-returned", Rect2(.22,.30,.56,.50))
	var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/container_feeder_40.json"))
	boat = VesselSpawn.instantiate_from_record(VesselSpawn.normalize_record({"uid":"rain-shelter-review","name":stock.name,"hull_id":stock.hull_id,"brick_layout":stock.brick_layout}))
	boat.freeze = true; add_child(boat); boat.position = Vector3(100,0,0)
	camera.global_position = boat.to_global(Vector3(2,11.65,41))
	camera.look_at(boat.to_global(Vector3(-.5,10.7,35.2)))
	await _capture("feeder-bridge", Rect2(.22,.65,.56,.30))
	moving = true
	await _capture("moving-feeder-bridge",Rect2(.22,.65,.56,.30))
	moving = false
	camera.global_position = boat.to_global(Vector3(0,7.3,16))
	camera.look_at(boat.to_global(Vector3(0,7.3,-12)))
	await _capture("exposed-feeder-deck",Rect2(.2,.35,.6,.5))
	WeatherLighting.precipitation = 0; rain._apply_weather()
	await get_tree().create_timer(2.5).timeout
	results.append({"dry_emission_off": not rain._particles.emitting,
		"dry_collision_off":not rain._shelter.visible,"reproduce_roof_leak":reproduce})
	if rain._particles.emitting or rain._shelter.visible:
		failures.append("dry weather must stop emission and shelter updates")
	results.append({"failures":failures})
	FileAccess.open(directory.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("RAIN SHELTER REVIEW ",directory)
	boat.queue_free(); rain.queue_free()
	for frame in 3: await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture(label: String, roi: Rect2) -> void:
	rain._particles.use_fixed_seed = true; rain._particles.seed = 912
	rain._particles.restart(); rain._apply_weather()
	await get_tree().create_timer(3).timeout
	var times: Array[float] = []; var start := Time.get_ticks_usec()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var gpu := 0.0
	for frame in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec(); times.append((now-start)/1000.0); start = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	times.sort()
	var was_moving := moving; moving = false
	rain._particles.speed_scale = 0
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var wet := get_viewport().get_texture().get_image()
	assert(wet.save_png(directory.path_join(label+".png")) == OK)
	rain._particles.hide()
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dry := get_viewport().get_texture().get_image()
	assert(dry.save_png(directory.path_join(label+"-without-drops.png")) == OK)
	var changed := 0; var tested := 0
	for y in range(int(roi.position.y*wet.get_height()),int(roi.end.y*wet.get_height())):
		for x in range(int(roi.position.x*wet.get_width()),int(roi.end.x*wet.get_width())):
			var a := wet.get_pixel(x,y); var b := dry.get_pixel(x,y)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))) > .025: changed += 1
			tested += 1
	var row := {"view":label,"roi_changed_pixels":changed,"roi_pixels":tested,
		"frame_median_ms":times[60],"frame_p95_ms":times[114],"gpu_mean_ms":gpu/120.0}
	results.append(row); print("RAIN_SHELTER ",row)
	var covered := label in ["covered-canopy","roof-returned","feeder-bridge","moving-feeder-bridge"]
	# TAA/lighting rounding can move a few pixels; obvious streaks change tens.
	if (covered and changed > 5) or (not covered and changed < 20):
		failures.append(label+": unexpected interior/exterior rain pixels "+str(changed))
	rain._particles.show(); rain._particles.speed_scale = 1; moving = was_moving
