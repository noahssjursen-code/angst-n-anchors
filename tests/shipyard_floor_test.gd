extends Node

func _ready() -> void:
	var editor := ShipyardBrickEditor.new()
	editor.standalone_tool = true
	add_child(editor)
	for i in range(8):
		await get_tree().process_frame
	var parts := editor.get("_imported_parts_editor") as ImportedShipPartsEditor
	assert(parts.active_floor == 0 and parts.floor_down.disabled)
	editor.call("_select_brick","cabin_wall_straight")
	var lower := {"asset_id":"cabin_wall_straight","position":[0.0,2.92,1.0],"yaw_degrees":0.0}
	parts.place_record(lower)
	parts.structure_anchor = Vector3(0,2.92,0)
	parts.floor_up.pressed.emit()
	assert(parts.active_floor == 1 and parts.structure_anchor == null and parts.selection.is_empty())
	assert(is_equal_approx(parts.floor_y(),5.12))
	assert(is_equal_approx(parts.reference_root.position.y,5.12))
	assert(is_equal_approx(editor.get("_grid_overlay").position.y,2.2))
	var camera := editor.get("_camera") as Camera3D
	var start := Vector3(0,5.12,1)
	var end := Vector3(0,5.12,0)
	_click(editor,camera.unproject_position(start))
	assert(parts.structure_anchor.distance_to(start) < 0.001)
	var candidate := parts.candidate_at(camera.unproject_position(end))
	assert(not candidate.is_empty() and parts._position(candidate).distance_to(start) < 0.001)
	_click(editor,camera.unproject_position(end))
	assert(parts.records.size() == 2, "Upper wall must not replace the lower wall")
	assert(parts.slot_key(lower) != parts.slot_key(candidate))
	editor.call("_set_tool",ShipyardBrickEditor.Tool.MARK)
	parts.select_box(Rect2(Vector2.ZERO,Vector2(editor.get("_viewport").size)),false)
	assert(parts.selection.size() == 1 and parts.selection.has(parts.slot_key(candidate)))
	parts.delete_selected()
	assert(parts.records.size() == 1 and parts.records.has(parts.slot_key(lower)))
	parts.undo()
	assert(parts.records.size() == 2)
	parts.save_draft("user://shipyard_drafts/floor_test.json")
	parts.set_floor(0)
	for model in parts.parts_root.get_children():
		assert(model.visible == (model.position.y < 3.0))
	parts.load_draft("user://shipyard_drafts/floor_test.json")
	assert(parts.active_floor == 1 and parts.records.size() == 2)
	parts.set_floor(0)
	parts.select_box(Rect2(Vector2.ZERO,Vector2(editor.get("_viewport").size)),false)
	assert(parts.selection.size() == 1 and parts.selection.has(parts.slot_key(lower)))
	# Legacy drafts without floor metadata continue to open on deck.
	var legacy := parts._draft_data()
	legacy.erase("active_floor")
	var file := FileAccess.open("user://shipyard_drafts/floor_legacy_test.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	parts.set_floor(2)
	parts.load_draft("user://shipyard_drafts/floor_legacy_test.json")
	assert(parts.active_floor == 0)
	_key(parts, KEY_PAGEUP, true)
	assert(parts.active_floor == 0 and parts.cell_offset == 1)
	assert(is_equal_approx(parts.floor_y(), 3.02))
	assert(is_equal_approx(parts.reference_root.position.y, 3.02))
	assert(is_equal_approx(editor.get("_grid_overlay").position.y, 0.1))
	_key(parts, KEY_PAGEUP, false)
	assert(parts.active_floor == 1 and parts.cell_offset == 1)
	assert(is_equal_approx(parts.floor_y(), 5.22))
	parts.save_draft("user://shipyard_drafts/cell_test.json")
	parts.set_floor(0)
	parts.load_draft("user://shipyard_drafts/cell_test.json")
	assert(parts.active_floor == 1 and parts.cell_offset == 1)
	_key(parts, KEY_PAGEDOWN, true)
	assert(parts.active_floor == 1 and parts.cell_offset == 0)
	_key(parts, KEY_PAGEDOWN, true)
	assert(parts.active_floor == 0 and parts.cell_offset == 21)
	_key(parts, KEY_PAGEUP, true)
	assert(parts.active_floor == 1 and parts.cell_offset == 0)
	parts.set_floor(0)
	_key(parts, KEY_PAGEDOWN, true)
	assert(parts.active_floor == 0 and parts.cell_offset == 0)
	parts.set_floor(parts.MAX_FLOOR)
	_key(parts, KEY_PAGEUP, true)
	assert(parts.active_floor == parts.MAX_FLOOR and parts.cell_offset == 0)
	print("PASS: Shift Page Up/Down 10 cm cells, full-floor offset preservation, boundary normalization, clamping and saved fine elevation")
	print("PASS: 2.2 m floor buttons, placement plane, independent stacked parts, selection/delete isolation, upper-floor hiding, reference/grid height, save/load and legacy drafts")
	editor.queue_free()
	for i in range(4):
		await get_tree().process_frame
	get_tree().quit()

func _click(editor: ShipyardBrickEditor, point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		editor.call("_on_viewport_gui_input",event)

func _key(parts: ImportedShipPartsEditor, code: Key, shift: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.shift_pressed = shift
	assert(parts.key_input(event))
