extends Node3D
const DRAFT := "res://resources/models/examples/coastal_trawler_draft.json"
var boat: ImportedDraftVessel
var camera: Camera3D
var fishing: FishingSystem

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
		assert(parts.records.size() == 60)
		var temporary := OS.get_cache_dir().path_join("trawler-kit-%d.json" % OS.get_process_id())
		parts.save_draft(temporary)
		parts.load_draft(temporary)
		assert(parts.records.size() == 60)
		DirAccess.remove_absolute(temporary)
		print("TRAWLER DRAFT PASS: real builder validation and save/load, 60 placements")
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
	label.text = "COASTAL TRAWLER / editable kit assembly\nBlender winch + separate rotating drum / insulated deck catch tanks\n1: whole boat   2: working deck   Esc: close"
	label.position = Vector2(24,70)
	label.add_theme_font_size_override("font_size",20)
	canvas.add_child(label)
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
		get_tree().quit()

func _deck_view() -> void:
	camera.size=9
	camera.position=Vector3(7,9,11)
	camera.look_at(Vector3(0,3.5,3.5))

func _process(delta: float) -> void:
	if is_instance_valid(fishing):
		fishing._drum_rotation_node.rotate_z(delta)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):get_tree().quit()
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_2:_deck_view()
		if event.keycode==KEY_1:
			camera.size=17
			camera.position=Vector3(15,15,19)
			camera.look_at(Vector3(0,2,0))
