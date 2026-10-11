extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	assert(ShipyardPlaytestMode.active(), "Run with -- --shipyard-playtest")
	create_timer(60).timeout.connect(func(): quit(1))
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--baseline-source="):continue
		var baseline := GDScript.new()
		baseline.source_code=FileAccess.get_file_as_string(arg.trim_prefix("--baseline-source="))
		assert(baseline.reload()==OK)
		for variant in LandDecorCache.VARIANT_COUNT:
			var old:Node3D=baseline.call("house_instance",variant,0,0)
			var current:=LandDecorCache.house_instance(variant,0,0)
			assert(old.get_child_count()==current.get_child_count())
			for index in current.get_child_count():
				var a:=old.get_child(index) as MeshInstance3D
				var b:=current.get_child(index) as MeshInstance3D
				assert(a.mesh.surface_get_arrays(0)==b.mesh.surface_get_arrays(0),"Cache migration changed vertex data")
				assert(a.material_override==b.material_override and a.transform==b.transform and a.cast_shadow==b.cast_shadow)
			old.free()
			current.free()
		var retained:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		baseline.call("clear")
		print("BASELINE ORPHANS RELEASED ",retained-int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
		print("BASELINE GEOMETRY PASS: all eight variants, vertex/normal/index/UV data and materials identical")
	LandDecorCache.clear()
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for cycle in 3:
		for variant in LandDecorCache.VARIANT_COUNT:
			var first := LandDecorCache.house_instance(variant,0,0)
			var second := LandDecorCache.house_instance(variant,0,0)
			assert(first.get_child_count()==5)
			for index in first.get_child_count():
				var a := first.get_child(index) as MeshInstance3D
				var b := second.get_child(index) as MeshInstance3D
				assert(a.mesh == b.mesh and a.material_override == b.material_override)
				assert(a.transform == b.transform)
			# Existing stamps must remain valid across eviction/rebuild.
			LandDecorCache.clear()
			assert((first.get_child(0) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()>0)
			first.free()
			second.free()
		# A populated cache must own resources, not orphan rendering nodes.
		var last := LandDecorCache.house_instance(0,0,0)
		last.free()
		assert(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))==orphan_count,"Village cache retains orphan nodes")
	print("LAND DECOR CACHE PASS: shared resources, live eviction, three rebuild cycles, zero orphan nodes")
	if OS.get_cmdline_user_args().has("--render-review"):
		await render_review()
	quit()

func render_review() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.35,.45,.55)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.65,.72,.8)
	environment.environment.ambient_light_energy = .6
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	sun.light_energy = 1.2
	scene.add_child(sun)
	for variant in LandDecorCache.VARIANT_COUNT:
		var house := LandDecorCache.house_instance(variant,0,0)
		scene.add_child(house)
		house.position = Vector3((variant % 4)*12,0,(variant / 4)*14)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(47,34,55)
	camera.look_at(Vector3(18,2,7))
	camera.current = true
	for frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var directory := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("village-cache-"+str(Time.get_unix_time_from_system()).replace(".","-")+".png")
	assert(root.get_texture().get_image().save_png(path)==OK)
	print("CAPTURE ",path)
	scene.queue_free()
	await process_frame
