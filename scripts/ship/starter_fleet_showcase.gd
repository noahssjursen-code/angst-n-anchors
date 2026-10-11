extends Node3D
## F6: the exact stock blueprints used by company onboarding and draft copies.
var boat: ImportedDraftVessel
var camera: Camera3D
var label: Label
var current := 0

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("263943")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(camera)
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(95,24)
	label.add_theme_font_size_override("font_size",24)
	ui.add_child(label)
	await show_ship(0)
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture-dir")
	if index >= 0:
		for vessel in 4:
			await show_ship(vessel)
			await capture(args[index+1].path_join("starter-%s.png" % CompanyContracts.starter_options()[vessel].id))
			if vessel == 1:
				for pad in boat.get_cargo_pads(): pad.add_container(ContainerUnit.create())
				await capture(args[index+1].path_join("starter-general_cargo-loaded.png"))
				for pad in boat.get_cargo_pads(): pad.remove_container_at(0)
			for part in boat.part_roots:
				if part.get_meta("asset_id") in ["roof_tile", "marine_exhaust_stack"]: part.hide()
			var chair: Node3D
			for part in boat.part_roots:
				if part.get_meta("asset_id") == "helm_chair": chair = part
			camera.size = 8 if vessel == 3 else 6
			camera.position = chair.position + Vector3(2,9,-3)
			camera.look_at(chair.position + Vector3(0,.6,-.3))
			await capture(args[index+1].path_join("starter-%s-bridge.png" % CompanyContracts.starter_options()[vessel].id))
		print("STARTER FLEET CAPTURED: canonical stock, four ships and bridge cutaways")
		ModelCache.clear()
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
	camera.position = Vector3(boat.length_m*.72, boat.depth_m+boat.length_m*.67,-boat.length_m*.78)
	camera.size = boat.length_m*.98
	camera.look_at(Vector3(0,boat.depth_m+1,0))
	camera.make_current()
	label.text = str(option.label).to_upper() + "\n" + str(option.role) + "\n1–4 · Vessels"
	for i in 8: await get_tree().process_frame

func capture(path: String) -> void:
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and event is InputEventKey:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4: show_ship(event.keycode - KEY_1)
