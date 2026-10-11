extends Node3D
const DRAFT := "res://resources/models/examples/coastal_cargo_draft.json"
var boat: ImportedDraftVessel
var camera: Camera3D

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	if OS.get_cmdline_user_args().has("--verify-draft"):
		var editor := ShipyardBrickEditor.new()
		editor.standalone_tool = true
		add_child(editor)
		for i in 8: await get_tree().process_frame
		var parts := editor.get("_imported_parts_editor") as ImportedShipPartsEditor
		parts.load_draft(DRAFT)
		assert(parts.draft_path == DRAFT and parts.records.size() == 93)
		assert(parts.hull_id == "hull_24x8" and is_equal_approx(parts.floor_y(),3.6))
		assert(editor._grid.half_loa == 12 and editor._grid.half_beam == 4)
		for model in parts.parts_root.get_children():
			if parts.records[str(model.get_meta("record_key"))].asset_id == "hatch_cover_5x4":
				assert(model.visible and parts._on_active_floor(model), "Covers must be visible and selectable on deck")
		assert(not parts._on_deck(Vector3(0,3.6,0)), "No placement on the empty hold")
		assert(parts._on_deck(Vector3(3.3,3.6,0)))
		parts.set_floor(1,2)
		assert(is_equal_approx(parts.floor_y(),6.0))
		var temporary := OS.get_cache_dir().path_join("cargo-kit-%d.json" % OS.get_process_id())
		parts.save_draft(temporary)
		parts.load_draft("res://resources/models/examples/coastal_trawler_draft.json")
		assert(parts.hull_id == "trawler_hull_14m" and is_equal_approx(parts.floor_y(),2.92))
		parts.load_draft(temporary)
		assert(parts.hull_id == "hull_24x8" and parts.records.size() == 93)
		assert(is_equal_approx(parts.floor_y(),6.0))
		var before := parts._draft_state()
		var invalid := parts._draft_data().duplicate(true)
		invalid.hull = "not_an_installed_hull"
		var file := FileAccess.open(temporary,FileAccess.WRITE)
		file.store_string(JSON.stringify(invalid));file.close()
		parts.load_draft(temporary)
		assert(before == parts._draft_state(), "Invalid hull must preserve current draft")
		DirAccess.remove_absolute(temporary)
		parts.set_floor(0,0)
		editor.call("_show_toast", "Cargo draft verified: 24 × 8 m · 93 editable parts")
		var capture_args := OS.get_cmdline_user_args()
		var capture_index := capture_args.find("--capture")
		if capture_index >= 0:
			for i in 12: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture_args[capture_index+1])
		print("CARGO DRAFT PASS: two hulls, 93 records, floor datum, opening, save/load and invalid-load preservation")
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
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	boat = ImportedDraftVessel.new()
	boat.configure(JSON.parse_string(FileAccess.get_file_as_string(DRAFT)))
	boat.freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(boat)
	assert(boat.length_m == 24 and boat.beam_m == 8 and boat.depth_m == 3.6)
	assert(boat.part_roots.size() == 93)
	var drive := boat.get_node("HullVisual/DriveGear") as ShipDriveVisual
	assert(drive.propeller.position.z > 12)
	assert(drive.apply_snapshot({"throttle":.5,"steering":.7,"powered":true},1))
	drive.local_boat = null
	var angle := drive.propeller.rotation.z
	drive._process(.12)
	assert(not is_equal_approx(angle,drive.propeller.rotation.z))
	assert(is_equal_approx(drive.rudder.rotation.y,deg_to_rad(19.6)))
	# The uncovered hull must not have a hidden rectangular walk deck across its hold.
	var empty := ImportedDraftVessel.new()
	empty.configure({"hull":"hull_24x8","parts":[]})
	empty.freeze = true;empty.position.x = 40
	add_child(empty)
	for i in 3: await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(40,5,0),Vector3(40,0,0),BoatBody.LAYER_BOAT_WALK)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	assert(not hit.is_empty() and absf(hit.position.y-1.6)<.02, "Open hold ray must reach tank top")
	ray.from = Vector3(43.3,5,0);ray.to=Vector3(43.3,0,0)
	hit = get_world_3d().direct_space_state.intersect_ray(ray)
	assert(not hit.is_empty() and absf(hit.position.y-3.6)<.02, "Side walkway must remain solid")
	empty.queue_free()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30
	add_child(camera)
	camera.position = Vector3(23,25,-30)
	camera.look_at(Vector3(0,2,0));camera.make_current()
	var canvas := CanvasLayer.new();add_child(canvas)
	var label := Label.new();label.position=Vector2(24,70)
	label.text="COASTAL CARGO / 24 x 8 m editable platform\n93 separate placements / lift-away covers / real hold opening\n1: whole vessel   2: open hold   Esc: close"
	label.add_theme_font_size_override("font_size",20);canvas.add_child(label)
	print("CARGO ASSEMBLY PASS: actual hull dimensions, separate covers, mounted propeller and rudder motion")
	var args := OS.get_cmdline_user_args();var index := args.find("--capture")
	if index>=0:
		for i in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(args[index+1]) == OK)
		_open_view()
		for i in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(args[index+1].get_basename()+"-hold.png") == OK)
		get_tree().quit()

func _open_view() -> void:
	for p in boat.part_roots:
		if p.get_meta("asset_id") == "hatch_cover_5x4": p.hide()
	camera.size=16;camera.position=Vector3(13,20,-14);camera.look_at(Vector3(0,2,0))

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): get_tree().quit()
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_2:_open_view()
		if event.keycode==KEY_1:
			for p in boat.part_roots:p.show()
			camera.size=30;camera.position=Vector3(23,25,-30);camera.look_at(Vector3(0,2,0))
