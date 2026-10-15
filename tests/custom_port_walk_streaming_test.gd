extends "res://tests/custom_port_showcase_input_test.gd"
## Real workshop/freecam regression. Baseline mode documents the former stall.
const FAR_OFFSET := Vector3(-14500, 100, 0)
const READY_RADIUS := 35.0
var workshop: Node3D

func _run() -> void:
	workshop = WORKSHOP.instantiate()
	add_child(workshop)
	var deadline := Time.get_ticks_msec() + 60000
	while not workshop.ready_for_review and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(workshop.ready_for_review, "The actual generated-world workshop becomes ready")
	if not workshop.ready_for_review:
		await _finish_scene()
		return
	# Let the empty-workshop deferred picker open, then close it via Build.
	await _settle()
	workshop.build()
	_check(not workshop.map.visible and not workshop.player.is_physics_processing(), "Build closes the map and freezes the player")
	_check(workshop.terrain.is_ready_around(workshop.player.global_position, READY_RADIUS), "The player's starting ground was loaded")
	workshop.camera.position = workshop.site + FAR_OFFSET
	workshop.camera.reset_physics_interpolation()
	_check(absf(FAR_OFFSET.x) > workshop.terrain.visual_radius_m, "Freecam is beyond the real terrain visual radius")
	deadline = Time.get_ticks_msec() + 15000
	while not _player_ground_absent() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_player_ground_absent(), "Natural camera streaming unloads the player chunk and its requests")
	if not _player_ground_absent():
		print("WALK_STREAMING_SETUP ", JSON.stringify(_proof()))
		await _finish_scene()
		return
	var before_walk := _proof()
	workshop.walk()
	if OS.get_cmdline_user_args().has("--expect-walk-stall"):
		await _observe_baseline(before_walk)
		await _finish_scene()
		return
	_check(workshop._walk_when_ground_ready and workshop.building, "Walk waits while player ground is missing")
	_check(workshop.terrain.is_boot_priority() and workshop.terrain.boot_focus().is_equal_approx(workshop.player.global_position), "Pending Walk pins terrain at the player")
	_check(_near_requests() > 0, "Pending Walk requests missing player terrain")
	_check(not workshop.player.is_physics_processing(), "Physics stays paused until collision is ready")
	await _await_walking("Walk from distant freecam")
	if workshop.building or workshop._walk_when_ground_ready:
		await _finish_scene()
		return
	for action in ["build", "open_map", "open_new_harbour"]:
		# Evict deterministically; request and cancel before any worker commit.
		workshop.build()
		workshop.camera.position = workshop.site + FAR_OFFSET
		workshop.terrain._refresh_requests(workshop.camera.global_position)
		_check(_player_ground_absent(), action + ": player terrain absent before Walk")
		workshop.walk()
		_check(workshop._walk_when_ground_ready and workshop.terrain.is_boot_priority(), action + ": Walk has a pending terrain pin")
		workshop.call(action)
		_check(not workshop._walk_when_ground_ready and not workshop.terrain.is_boot_priority(), action + ": cancellation releases the terrain pin")
		_check(not workshop.player.is_physics_processing() and workshop.building, action + ": cancellation keeps the player frozen")
		workshop.terrain._refresh_requests(workshop.camera.global_position)
		await _settle()
		_check(not workshop._walk_when_ground_ready and not workshop.terrain.is_boot_priority() and not workshop.player.is_physics_processing(), action + ": no deferred walk restarts")
		if action == "open_map": _check(workshop.map.visible, "Map cancellation keeps the map open")
		if action == "open_new_harbour": _check(workshop.map.visible and workshop.choosing_site, "New harbour cancellation keeps the coastline chooser open")
	workshop.build()
	workshop.walk()
	await _await_walking("Walk after canceled requests")
	if workshop.building or workshop._walk_when_ground_ready:
		await _finish_scene()
		return
	# H must teleport first, pin its destination and resume after collision.
	var home: Dictionary = workshop._find_home()
	_check(home.get("ok", false), "The real harbour has a valid home target")
	workshop.player.global_position = workshop.site + Vector3(-4500, 120, 0)
	workshop.player.reset_physics_interpolation()
	workshop.terrain._refresh_requests(workshop.camera.global_position)
	var home_target: Vector3 = workshop.site + home.get("local", Vector3.ZERO)
	_check(not workshop.terrain.is_ready_around(home_target, READY_RADIUS), "Home terrain is absent before H")
	var event := InputEventKey.new()
	event.keycode = KEY_H
	event.physical_keycode = KEY_H
	event.pressed = true
	workshop._input(event)
	_check(workshop.player.global_position.is_equal_approx(home_target), "H teleports to the actual harbour home")
	_check(workshop._walk_when_ground_ready and not workshop.player.is_physics_processing(), "H pauses walking while home collision is missing")
	_check(workshop.terrain.is_boot_priority() and workshop.terrain.boot_focus().is_equal_approx(home_target), "H pins terrain at the home destination")
	await _await_walking("Home teleport")
	await _finish_scene()

