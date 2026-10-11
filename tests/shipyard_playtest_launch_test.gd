extends Node

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Run this test with --shipyard-playtest --verify-playtest-launch")
	var editor := ShipyardBrickEditor.new()
	editor.standalone_tool = true
	add_child(editor)
	for i in range(8):
		await get_tree().process_frame
	var parts := editor.get("_imported_parts_editor") as ImportedShipPartsEditor
	for id in ["cabin_door_straight", "helm_wheel", "helm_throttle", "helm_chair"]:
		var index := parts.records.size()
		var record := {"asset_id":id, "position":[float(index) * .7 - 1.0, 2.92 + (.85 if id in ["helm_wheel", "helm_throttle"] else 0.0), 0.0], "yaw_degrees":0.0}
		parts.records[parts.slot_key(record)] = record
	var before := parts._draft_state()
	var previous_saved := parts.saved_state
	var previous_path := parts.draft_path
	var button := editor.find_child("PlaytestBoat", true, false) as Button
	assert(button != null)
	button.pressed.emit()
	assert(ShipyardPlaytestMode.child_pid > 0)
	assert(not ShipyardPlaytestMode.launch(parts._draft_data()).is_empty(), "Duplicate test windows must be rejected")
	var deadline := Time.get_ticks_msec() + 90000
	while OS.is_process_running(ShipyardPlaytestMode.child_pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(.5).timeout
	assert(not OS.is_process_running(ShipyardPlaytestMode.child_pid), "Playtest did not complete")
	assert(before == parts._draft_state())
	assert(previous_path == parts.draft_path and previous_saved == parts.saved_state, "Playtest must not save or rename the builder draft")
	var cache := OS.get_cache_dir().path_join("angst-n-anchors-playtest")
	var verified := false
	for file in DirAccess.get_files_at(cache):
		if file.begins_with("draft-%d-" % OS.get_process_id()) and file.ends_with(".verified"):
			verified = FileAccess.get_file_as_string(cache.path_join(file)) == "passed"
			DirAccess.remove_absolute(cache.path_join(file))
	assert(verified, "Child did not pass runtime checks")
	print("PLAYTEST LAUNCH PASS: actual button, separate process, duplicate guard, current unsaved draft preserved")
	get_tree().quit()
