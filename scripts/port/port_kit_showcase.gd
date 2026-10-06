extends Node3D

var boat: ImportedDraftVessel
var camera: Camera3D
var pump: FishLandingPump
var label: Label

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("263943")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.7;add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.shadow_enabled=true;add_child(sun)
	boat=ImportedDraftVessel.new()
	boat.configure(JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/coastal_trawler_draft.json")))
	boat.freeze=true;boat.process_mode=Node.PROCESS_MODE_DISABLED;add_child(boat)
	var quay:=MeshBuilder.box(Vector3(15,2.92,22),Color(.19,.21,.22),.9,0)
	quay.position=Vector3(-11,1.46,0);add_child(quay)
	var posts:Array[MooringPost]=[]
	for z in [-2.8,6.0]:
		var post:=MooringPost.new();post.position=Vector3(-4.4,2.92,z);add_child(post);posts.append(post)
	pump=FishLandingPump.new();pump.position=Vector3(-9,2.92,0);add_child(pump)
	var bank:=ShoreRswTankBank.new();add_child(bank);bank.hide();pump.bind_receiver(bank)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=24;add_child(camera)
	camera.position=Vector3(16,19,20);camera.look_at(Vector3(-4,3,0));camera.make_current()
	var canvas:=CanvasLayer.new();add_child(canvas);label=Label.new();label.position=Vector2(24,70)
	label.add_theme_font_size_override("font_size",20);canvas.add_child(label)
	label.text="PORT KIT / Blender mooring fittings and four-part landing plant\nExisting mooring constraints, dynamic ropes, hose and CatchLot transfer"
	for i in 8:await get_tree().process_frame
	var mooring:=boat.find_child("MooringComponent",true,false) as MooringComponent
	assert(mooring._ship_cleat_nodes().size()==4)
	for point: MooringPoint in mooring._ship_cleat_nodes():
		assert(point._rope_anchor != null)
		assert(point.to_local(point.get_anchor_global_position()).is_equal_approx(Vector3(0,.52*.85,0)))
		var shape:=ImportedHullCatalog.make_grid("trawler_hull_14m").deck_polygon
		assert(Geometry2D.is_point_in_polygon(Vector2(point.position.x,point.position.z),shape))
	posts[0].bollard_scale=1.2
	assert(posts[0].to_local(posts[0].get_anchor_global_position()).is_equal_approx(Vector3(0,.624,0)))
	assert(is_instance_valid(posts[0]._prompt_layer),"Model rebuild must preserve interaction prompt")
	posts[0].bollard_scale=1
	assert(mooring.toggle_line_from_post(posts[0]))
	assert(mooring.toggle_line_from_post(posts[1]))
	assert(mooring.bow_line_tied and mooring.stern_line_tied)
	mooring._update_rope_visuals()
	var start:=mooring._cleat_anchor(mooring._bow_point)
	var sampled:=mooring._rope_sample_points(start,posts[0].get_anchor_global_position())
	assert(sampled[0].is_equal_approx(start) and sampled[-1].is_equal_approx(posts[0].get_anchor_global_position()))
	boat.position.y+=.25;boat.rotation.z=.025;mooring._update_rope_visuals()
	assert(mooring._cleat_anchor(mooring._bow_point).distance_to(start)>.15)
	boat.position.y=0;boat.rotation.z=0;mooring._update_rope_visuals()
	var hold:=boat.get_catch_holds()[0]
	assert(hold.accept_lot(CatchLot.create({"lot_id":"port-kit","mass_kg":250})).is_empty())
	pump.connect_seconds=.1;pump.flush_seconds=.1;pump.pump_rate_kg_s=50
	assert(pump.start_unload(boat));pump.set_process(false);pump._process(.11);pump._process(2)
	assert(is_equal_approx(bank.total_mass_kg(),100))
	assert(is_equal_approx(hold.state.total_mass_kg(),150))
	assert(pump._connection_marker.global_position.is_equal_approx(pump.to_global(Vector3(3.72,1.35,-.82))))
	assert(pump._hose_root.visible)
	var args:=OS.get_cmdline_user_args();var index:=args.find("--capture")
	if index>=0:
		var path:=args[index+1]
		await _capture(path)
		camera.size=12;camera.position=Vector3(0,11,-12);camera.look_at(pump.position+Vector3(-.4,2,0))
		label.text="LANDING PLANT / separate skid, separator, drive and receiving trough\n100 kg received / 150 kg aboard / live flexible hose"
		await _capture(path.get_basename()+"-pump.png")
		camera.size=5;camera.position=Vector3(1,7,10);camera.look_at(Vector3(-3.2,3.2,6))
		label.text="MOORING / authored rope sockets / existing dynamic line"
		await _capture(path.get_basename()+"-mooring.png")
	for i in 50:
		pump._process(.1)
		if pump.state_label()==FishLandingPump.STATE_COMPLETE:break
	assert(is_equal_approx(bank.total_mass_kg(),250) and is_zero_approx(hold.state.total_mass_kg()))
	assert(pump.state_label()==FishLandingPump.STATE_COMPLETE and not pump._hose_root.visible)
	mooring.release_mooring();assert(not mooring.bow_line_tied and not mooring.stern_line_tied)
	for mesh in mooring._bow_rope_segments:assert(not mesh.visible)
	print("PORT KIT PASS: four discovered cleats, transformed sockets, rebuilt prompt, tie/release and moving anchors, actual 250 kg transfer and hose disconnect")
	if index>=0:
		boat.queue_free();pump.queue_free();bank.queue_free()
		for post in posts:post.queue_free()
		for i in 4:await get_tree().process_frame
		get_tree().quit()

func _capture(path: String) -> void:
	for i in 8:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):get_tree().quit()
