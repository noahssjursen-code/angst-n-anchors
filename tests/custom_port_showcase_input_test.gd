extends Node

## Real workshop controls, isolated from the captain's save and live services.
const WORKSHOP := preload("res://scenes/showcases/custom_port_showcase.tscn")
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Run this test with -- --shipyard-playtest")
		get_tree().quit(1)
		return
	_run.call_deferred()

func _run() -> void:
	var workshop = WORKSHOP.instantiate()
	add_child(workshop)
	var deadline := Time.get_ticks_msec() + 45000
	while not workshop.ready_for_review and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(workshop.ready_for_review, "The actual port workshop becomes ready")
	if not workshop.ready_for_review:
		_finish()
		return
	workshop._set_cursor(true)
	workshop.library.search.grab_focus()
	var search_revision: int = workshop.state.revision()
	var search_yaw: float = workshop.build_yaw_degrees
	for code in [KEY_R, KEY_M, KEY_H, KEY_G, KEY_1]: await _key(code)
	_check(workshop.building and workshop.cursor_mode and not workshop.map.visible and
		workshop.build_yaw_degrees == search_yaw and workshop.state.revision() == search_revision,
		"Typing in library search cannot trigger building shortcuts")
	await _key(KEY_ESCAPE)
	_check(workshop.building and workshop.cursor_mode and not workshop.library.search.has_focus(),
		"Escape leaves search without switching to walking")
	workshop.library.search.text = "tractor"
	workshop.library.search.text_changed.emit("tractor")
	_check(workshop.library.visible_asset_ids() == ["tractor_tire_fender"], "The real library filters to the matching piece")
	workshop.library.search.grab_focus()
	await _key(KEY_ENTER)
	_check(workshop.selected == "tractor_tire_fender" and workshop.camera.flying and not workshop.library.search.has_focus(),
		"Enter on a unique search equips it and releases typing focus before flight")
	workshop._set_cursor(true)
	workshop.library.search.grab_focus()
	await _key(KEY_TAB)
	_check(workshop.camera.flying and not workshop.library.search.has_focus(), "Tab exits search into free flight")
	workshop.library.search.text = ""
	workshop.library.search.text_changed.emit("")
	workshop.choose("foundation")
	workshop.walk()
	workshop.open_map()
	var chart_port: Dictionary=workshop.map.data.port_info(str(workshop.state.to_dict().id))
	_check(chart_port.get("source","")=="custom" and chart_port.get("platform_polygons_m",[]).size()>0,
		"The workshop map receives actual constructed footprints")
	_check(not chart_port.has("stores") and not chart_port.has("vessels") and not chart_port.has("receipts"),
		"The construction map receives only passive public port data")
	_check(workshop.map.visible and not workshop.player.is_physics_processing(), "The map pauses walking")
	if OS.get_cmdline_user_args().has("--capture-input"):
		await get_tree().create_timer(1.0).timeout
		await workshop._capture("build-plot-map")
	workshop.map.close_requested.emit()
	_check(not workshop.map.visible and workshop.player.is_physics_processing() and not workshop.cursor_mode,
		"Closing the map returns to walking")
	workshop.open_map()
	await _key(KEY_ESCAPE)
	_check(not workshop.map.visible and workshop.player.is_physics_processing(), "Escape from the map also resumes walking")
	workshop.build()
	workshop.open_map()
	workshop.map.close_requested.emit()
	_check(workshop.camera.flying and not workshop.cursor_mode, "Closing the map restores flying when opened from freecam")
	workshop._set_cursor(true)
	workshop.open_map()
	workshop.map.close_requested.emit()
	_check(not workshop.camera.flying and workshop.cursor_mode, "Closing the map preserves the build-library mouse mode")
	workshop.build()
	workshop.camera.position = workshop.SITE + Vector3(0, 20, -25)
	workshop.camera.look_at(workshop.SITE + Vector3(0, 0, -24))
	await _settle()
	_check(not workshop.preview.is_empty() and is_instance_valid(workshop.ghost) and workshop.ghost.visible,
		"A deck-plane target has a visible placement ghost")
	workshop.walk()
	_check(not workshop.ghost.visible, "Walking hides the construction ghost")
	workshop.build()
	await _settle()
	_check(is_instance_valid(workshop.ghost) and workshop.ghost.visible, "Re-entering build restores the ghost at the unchanged aim")
	workshop.open_inspector()
	_check(not workshop.ghost.visible and workshop.preview.is_empty(), "Reading port records clears the frozen construction target")
	workshop.open_map()
	_check(workshop.map.visible and not workshop.inspector.visible and not workshop.camera.flying,
		"Switching from port records to plots leaves exactly one panel and pauses flight")
	await _key(KEY_ESCAPE)
	_check(not workshop.map.visible and not workshop.inspector.visible and workshop.camera.flying,
		"Escape after switching panels returns to freecam without trapping the mouse")
	workshop._set_cursor(true)
	workshop.open_inspector()
	workshop.inspector.close_requested.emit()
	_check(workshop.cursor_mode and not workshop.camera.flying, "Closing port records restores the library cursor when opened there")
	workshop.open_inspector()
	workshop.hotbar.slots[0].pressed.emit()
	_check(not workshop.inspector.visible and workshop.camera.flying, "The build-tool hotbar closes port records before resuming freecam")
	workshop.open_inspector()
	workshop.choose("foundation")
	_check(not workshop.inspector.visible and workshop.camera.flying, "Choosing a library piece closes port records and enables construction")
	workshop.open_map()
	workshop.open_inspector()
	_check(workshop.inspector.visible and not workshop.map.visible, "Opening port records also replaces an open map")
	workshop.inspector.close_requested.emit()
	await _settle()
	_check(workshop.ghost.visible and workshop.camera.flying, "Closing the final panel restores a fresh construction ghost")
	# Moving a large preview must only move its transform, not rebuild a crane
	# every time the aim crosses another grid cell.
	for asset in ["foundation", "container_crane_bay"]:
		workshop.choose(asset)
		workshop.camera.position=workshop.SITE+Vector3(-60,25,5)
		workshop.camera.look_at(workshop.SITE+Vector3(-60,0,10))
		await _settle()
		var first_ghost: int=workshop.ghost.get_instance_id()
		var first_position: Vector3=workshop.ghost.position
		var first_valid: bool=workshop.preview.ok
		workshop.camera.position.x+=8
		await _settle()
		_check(first_valid==bool(workshop.preview.ok) and first_position!=workshop.ghost.position,
			"%s preview moves between different grid targets with matching validity"%asset)
		_check(first_ghost==workshop.ghost.get_instance_id(), "%s reuses its existing preview model while aiming"%asset)
	workshop.choose("foundation")
	await _settle()
	if OS.get_cmdline_user_args().has("--capture-input"):
		workshop.camera.position=workshop.SITE+Vector3(-86,18,-20)
		workshop.camera.look_at(workshop.SITE+Vector3(-64,0,6))
		await _settle()
		await RenderingServer.frame_post_draw
		var folder:="C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(folder)
		var path:=folder.path_join("custom-port-build-controls-%d-%d.png"%[Time.get_unix_time_from_system(),OS.get_process_id()])
		get_viewport().get_texture().get_image().save_png(path)
		print("CUSTOM_PORT_INPUT_CAPTURE ",path)
	var revision: int = workshop.state.revision()
	var placement_count: int = workshop.state.to_dict().placements.size()
	workshop.camera.rotation.x = 0.35
	await _settle()
	_check(workshop.preview.is_empty() and workshop.hovered_id.is_empty() and not workshop.ghost.visible,
		"Aiming above the construction plane clears both placement and removal targets")
	await _mouse(MOUSE_BUTTON_LEFT)
	await _mouse(MOUSE_BUTTON_RIGHT)
	_check(workshop.state.revision() == revision and workshop.state.to_dict().placements.size() == placement_count,
		"Clicking above the plane cannot mutate the previous off-screen target")
	_finish()

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _mouse(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _finish() -> void:
	if failures.is_empty(): print("CUSTOM PORT WORKSHOP INPUT PASS (%d checks)" % checks)
	else:
		for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
