extends "res://tests/provision_hoist_review.gd"
## F6 with --shipyard-playtest. 1/2/3: rock/heath/woodland, V: overview.
## --capture-terrain saves all six views to the machine screenshot archive.
var ground: MeshInstance3D
var kind := 0
var wide := false
var material: ShaderMaterial
var label: Label

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	output = "C:/Users/noahs/Pictures/machinescreenshots/terrain-material-" + str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.35,.43,.52)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .45
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28,-35,0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 58
	add_child(camera)
	camera.current = true
	material = ShaderMaterial.new()
	material.shader = load("res://resources/shaders/terrain.gdshader")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-shader="):
			var baseline := Shader.new()
			baseline.code = FileAccess.get_file_as_string(arg.trim_prefix("--baseline-shader="))
			material.shader = baseline
	TerrainSurfaceMaps.bind_to_material(material,90210)
	label = Label.new()
	label.position = Vector2(20,60)
	add_child(label)
	if not OS.get_cmdline_user_args().has("--capture-terrain"):
		show_surface()
		return
	for variant in 3:
		kind = variant
		show_surface()
		await shot(["rock","heath","forest-floor"][kind]+"-close",eye(false),target())
		await shot(["rock","heath","forest-floor"][kind]+"-wide",eye(true),target())
	print("TERRAIN MATERIAL REVIEW COMPLETE ",output)
	get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): return
	if event.keycode >= KEY_1 and event.keycode <= KEY_3:
		kind = event.keycode - KEY_1
		show_surface()
	elif event.keycode == KEY_V:
		wide = not wide
		camera.position = eye(wide)
		camera.look_at(target())

func target() -> Vector3:
	return Vector3(0,1.5 if kind == 0 else 30.0,0)

func eye(overview: bool) -> Vector3:
	return target() + (Vector3(0,18,26) if overview else Vector3(2,1.7,5))

func show_surface() -> void:
	if is_instance_valid(ground): ground.free()
	var image := Image.create(4,4,false,Image.FORMAT_R8)
	image.fill(Color.WHITE if kind == 2 else Color.BLACK)
	material.set_shader_parameter("forest_map",ImageTexture.create_from_image(image))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in 65:
		for x in 65:
			surface.set_color(Color(1,1,1,1 if kind == 0 else 0))
			surface.add_vertex(Vector3(x-32,target().y+.3*sin(x*.22)*cos(z*.17),z-32))
	for z in 64:
		for x in 64:
			var a := z*65+x
			for index in [a,a+1,a+65,a+1,a+66,a+65]: surface.add_index(index)
	surface.generate_normals()
	ground = MeshInstance3D.new()
	ground.mesh = surface.commit()
	ground.material_override = material
	add_child(ground)
	camera.position = eye(wide)
	camera.look_at(target())
	label.text = "1 Rock    2 Heath    3 Woodland soil    V Close / overview\n" + ["Wet coastal bedrock","Heath","Forest floor"][kind]
