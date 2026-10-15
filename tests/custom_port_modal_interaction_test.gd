extends "res://tests/custom_port_walking_interaction_test.gd"

## The real NPC still lies under the paused player camera while another mode owns
## input. F must not talk through that stale camera or toggle a door behind UI.
func _run() -> void:
	workshop = WORKSHOP.instantiate()
	add_child(workshop)
	var deadline := Time.get_ticks_msec() + 60000
	while not workshop.ready_for_review and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(workshop.ready_for_review, "The fishing workshop is ready for modal input acceptance")
	if not workshop.ready_for_review: await _finish(); return
	workshop.walk()
	deadline = Time.get_ticks_msec() + 30000
	while (workshop.building or workshop._ground_pause) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(not workshop.building and not workshop._ground_pause, "Normal walking has a current collider")
	if workshop.building or workshop._ground_pause: await _finish(); return
	var operator: NpcInteractable = workshop.presenter.placement_nodes["landing-operator"]
	await _approach(workshop.site + Vector3(10, .12, 26.4), operator.global_position + Vector3.UP * 1.2)
	_check(operator._can_interact(), "The player's camera really targets the operator before pausing")
	var interactions: Array = []
	operator.interaction_requested.connect(func(): interactions.append(Time.get_ticks_usec()))
	var before: Dictionary = workshop.state.to_dict()
	for mode in ["builder", "cursor", "map", "inspector"]:
		workshop.walk()
		await get_tree().physics_frame
		match mode:
			"builder": await _tap(KEY_1)
			"cursor": await _tap(KEY_TAB)
			"map": await _tap(KEY_M)
			"inspector":
				await _tap(KEY_F)
				_check(workshop.inspector.visible, "Ordinary walking F still opens the operator")
				workshop.inspector.focus_berths()
		var prior := interactions.size()
		await _tap(KEY_F)
		_check(interactions.size() == prior, mode + ": F cannot reach the NPC through the paused player's camera")
		match mode:
			"builder": _check(workshop.building and not workshop.inspector.visible, "Builder retains its free camera and library")
			"cursor": _check(workshop.cursor_mode and not workshop.inspector.visible, "Released cursor does not open a conversation")
			"map": _check(workshop.map.visible and not workshop.inspector.visible, "F leaves the chart open")
			"inspector": _check(workshop.inspector.visible and workshop.inspector._tabs.current_tab == 0, "F does not reset the inspector's chosen tab")
	_check(workshop.state.to_dict() == before, "Blocked NPC input never mutates the port record")
	workshop.build()
	workshop._set_cursor(true)
	workshop.library.search.text = ""
	workshop.library.search.grab_focus()
	var before_typing := interactions.size()
	var text_event := InputEventKey.new()
	text_event.keycode = KEY_F
	text_event.physical_keycode = KEY_F
	text_event.unicode = 102
	text_event.pressed = true
	Input.parse_input_event(text_event)
	Input.flush_buffered_events()
	await get_tree().process_frame
	text_event = text_event.duplicate()
	text_event.pressed = false
	Input.parse_input_event(text_event)
	await get_tree().process_frame
	_check(workshop.library.search.text == "f", "The interaction guard still permits typing f into the build-library search")
	_check(interactions.size() == before_typing and not workshop.inspector.visible, "Typing f is consumed by the field without talking to the paused-camera NPC")
	workshop.walk()
	var door: Node3D = workshop.presenter.placement_nodes["front--6"]
	await _approach(workshop.site + Vector3(-6, .12, 21.7), _door_leaf(door).global_position)
	_check(_door_targeted(), "A real closed door is under the walking camera")
	var revision: int = workshop.state.revision()
	await _tap(KEY_TAB)
	await _tap(KEY_F)
	_check(not _door_open("front--6") and workshop.state.revision() == revision, "Cursor mode also prevents toggling a door through the paused camera")
	await _tap(KEY_TAB)
	await _tap(KEY_F)
	_check(_door_open("front--6") and workshop.state.revision() == revision + 1, "Returning to walking immediately restores ordinary door F interaction")
	await _capture("modal-input-restored-walking")
	await _finish()

func _finish() -> void:
	if is_instance_valid(workshop):
		workshop.queue_free()
		for frame in 3: await get_tree().process_frame
	print("CUSTOM PORT MODAL INTERACTION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
