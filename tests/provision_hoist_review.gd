extends Node3D
var crane: ProvisionCrane
var camera: Camera3D
var output: String
func _ready() -> void: call_deferred("review")
func shot(tag:String, eye:Vector3, target:Vector3) -> void:
	camera.position=eye;camera.look_at(target)
	for frame in 20:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path:=output.path_join(tag+".png")
	assert(get_viewport().get_texture().get_image().save_png(path)==OK)
	print("CAPTURE ",path)
func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(90).timeout.connect(func():get_tree().quit(1))
	output="C:/Users/noahs/Pictures/machinescreenshots/provision-hoist-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	var world:=WorldEnvironment.new();world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color(.32,.42,.53)
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color(.72,.8,.9);world.environment.ambient_light_energy=.65
	add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=1.4;sun.shadow_enabled=true;add_child(sun)
	if OS.get_cmdline_user_args().has("--baseline-structure"):
		var baseline:=GDScript.new()
		baseline.source_code="extends ProvisionCrane\nfunc _install_imported_structure() -> void:\n\tpass\n"
		assert(baseline.reload()==OK)
		crane=baseline.new()
	else:
		crane=ProvisionCrane.new()
	add_child(crane)
	for frame in 10:await get_tree().process_frame
	await get_tree().physics_frame
	var space:=get_world_3d().direct_space_state
	var mast_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(4,10,0),Vector3(0,10,0),1))
	assert(not mast_hit.is_empty(),"Mast lost its collision")
	var jib_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(crane.get_boom().to_global(Vector3(0,4,-10)),crane.get_boom().to_global(Vector3(0,0,-10)),1))
	assert(not jib_hit.is_empty(),"Jib lost its collision")
	if not OS.get_cmdline_user_args().has("--baseline-structure"):
		assert(crane.get_boom().to_local(jib_hit.position).y>1.1,"New upper chord is outside collision")
	camera=Camera3D.new();add_child(camera);camera.current=true
	var hook:=crane.get_hook_global()
	print("HOOK ",hook," TROLLEY ",crane.get_talje_global())
	await shot("whole",Vector3(55,48,50),Vector3(0,22,-15))
	await shot("mast-joint",Vector3(5,13,6),Vector3(0,11,0))
	await shot("jib-joint",crane.get_boom().global_position+Vector3(4,3,-7),crane.get_boom().global_position+Vector3(0,0,-10))
	await shot("hook",hook+Vector3(2.4,1.7,3.4),hook+Vector3(0,.5,0))
	await shot("trolley",crane.get_talje_global()+Vector3(3,-1,4),crane.get_talje_global())
	var start:=crane.get_hook_global();crane.hoist_length_m=18
	assert(crane.get_hook_global().is_equal_approx(start+Vector3(0,-8,0)))
	crane.trolley_z_m=-30;crane.slew_degrees=35
	await shot("moved",Vector3(55,48,50),Vector3(0,22,-15))
	print("PROVISION HOIST MOTION PASS")
	# Endpoints must meet the authored pulley tangents at every sampled pose.
	for size in [.5,1.0,1.4]:
		var test_crane:=ProvisionCrane.new();test_crane.model_scale=size;add_child(test_crane)
		for frame in 4:await get_tree().process_frame
		var mast:=test_crane.get_girder().get_node("mast_section_5m") as MultiMeshInstance3D
		var jib:=test_crane.get_boom().get_node("jib_section_5m") as MultiMeshInstance3D
		assert(mast.multimesh.instance_count==6 and jib.multimesh.instance_count==15)
		for i in 5:
			assert((mast.multimesh.get_instance_transform(i)*Vector3(0,5,0)).is_equal_approx(mast.multimesh.get_instance_transform(i+1).origin),"Mast seam gap")
		for i in 14:
			assert((jib.multimesh.get_instance_transform(i)*Vector3(0,0,-5)).is_equal_approx(jib.multimesh.get_instance_transform(i+1).origin),"Jib seam gap")
		for length in [2.0,10.0,32.0]:
			test_crane.hoist_length_m=length
			test_crane.slew_degrees=length*3
			test_crane.trolley_z_m=-length
			for x in [-.30,.30]:
				var end:=test_crane._wire_mesh.to_global(Vector3(x,-10,0))
				var tangent:=test_crane.get_hook().to_global(Vector3(x,.85,0)*size)
				assert(end.distance_to(tangent)<.0001,"Rope misses lower sheave")
			assert(test_crane.get_hook().scale==Vector3.ONE,"Hoist stretched the hook")
		test_crane.queue_free()
		await get_tree().process_frame
	var container:=ContainerNode.new();add_child(container)
	container.setup(ContainerUnit.create("hoist-review","provisions",3200,"20ft"))
	assert(crane.attach_container(container))
	var identity:=container.unit.to_dict()
	crane.hoist_length_m=22;crane.trolley_z_m=-24;crane.slew_degrees=-25
	var command:=ProvisionCraneCommand.new()
	command.slew_rate=.2;command.trolley_rate=.1;command.hoist_rate=-.1
	for frame in 90:
		crane.step(1.0/60.0,command)
		await get_tree().process_frame
	assert(container.to_global(Vector3(0,container.lift_height_m(),0)).distance_to(crane.get_hook_global())<.0001)
	assert(container.unit.to_dict()==identity)
	hook=crane.get_hook_global()
	await shot("loaded",hook+Vector3(7,4,10),hook+Vector3(0,-1,0))
	assert(crane.release_container_to_world(Vector3(4,0,4),self)==container)
	assert(container.global_position.is_equal_approx(Vector3(4,0,4)))
	assert(container.unit.to_dict()==identity)
	print("PROVISION HOIST PASS: 3 scales/3 lengths, tangent continuity, rigid block, real container pickup/move/release")
	camera.position=Vector3(55,48,50);camera.look_at(Vector3(0,22,-15))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var timings:Array[float]=[]
	for frame in 120:
		await get_tree().process_frame
		if frame>=30:timings.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	timings.sort()
	print("HOIST REVIEW GPU median_ms=",timings[timings.size()/2]," triangles=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)," draws=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	get_tree().quit()
