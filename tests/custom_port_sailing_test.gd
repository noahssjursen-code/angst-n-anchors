extends Node
## Actual workshop helm input and physics; the return pose is controlled setup.
const WORKSHOP := preload("res://scenes/showcases/custom_port_fishing_showcase.tscn")
const SESSION := preload("res://scripts/port/building/custom_port_vessel_session.gd")
const STATE := preload("res://scripts/port/state/custom_port_state.gd")
const VESSELS := preload("res://scripts/port/state/custom_port_vessel_projection.gd")
const PRESENTER := preload("res://scripts/port/building/custom_port_presenter.gd")
var workshop: Node3D
var boat: ImportedDraftVessel
var station: BridgeInteractable
var controller: BoatController
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var baseline_helmed := 0
var capture_pose := Transform3D.IDENTITY

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_run.call_deferred()

func _run() -> void:
	baseline_helmed = BoatController.helmed_count
	var passive := PRESENTER.new()
	_check(not passive.retain_departed_vessels, "Departed vessel retention remains opt-in")
	passive.free()
	workshop = WORKSHOP.instantiate()
	add_child(workshop)
	var deadline := Time.get_ticks_msec() + 60000
	while not workshop.ready_for_review and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(workshop.ready_for_review, "The real fishing workshop becomes ready")
	if not workshop.ready_for_review: await _finish(); return
	boat = workshop.presenter.vessel_nodes.get("nordlys")
	_check(is_instance_valid(boat), "The preloaded fishing vessel has a real imported body")
	if not is_instance_valid(boat): await _finish(); return
	controller = boat.get_node("BoatController")
	var stations := boat.get_bridge_stations()
	_check(not stations.is_empty(), "The actual vessel contains a helm")
	if stations.is_empty(): await _finish(); return
	for candidate in stations:
		if candidate._boat_controller == controller:
			station = candidate
			break
	_check(station != null, "The selected interaction controls the actual engine helm")
	if station == null: await _finish(); return
	var original := _vessel()
	var original_lots: Array = original.lots.duplicate(true)
	var original_holds := boat.get_catch_hold_states().duplicate(true)
	var original_instance := boat.get_instance_id()
	var original_berth := str(original.berth_id)
	var berth := _berth(original_berth)
	var target: Transform3D = workshop.vessel_session.berth_pose(berth, original)
	capture_pose = Transform3D(Basis.IDENTITY, target.origin + target.basis * Vector3(27, 19, 28))
	capture_pose = capture_pose.looking_at(target.origin + Vector3.UP * 4)
	_check(is_equal_approx(CustomPortState._mass(original_lots), 458.5), "The scenario has its explicit 458.5 kg catch")
	_check(boat.freeze and boat.gangway.deployed, "The starting vessel is secured with its gangway deployed")
	await _capture("01-before")
	workshop.walk()
	deadline = Time.get_ticks_msec() + 15000
	while workshop.building and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	_check(not workshop.building and not workshop.vessel_session.input_blocked, "Walk enables the real workshop controls")
	await get_tree().physics_frame
	await get_tree().physics_frame
	workshop.player.set_physics_process(false)
	workshop.player.set_process(false)
	_check(_aim_at_helm(), "The player's ray can reach the real helm without an intervening wall")
	if station._boarding_player() != workshop.player: await _finish(); return
	await _tap(KEY_F)
	workshop.player.set_process(true)
	print("SAILING_BOARD_STATE station=", station.get_path(), " occupied=", station.is_occupied(), " player_occupied=", workshop.player.is_vehicle_occupied(), " blocked=", workshop.vessel_session.input_blocked, " process_input=", station.is_processing_unhandled_input(), " eligible=", station._boarding_player() == workshop.player, " active=", controller._active)
	_check(station.is_occupied() and workshop.player.is_vehicle_occupied() and controller._active, "Real F enters the helm and activates BoatController")
	_check(get_viewport().get_camera_3d() == boat.get_node("BoatCamera") and not workshop.player.is_physics_processing(), "Helm owns the camera while player walking physics is paused")
	if not station.is_occupied(): await _finish(); return
	var revision: int = workshop.state.revision()
	await _tap(KEY_B)
	_check(workshop.vessel_session.last_result.get("ok", false) and workshop.state.revision() == revision + 1 and _vessel().berth_id == "", "Real B emits exactly one accepted departure")
	_check(boat.get_instance_id() == original_instance and workshop.presenter.vessel_nodes.get("nordlys") == boat, "Departure retains the exact occupied vessel instance")
	var mooring := boat.get_node("ShipGameplay/MooringComponent") as MooringComponent
	_check(not mooring.is_moored and not mooring.bow_line_tied and not mooring.stern_line_tied, "Departure releases both physical lines")
	_check(not boat.freeze and boat.is_physics_processing() and not boat.gangway.deployed and boat.gangway._walk.collision_layer == 0, "Departure enables sailing physics and stows gangway collision")
	if _vessel().berth_id != "": await _finish(); return
	var afloat_pose := boat.global_transform
	workshop.presenter.load_record(workshop.state.to_dict(), workshop.state.derived_berths())
	_check(workshop.presenter.vessel_nodes.get("nordlys") == boat and boat.global_transform.is_equal_approx(afloat_pose), "Re-presenting an afloat snapshot preserves instance and session pose")
	_check(_vessel().lots == original_lots and boat.get_catch_hold_states() == original_holds, "Departure and snapshot refresh preserve complete durable and physical cargo")
	var prop := boat.get_node("PropulsionComponent") as PropulsionComponent
	_check(not prop.engine_running and boat.get_fuel_fraction() > 0, "The real engine starts off with usable fuel")
	await _tap(KEY_I)
	await _tap(KEY_W)
	var motion_start := boat.global_position
	var forward := -boat.global_basis.z
	var fuel_start := boat.fuel_l
	for frame in 240: await get_tree().physics_frame
	var displacement := boat.global_position - motion_start
	var forward_distance := Vector2(displacement.x, displacement.z).dot(Vector2(forward.x, forward.z).normalized())
	print("SAILING_PROPULSION ", JSON.stringify({"forward_m": forward_distance, "displacement_m": displacement.length(), "throttle": prop.throttle, "speed_m_s": boat.linear_velocity.length(), "fuel_used_l": fuel_start - boat.fuel_l}))
	_check(prop.engine_running and prop.throttle < -.05 and controller.get_throttle_stage_idx() > 1, "Real I/W input starts the engine and orders ahead thrust")
	_check(forward_distance > .25 and boat.fuel_l < fuel_start, "Propulsion moves the body forward and consumes fuel without test-applied force")
	deadline = Time.get_ticks_msec() + 16000
	while forward_distance < 10 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		displacement = boat.global_position - motion_start
		forward_distance = Vector2(displacement.x, displacement.z).dot(Vector2(forward.x, forward.z).normalized())
	print("SAILING_OFFSHORE ", JSON.stringify({"forward_m": forward_distance, "displacement_m": displacement.length(), "speed_m_s": boat.linear_velocity.length()}))
	_check(forward_distance >= 10, "Unassisted propulsion takes the vessel at least 10 metres beyond its departure pose")
	await _capture("02-underway")
	await _tap(KEY_X)
	_check(controller.get_throttle_stage_idx() == 1, "Real X stops the offshore engine order")
	var offshore_document: Dictionary = workshop.state.to_dict()
	await _tap(KEY_B)
	_check(not workshop.vessel_session.last_result.get("ok", false) and workshop.state.to_dict() == offshore_document and _vessel().berth_id == "", "Real offshore B rejects mooring without changing state or cargo")
	_check(not mooring.is_moored and not boat.freeze and not boat.gangway.deployed, "Rejected offshore mooring leaves the vessel afloat with lines and gangway stowed")
	await _tap(KEY_1)
	_check(controller.get_throttle_stage_idx() == 1 and not workshop.building and station.is_occupied(), "Helm key 1 stops the engine order without entering build mode")
	for action in ["open_map", "open_inspector"]:
		workshop.call(action)
		var modal_revision: int = workshop.state.revision()
		var modal_stage := controller.get_throttle_stage_idx()
		await _tap(KEY_W)
		await _tap(KEY_B)
		await _tap(KEY_5)
		_check(workshop.vessel_session.input_blocked and controller.get_throttle_stage_idx() == modal_stage and workshop.state.revision() == modal_revision, action + ": modal blocks polled and event-driven helm input")
		await _tap(KEY_ESCAPE)
		_check(station.is_occupied() and not workshop.vessel_session.input_blocked and not workshop.player.is_physics_processing() and get_viewport().get_camera_3d() == boat.get_node("BoatCamera"), action + ": closing restores helm input without enabling player physics")
	await _check_rejections(target, berth, original)
	# Explicitly controlled approach setup after the independent propulsion proof.
	boat.snap_to_transform(target)
	boat.reset_physics_interpolation()
	await get_tree().physics_frame
	revision = workshop.state.revision()
	await _tap(KEY_B)
	_check(workshop.vessel_session.last_result.get("ok", false) and workshop.state.revision() == revision + 1 and _vessel().berth_id == original_berth, "Real B accepts the controlled return exactly once")
	_check(boat.freeze and mooring.bow_line_tied and mooring.stern_line_tied and boat.gangway.deployed, "Return secures the vessel and restores the usable gangway")
	_check(station.is_occupied() and workshop.presenter.vessel_nodes.get("nordlys") == boat, "Returning preserves the occupied helm and vessel instance")
	_check(_vessel().lots == original_lots and boat.get_catch_hold_states() == original_holds, "Sailing out and returning preserves all catch identity and metadata")
	await _capture("03-return")
	await _tap(KEY_TAB)
	_check(workshop.cursor_mode and workshop.vessel_session.input_blocked and station.is_occupied(), "Tab releases the cursor and pauses helm input")
	await _tap(KEY_ESCAPE)
	_check(not station.is_occupied() and not workshop.player.is_vehicle_occupied() and not controller._active, "Escape leaves the actual helm")
	_check(not workshop.building and not workshop.player.is_physics_processing() and not workshop.player.is_processing_unhandled_input() and get_viewport().get_camera_3d() == workshop.player.camera, "Leaving a paused helm restores the player camera while keeping walking input paused")
	if station.is_occupied(): await _finish(); return
	await _tap(KEY_TAB)
	_check(not workshop.cursor_mode and workshop.player.is_physics_processing() and workshop.player.is_processing_unhandled_input(), "Recapturing the cursor resumes on-foot controls")
	await _tap(KEY_1)
	_check(workshop.building and workshop.camera.current and workshop.camera.flying and not workshop.player.is_physics_processing() and workshop.vessel_session.input_blocked, "On-foot key 1 returns cleanly to build/freecam")
	await _transfer_after_return(original_lots)
	await _check_identical_restore()
	await _check_default_presenter()
	await _finish()

