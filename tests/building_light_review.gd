extends "res://tests/provision_hoist_review.gd"
var probes: Array[Vector3] = []
func brightness() -> float:
	var image := get_viewport().get_texture().get_image()
	var total := 0.0
	for point in probes:
		var p := Vector2i(camera.unproject_position(point))
		for y in range(-2,3):
			for x in range(-2,3):
				var c := image.get_pixel(p.x+x,p.y+y)
				total += c.r+c.g+c.b
	return total
func review() -> void:
	assert(ShipyardPlaytestMode.active())
	output="C:/Users/noahs/Pictures/machinescreenshots/building-lighting-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.12,.15,.19)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.5
	add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-30,0);sun.light_energy=1.2;add_child(sun)
	camera=Camera3D.new();add_child(camera);camera.current=true
	var swatch := MeshInstance3D.new()
	swatch.mesh = BoxMesh.new()
	var paint := StandardMaterial3D.new();paint.albedo_color=Color(.4,.2,.1)
	swatch.material_override=paint;add_child(swatch)
	await ImpostorCache.bake_from_node(self,"albedo-check",swatch,64)
	var samples: Array[float] = []
	for texture in ImpostorCache._entries["albedo-check"].textures.values():
		var image: Image = texture.get_image()
		assert(image.has_mipmaps())
		samples.append(image.get_pixel(image.get_width()/2,image.get_height()/2).r)
	assert(samples.max()-samples.min()<.025,"Bake contains directional lighting")
	assert(paint.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL,"Baking changed source material")
	swatch.free()
	for i in 3:
		var source:=LandDecorCache.house_instance(i,0,0)
		add_child(source)
		await ImpostorCache.bake_from_node(self,"review"+str(i),source,256)
		if OS.get_cmdline_user_args().has("--geometry-houses"):
			ImpostorCache.register_geometry("review"+str(i),LandDecorCache.house_distance_mesh(i))
		source.position=Vector3((i-1)*25,0,0)
		var proxy:=ImpostorCache.instance("review"+str(i));add_child(proxy);proxy.position=source.position+Vector3(0,0,30)
		probes.append(proxy.position+Vector3(0,3,0))
	await shot("day",Vector3(62,45,85),Vector3(0,3,14))
	var day_brightness := brightness()
	await shot("roof-close",Vector3(16,12,53),Vector3(0,4,30))
	sun.rotation_degrees=Vector3(-25,150,0)
	await shot("opposite-sun",Vector3(62,45,85),Vector3(0,3,14))
	sun.light_energy=.025;env.environment.ambient_light_energy=.025
	await shot("night",Vector3(62,45,85),Vector3(0,3,14))
	var night_brightness := brightness()
	assert(night_brightness < day_brightness*.25, "Distant buildings stay bright at night")
	print("BUILDING LIGHT RESPONSE ",day_brightness," -> ",night_brightness)
	print("BUILDING LIGHT REVIEW COMPLETE ",output)
	get_tree().quit()
