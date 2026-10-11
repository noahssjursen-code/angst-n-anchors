extends Node3D
var renderer: WorldRenderer
var camera: Camera3D
var ridge: MeshInstance3D
var output: String
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(100).timeout.connect(func():get_tree().quit(2))
	WorldClock.set_process(false)
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.time_of_day = .24
	WeatherLighting.cloud_cover = 0.0
	WeatherLighting.visibility = 1.0
	WeatherLighting.precipitation = 0.0
	renderer = WorldRenderer.new()
	add_child(renderer)
	camera = Camera3D.new()
	camera.far = 12000
	camera.position = Vector3(0, 9, 0)
	add_child(camera)
	camera.current = true
	var sun: Vector3 = SolarCycle.sample(.24).sun_direction
	var horizontal := Vector3(sun.x, 0, sun.z).normalized()
	camera.look_at(horizontal * 1500 + Vector3.UP * 60)
	ridge = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2500, 400, 300)
	ridge.mesh = mesh
	ridge.position = horizontal * 1500 + Vector3.UP * 170
	ridge.basis = Basis.looking_at(horizontal)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(.12,.15,.10)
	ridge.material_override = mat
	add_child(ridge)
	output = "C:/Users/noahs/Pictures/machinescreenshots/solar-coast-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")
func capture(label:String) -> void:
	for i in 35: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(label + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ",path)
func run() -> void:
	ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await capture("before-ridge-transparent-to-light")
	ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	await capture("after-ridge-occlusion")
	# Tiny clock steps previously never notified lighting at all.
	var notifications := [0]
	WeatherLighting.state_changed.connect(func():notifications[0]+=1)
	for i in 240:
		WeatherLighting.time_of_day = .24 + float(i + 1) / (60.0 * 1440.0)
		await get_tree().process_frame
		var actual := renderer._sun.global_basis.z
		var expected: Vector3 = SolarCycle.sample(WeatherLighting.time_of_day).sun_direction
		assert(actual.angle_to(expected) < .001, "Sun must follow every clock step")
	assert(notifications[0] >= 35, "Small clock steps must accumulate into lighting refreshes")
	print("SOLAR CONTINUITY PASS notifications=",notifications[0])
	WeatherLighting.time_of_day = .40
	await capture("sun-above-ridge")
	print("SOLAR COAST REVIEW PASS")
	get_tree().quit()
