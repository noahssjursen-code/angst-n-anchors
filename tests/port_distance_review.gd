extends "res://tests/provision_hoist_review.gd"

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(120).timeout.connect(func():get_tree().quit(1))
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
	if OS.get_cmdline_user_args().has("--compare-models"):
		var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/scenery/port_distance/crane_lods.json"))
		for path: String in provenance.inputs:
			assert(FileAccess.get_sha256(path)==provenance.inputs[path], "Rebuild outdated crane LOD: "+path)
		var label:=Label.new();label.position=Vector2(16,70);add_child(label)
		for kind in ["provision","bulk"]:
			# Export the current assembled source first with export_crane_sources.
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			assert(document.append_from_file("res://resources/models/_source/port_distance/"+kind+"_source.glb", state)==OK)
			var full := document.generate_scene(state) as Node3D
			var low := ImpostorService.stamp("crane:"+kind)
			add_child(full);add_child(low)
			var bounds := ImpostorCache.compute_local_aabb(full)
			var low_bounds := ImpostorCache.compute_local_aabb(low)
			print("CRANE MATCH ",kind," detailed ",bounds," low ",low_bounds)
			assert(bounds.get_center().distance_to(low_bounds.get_center()) < 1.0,"Crane origin or pose mismatch")
			assert((bounds.size-low_bounds.size).length() < 2.0,"Crane silhouette mismatch")
			for variant in ["detailed","lod1"]:
				full.visible=variant=="detailed";low.visible=variant=="lod1"
				label.text=kind+" / "+variant+" / same camera"
				await shot(kind+"-match-"+variant,bounds.get_center()+Vector3(65,25,70),bounds.get_center())
			full.free();low.free()
		print("CRANE MATCH PASS ",output)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--capture-silhouette"):
		camera.far = 12000
		camera.fov = 30
		var proxy := ImpostorService.stamp("crane:provision")
		add_child(proxy)
		for distance in [600, 1500, 3500]:
			for preserve in [false, true]:
				for mesh: MeshInstance3D in proxy.find_children("*", "MeshInstance3D", true, false):
					mesh.lod_bias = 128.0 if preserve else 1.0
				await shot("silhouette-%d-%s" % [distance, "authored" if preserve else "auto"], Vector3(distance * .65, 25, distance * .76), Vector3(0, 25, 0))
				print("SILHOUETTE ",distance," authored ",preserve," triangles ",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		proxy.free()
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--capture-range"):
		camera.far=20000
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		camera.size=110
		var label:=Label.new();label.position=Vector2(16,70);add_child(label)
		camera.position=Vector3(0,50,3500);camera.look_at(Vector3(0,20,0))
		var host:=PortStructureLod.new();add_child(host)
		host.setup("crane:provision",func()->Node3D:return Node3D.new(),PortStructureLod.PROFILE_TALL)
		var baseline:=OS.get_cmdline_user_args().has("--baseline-range")
		for distance in [3500,4300,5600,7800,8400]:
			camera.position=Vector3(0,50,distance);camera.look_at(Vector3(0,20,0))
			await get_tree().create_timer(.4).timeout
			var should_show:bool=distance<=4000 if baseline else distance<=8000
			assert((host.get_child_count()>0)==should_show,"Crane distance transition mismatch")
			label.text="Crane range inspection: %dm | orthographic view | %s" % [distance,"visible" if should_show else "culled"]
			await shot("range-"+str(distance),camera.position,Vector3(0,20,0))
		host.free()
		print("PORT RANGE PASS ",output)
		get_tree().quit()
		return
	for kind in ["provision", "bulk"]:
		var proxy := ImpostorService.stamp("crane:" + kind)
		add_child(proxy)
		var meshes := proxy.find_children("*", "MeshInstance3D", true, false)
		assert(meshes.size() == 1, "Distance crane should be one static mesh")
		var mesh := (meshes[0] as MeshInstance3D).mesh
		assert(mesh.get_surface_count() <= 4)
		assert(mesh.get_faces().size() / 3 <= (40000 if kind=="provision" else 6500))
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
