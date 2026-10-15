extends Node

## Native player targeting/input acceptance. Teleports only arrange each approach;
## Neither operator handlers nor inspector opening are called by this test.
const WORKSHOP := preload("res://scenes/showcases/custom_port_fishing_showcase.tscn")
var workshop: Node3D
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	_run.call_deferred()

func _run() -> void:
	workshop = WORKSHOP.instantiate()
	add_child(workshop)
	var deadline := Time.get_ticks_msec() + 60000
	while not workshop.ready_for_review and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(workshop.ready_for_review, "The actual fishing harbour becomes ready")
	if not workshop.ready_for_review: await _finish(); return
	workshop.walk()
	deadline = Time.get_ticks_msec() + 30000
	while (workshop.building or workshop._ground_pause) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(not workshop.building and not workshop._ground_pause and workshop.player.camera.current,
		"Walk waits for the current terrain collider and selects the ordinary player camera")
	if workshop.building or workshop._ground_pause: await _finish(); return
	var operator: NpcInteractable = workshop.presenter.placement_nodes.get("landing-operator")
	_check(is_instance_valid(operator), "The saved custom operator has its actual interaction component")
	if not is_instance_valid(operator): await _finish(); return
	var before: Dictionary = workshop.state.to_dict()
	await _approach(workshop.site + Vector3(10, .12, 26.4), operator.global_position + Vector3.UP * 1.2)
	_check(workshop.player.is_on_floor() and workshop.player.is_physics_processing(), "The player stands freely on the authored quay")
	_check(operator._can_interact(), "The normal player camera ray reaches the fish operator within four metres")
	await _capture("01-facing-operator")
	await _tap(KEY_F)
	_check(workshop.inspector.visible and workshop.inspector._tabs.current_tab == 1,
		"Physical F input opens the Cargo tab through normal NPC targeting")
	_check(workshop.inspector._selected(workshop.inspector._store) == "fish-receiver" and
		workshop.inspector._selected(workshop.inspector._vessel) == "nordlys",
		"The spoken-to operator selects its fish receiver and the arrived Nordlys")
	_check(not workshop.player.is_physics_processing() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"The conversation captures controls without moving the player")
	_check(workshop.state.to_dict() == before, "Opening the conversation does not alter cargo or authority records")
	await _capture("02-operator-cargo")
	await _tap(KEY_ESCAPE)
	_check(not workshop.inspector.visible and not workshop.building and workshop.player.is_physics_processing() and
		workshop.player.camera.current and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"Escape returns to the same ordinary walking mode and captured first-person camera")
	if workshop.inspector.visible: await _finish(); return
	await _check_door()
	await _finish()

func _check_door() -> void:
	const DOOR_ID := "front--6"
	var door: Node3D = workshop.presenter.placement_nodes.get(DOOR_ID)
	_check(is_instance_valid(door), "The custom workshop contains its placed door")
	if not is_instance_valid(door): return
	await _approach(workshop.site + Vector3(-6, .12, 21.7), door.global_position + Vector3.UP * 1.2)
	_check(_door_targeted(door), "The walking camera first-hits the closed decorative door")
	var prior: int = workshop.state.revision()
	await _tap(KEY_F)
	_check(not _door_open(DOOR_ID) and workshop.state.revision() == prior,
		"Physical F leaves the decorative entrance closed without publishing a state change")
	_check(not workshop.inspector.visible and workshop.player.is_physics_processing(),
		"The decorative door does not capture player controls or open a service panel")
	Input.action_press("move_forward")
	for frame in 90: await get_tree().physics_frame
	Input.action_release("move_forward")
	_check(workshop.player.global_position.z < door.global_position.z - .25,
		"The actual walking player cannot pass through the closed entrance")
	await _capture("03-decorative-door")

func _approach(position: Vector3, target: Vector3) -> void:
	workshop.player.global_position = position
	workshop.player.velocity = Vector3.ZERO
	workshop.player.reset_physics_interpolation()
	for frame in 30: await get_tree().physics_frame
	await _aim(target)

func _aim(target: Vector3) -> void:
	var camera: Camera3D = workshop.player.camera
	var control: PlayerCamera = workshop.player.get_node("PlayerCamera")
	_check(control.get_mode() == PlayerCamera.CameraMode.FIRST_PERSON, "The test uses the real first-person camera mode")
	var direction := (target - camera.global_position).normalized()
	var yaw := atan2(-direction.x, -direction.z)
	control.shift_look_yaw(wrapf(yaw - control.get_look_yaw(), -PI, PI))
	for frame in 2: await get_tree().process_frame
	direction = (target - camera.global_position).normalized()
	var wanted_pitch := asin(clampf(direction.y, -1, 1))
	var motion := InputEventMouseMotion.new()
	var sensitivity := control.mouse_sensitivity * GameSettings.mouse_sensitivity
	motion.relative = Vector2(0, -(wanted_pitch - camera.rotation.x) / sensitivity * (-1.0 if GameSettings.invert_mouse_y else 1.0))
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	for frame in 4: await get_tree().physics_frame

func _door_targeted(door: Node3D) -> bool:
	var camera: Camera3D = workshop.player.camera
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 4, 1)
	ray.exclude = [workshop.player.get_rid()]
	var hit := workshop.get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and door.is_ancestor_of(hit.collider)

func _door_open(id: String) -> bool:
	for placement in workshop.state.to_dict().placements:
		if str(placement.id) == id: return placement.get("attributes", {}).get("door_open", false)
	return false

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
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args(): return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	var path := archive.path_join("custom-port-walking-interaction-%d-%d-%s.png" % [Time.get_unix_time_from_system(), OS.get_process_id(), label])
	_check(get_viewport().get_texture().get_image().save_png(path) == OK, "Walking interaction capture archived: " + label)
	captures.append(path)
	print("WALKING_INTERACTION_CAPTURE ", path)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func _finish() -> void:
	if is_instance_valid(workshop):
		workshop.queue_free()
		for frame in 3: await get_tree().process_frame
	print("CUSTOM PORT WALKING INTERACTION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size(), " captures=", JSON.stringify(captures))
	get_tree().quit(0 if failures.is_empty() else 1)