func _aim_at_helm() -> bool:
	# Same bounded ray-checked setup as shipyard_playtest._aim_at_interaction.
	var target := station._interact_area.global_position
	var view := workshop.player.get_node("Camera3D") as Camera3D
	for index in 16:
		var angle := float(index) * TAU / 16.0
		var offset := station.global_basis * Vector3(sin(angle), .25, cos(angle)) * .9
		workshop.player.global_position = target + offset - Vector3(0, 1.6, 0)
		workshop.player.velocity = Vector3.ZERO
		view.global_position = target + offset
		view.look_at(target)
		if station._boarding_player() == workshop.player:
			print("SAILING_HELM_APPROACH index=", index, " player=", workshop.player.global_position)
			return true
	return false

func _check_rejections(target: Transform3D, berth: Dictionary, vessel: Dictionary) -> void:
	var fast := SESSION.arrival_check(target, Vector3(2, 0, 0), target, vessel, berth)
	var skewed := target
	skewed.basis = Basis(Vector3.UP, PI * .5) * target.basis
	var angled := SESSION.arrival_check(skewed, Vector3.ZERO, target, vessel, berth)
	var distant := target
	distant.origin += target.basis.x * 4
	var outside := SESSION.arrival_check(distant, Vector3.ZERO, target, vessel, berth)
	_check(not fast.ok and fast.code == "too_fast", "Arrival rejects excess speed")
	_check(not angled.ok and angled.code == "not_aligned", "Arrival rejects a crosswise hull")
	_check(not outside.ok and outside.code == "not_alongside", "Arrival rejects an approach beyond the berth pocket")
	var small := berth.duplicate(true)
	small.max_length_m = float(vessel.length_m) - 1
	var fit := CustomPortBerths.fit(small, vessel)
	_check(not fit.ok and "insufficient_length" in fit.reasons, "Berth fitting rejects insufficient length")
	var document: Dictionary = workshop.state.to_dict()
	var blocker: Dictionary = VESSELS.from_prebuilt("fishing_hook_line", "occupied-test", "company-blocker")
	blocker.berth_id = berth.id
	document.vessels.append(blocker)
	var occupied := STATE.from_dict(document, document.world, workshop.catalog)
	_check(occupied.validation_errors.is_empty(), "Occupied-arrival copy is a valid authority document")
	if not occupied.validation_errors.is_empty(): return
	var original_state: CustomPortState = workshop.vessel_session.state
	var before := occupied.to_dict()
	var before_pose := boat.global_transform
	workshop.vessel_session.state = occupied
	var result: Dictionary = workshop.vessel_session.request_dock("nordlys", str(berth.id))
	workshop.vessel_session.state = original_state
	_check(not result.ok and result.code == "vessel_does_not_fit" and "occupied" in result.get("details", {}).get("reasons", []), "Adapter rejects a valid but occupied berth before physical mooring")
	_check(occupied.to_dict() == before and boat.global_transform.is_equal_approx(before_pose) and not boat.get_node("ShipGameplay/MooringComponent").is_moored, "Rejected arrival preserves state, cargo, pose and released lines")