func _observe_baseline(before_walk: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	var samples := 0
	var always_stalled := true
	var no_player_requests := true
	while Time.get_ticks_msec() - started < 2000:
		await get_tree().process_frame
		samples += 1
		always_stalled = always_stalled and workshop.building and workshop._walk_when_ground_ready and not workshop.player.is_physics_processing()
		no_player_requests = no_player_requests and _near_requests() == 0 and not workshop.terrain.is_boot_priority()
	_check(always_stalled, "Baseline remains building/waiting with paused physics for two seconds")
	_check(no_player_requests, "Baseline never requests player terrain or pins its focus")
	_check(not workshop.terrain.is_ready_around(workshop.player.global_position, READY_RADIUS), "Baseline player collision stays unavailable")
	print("WALK_STREAMING_BASELINE ", JSON.stringify({"before_walk": before_walk, "after_wait": _proof(),
		"observed_ms": Time.get_ticks_msec() - started, "samples": samples,
		"always_stalled": always_stalled, "no_player_requests": no_player_requests}))

func _await_walking(label: String) -> void:
	var started := Time.get_ticks_msec()
	var deadline := started + 30000
	var safe := true
	while (workshop.building or workshop._walk_when_ground_ready) and Time.get_ticks_msec() < deadline:
		if workshop.player.is_physics_processing() and not workshop.terrain.is_ready_around(workshop.player.global_position, READY_RADIUS): safe = false
		await get_tree().process_frame
	_check(safe, label + ": physics never starts before collision readiness")
	_check(not workshop.building and not workshop._walk_when_ground_ready and workshop.player.is_physics_processing(), label + ": walking resumes within the deadline")
	_check(workshop.terrain.is_ready_around(workshop.player.global_position, READY_RADIUS), label + ": player collision is ready")
	_check(get_viewport().get_camera_3d() == workshop.player.camera, label + ": the player camera is current")
	_check(not workshop.terrain.is_boot_priority(), label + ": successful walking releases terrain priority")
	print("WALK_STREAMING_RECOVERY ", label, " elapsed_ms=", Time.get_ticks_msec() - started, " ", JSON.stringify(_proof()))

func _player_ground_absent() -> bool:
	var coord := WorldTerrainStreamer.world_to_chunk(Vector2(workshop.player.global_position.x, workshop.player.global_position.z))
	return not workshop.terrain._chunks.has(WorldTerrainStreamer.chunk_key(coord)) and not workshop.terrain.is_ready_around(workshop.player.global_position, READY_RADIUS) and not workshop.terrain.is_boot_priority() and _near_requests() == 0

func _near_requests() -> int:
	var desired := WorldTerrainStreamer.select_chunk_requests(Vector2(workshop.player.global_position.x, workshop.player.global_position.z),
		workshop.layout.half_extent_m, READY_RADIUS, workshop.terrain.lod_distances_m)
	var keys := {}
	for request in desired:
		var key := WorldTerrainStreamer.chunk_key(request.coord)
		if workshop.terrain._queued.has(key): keys[key] = true
		if workshop.terrain._build_task_id >= 0 and workshop.terrain._build_task_job.get("coord") == request.coord: keys[key] = true
	return keys.size()

func _proof() -> Dictionary:
	var coord := WorldTerrainStreamer.world_to_chunk(Vector2(workshop.player.global_position.x, workshop.player.global_position.z))
	return {"building": workshop.building, "waiting": workshop._walk_when_ground_ready,
		"physics": workshop.player.is_physics_processing(), "boot_priority": workshop.terrain.is_boot_priority(),
		"player_chunk_loaded": workshop.terrain._chunks.has(WorldTerrainStreamer.chunk_key(coord)),
		"collision_ready": workshop.terrain.is_ready_around(workshop.player.global_position, READY_RADIUS),
		"near_requests": _near_requests(), "freecam_current": get_viewport().get_camera_3d() == workshop.camera,
		"camera_distance_m": workshop.camera.global_position.distance_to(workshop.player.global_position),
		"visual_radius_m": workshop.terrain.visual_radius_m}

func _finish_scene() -> void:
	if is_instance_valid(workshop):
		workshop.queue_free()
		await get_tree().process_frame
	for failure in failures: push_error(failure)
	print("CUSTOM PORT WALK STREAMING ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
