extends Node3D
## Rendered regression: CPU instance counts cannot detect a shader erasing trees.
var output: String
var camera: Camera3D
var failures := 0

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	run.call_deferred()

func run() -> void:
	output = "C:/Users/noahs/Pictures/machinescreenshots/forest-lod-test-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))
	ForestTreeMesh.request_assets()
	while not ForestTreeMesh.assets_ready(): await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--reproduce-shadowed-name"):
		# Demonstrate that this test actually detects the original renderer bug.
		var source := FileAccess.get_file_as_string("res://scripts/world/forest_lod.gdshaderinc")
		source = source.replace("far_representation", "distant")
		var shader: Shader = ForestTreeMesh.FOLIAGE
		shader.code = shader.code.replace('#include "forest_lod.gdshaderinc"', source)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.0
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-30,0)
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 65
	camera.far = 5000
	add_child(camera)
	camera.current = true
	var middle: Array[MultiMeshInstance3D] = []
	var detailed: Array[MultiMeshInstance3D] = []
	for species in 4:
		var node := MultiMeshInstance3D.new()
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh.mesh = ForestTreeMesh.species_mesh(species,false)
		node.multimesh.instance_count = 1
		node.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY, Vector3(10000+(species-1.5)*16,0,8000)))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		middle.append(node)
		var near_node := MultiMeshInstance3D.new()
		near_node.multimesh = node.multimesh.duplicate()
		near_node.multimesh.mesh = ForestTreeMesh.species_mesh(species,true)
		near_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(near_node)
		near_node.set_instance_shader_parameter("forest_lod_enabled",1.0)
		detailed.append(near_node)
	for distance in [60.0,140.0,155.0,170.0,185.0,200.0]:
		camera.position = Vector3(10000,6,8000+distance)
		camera.look_at(Vector3(10000,6,8000))
		for node in middle: node.set_instance_shader_parameter("forest_lod_enabled",1.0)
		var visible := await pixels("handover-%d"%distance)
		for species in 4:
			if visible[species]<30:
				push_error("Near-to-middle transition lost a tree")
				failures+=1
	for node in detailed: node.visible=false
	for distance in [220.0,750.0,1800.0]:
		camera.position = Vector3(10000,6,8000+distance)
		camera.look_at(Vector3(10000,6,8000))
		for node in middle: node.set_instance_shader_parameter("forest_lod_enabled",0.0)
		var reference := await pixels("reference-%d"%distance)
		for node in middle: node.set_instance_shader_parameter("forest_lod_enabled",1.0)
		var visible := await pixels("streamed-%d"%distance)
		for species in 4:
			var ratio := float(visible[species])/maxi(reference[species],1)
			print("FOREST VISIBLE species=",species," distance=",distance," reference=",reference[species]," streamed=",visible[species]," ratio=",ratio)
			if reference[species]<30 or ratio<.95:
				push_error("Middle-distance forest disappeared")
				failures+=1
	print("FOREST LOD RENDER ","PASS" if failures==0 else "FAIL", " ",output)
	get_tree().quit(0 if failures==0 else 1)

func pixels(tag: String) -> Array[int]:
	for frame in 5: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var view := get_viewport().get_texture().get_image()
	assert(view.save_png(output.path_join(tag+".png"))==OK)
	var result: Array[int] = [0,0,0,0]
	for y in range(view.get_height()):
		for x in range(view.get_width()):
			var colour := view.get_pixel(x,y)
			if maxf(colour.r,maxf(colour.g,colour.b))>.08:
				result[mini(3,x*4/view.get_width())]+=1
	return result