func _transfer_after_return(original_lots: Array) -> void:
	workshop.open_inspector()
	var panel: CustomPortInspector = workshop.inspector
	_select(panel._vessel, "nordlys")
	panel._refresh_vessel()
	_select(panel._store, "fish-receiver")
	panel._refresh_store()
	_select(panel._unload_lot, "large-halibut")
	panel._refresh_unload_action()
	var revision: int = workshop.state.revision()
	panel._quantity.value = 999
	panel._unload.pressed.emit()
	var landed: Dictionary = workshop.state.to_dict()
	var expected: Dictionary = {}
	for lot in original_lots:
		if lot.id == "large-halibut": expected = lot
	var actual: Dictionary = {}
	for lot in landed.stores[0].lots:
		if lot.id == "large-halibut": actual = lot
	_check(workshop.state.revision() == revision + 1 and actual == expected, "After return, native inspector unloads the exact whole fish")
	var deadline := Time.get_ticks_msec() + 20000
	while workshop.transfers.is_busy() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	_check(not workshop.transfers.is_busy(), "Post-return catch transfer presentation completes")
	_check(is_equal_approx(CustomPortState._mass(_vessel().lots), 420) and is_equal_approx(_runtime_mass(), 420), "Post-return authoritative and physical vessel catch agree")
	workshop.inspector.close_requested.emit()

