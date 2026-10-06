extends Node3D
const DRAFT := "res://resources/models/examples/coastal_trawler_draft.json"
var boat: ImportedDraftVessel
var camera: Camera3D
var fishing: FishingSystem
var animate:=false

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	if OS.get_cmdline_user_args().has("--verify-draft"):
		# Exercise the real builder's validation and persistence for this example.
		var editor := ShipyardBrickEditor.new()
		editor.standalone_tool = true
		add_child(editor)
		for i in 8: await get_tree().process_frame
		var parts := editor.get("_imported_parts_editor") as ImportedShipPartsEditor
		parts.load_draft(DRAFT)
		assert(parts.draft_path == DRAFT, "Example must pass builder validation")
		assert(parts.records.size() == 67)
		var temporary := OS.get_cache_dir().path_join("trawler-kit-%d.json" % OS.get_process_id())
		parts.save_draft(temporary)
		parts.load_draft(temporary)
		assert(parts.records.size() == 67)
		DirAccess.remove_absolute(temporary)
		print("TRAWLER DRAFT PASS: real builder validation and save/load, 67 placements")
		editor.queue_free()
		for i in 4: await get_tree().process_frame
		get_tree().quit()
		return
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("263943")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_energy = 1.5
	add_child(sun)
	boat = ImportedDraftVessel.new()
	boat.configure(JSON.parse_string(FileAccess.get_file_as_string(DRAFT)))
	boat.freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(boat)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17
	add_child(camera)
	camera.position = Vector3(15,15,19)
	camera.look_at(Vector3(0,2,0))
	camera.make_current()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var label := Label.new()
	label.text = "COASTAL TRAWLER / editable kit assembly\nBlender winch + separate rotating drum / insulated deck catch tanks\nG: deploy / recover   1: whole boat   2: working deck   Esc: close"
	label.position = Vector2(24,70)
	label.add_theme_font_size_override("font_size",20)
	canvas.add_child(label)
	for i in 3:await get_tree().physics_frame
	fishing = boat.get_fishing_systems()[0]
	assert(fishing.authored_winch != null)
	var holds := boat.get_catch_holds()
	assert(holds.size() == 2)
	assert(holds[0].get_hose_drop_world().distance_to(holds[0].global_position) > .8)
	var drum := fishing._drum_rotation_node
	var before := drum.rotation.z
	fishing.apply_trawl_desired(true)
	fishing._process(.5)
	assert(not is_equal_approx(before,drum.rotation.z))
	_advance(12)
	_verify_rig()
	fishing.apply_trawl_desired(false)
	before = drum.rotation.z
	fishing._process(.5)
	assert(is_equal_approx(before,drum.rotation.z))
	assert(holds[0].accept_lot(CatchLot.create({"lot_id":"kit-test","mass_kg":250})).is_empty())
	var bank := ShoreRswTankBank.new()
	add_child(bank)
	bank.hide()
	var pump := FishLandingPump.new()
	add_child(pump)
	pump.hide()
	pump.bind_receiver(bank)
	pump.connect_seconds=.01
	pump.flush_seconds=.01
	assert(pump.start_unload(boat))
	pump.set_process(false)
	for i in 30: pump._process(.1)
	assert(is_equal_approx(bank.total_mass_kg(),250))
	assert(is_zero_approx(holds[0].state.total_mass_kg()))
	pump.queue_free()
	bank.queue_free()
	print("FISHING KIT PASS: imported drum motion, hold discovery, catch inventory and real shore transfer")
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture")
	if index>=0:
		for i in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(args[index+1]) == OK)
		_deck_view()
		for i in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(args[index+1].get_basename()+"-deck.png") == OK)
		fishing.apply_trawl_desired(true)
		for stage in [.22,.36,.48,.72]:
			_advance((stage-fishing.imported_rig.deployment_fraction)*fishing.imported_rig.deploy_seconds)
			camera.size=17;camera.position=Vector3(15,12,21);camera.look_at(Vector3(0,3,7))
			label.text="TRAWL DEPLOYMENT / %d%%\nContinuous door travel / folded net / winch-driven warp" % roundi(stage*100)
			await _capture(args[index+1].get_basename()+"-stage-%d.png" % roundi(stage*100))
		_advance(12)
		camera.size=33;camera.position=Vector3(26,22,38);camera.look_at(Vector3(0,1,10))
		label.text="DEPLOYED TRAWL / existing fishing state\nTwo warps over actual blocks / separate doors / open diamond mesh"
		await _capture(args[index+1].get_basename()+"-deployed.png")
		label.hide();camera.size=12;camera.position=Vector3(10,5,13);camera.look_at(Vector3(0,-.6,20))
		await _capture(args[index+1].get_basename()+"-net.png")
		camera.size=3.2;camera.position=Vector3(1.8,6.8,7.6);camera.look_at(Vector3(.95,5.2,5))
		await _capture(args[index+1].get_basename()+"-block.png")
		boat.queue_free()
		for i in 4:await get_tree().process_frame
		get_tree().quit()
	else:animate=true

