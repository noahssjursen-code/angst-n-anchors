extends "res://tests/provision_hoist_review.gd"
func review() -> void:
	assert(ShipyardPlaytestMode.active())
	output="C:/Users/noahs/Pictures/machinescreenshots/coastal-assets-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.36,.43,.50);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.6;add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=1.2;add_child(sun)
	camera=Camera3D.new();add_child(camera);camera.current=true
	for kind in ["provision","bulk"]:
		var proxy:=ImpostorService.stamp("crane:"+kind);add_child(proxy)
		var box:=ImpostorCache.compute_local_aabb(proxy)
		print("PROXY ",kind," BOUNDS ",box)
		await shot(kind,box.get_center()+Vector3(65,30,70),box.get_center())
		proxy.free()
	for species in 4:
		var mi:=MeshInstance3D.new();mi.mesh=ForestTreeMesh.species_mesh(species,true);add_child(mi);mi.position.x=species*9
	await shot("vegetation-lineup",Vector3(15,8,30),Vector3(14,4,0))
	print("COASTAL ASSET REVIEW COMPLETE ",output)
	get_tree().quit()
