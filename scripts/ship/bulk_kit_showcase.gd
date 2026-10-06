extends Node3D
const DRAFT := "res://resources/models/examples/coastal_bulk_draft.json"
var boat: ImportedDraftVessel
var camera: Camera3D
var crane: BulkCrane
var label: Label

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	if OS.get_cmdline_user_args().has("--verify-draft"):
		var editor := ShipyardBrickEditor.new();editor.standalone_tool=true;add_child(editor)
		for i in 8: await get_tree().process_frame
		var parts := editor._imported_parts_editor as ImportedShipPartsEditor
		parts.load_draft(DRAFT)
		assert(parts.draft_path==DRAFT and parts.records.size()==87, "Coaming and divider must coexist")
		var temporary:=OS.get_cache_dir().path_join("bulk-kit-%d.json"%OS.get_process_id())
		parts.save_draft(temporary);parts.load_draft(temporary)
		assert(parts.records.size()==87)
		DirAccess.remove_absolute(temporary)
		print("BULK DRAFT PASS: 87 placements, independent divider slot and save/load")
		editor.queue_free()
		for i in 3:await get_tree().process_frame
		get_tree().quit();return
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("263943")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6;add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.shadow_enabled=true;add_child(sun)
	boat=ImportedDraftVessel.new();boat.configure(JSON.parse_string(FileAccess.get_file_as_string(DRAFT)))
	boat.freeze=true;boat.process_mode=Node.PROCESS_MODE_DISABLED;add_child(boat)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=30;add_child(camera)
	camera.position=Vector3(23,25,-30);camera.look_at(Vector3(0,2,0));camera.make_current()
	var canvas:=CanvasLayer.new();add_child(canvas);label=Label.new();label.position=Vector2(24,70)
	label.add_theme_font_size_override("font_size",20);canvas.add_child(label)
	label.text="COASTAL BULK / divided hold assembly\nForward hatch open / aft hatch covered / real bulk inventory"
	var holds:=boat.get_bulk_holds()
	assert(holds.size()==2 and holds[0].cargo_accessible and not holds[1].cargo_accessible)
	assert(is_equal_approx(holds[0].state.capacity_tonnes_t,40))
	assert(is_equal_approx(holds[1].accept_lot(BulkCargoLot.create("iron_ore",3)).tonnes_t,3),"Covered hatch must reject cargo")
	assert(holds[0].accept_lot(BulkCargoLot.create("iron_ore",12)).is_empty())
	assert(is_equal_approx(boat.cargo_mass,12000),"Bulk inventory must contribute to vessel mass")
	assert(is_equal_approx(holds[0].accept_lot(BulkCargoLot.create("coal",2)).tonnes_t,2),"Do not mix incompatible commodities")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(holds[0].state.to_dict()))
	holds[0].withdraw_lot(12);assert(is_zero_approx(boat.cargo_mass))
	holds[0].apply_state(saved);assert(is_equal_approx(boat.cargo_mass,12000))
	crane=BulkCrane.new();crane.show_operator=false;crane.model_scale=1;crane.bucket_scale=.7
	crane.simulate_bulk_material=false;crane.position=Vector3(-22,0,0);add_child(crane)
	var operator:=BulkCraneAutoOperator.new();operator.name="AutoOperator";operator.max_cycles=1;crane.add_child(operator)
	var mound:=OreMound.create("iron_ore",Vector3(8,3,8),42);mound.position=Vector3(-37,0,-18);add_child(mound)
	var quay:=MeshBuilder.box(Vector3(38,3.6,52),Color(.16,.18,.19),.9,0)
	quay.position=Vector3(-24,-1.8,-3);add_child(quay)
	for i in 8:await get_tree().process_frame
	assert(crane.can_reach_ship(boat))
	assert(not crane.start_auto_load(boat,"iron_ore",mound,holds[1]),"Explicit covered target must be rejected")
	# Existing crane -> falling BulkCargoLot -> hold, preserving total ship/bucket mass.
	crane.grab_from_hold(holds[0])
	assert(is_equal_approx(holds[0].state.filled_tonnes_t+crane.bucket_lot.tonnes_t,12))
	crane.force_release_at(holds[0].get_crane_aim_global())
	for i in 20:await get_tree().physics_frame
	assert(is_equal_approx(holds[0].state.filled_tonnes_t,12))
	assert(is_zero_approx(holds[1].state.filled_tonnes_t))
	assert(is_equal_approx(boat.cargo_mass,12000))
	print("BULK TRANSFER PASS: covered rejection, commodity rejection, mass, JSON state, actual crane lot/drop conservation")
	if OS.get_cmdline_user_args().has("--verify-auto"):
		assert(crane.start_auto_load(boat,"iron_ore",mound,holds[0]))
		operator.set_process(false)
		var boom_before:=crane.boom_angle_deg
		var captured_motion:=false
		for i in 1600:
			operator._process(.1)
			await get_tree().physics_frame
			if not captured_motion and operator.get_phase()==BulkCraneAutoOperator.Phase.DUMP_B:
				assert((holds[0] as ImportedBulkHold).contains_grab_mouth(crane.get_bucket_mouth_global()), "Actual grab must enter the hatch, not teleport cargo to a target")
				captured_motion=true
				var capture_args:=OS.get_cmdline_user_args();var capture_index:=capture_args.find("--capture")
				if capture_index>=0:
					camera.size=57;camera.position=Vector3(30,42,-50);camera.look_at(Vector3(-15,6,-4))
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(capture_args[capture_index+1].get_basename()+"-loading.png")
					camera.size=30;camera.position=Vector3(23,25,-30);camera.look_at(Vector3(0,2,0))
			if not operator.is_active():break
		assert(not operator.is_active(),"One real auto cycle must complete")
		for i in 30:await get_tree().physics_frame
		assert(holds[0].state.filled_tonnes_t>12 and is_zero_approx(holds[1].state.filled_tonnes_t))
		assert(not is_equal_approx(boom_before,crane.boom_angle_deg))
		print("BULK AUTO PASS: existing operator completed one load cycle into the imported open hold")
	label.text += "\nForward: %.1f / 40 t · Aft: covered"%holds[0].state.filled_tonnes_t
	var args:=OS.get_cmdline_user_args();var index:=args.find("--capture")
	if index>=0:
		crane.hide();mound.hide();quay.hide()
		for i in 12:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[index+1])
		camera.size=13;camera.position=Vector3(8,20,-8);camera.look_at(Vector3(0,2.5,0))
		for i in 12:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[index+1].get_basename()+"-hold.png")
		crane.show();mound.show();quay.show()
		camera.size=57;camera.position=Vector3(30,42,-50);camera.look_at(Vector3(-15,6,-4))
		for i in 12:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[index+1].get_basename()+"-crane.png")
		crane.queue_free();mound.queue_free();boat.queue_free()
		for i in 4:await get_tree().process_frame
		get_tree().quit()

func _unhandled_key_input(event:InputEvent)->void:
	if event.is_action_pressed("ui_cancel"):get_tree().quit()
