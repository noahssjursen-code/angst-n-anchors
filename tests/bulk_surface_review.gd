extends Node3D

## Identical heaps near the origin and at a distant port. Pure presentation;
## no stockpile inventory, captain save or authority state is mutated.
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("263943")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .5
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	add_child(sun)
	var group := Node3D.new()
	add_child(group)
	for index in 2:
		var mound := OreMoundBuilder.build_mound("iron_ore" if index == 0 else "coal", Vector3(12, 4, 12), 42)
		mound.position.x = index * 14
		group.add_child(mound)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30
	group.add_child(camera)
	camera.position = Vector3(21, 13, 19)
	camera.look_at(Vector3(7, 1, 0))
	camera.make_current()
	var directory := "C:/Users/noahs/Pictures/machinescreenshots/bulk-surface-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(directory)
	var images: Array[Image] = []
	for offset in [0.0, 16384.0]:
		group.position = Vector3(offset, 0, offset)
		for frame in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png(directory.path_join("offset-%d.png" % offset))
		images.append(image)
	var error := 0.0
	var count := 0
	for y in range(180, 680, 4):
		for x in range(140, 1140, 4):
			var a := images[0].get_pixel(x, y)
			var b := images[1].get_pixel(x, y)
			error += absf(a.r-b.r) + absf(a.g-b.g) + absf(a.b-b.b)
			count += 3
	print("BULK SURFACE translation mean channel error: ", error / count, " CAPTURE ", directory)
	if OS.get_cmdline_user_args().has("--verify-translation"):
		assert(error / count < .01, "Material must retain its appearance at distant ports")
	get_tree().quit()
