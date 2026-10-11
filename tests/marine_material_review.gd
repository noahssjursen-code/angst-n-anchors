extends Node3D

## F6 material review: stock ship construction path, optical finishes retained,
## close-up/day/night inspection and immutable per-instance paint verification.
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var boat: ImportedDraftVessel
var output: String
var labels: Label
var current := 0

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	if OS.get_cmdline_user_args().has("--capture") or OS.get_cmdline_user_args().has("--capture-library"):
		get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(2))
	SurfaceMaterialLibrary.enabled = not OS.get_cmdline_user_args().has("--baseline")
	output = "C:/Users/noahs/Pictures/machinescreenshots/marine-materials-" + ("before-" if not SurfaceMaterialLibrary.enabled else "after-") + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color("597b9b")
	sky.sky_horizon_color = Color("b0bec1")
	sky.ground_bottom_color = Color("58646a")
	sky.ground_horizon_color = Color("989e98")
	environment.sky.sky_material = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = .55
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 40, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.fov=55
	add_child(camera)
	camera.make_current()
	var ui := CanvasLayer.new()
	add_child(ui)
	labels = Label.new()
	labels.position = Vector2(24, 60)
	labels.add_theme_font_size_override("font_size", 22)
	ui.add_child(labels)
	await show_ship(0)
	if OS.get_cmdline_user_args().has("--capture"):
		for index in 4:
			await show_ship(index)
			var id: String = CompanyContracts.starter_options()[index].id
			await shot(id + "-whole")
			camera.position = Vector3(boat.beam_m * .9, boat.depth_m + 1, -boat.length_m * .34)
			camera.look_at(Vector3(boat.beam_m * .45, boat.depth_m * .58, 0))
			await shot(id + "-hull")
			var chair: Node3D
			for part in boat.part_roots:
				if part.get_meta("asset_id") in ["roof_tile", "marine_exhaust_stack"]: part.hide()
				if part.get_meta("asset_id") == "helm_chair": chair = part
			camera.position = chair.position + Vector3(2.0, 3.3, -2.7)
			camera.look_at(chair.position + Vector3(0, .55, -.4))
			await shot(id + "-bridge")
			camera.position = chair.position + Vector3(-1.3, 2.6, 1.8)
			camera.look_at(chair.position + Vector3(0, .8, -.65))
			await shot(id + "-seat-console")
			if index == 0:
				sun.light_energy = .035
				environment.ambient_light_energy = .16
				var lamp := OmniLight3D.new()
				lamp.position = chair.position + Vector3(-1, 2.0, -1)
				lamp.light_color = Color("ffe0b2")
				lamp.light_energy = 2.5
				lamp.omni_range = 5
				add_child(lamp)
				await shot(id + "-artificial")
				lamp.free()
				sun.light_energy = 1.35
				environment.ambient_light_energy = .55
		print("MARINE MATERIAL REVIEW PASS stock fleet captured; texture bytes=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED))
		get_tree().quit()

func show_ship(index: int) -> void:
	current = index
	if is_instance_valid(boat):
		boat.queue_free()
		for i in 3: await get_tree().process_frame
	var option := CompanyContracts.starter_options()[index]
	boat = VesselSpawn.instantiate_from_record(CompanyService.build_starter_vessel_record(option.id))
	boat.freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(boat)
	camera.position = Vector3(boat.length_m * .62, boat.depth_m + boat.length_m * .52, -boat.length_m * .72)
	camera.look_at(Vector3(0, boat.depth_m + .8, 0))
	labels.text = str(option.label) + " · " + ("Original materials" if not SurfaceMaterialLibrary.enabled else "Shared marine finishes") + "\n1–4 · Ships"
	for i in 15: await get_tree().process_frame

func shot(tag: String) -> void:
	camera.make_current()
	for i in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(tag + ".png")
	assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	print("CAPTURE ", path)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode >= KEY_1 and event.keycode <= KEY_4: show_ship(event.keycode - KEY_1)