func _check_identical_restore() -> void:
	workshop.build()
	var saved: Dictionary = workshop.state.to_dict()
	var saved_state: CustomPortState = workshop.state
	var old_boat := boat
	var old_gangway := boat.gangway
	var old_hold: Node = boat.get_catch_holds()[0]
	var saved_holds := boat.get_catch_hold_states().duplicate(true)
	var berth_id := str(_vessel().berth_id)
	var old_berth: Node = workshop.presenter.berth_nodes[berth_id]
	var presented: Array = []
	var on_presented := func(id: String, body: BoatBody) -> void: presented.append({"id": id, "instance": body.get_instance_id()})
	workshop.presenter.vessel_presented.connect(on_presented)
	workshop.save_path = "user://custom_ports/sailing-restore-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	workshop.save_port()
	_check(FileAccess.file_exists(workshop.save_path) and workshop.state.to_dict() == saved, "Save writes the complete post-transfer document without changing state")
	workshop.load_port()
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(workshop.state != saved_state and workshop.state.to_dict() == saved, "Load rehydrates an identical saved revision with every durable field preserved")
	boat = workshop.presenter.vessel_nodes.get("nordlys")
	_check(is_instance_valid(boat) and not is_instance_valid(old_boat) and not is_instance_valid(old_hold) and not is_instance_valid(old_gangway) and not is_instance_valid(old_berth), "Identical restore replaces and frees the previous boat, hold, gangway and berth")
	if is_instance_valid(boat):
		var deadline := Time.get_ticks_msec() + 5000
		while not boat.gangway.deployed and Time.get_ticks_msec() < deadline: await get_tree().physics_frame
		_check(presented.size() == 1 and presented[0].id == "nordlys" and workshop.presenter.vessel_nodes.size() == 1, "Identical restore presents exactly one replacement vessel")
		_check(boat.get_catch_hold_states() == saved_holds and is_equal_approx(_runtime_mass(), 420), "Restored physical catch holds preserve the exact remaining 420 kg")
		_check(boat.freeze and boat.gangway.deployed and boat.gangway._projected_berth == workshop.presenter.berth_nodes[berth_id], "Restored vessel is secured with its gangway attached to the replacement berth")
		var replacement_id := boat.get_instance_id()
		workshop._on_state_changed(workshop.state.to_dict(), {})
		await get_tree().process_frame
		_check(presented.size() == 1 and workshop.presenter.vessel_nodes.nordlys.get_instance_id() == replacement_id, "Repeated presentation after restore keeps the single replacement body")
		await _capture("04-restored")
	workshop.presenter.vessel_presented.disconnect(on_presented)
	print("SAILING_RESTORE ", JSON.stringify({"path": ProjectSettings.globalize_path(workshop.save_path), "presented": presented.size(), "revision": workshop.state.revision(), "mass_kg": CustomPortState._mass(_vessel().lots)}))

