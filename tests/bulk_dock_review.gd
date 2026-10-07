extends "res://scripts/port/port_showcase.gd"

## Uses the generated port's actual crane/stockpile spacing and NPC, with an
## isolated starter vessel at the berth's normal docking position.
var failures: Array[String] = []
var output := ""
var review_focus := Vector3.ZERO

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	super._ready()
	get_tree().create_timer(180).timeout.connect(func():get_tree().quit(2))
	call_deferred("verify")

func verify() -> void:
	for i in 120: await get_tree().process_frame
	var visual := get_node("GeneratedPort/PortPlot/PortLayoutGraph")
	var harbour := visual._harbour as HarbourController
	var slot: QuayBerthSlot
	for candidate in harbour.berths():
		if (candidate as QuayBerthSlot).family == "bulk_ore": slot = candidate; break
	if slot == null: _finish("No bulk berth in fixture"); return
	_camera.global_position = slot.global_position + Vector3(25, 30, 30)
	_camera.look_at(slot.global_position)
	for i in 120: await get_tree().process_frame
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/bulk_small.json"))
	var boat := ImportedDraftVessel.new()
	boat.configure(record.brick_layout)
	boat.freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(boat)
	boat.global_transform = slot.global_transform * slot.ship_dock_local(4.0)
	boat.global_position.y = -1.5
	var job: BulkCraneEquipmentJob
	for id in harbour.equipment_ids_on_berth(slot.berth_id):
		var candidate := harbour.get_equipment(id) as BulkCraneEquipmentJob
		if candidate == null: continue
		var crane := candidate._crane
		print("LIVE DOCK CANDIDATE ", id, " crane=", crane.global_position, " hold=", boat.get_bulk_holds()[0].global_position, " can_serve=", candidate.can_serve(boat, "load"), " pile=", crane.find_nearest_ore_mound())
		if candidate.can_serve(boat, "load"): job = candidate; break
	if job == null: _finish("No crane reaches normal berth position"); return
	harbour.plug_ship(slot.berth_id, boat)
	var crane := job._crane
	var auto := crane.get_auto_operator()
	var full_job := OS.get_cmdline_user_args().has("--full-job")
	auto.max_cycles = 0 if full_job else 1
	auto.set_process(false)
	var npc := crane.get_parent().get_node("CraneOperator") as CraneOperatorNpc
	output = "C:/Users/noahs/Pictures/machinescreenshots/bulk-live-dock-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	get_node("HudLayer").hide()
	var focus := (boat.global_position + crane.global_position) * .5
	review_focus = focus
	_camera.global_position = focus + Vector3(45, 32, 50)
	_camera.look_at(focus + Vector3.UP * 6)
	_camera.make_current()
	set_process(false)
	set_process_unhandled_input(false)
	var events: Array[String] = []
	job.job_started.connect(func(_ctx): events.append("started"))
	job.job_completed.connect(func(_ctx, _report): events.append("completed"))
	job.job_stopped.connect(func(_ctx): events.append("stopped"))
	for mode in ["load", "unload"]:
		events.clear()
		var before := boat.cargo_mass
		if mode == "load": npc._panel._btn_load.pressed.emit()
		else: npc._panel._btn_unload.pressed.emit()
		var last_phase := -1
		for i in 6400:
			auto._process(.1)
			if last_phase != auto.get_phase():
				last_phase = auto.get_phase()
				print("LIVE DOCK ", mode, " ", auto.get_status_line(), " mouth=", crane.get_bucket_mouth_global(), " failure=", job.last_failure)
				if last_phase == BulkCraneAutoOperator.Phase.DUMP_B: await capture(mode + "-at-target-" + str(i))
			if not auto.is_active(): break
			await get_tree().physics_frame
		for i in 30: await get_tree().physics_frame
		if events != ["started", "completed"]: failures.append(mode + " lifecycle " + str(events) + " " + job.last_failure)
		if not (boat.cargo_mass > before if mode == "load" else boat.cargo_mass < before): failures.append(mode + " did not transfer inventory")
		if full_job:
			for hold in boat.get_bulk_holds():
				if hold.cargo_accessible and not (is_zero_approx(hold.state.available_tonnes_t()) if mode == "load" else hold.state.is_empty()): failures.append(mode + " did not finish the whole vessel")
		print("LIVE DOCK RESULT ", mode, " kg=", before, " -> ", boat.cargo_mass)
		await capture(mode + "-finished")
	harbour.unplug_ship(boat)
	boat.queue_free()
	for i in 5: await get_tree().process_frame
	_finish("")

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"): return
	_camera.global_position = review_focus + Vector3(45, 32, 50)
	_camera.look_at(review_focus + Vector3.UP * 6)
	_camera.make_current()
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
	print("CAPTURE ", output.path_join(label + ".png"))

func _finish(error: String) -> void:
	if not error.is_empty(): failures.append(error)
	print("BULK LIVE DOCK ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
