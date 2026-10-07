extends "res://scripts/port/port_showcase.gd"

## Real generated berth, NPC, imported crane, ISO beds and freight accounting.
## Test contracts are session-only; captain saves are disabled by the playtest flag.
var failures: Array[String] = []
var output := ""

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	super._ready()
	get_tree().create_timer(180).timeout.connect(func(): get_tree().quit(2))
	call_deferred("verify")

func verify() -> void:
	for i in 100: await get_tree().process_frame
	var visual := get_node("GeneratedPort/PortPlot/PortLayoutGraph")
	var harbour := visual._harbour as HarbourController
	var slot: QuayBerthSlot
	for candidate: QuayBerthSlot in harbour.berths():
		print("PROVISION BERTH ", candidate.family)
		if candidate.family == "general": slot = candidate; break
	if slot == null: finish("Missing cargo berth"); return
	_camera.global_position = slot.global_position + Vector3(30, 30, 30)
	_camera.look_at(slot.global_position)
	for i in 100: await get_tree().process_frame
	var record := CompanyService.build_starter_vessel_record("general_cargo")
	var boat := VesselSpawn.instantiate_from_record(record) as ImportedDraftVessel
	boat.freeze = true
	boat.process_mode = Node.PROCESS_MODE_DISABLED
	boat.set_meta("vessel_uid", "provision-isolated")
	add_child(boat)
	boat.global_transform = slot.global_transform * slot.ship_dock_local(4.0)
	boat.global_position.y = -1.5
	var job: ProvisionCraneEquipmentJob
	for id in harbour.equipment_ids_on_berth(slot.berth_id):
		var candidate := harbour.get_equipment(id) as ProvisionCraneEquipmentJob
		if candidate != null and candidate.can_reach_ship(boat): job = candidate; break
	if job == null: finish("No crane reaches cargo ship"); return
	harbour.plug_ship(slot.berth_id, boat)
	var crane := job._crane
	var auto := crane.get_auto_operator() as ProvisionCraneAutoOperator
	auto.set_process(false)
	var yard := auto._find_yard_pad()
	if yard == null: finish("Missing serving yard"); return
	var unloading := OS.get_cmdline_user_args().has("--unload")
	var origin := "remote-fixture" if unloading else harbour.port_id()
	var destination := harbour.port_id() if unloading else "remote-fixture"
	FreightService._active = [{"id":"provision-test", "origin_port_id":origin,
		"destination_port_id":destination, "commodity_id":"provisions", "handling_mode":"general",
		"status":"loaded" if unloading else "accepted", "quantity":2.0,
		"loaded_quantity":2.0 if unloading else 0.0, "delivered_quantity":0.0,
		"issued_quantity":2, "vessel_uid":"provision-isolated", "pay_marks":0,
		"consignment":{"consignment_id":"provision-test-consignment"}}]
	for i in 2:
		var unit := ContainerUnit.create("provision-" + str(i), "provisions", 5000, "20ft")
		unit.origin_port_id = origin
		unit.destination_port_id = destination
		unit.freight_contract_id = "provision-test"
		unit.consignment_id = "provision-test-consignment"
		var pad: CargoSlotPadComponent = boat.get_cargo_pads()[i] if unloading else yard
		if pad.add_container(unit) < 0: failures.append("Fixture container does not fit")
	var npc := crane.get_parent().get_node("CraneOperator") as CraneOperatorNpc
	var events: Array[String] = []
	var contexts: Array[Dictionary] = []
	job.job_started.connect(func(ctx): events.append("started"); contexts.append(ctx))
	job.job_completed.connect(func(ctx, _report): events.append("completed"); contexts.append(ctx))
	job.job_stopped.connect(func(ctx): events.append("stopped"); contexts.append(ctx))
	var focus := (crane.global_position + boat.global_position) * .5
	_camera.global_position = focus + Vector3(38, 29, 44)
	_camera.look_at(focus + Vector3.UP * 6)
	_camera.make_current()
	set_process(false)
	set_process_unhandled_input(false)
	get_node("HudLayer").hide()
	output = "C:/Users/noahs/Pictures/machinescreenshots/provision-dock-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	await capture("before")
	if unloading: npc._panel._btn_unload.pressed.emit()
	else: npc._panel._btn_load.pressed.emit()
	if not auto.is_active(): failures.append("NPC did not start job")
	var identity := job.authority_context()
	if job.start_job(boat, QuayEquipmentJob.MODE_LOAD): failures.append("Duplicate job start accepted")
	if job.authority_context() != identity: failures.append("Duplicate start replaced job identity")
	var previous := -1
	var interrupted := false
	var moving := OS.get_cmdline_user_args().has("--moving")
	var bob_origin := boat.global_transform
	var cancel_resume := OS.get_cmdline_user_args().has("--cancel-resume")
	var blocked_drop := OS.get_cmdline_user_args().has("--blocked-drop")
	var blocked_approach := OS.get_cmdline_user_args().has("--blocked-approach")
	var early_release_checked := false
	var temporary_blocker := -1
	var blocked_pad: CargoSlotPadComponent
	for i in 10000:
		if moving:
			boat.global_transform = bob_origin
			boat.global_position.y += sin(i * .021) * .14
			boat.rotate_object_local(Vector3.FORWARD, sin(i * .015) * .008)
		if not early_release_checked and auto._phase == ProvisionCraneAutoOperator.Phase.TO_DROP:
			early_release_checked = true
			var held := crane.get_attached_container()
			if crane.release_container_on_pad(auto._destination_pad()) != null: failures.append("Early auto release detached cargo")
			if crane.release_container() != null: failures.append("Early manual release detached cargo")
			if crane.get_attached_container() != held: failures.append("Airborne cargo lost")
		if blocked_approach and not interrupted and auto._phase == ProvisionCraneAutoOperator.Phase.TO_DROP:
			interrupted = true
			var held := crane.get_attached_container()
			var destination_pad := auto._destination_pad()
			var saved_pose := destination_pad.global_transform
			destination_pad.global_position += Vector3(200, 0, 200)
			for step_index in 1000:
				auto._process(.05)
				if not auto.is_active(): break
				if step_index % 4 == 0: await get_tree().process_frame
			if auto.is_active() or job.last_failure.is_empty(): failures.append("Unreachable approach did not fail visibly")
			if crane.get_attached_container() != held: failures.append("Unreachable approach detached cargo")
			await capture("unreachable-retains-cargo")
			destination_pad.global_transform = saved_pose
			if unloading: npc._panel._btn_unload.pressed.emit()
			else: npc._panel._btn_load.pressed.emit()
			if not auto.is_active(): failures.append("Cannot retry after unreachable approach")
		if cancel_resume and not interrupted and auto._phase == ProvisionCraneAutoOperator.Phase.TO_DROP:
			interrupted = true
			var held := crane.get_attached_container()
			npc._panel._btn_stop.pressed.emit()
			if crane.get_attached_container() != held: failures.append("Cancel lost suspended cargo")
			if unloading: npc._panel._btn_unload.pressed.emit()
			else: npc._panel._btn_load.pressed.emit()
			if not auto.is_active(): failures.append("Cannot resume a suspended lift")
		if blocked_drop and not interrupted and auto._phase == ProvisionCraneAutoOperator.Phase.RELEASE:
			interrupted = true
			blocked_pad = auto._destination_pad()
			temporary_blocker = blocked_pad.add_container(ContainerUnit.create("occupied-fixture", "provisions", 5000, "20ft"))
			if temporary_blocker < 0: failures.append("Could not occupy target bed")
			var held := crane.get_attached_container()
			auto._process(.05)
			if auto.is_active() or job.last_failure.is_empty(): failures.append("Occupied destination did not fail visibly")
			if crane.get_attached_container() != held: failures.append("Occupied destination detached cargo")
			blocked_pad.remove_container_at(temporary_blocker)
			if unloading: npc._panel._btn_unload.pressed.emit()
			else: npc._panel._btn_load.pressed.emit()
			if not auto.is_active(): failures.append("Cannot retry blocked destination")
		auto._process(.05)
		if i % 300 == 0 and auto.is_active():
			print("PROVISION TRACK ", auto._phase, " aim=", auto._current_aim(), " hook=", crane.get_hook_global(), " pivot=", crane.get_slew_pivot_global(), " trolley=", crane.trolley_z_m, " limits=", crane.horizontal_reach_limits_m())
		if previous != auto._phase:
			previous = auto._phase
			print("PROVISION PHASE ", auto.get_status_line(), " hook=", crane.get_hook_global(), " target=", auto._drop_aim(false), " held=", crane.get_attached_container(), " events=", events)
			if previous == ProvisionCraneAutoOperator.Phase.RELEASE: await capture("release-" + str(i))
		if not auto.is_active(): break
		if i % 4 == 0: await get_tree().process_frame
	for i in 4: await get_tree().process_frame
	var onboard := 0
	for pad in boat.get_cargo_pads(): onboard += pad.iter_container_nodes().size()
	if onboard != (0 if unloading else 2): failures.append("Wrong onboard count: " + str(onboard))
	if crane.get_attached_container() != null: failures.append("Container remains suspended")
	var interrupted_case := cancel_resume or blocked_drop or blocked_approach
	var expected := ["started", "stopped", "started", "completed"] if interrupted_case else ["started", "completed"]
	if events != expected: failures.append("Wrong lifecycle: " + str(events))
	if contexts.size() != expected.size() or str(contexts[0].get("vessel_id", "")).is_empty(): failures.append("Lost job identity")
	if interrupted_case and not interrupted: failures.append("Interruption case was not exercised")
	if not early_release_checked: failures.append("Early release was not exercised")
	for context in contexts:
		if context.get("vessel_id", "") != "provision-isolated": failures.append("Job vessel identity changed")
	if not unloading:
		for pad in boat.get_cargo_pads():
			for container in pad.iter_container_nodes():
				if not is_equal_approx(container.position.y, ContainerNode.floor_offset_y() if pad.show_pad_visual else 0.0): failures.append("Container is not resting on deck")
	if not unloading and float(FreightService._active[0].loaded_quantity) != 2.0: failures.append("Freight not recorded loaded")
	if unloading and not FreightService._active.is_empty(): failures.append("Freight not recorded delivered")
	print("PROVISION RESULT onboard=", onboard, " yard=", yard.iter_container_nodes().size(), " active=", auto.is_active(), " held=", crane.get_attached_container(), " freight=", FreightService._active)
	print("PROVISION FAILURE ", job.get("last_failure"))
	await capture("finished")
	_camera.global_position = boat.to_global(Vector3(14, 12, 17))
	_camera.look_at(boat.to_global(Vector3(0, 3, 0)))
	await capture("deck-close")
	finish("")

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"): return
	_camera.make_current()
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(label + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func finish(error: String) -> void:
	if not error.is_empty(): failures.append(error)
	print("PROVISION DOCK ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