func _capture(path:String) -> void:
	for i in 12:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

func _verify_rig() -> void:
	var rig:=fishing.imported_rig
	assert(rig!=null and rig.gantry!=null and fishing._net_mesh==null,"Imported vessel must use actual net assets")
	assert(rig.net.visible and not rig.bundle.visible and rig.routes.size()==2)
	assert(rig.ropes.size()==24)
	assert(is_equal_approx(rig.deployment_fraction,1.0) and not rig.is_transitioning())
	var drum_before:=fishing._drum_rotation_node.rotation.z
	_advance(.5)
	assert(is_equal_approx(drum_before,fishing._drum_rotation_node.rotation.z),"Winch must hold the warp while towing")
	boat._sync_moving_part_colliders()
	var stow_colliders:=0
	for item in boat.moving_colliders:
		if item.get("fishing_stow",false):
			stow_colliders+=1;assert(item.collision.disabled)
	assert(stow_colliders>0,"Stowed equipment must have walking collision")
	for route in rig.routes:
		assert(route.size()==11)
		var start:=boat.to_local(route[9]);var end:=boat.to_local(route[10])
		var crossing:=start.lerp(end,(7-start.z)/(end.z-start.z))
		assert(crossing.y>3.80,"Tow warp must clear the stern bulwark")
	# Roll/yaw/translation must preserve ship-side authored endpoints and finite spans.
	var original:=boat.transform
	boat.position=Vector3(31,3,-22);boat.rotation=Vector3(.08,.75,-.15)
	fishing._process(.1)
	for i in 2:
		var name_:String="PayoutPort" if i==0 else "PayoutStarboard"
		assert(rig.routes[i][0].is_equal_approx((fishing.authored_winch.find_child(name_,true,false) as Node3D).global_position))
	for line_ in rig.ropes:
		assert(line_.global_position.is_finite() and line_.global_basis.determinant()>0)
	boat.transform=original
	fishing.apply_trawl_desired(false)
	_advance(4.8)
	assert(rig.net.visible and not rig.bundle.visible,"Recovery cannot instantly hide deployed gear")
	assert(rig.warp_travel_delta<0,"Recovering warp must reverse drum/sheave travel")
	var mid_pose:=rig.net.global_transform
	fishing.apply_trawl_desired(true)
	assert(rig.net.global_transform.is_equal_approx(mid_pose),"Reversing mid-haul must preserve the pose")
	_advance(.1)
	assert(rig.warp_travel_delta>0)
	fishing.apply_trawl_desired(false)
	_advance(17)
	boat._sync_moving_part_colliders()
	for item in boat.moving_colliders:
		if item.get("fishing_stow",false):assert(not item.collision.disabled)
	assert(not rig.net.visible and rig.bundle.visible)
	for door in rig.doors:assert(door.transform.is_equal_approx(Transform3D.IDENTITY))
	# Stowed warps remain attached; deployment/recovery must clear the real stern.
	fishing.apply_trawl_desired(true)
	for i in 60:
		_advance(.2)
		for door in rig.doors:
			var box:=boat.global_transform.affine_inverse()*door.global_transform*BrickCatalog.visual_bounds(door)
			if box.position.z<7.1 and box.end.z>6.9:assert(box.position.y>3.92,"Door swept through stern bulwark")
		if i in [10,17,23,35,59]:
			for mesh:MeshInstance3D in rig.net.find_children("*","MeshInstance3D",true,false):
				for surface in mesh.mesh.get_surface_count():
					var vertices:=boat.assembler.deformed_vertices(mesh,surface)
					for j in range(0,vertices.size(),24):
						var p:=boat.to_local(mesh.to_global(vertices[j]))
						if absf(p.z-7)<.15:assert(p.y>3.92,"Folded net swept through stern bulwark")
	fishing.apply_trawl_desired(false)
	_advance(17)
	print("TRAWL RIG PASS: 12s deployment/16s recovery, reverse mid-haul, winch hold/reverse, clearance, authored anchors and stow collision")

func _advance(seconds:float) -> void:
	var remaining:=seconds
	while remaining>.00001:
		var dt:=minf(remaining,.05)
		fishing._process(dt)
		remaining-=dt

func _deck_view() -> void:
	camera.size=9
	camera.position=Vector3(7,9,11)
	camera.look_at(Vector3(0,3.5,3.5))

func _process(delta: float) -> void:
	if animate and is_instance_valid(fishing):
		fishing._process(delta)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):get_tree().quit()
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_G and is_instance_valid(fishing):fishing.apply_trawl_desired(not fishing.trawling)
		if event.keycode==KEY_2:_deck_view()
		if event.keycode==KEY_1:
			camera.size=17
			camera.position=Vector3(15,15,19)
			camera.look_at(Vector3(0,2,0))
