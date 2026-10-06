extends Node3D
const DRAFT := "res://resources/models/examples/coastal_32m_draft.json"
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
		assert(parts.draft_path == DRAFT and parts.records.size() == 113)
		assert(parts.hull_id == "hull_32x10" and is_equal_approx(parts.floor_y(),4.5))
		assert(editor._grid.half_loa == 16 and editor._grid.half_beam == 5)
		for model in parts.parts_root.get_children():
			if parts.records[str(model.get_meta("record_key"))].asset_id == "hatch_cover_6x3":
				assert(model.visible and parts._on_active_floor(model), "Covers must be visible and selectable on deck")
		assert(not parts._on_deck(Vector3(0,4.5,0)), "No placement on the empty hold")
		assert(parts._on_deck(Vector3(4,4.5,0)))
		editor.set("_brick_id","hold_coaming_5x8")
		assert(parts._furniture_candidate(Vector3.ZERO).asset_id=="hold_coaming_6x12")
		editor.set("_brick_id","hatch_cover_5x4")
		for station in [-4.5,-1.5,1.5,4.5]:
			var candidate := parts._furniture_candidate(Vector3(1,4.5,station+.2))
			assert(candidate.asset_id=="hatch_cover_6x3" and is_equal_approx(candidate.position[0],0) and is_equal_approx(candidate.position[1],5.24) and is_equal_approx(candidate.position[2],station))
		parts.set_floor(1,2)
		assert(is_equal_approx(parts.floor_y(),6.9))
		var temporary := OS.get_cache_dir().path_join("coaster-kit-%d.json" % OS.get_process_id())
		parts.save_draft(temporary)
		parts.load_draft("res://resources/models/examples/coastal_trawler_draft.json")
		assert(parts.hull_id == "trawler_hull_14m" and is_equal_approx(parts.floor_y(),2.92))
		parts.load_draft(temporary)
		assert(parts.hull_id == "hull_32x10" and parts.records.size() == 113)
		assert(is_equal_approx(parts.floor_y(),6.9))
		var before := parts._draft_state()
		var invalid := parts._draft_data().duplicate(true)
		invalid.hull = "not_an_installed_hull"
		var file := FileAccess.open(temporary,FileAccess.WRITE)
		file.store_string(JSON.stringify(invalid));file.close()
		parts.load_draft(temporary)
		assert(before == parts._draft_state(), "Invalid hull must preserve current draft")
		DirAccess.remove_absolute(temporary)
		parts.set_floor(0,0)
		editor.call("_show_toast", "Coaster draft verified: 32 × 10 m · 113 editable parts")
		var capture_args := OS.get_cmdline_user_args()
		var capture_index := capture_args.find("--capture")
		if capture_index >= 0:
			for i in 12: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture_args[capture_index+1])
		print("COASTER DRAFT PASS: cross-hull, 113 records, floor datum, opening, save/load and invalid-load preservation")
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
	assert(boat.length_m == 32 and boat.beam_m == 10 and boat.depth_m == 4.5)
	assert(boat.part_roots.size() == 113)
	var covers: Array[Node3D] = []
	for part in boat.part_roots:
		if part.get_meta("asset_id")=="hatch_cover_6x3":covers.append(part)
	assert(covers.size()==4)
	var original_tint := _panel_color(covers[1])
	assert(original_tint.is_equal_approx(Color(.4,.47,.47)),"Authored equipment paint must survive runtime assembly")
	ModelPaint.apply(covers[0],{"wall":Color(.15,.35,.55)})
	assert(_panel_color(covers[0]).is_equal_approx(Color(.15,.35,.55)))
	assert(_panel_color(covers[1]).is_equal_approx(original_tint),"Repaint must not change another cover")
	ModelPaint.apply(covers[0],{"wall":original_tint})
	var drive := boat.get_node("HullVisual/DriveGear") as ShipDriveVisual
	assert(is_equal_approx(drive.propeller.position.z,14.9))
	assert(drive.apply_snapshot({"throttle":.5,"steering":.7,"powered":true},1))
	drive.local_boat = null
	var angle := drive.propeller.rotation.z
	drive._process(.12)
	assert(not is_equal_approx(angle,drive.propeller.rotation.z))
	assert(is_equal_approx(drive.rudder.rotation.y,deg_to_rad(19.6)))
	# The uncovered hull must not have a hidden rectangular walk deck across its hold.
	var empty := ImportedDraftVessel.new()
	empty.configure({"hull":"hull_32x10","parts":[]})
	empty.freeze = true;empty.position.x = 40
	add_child(empty)
	for i in 3: await get_tree().physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(40,7,0),Vector3(40,0,0),BoatBody.LAYER_BOAT_WALK)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	assert(not hit.is_empty() and absf(hit.position.y-1.4)<.02, "Open hold ray must reach tank top")
	ray.from = Vector3(44,7,0);ray.to=Vector3(44,0,0)
	hit = get_world_3d().direct_space_state.intersect_ray(ray)
	assert(not hit.is_empty() and absf(hit.position.y-4.5)<.02, "Side walkway must remain solid")
	empty.queue_free()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 33
	add_child(camera)
	camera.position = Vector3(34,29,-39)
	camera.look_at(Vector3(0,2,0));camera.make_current()
	var canvas := CanvasLayer.new();add_child(canvas)
	var label := Label.new();label.position=Vector2(24,70)
	label.text="COASTAL PLATFORM / 32 x 10 m editable platform\n113 separate placements / lift-away covers / real hold opening\n1: whole vessel   2: open hold   Esc: close"
	label.add_theme_font_size_override("font_size",20);canvas.add_child(label)
	print("COASTER ASSEMBLY PASS: actual hull dimensions, separate covers, mounted propeller and rudder motion")
	var args := OS.get_cmdline_user_args();var index := args.find("--capture")
	if index>=0:
		for i in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(args[index+1]) == OK)
		_open_view()
		for i in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		assert(get_viewport().get_texture().get_image().save_png(args[index+1].get_basename()+"-hold.png") == OK)
		camera.size=12;camera.position=Vector3(8,10,-21);camera.look_at(Vector3(0,4,-13))
		for i in 12:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[index+1].get_basename()+"-bow.png")
		camera.size=17;camera.position=Vector3(13,3,25);camera.look_at(Vector3(0,2,12))
		for i in 12:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[index+1].get_basename()+"-stern.png")
		boat.queue_free()
		for i in 4:await get_tree().process_frame
		get_tree().quit()

func _open_view() -> void:
	for p in boat.part_roots:
		if p.get_meta("asset_id") == "hatch_cover_6x3": p.hide()
	camera.size=23;camera.position=Vector3(17,24,-20);camera.look_at(Vector3(0,2,0))

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): get_tree().quit()
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_2:_open_view()
		if event.keycode==KEY_1:
			for p in boat.part_roots:p.show()
			camera.size=33;camera.position=Vector3(34,29,-39);camera.look_at(Vector3(0,2,0))

func _panel_color(part: Node3D) -> Color:
	for item: MeshInstance3D in part.find_children("*","MeshInstance3D",true,false):
		for i in item.mesh.get_surface_count():
			var material := item.mesh.surface_get_material(i) as StandardMaterial3D
			if material.resource_name.begins_with("Warm white painted steel"):
				return (item.get_active_material(i) as StandardMaterial3D).albedo_color
	assert(false,"No paint region on imported cover")
	return Color.BLACK
