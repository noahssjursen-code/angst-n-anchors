extends Node3D
## Runs the normal crane operator against the new continuous imported hold.
const DRAFT := "res://resources/models/examples/coastal_32m_draft.json"
var boat: ImportedDraftVessel
var camera: Camera3D
var label: Label
var capture_path := ""

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture")
	if index >= 0: capture_path = args[index+1]
	var snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DRAFT))
	var covered := _vessel(snapshot)
	var covered_hold := covered.get_bulk_holds()[0]
	assert(covered.get_bulk_holds().size()==1 and not covered_hold.cargo_accessible)
	assert(covered_hold.accept_lot(BulkCargoLot.create("iron_ore",3)).tonnes_t==3)
	assert(covered_hold.withdraw_lot(3).is_empty())
	covered.queue_free()
	for i in 3: await get_tree().process_frame
	# A single remaining/rotated cover still closes the continuous hatch.
	var partial := snapshot.duplicate(true)
	partial.parts = partial.parts.filter(func(p: Dictionary): return p.asset_id!="hatch_cover_6x3" or p.position[2]==-1.5)
	for part: Dictionary in partial.parts:
		if part.asset_id=="hatch_cover_6x3": part.yaw_degrees=15
	covered = _vessel(partial)
	assert(not covered.get_bulk_holds()[0].cargo_accessible)
	covered.queue_free()
	for i in 3: await get_tree().process_frame
	var open := snapshot.duplicate(true)
	open.parts = open.parts.filter(func(p: Dictionary): return p.asset_id!="hatch_cover_6x3")
	boat = _vessel(open)
	var hold := boat.get_bulk_holds()[0] as ImportedBulkHold
	assert(hold.cargo_accessible and is_equal_approx(hold.state.capacity_tonnes_t,120))
	assert(is_equal_approx(hold.global_position.y-hold.hold_depth_m,1.4),"Fill must rest on the actual tank top")
	assert(hold.accept_lot(BulkCargoLot.create("iron_ore",146)).tonnes_t==26)
	assert(is_equal_approx(boat.cargo_mass,120000),"Capacity overflow cannot add ship mass")
	assert(hold.accept_lot(BulkCargoLot.create("coal",2)).tonnes_t==2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(hold.state.to_dict()))
	hold.withdraw_lot(200)
	assert(is_zero_approx(boat.cargo_mass))
	hold.apply_state(saved)
	assert(is_equal_approx(boat.cargo_mass,120000))
	hold.withdraw_lot(155)
	hold.accept_lot(BulkCargoLot.create("iron_ore",45))
	# Misplaced coamings cannot create inventory capacity on a solid deck.
	var invalid := {"hull":"hull_32x10","parts":[{"asset_id":"hold_coaming_6x12","position":[0,6.7,0],"yaw_degrees":0}]}
	var bad := _vessel(invalid)
	assert(bad.get_bulk_holds().is_empty())
	bad.queue_free()
	var env := WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("263943")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.6;add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.shadow_enabled=true;add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=37;add_child(camera)
	camera.position=Vector3(33,34,-40);camera.look_at(Vector3(0,3,0));camera.make_current()
	var canvas:=CanvasLayer.new();add_child(canvas);label=Label.new();label.position=Vector2(24,70)
	label.add_theme_font_size_override("font_size",20);canvas.add_child(label)
	label.text="32 M COASTER / one continuous 6 x 12 m cargo hold\nLift-off covers removed / 120 t provisional game capacity"
	var crane:=BulkCrane.new();crane.show_operator=false;crane.model_scale=1;crane.bucket_scale=.7
	crane.simulate_bulk_material=false;crane.position=Vector3(-22,0,0);add_child(crane)
	var operator:=BulkCraneAutoOperator.new();operator.name="AutoOperator";operator.max_cycles=1;crane.add_child(operator)
	var mound:=OreMound.create("iron_ore",Vector3(8,3,8),42);mound.position=Vector3(-37,0,-18);add_child(mound)
	var quay:=MeshBuilder.box(Vector3(38,4.5,52),Color(.16,.18,.19),.9,0)
	quay.position=Vector3(-25,-2.25,-3);add_child(quay)
	for i in 8:await get_tree().process_frame
	assert(crane.can_reach_ship(boat))
	crane.grab_from_hold(hold)
	assert(is_equal_approx(hold.state.filled_tonnes_t+crane.bucket_lot.tonnes_t,45))
	crane.force_release_at(hold.get_crane_aim_global())
	for i in 20:await get_tree().physics_frame
	assert(is_equal_approx(hold.state.filled_tonnes_t,45))
	assert(is_equal_approx(boat.cargo_mass,45000))
	assert(crane.start_auto_load(boat,"iron_ore",mound,hold))
	operator.set_process(false)
	var completed:=false
	operator.cycle_completed.connect(func(_op: int,_cycle: int): set_meta("cycle_complete",true))
	for i in 1600:
		operator._process(.1)
		await get_tree().physics_frame
		if not completed and operator.get_phase()==BulkCraneAutoOperator.Phase.DUMP_B:
			assert(hold.contains_grab_mouth(crane.get_bucket_mouth_global()),"Actual grab must enter the coaming")
			completed=true
			camera.size=63;camera.position=Vector3(32,42,-50);camera.look_at(Vector3(-14,6,-4))
			await _capture("-loading")
		if not operator.is_active():break
	for i in 30:await get_tree().physics_frame
	assert(completed and get_meta("cycle_complete",false) and not operator.is_active())
	assert(hold.state.filled_tonnes_t>45 and hold.state.filled_tonnes_t<=120)
	assert(is_equal_approx(boat.cargo_mass,hold.state.filled_tonnes_t*1000))
	label.text += "\n%.1f t loaded / actual crane cycle completed" % hold.state.filled_tonnes_t
	crane.hide();mound.hide();quay.hide()
	camera.size=37;camera.position=Vector3(33,34,-40);camera.look_at(Vector3(0,3,0))
	await _capture("")
	camera.size=15;camera.position=Vector3(9,18,-13);camera.look_at(Vector3(0,2.4,0))
	await _capture("-hold")
	print("COASTER CARGO PASS: single hold, full/partial cover rejection, authored floor, 120t cap, overflow, mass, state roundtrip, real crane cycle")
	if args.has("--verify") or not capture_path.is_empty():
		boat.queue_free();crane.queue_free();mound.queue_free()
		for i in 4:await get_tree().process_frame
		get_tree().quit()

func _vessel(snapshot: Dictionary) -> ImportedDraftVessel:
	var result:=ImportedDraftVessel.new();result.configure(snapshot)
	result.freeze=true;result.process_mode=Node.PROCESS_MODE_DISABLED;add_child(result)
	return result

func _capture(suffix: String) -> void:
	if capture_path.is_empty():return
	for i in 8:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(capture_path.get_basename()+suffix+".png")==OK)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):get_tree().quit()
