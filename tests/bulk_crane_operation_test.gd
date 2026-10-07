extends Node3D

## Real imported grab, NPC request path, equipment lifecycle and falling cargo.
var failures: Array[String] = []
var crane: BulkCrane
var operator: BulkCraneAutoOperator
var boat: ImportedDraftVessel
var hold: ImportedBulkHold
var mound: OreMound
var job: BulkCraneEquipmentJob
var npc: CraneOperatorNpc
var harbour: HarbourController
var events: Array[String] = []
var contexts: Array[Dictionary] = []
var camera: Camera3D
var captures := ""

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(150).timeout.connect(func(): get_tree().quit(2))
	var compact := OS.get_cmdline_user_args().has("--compact")
	if OS.get_cmdline_user_args().has("--rotated"):
		position = Vector3(8200, 0, -12500)
		rotation.y = .65
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("344d5d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .5
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(25, 37, 42)
	add_child(camera)
	camera.look_at(Vector3(-20, 7, 0))
	camera.make_current()
	if OS.get_cmdline_user_args().has("--capture"):
		captures = "C:/Users/noahs/Pictures/machinescreenshots/bulk-operation-" + str(Time.get_unix_time_from_system()).replace(".", "-")
		DirAccess.make_dir_recursive_absolute(captures)
	var draft_path := "res://resources/models/examples/coastal_bulk_draft.json" if compact else "res://resources/models/examples/coastal_32m_draft.json"
	var draft: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(draft_path))
	draft.parts = draft.parts.filter(func(p: Dictionary): return p.asset_id != "hatch_cover_6x3")
	boat = ImportedDraftVessel.new()
	boat.configure(draft)
	boat.freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(boat)
	hold = boat.get_bulk_holds()[0] as ImportedBulkHold
	crane = BulkCrane.new()
	crane.show_operator = false
	crane.position = Vector3(-32, 2, 0)
	add_child(crane)
	var quay := MeshBuilder.box(Vector3(60, 4, 68), Color("434b50"), .9, 0)
	quay.position = Vector3(-37, 0, -3)
	add_child(quay)
	operator = BulkCraneAutoOperator.new()
	operator.name = "AutoOperator"
	operator.max_cycles = 1
	crane.add_child(operator)
	operator.set_process(false)
	harbour = HarbourController.new()
	harbour.setup("bulk-regression")
	add_child(harbour)
	var berth := QuayBerthSlot.new()
	berth.setup("bulk-regression/a", "a", "bulk", PackedStringArray(["iron_ore"]), 80, 20)
	harbour.add_child(berth)
	harbour.register_berth(berth)
	job = BulkCraneEquipmentJob.new()
	job.setup("bulk-regression/grab", "equip_grab_unloader", berth.berth_id)
	crane.add_child(job)
	job.bind_crane(crane)
	harbour.register_equipment(job, berth.berth_id)
	job.job_started.connect(func(_ctx): events.append("started"))
	job.job_completed.connect(func(_ctx, _report): events.append("completed"))
	job.job_stopped.connect(func(_ctx): events.append("stopped"))
	job.job_started.connect(func(ctx): contexts.append(ctx))
	job.job_completed.connect(func(ctx, _report): contexts.append(ctx))
	_check(harbour.plug_ship(berth.berth_id, boat), "ship moored through harbour")
	npc = CraneOperatorNpc.new()
	npc.position = Vector3(-35, 2, 3)
	npc.configure(harbour, berth.berth_id, job.equipment_id())
	add_child(npc)
	mound = OreMound.create("iron_ore", Vector3(10, 4, 10), 42)
	add_child(mound)
	for i in 8: await get_tree().process_frame
	# A scoop requires an open -> closed stroke at the material, never opening.
	mound.global_position = crane.get_bucket_mouth_global() - Vector3(0, 1.68, 0)
	crane.set_bucket_jaws_target(1)
	for i in 12: crane.step(.05)
	_check(crane.get_bucket_lot().is_empty(), "opening an empty grab must not pick up")
	var open_gap := _lip_gap()
	await _capture_grab("manual-open")
	crane.bucket_lot = BulkCargoLot.empty()
	crane.set_bucket_jaws_target(0)
	for i in 12: crane.step(.05)
	_check(not crane.get_bucket_lot().is_empty(), "closing at stockpile picks up")
	_check(_lip_gap() < open_gap * .2, "authored jaw lips actually close while picking up")
	await _capture_grab("manual-closed")
	var loaded := crane.get_bucket_lot().tonnes_t
	for i in 12: crane.step(.05)
	_check(is_equal_approx(crane.get_bucket_lot().tonnes_t, loaded), "closed grab keeps its load")
	crane.set_bucket_jaws_target(1)
	for i in 12: crane.step(.05)
	_check(crane.get_bucket_lot().is_empty(), "opening releases cargo")
	# Moving a closed empty grab into material is not a new scoop.
	mound.position += Vector3(100, 0, 0)
	crane.set_bucket_jaws_target(0)
	for i in 12: crane.step(.05)
	mound.position -= Vector3(100, 0, 0)
	for i in 12: crane.step(.05)
	_check(crane.get_bucket_lot().is_empty(), "closed empty grab cannot scoop without another stroke")
	for child in get_children():
		if child is BulkMaterialDrop: child.queue_free()
	crane.bucket_lot = BulkCargoLot.empty()
	mound.position = Vector3(-54, 2, -24)
	hold.accept_lot(BulkCargoLot.create("iron_ore", 30))
	for mode in ["load", "unload"]:
		events.clear()
		var before := hold.state.filled_tonnes_t
		npc._panel.visible = true
		if mode == "load": npc._panel._btn_load.pressed.emit()
		else: npc._panel._btn_unload.pressed.emit()
		_check(job.served_ship() == boat and job.job_mode() == mode, mode + " retains dock job context")
		_check(npc._panel._btn_load.disabled and npc._panel._btn_unload.disabled, "running job disables duplicate start buttons")
		_check(not job.start_job(boat, mode), "duplicate request rejected without clearing active identity")
		_check(job.served_ship() == boat and job.job_mode() == mode, "duplicate request preserves identity")
		var last_phase := -1
		for i in 1600:
			operator._process(.1)
			if operator.get_phase() != last_phase:
				last_phase = operator.get_phase()
				print("BULK PHASE ", mode, " ", operator.get_status_line(), " mouth=", crane.get_bucket_mouth_global(), " hold=", hold.global_position, " hoist=", crane.hoist_length_m)
				if last_phase == BulkCraneAutoOperator.Phase.RAISE_A:
					_check(not crane.get_bucket_lot().is_empty() and crane.bucket_open < .13, "loaded grab has closed jaws")
					await _capture_grab(mode + "-scoop")
				if last_phase == BulkCraneAutoOperator.Phase.DUMP_B:
					if mode == "load": _check(hold.contains_grab_mouth(crane.get_bucket_mouth_global()), "actual mouth enters hatch before release")
					_check(npc._panel._status.text.contains("open + dump"), "NPC panel follows phase changes")
					npc._panel.visible = false
					await _capture(mode + "-over-target")
					npc._panel.visible = true
			if not operator.is_active(): break
			await get_tree().physics_frame
		for i in 30: await get_tree().physics_frame
		print("BULK RESULT ", mode, " cargo ", before, " -> ", hold.state.filled_tonnes_t, " events ", events)
		_check(not operator.is_active() and not job.is_job_active(), mode + " releases equipment after cycle")
		_check(events == ["started", "completed"], mode + " emits one start/completion without false stop")
		_check(hold.state.filled_tonnes_t > before if mode == "load" else hold.state.filled_tonnes_t < before, mode + " transfers cargo")
		var expected := minf(before + crane.bucket_capacity_tonnes_t(), hold.state.capacity_tonnes_t) if mode == "load" else maxf(before - crane.bucket_capacity_tonnes_t(), 0)
		_check(is_equal_approx(expected, hold.state.filled_tonnes_t), "exact transferred tonnage with no overflow")
		_check(is_equal_approx(boat.cargo_mass, hold.state.filled_tonnes_t * 1000), "ship mass follows transferred inventory")
		_check(npc._panel._status.text.contains("idle"), "NPC panel exits running status")
		await _capture(mode + "-end")
	# Stop during a final loaded scoop, then continue unloading. Inventory stays
	# in the grab and the restarted job finishes even though the hold is empty.
	hold.withdraw_lot(INF)
	hold.accept_lot(BulkCargoLot.create("iron_ore", 5))
	events.clear()
	npc._panel._btn_unload.pressed.emit()
	for i in 600:
		operator._process(.1)
		if operator.get_phase() == BulkCraneAutoOperator.Phase.RAISE_A or not operator.is_active(): break
		await get_tree().physics_frame
	_check(is_equal_approx(crane.get_bucket_lot().tonnes_t, 5) and hold.state.is_empty(), "last scoop is in the grab")
	npc._panel._btn_stop.pressed.emit()
	_check(events == ["started", "stopped"] and is_equal_approx(crane.get_bucket_lot().tonnes_t, 5), "stop retains carried cargo")
	events.clear()
	contexts.clear()
	_check(harbour.plug_equipment(job.equipment_id(), boat, "unload", "", {"operation_id":"resume-regression", "owner_actor_id":"fixture"}), "resume final unload scoop through dock")
	# Simultaneous manual input must not fight the automatic operator.
	var command := BulkCraneCommand.new()
	command.bucket_target = 1
	command.hoist_rate = 1
	var previous_hoist := crane.hoist_length_m
	crane.step(.5, command)
	_check(is_equal_approx(previous_hoist, crane.hoist_length_m) and crane.bucket_open < .13, "manual control cannot interfere with active auto job")
	for i in 1600:
		operator._process(.1)
		if not operator.is_active(): break
		await get_tree().physics_frame
	_check(events == ["started", "completed"] and crane.get_bucket_lot().is_empty(), "resumed final scoop finishes once")
	_check(contexts.size() == 2 and contexts[0].get("operation_id") == "resume-regression" and contexts[0] == contexts[1], "authority context survives start through completion")
	# A lower target beyond the available wire must stop explicitly, not hang or
	# teleport a payload. Use the same NPC/job path and retain the carried lot.
	events.clear()
	crane.hoist_max_m = 8.0
	npc._panel._btn_load.pressed.emit()
	for i in 500:
		operator._process(.1)
		if not operator.is_active(): break
		await get_tree().physics_frame
	_check(not job.is_job_active() and not operator.is_active(), "unreachable lower target stops job")
	_check(events == ["started", "stopped"] and not job.last_failure.is_empty(), "unreachable target reports failure without false completion")
	_check(npc._panel._status.text.contains("cannot reach"), "NPC explains failed approach")
	await _capture("unreachable-target-message")
	# Stopping an inactive operator must never manufacture another job event.
	operator.stop()
	_check(events == ["started", "stopped"], "idle stop is silent")
	print("BULK OPERATION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	harbour.unregister_all()
	for child in get_children(): child.queue_free()
	for i in 5: await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture_grab(label: String) -> void:
	if captures.is_empty(): return
	var old_pose := camera.global_transform
	var mouth := crane.get_bucket_mouth_global()
	camera.global_position = mouth + Vector3(10, 6, 10)
	camera.look_at(mouth + Vector3.UP)
	# Show the mechanism unobscured; stockpile remains present for the operation.
	var pile_visible := mound.visible
	mound.hide()
	var panel_visible := npc._panel.visible
	npc._panel.hide()
	await _capture(label)
	mound.visible = pile_visible
	npc._panel.visible = panel_visible
	camera.global_transform = old_pose

func _lip_gap() -> float:
	var left := crane._shell_left.find_child("CuttingLip", true, false) as Node3D
	var right := crane._shell_right.find_child("CuttingLip", true, false) as Node3D
	return left.global_position.distance_to(right.global_position)

func _capture(label: String) -> void:
	if captures.is_empty(): return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(captures.path_join(label + ".png"))
	print("CAPTURE ", captures.path_join(label + ".png"))

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		print("FAILED: ", label)
