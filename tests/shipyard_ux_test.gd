extends Node

func _ready() -> void:
	var editor := ShipyardBrickEditor.new()
	editor.standalone_tool = true
	add_child(editor)
	for i in range(8):
		await get_tree().process_frame
	var parts := editor.get("_imported_parts_editor") as ImportedShipPartsEditor
	assert(editor.find_child("RegistrationOption",true,false) == null)
	editor.call("_select_brick","cabin_wall_straight")
	parts.structure_anchor = Vector3(-1,2.92,1)
	parts.refresh_ui()
	assert(parts.end_run_button.visible)
	# Escape works even with a toolbar button focused.
	parts.end_run_button.grab_focus()
	assert(parts.end_run_button.has_focus())
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape,true)
	await get_tree().process_frame
	assert(parts.structure_anchor == null and not parts.end_run_button.visible)
	assert(editor.get("_brick_id") == "cabin_wall_straight")
	parts.structure_anchor = Vector3(1,2.92,1)
	for pressed in [true,false]:
		var right := InputEventMouseButton.new()
		right.button_index = MOUSE_BUTTON_RIGHT
		right.position = Vector2(300,300)
		right.pressed = pressed
		editor.call("_on_viewport_gui_input",right)
	assert(parts.structure_anchor == null)
	parts.place_record({"asset_id":"cabin_wall_straight","position":[-1.0,2.92,1.0],"yaw_degrees":0.0})
	var path := "user://shipyard_drafts/ux_test_one.json"
	parts.save_draft(path)
	assert(parts.draft_path == path and parts._draft_state() == parts.saved_state)
	var original := FileAccess.get_file_as_string(path)
	parts.place_record({"asset_id":"cabin_window_straight","position":[1.0,2.92,1.0],"yaw_degrees":0.0})
	assert(parts._draft_state() != parts.saved_state)
	parts.save_draft()
	assert(FileAccess.get_file_as_string(path+".bak") == original)
	assert(parts.records.size() == 2 and parts._draft_state() == parts.saved_state)
	parts.show_save_as()
	assert(parts.save_dialog.visible)
	parts.save_dialog.hide()
	parts.save_dialog.file_selected.emit(ProjectSettings.globalize_path("user://shipyard_drafts/ux_test_two.json"))
	assert(parts.draft_path.ends_with("ux_test_two.json"))
	parts.new_draft()
	assert(parts.records.is_empty())
	parts.request_open()
	assert(parts.load_dialog.visible)
	parts.load_dialog.hide()
	parts.load_dialog.file_selected.emit(path)
	assert(parts.records.size() == 2)
	var before := parts._draft_state()
	var broken := FileAccess.open("user://shipyard_drafts/ux_invalid.json",FileAccess.WRITE)
	broken.store_string('{"version":1,"hull":"trawler_hull_14m","parts":[{"asset_id":"cabin_wall_straight","position":[1]}]}')
	broken.close()
	parts.load_draft("user://shipyard_drafts/ux_invalid.json")
	assert(parts._draft_state() == before)
	# Dirty draft guard offers save/discard/cancel instead of silently dropping work.
	parts.records.clear()
	parts._guard(func() -> void: parts.set_meta("continued",true))
	assert(parts.unsaved_dialog.visible and not parts.has_meta("continued"))
	parts.unsaved_dialog.hide()
	parts.unsaved_dialog.canceled.emit()
	assert(not parts.pending_action.is_valid())
	parts._guard(func() -> void: parts.set_meta("continued",true))
	parts.unsaved_dialog.custom_action.emit("discard")
	assert(parts.get_meta("continued"))
	parts.load_draft(path)
	assert(parts.records.size() == 2)
	print("PASS: focused Escape, right-click end-run, retained family; registration removed; named save/open, overwrite backup, Save As, invalid file isolation, unsaved guard/cancel/discard")
	editor.queue_free()
	for i in range(4):
		await get_tree().process_frame
	get_tree().quit()
