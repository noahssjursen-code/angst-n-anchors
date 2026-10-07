extends "res://tests/provision_hoist_review.gd"

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(180).timeout.connect(func():get_tree().quit(1))
	output = "C:/Users/noahs/Pictures/machinescreenshots/port-model-lod-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.25,.32,.38)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.7,.78,.87)
	environment.environment.ambient_light_energy = .55
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40,-30,0)
	add_child(sun)
	camera = Camera3D.new()
	camera.far = 12000
	camera.fov = 40
	add_child(camera);camera.current = true
	var label := Label.new();label.position=Vector2(16,70);add_child(label)
	if OS.get_cmdline_user_args().has("--benchmark"):
		await benchmark(environment, sun)
		get_tree().quit()
		return
	for path: String in PortModelLod.manifest():
		var record: Dictionary = PortModelLod.manifest()[path]
		assert(FileAccess.get_sha256(path) == record.source_sha256, "Rebuild outdated port LOD")
		var source := (load(path) as PackedScene).instantiate() as Node3D
		add_child(source)
		var detailed := source.find_children("*", "MeshInstance3D", true, false)
		var bounds := ImpostorCache.compute_local_aabb(source)
		PortModelLod.attach(source,path)
		var low := source.get_node("DistanceModel") as Node3D
		var low_meshes := low.find_children("*", "MeshInstance3D", true, false)
		assert(low_meshes.size()==1)
		var far := low_meshes[0] as MeshInstance3D
		assert(far.mesh.get_faces().size()/3 <= int(record.detailed_triangles)*.5)
		var low_bounds := ImpostorCache.compute_local_aabb(low)
		assert(bounds.get_center().distance_to(low_bounds.get_center()) < .15, "LOD moved away from authored origin")
		assert((bounds.size-low_bounds.size).length() < .35, "LOD lost silhouette bounds")
		assert(low.find_children("*", "CollisionObject3D",true,false).is_empty())
		for mesh:MeshInstance3D in detailed:
			assert(mesh.get_node(mesh.visibility_parent)==far)
		var name := path.get_file().get_basename()
		var eye := bounds.get_center()+Vector3(1,.65,1.2).normalized()*bounds.size.length()*1.8
		for variant in ["detailed", "lod1"]:
			# Force each representation at identical framing for art review.
			far.visibility_range_begin = 0
			far.visible = variant == "lod1"
			for mesh:MeshInstance3D in detailed:
				mesh.visibility_parent=NodePath()
				mesh.visible=variant == "detailed"
			label.text = name + " / " + variant + " / same camera"
			await shot(name+"-"+variant,eye,bounds.get_center())
		for mesh:MeshInstance3D in detailed:
			mesh.visible=true;mesh.visibility_parent=mesh.get_path_to(far)
		far.visible=true;far.visibility_range_begin=float(record.switch_m)
		# Repeated crossing in both directions, with normal visibility settings.
		var crossing := 0
		for distance in [float(record.switch_m)-30, float(record.switch_m)+30, float(record.switch_m)-30]:
			crossing += 1
			label.text = name + " / actual transition / " + str(distance) + "m"
			await shot(name+"-range-"+str(int(distance))+"-"+str(crossing),bounds.get_center()+Vector3(0,.12,1).normalized()*distance,bounds.get_center())
		print("FACILITY PASS ",name," triangles ",record.detailed_triangles," -> ",record.lod_triangles)
		source.free()
	print("PORT MODEL LOD PASS ",output)
	get_tree().quit()

func benchmark(environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var roots: Array[Node3D] = []
	var index := 0
	for path:String in PortModelLod.manifest():
		for column in 4:
			var root := HarbourEnvironmentKit.model(self,path,Vector3((column-1.5)*60,0,(index-3)*35))
			HarbourEnvironmentKit.solid(root,Vector3(0,2,0),Vector3(2,4,2))
			roots.append(root)
		index+=1
	camera.position=Vector3(210,210,500)
	camera.look_at(Vector3(0,5,0))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var round_index := 0
	for use_lod in [false,true,false,true]:
		round_index += 1
		for root in roots: root.get_node("DistanceModel").visible=use_lod
		var timings:Array[float]=[]
		for frame in 350:
			await RenderingServer.frame_post_draw
			if frame>=100: timings.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		timings.sort()
		print("FACILITY BENCH authored=",use_lod," gpu_median_ms=",timings[timings.size()/2]," draws=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)," triangles=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		await shot("yard-"+str(round_index)+("-lod1" if use_lod else "-original"),camera.position,Vector3(0,5,0))
		for root in roots: assert(root.find_children("*","StaticBody3D",true,false).size()==1,"Visual LOD must not remove collision")
	environment.environment.ambient_light_energy=.035;sun.light_energy=.02
	await shot("yard-night",camera.position,Vector3(0,5,0))
	for root in roots: root.free()
	print("FACILITY BENCH PASS ",output)