func _check_default_presenter() -> void:
	# Minimal read model with the real vessel and derived berth; no extra world.
	var passive := PRESENTER.new()
	add_child(passive)
	var vessel := _vessel().duplicate(true)
	var snapshot := {"id": "passive-lifecycle", "origin_m": [100000, 0, 100000], "placements": [], "stores": [], "vessels": [vessel]}
	var berths: Array = [_berth(str(vessel.berth_id))]
	passive.load_record(snapshot, berths)
	var docked: BoatBody = passive.vessel_nodes.get("nordlys")
	_check(not passive.retain_departed_vessels and is_instance_valid(docked), "Default presenter creates the actual docked vessel without sailing opt-in")
	var departed := snapshot.duplicate(true)
	departed.vessels[0].berth_id = ""
	passive.load_record(departed, berths)
	await get_tree().process_frame
	_check(passive.vessel_nodes.is_empty() and not is_instance_valid(docked), "Default presenter removes and frees an actual vessel when its record departs")
	passive.clear_record()
	passive.queue_free()
	await get_tree().process_frame

func _runtime_mass() -> float:
	var total := 0.0
	for hold in boat.get_catch_hold_states():
		for lot in hold.lots: total += float(lot.mass_kg)
	return total

func _vessel() -> Dictionary:
	for vessel in workshop.state.to_dict().vessels:
		if vessel.id == "nordlys": return vessel
	return {}

func _berth(id: String) -> Dictionary:
	for berth in workshop.state.derived_berths():
		if berth.id == id: return berth
	return {}

func _select(selector: OptionButton, id: String) -> void:
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == id: selector.select(index); return

func _tap(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	for frame in 3: await get_tree().physics_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	for frame in 2: await get_tree().physics_frame

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	if "--capture-restored-only" in OS.get_cmdline_user_args() and label != "04-restored": return
	var previous := get_viewport().get_camera_3d()
	var review_camera := Camera3D.new()
	workshop.add_child(review_camera)
	review_camera.global_transform = capture_pose
	review_camera.far = 16000
	review_camera.current = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	var path := archive.path_join("custom-port-sailing-%d-%d-%s.png" % [Time.get_unix_time_from_system(), OS.get_process_id(), label])
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "Sailing review capture archived: " + label)
	captures.append(path)
	print("SAILING_CAPTURE ", path)
	if is_instance_valid(previous): previous.current = true
	review_camera.queue_free()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _finish() -> void:
	for action in ["move_forward", "move_back", "boat_lines", "boat_engine_toggle"]: Input.action_release(action)
	if is_instance_valid(workshop):
		workshop.queue_free()
		await get_tree().process_frame
	_check(BoatController.helmed_count == baseline_helmed, "Teardown restores the global helm count")
	print("CUSTOM PORT SAILING ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size(), " captures=", JSON.stringify(captures))
	get_tree().quit(0 if failures.is_empty() else 1)
