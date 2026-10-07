extends "res://tests/provision_hoist_review.gd"

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	output = "C:/Users/noahs/Pictures/machinescreenshots/port-distance-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.32, .40, .46)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = .6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 40
	add_child(camera)
	camera.current = true
	for kind in ["provision", "bulk"]:
		var proxy := ImpostorService.stamp("crane:" + kind)
		add_child(proxy)
		var meshes := proxy.find_children("*", "MeshInstance3D", true, false)
		assert(meshes.size() == 1, "Distance crane should be one static mesh")
		var mesh := (meshes[0] as MeshInstance3D).mesh
		assert(mesh.get_surface_count() <= 3)
		assert(mesh.get_faces().size() / 3 <= 14000)
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			assert(material != null and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED)
			assert(not material.emission_enabled)
		var bounds := ImpostorCache.compute_local_aabb(proxy)
		assert(bounds.size.y > 30, "Export must retain the assembled mast/boom height")
		for night in [false, true]:
			env.environment.ambient_light_energy = .05 if night else .6
			sun.light_energy = .025 if night else 1.0
			await shot(kind + ("-night" if night else "-day"), bounds.get_center() + Vector3(65, 25, 70), bounds.get_center())
		proxy.free()
	print("PORT DISTANCE PASS: mesh budgets, retained height, live lighting; ", output)
	get_tree().quit()
