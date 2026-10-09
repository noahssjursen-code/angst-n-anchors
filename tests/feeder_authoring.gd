extends Node
## Reproducible authoring through the actual ship builder, including its validator,
## rebuild, native draft save and reload. Also leaves a reusable stock envelope.
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var editor := preload("res://scenes/apps/shipyard_brick_editor.tscn").instantiate() as ShipyardBrickEditor
	add_child(editor)
	await get_tree().process_frame
	var builder: ImportedShipPartsEditor = editor.get("_imported_parts_editor")
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/container_feeder_40_recipe.json"))
	var seen := {}
	for part: Dictionary in recipe.parts:
		var single := recipe.duplicate(true)
		single.parts = [part]
		if not ImportedShipPartsEditor.valid_draft(single): print("INVALID PART ",part)
		var key := ImportedShipPartsEditor.slot_key(part)
		if seen.has(key): print("DUPLICATE SLOT ",key," ",part," vs ",seen[key])
		seen[key] = part
	if not ImportedShipPartsEditor.valid_draft(recipe):
		get_tree().quit(1)
		return
	builder._load_draft_data(recipe)
	assert(builder.records.size() == recipe.parts.size())
	editor.set("_brick_id", "container_bed_20ft")
	for part: Dictionary in recipe.parts:
		if part.asset_id != "container_bed_20ft": continue
		var pos := Vector3(part.position[0],part.position[1],part.position[2])
		var snapped := builder._furniture_candidate(pos+Vector3(.13,0,.19))
		assert(snapped.position == part.position, "Every feeder cargo seat is replaceable in the editor")
	var path := "res://resources/models/examples/container_feeder_40_draft.json"
	builder.save_draft(path)
	var restored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	builder._load_draft_data(restored, path)
	assert(builder.records.size() == recipe.parts.size())
	var layout := restored.duplicate(true)
	layout.merge({"format":"imported_models", "hull_id":"hull_88x14"})
	assert(ImportedVesselLayout.valid(layout, "hull_88x14", true))
	var file := FileAccess.open("res://resources/data/vessels/prebuilt/container_feeder_40.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"format_version":3,"id":"container_feeder_40","name":"Northline 40 · Container Feeder","hull_id":"hull_88x14","shaft_power_kw":1500,"price_marks":98000,"draft":false,"brick_layout":layout},"  ")+"\n")
	file.close()
	editor.set("_cam_dist",115.0)
	editor.set("_cam_pitch",-25.0)
	editor.set("_cam_yaw",35.0)
	editor.set("_cam_target",Vector3(0,7,0))
	editor.call("_update_camera")
	print("FEEDER EDITOR SAVE/RELOAD PASS: ", builder.records.size(), " parts")
	if DisplayServer.get_name() != "headless":
		for frame in 30: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var capture := "C:/Users/noahs/Pictures/machinescreenshots/feeder-editor-%s.png" % str(Time.get_unix_time_from_system()).replace(".","-")
		DirAccess.make_dir_recursive_absolute(capture.get_base_dir())
		get_viewport().get_texture().get_image().save_png(capture)
		print("CAPTURE ",capture)
	if not OS.get_cmdline_user_args().has("--keep-open"): get_tree().quit()
