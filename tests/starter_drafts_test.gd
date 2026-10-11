extends Node

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var editor := ShipyardBrickEditor.new()
	editor.standalone_tool = true
	add_child(editor)
	for i in 8: await get_tree().process_frame
	var parts := editor.get("_imported_parts_editor") as ImportedShipPartsEditor
	var path := OS.get_cache_dir().path_join("starter-draft-%d.json" % OS.get_process_id())
	for option in CompanyContracts.starter_options():
		parts.load_starter(option.id)
		var expected := VesselSpawn.brick_layout_of(CompanyService.build_starter_vessel_record(option.id))
		assert(parts.draft_path.is_empty(), "Starter opens as a new copy, never a writable stock file")
		assert(parts.records.size()==expected.parts.size())
		assert(parts.hull_id==expected.hull)
		assert(parts.show_all_floors, "Complete starter visible on first opening")
		parts.engine_preset = str(MarineEngineCatalog.options(parts.hull_id).back().id)
		parts._refresh_engine_choice()
		assert(parts.draft_name==CompanyService.build_starter_vessel_record(option.id).name)
		parts.save_draft(path)
		var saved := parts._draft_data().duplicate(true)
		parts.new_draft()
		parts.load_draft(path)
		assert(PlayerData.json_equivalent(saved,parts._draft_data()), "Every placement, paint and floor must round-trip")
		var invalid := saved.duplicate(true)
		invalid.parts[0].asset_id = "invalid-part"
		parts._load_draft_data(invalid)
		assert(PlayerData.json_equivalent(saved,parts._draft_data()), "Invalid draft preserves current work")
	parts.load_starter("general_cargo")
	for model in parts.parts_root.get_children():
		if parts.records[str(model.get_meta("record_key"))].asset_id == "container_bed_20ft":
			assert(model.visible and parts._on_active_floor(model), "Cargo beds are editable from Deck")
	editor.set("_brick_id","container_bed_20ft")
	assert(parts._furniture_candidate(Vector3(1,3.6,-1)).position==[1.25,3.6,0], "Container beds snap onto the main cargo deck")
	parts.show_drafts()
	var args := OS.get_cmdline_user_args()
	var capture := args.find("--capture")
	if capture >= 0:
		parts.draft_menu.position = Vector2i(260,85)
		for i in 12: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[capture+1])
	parts.pending_action = Callable()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path+".bak")
	editor.queue_free()
	for i in 4: await get_tree().process_frame
	# Shipwright must preview the same imported model assembly as onboarding.
	var preview := ShipwrightPreview.new()
	add_child(preview)
	var entry := PrebuiltVesselCatalog.for_sale_entries()[0]
	preview.show_entry(entry,entry.prebuilt_layout)
	var boat := preview.get_node("Pivot/PreviewBoat") as ImportedDraftVessel
	assert(boat != null and boat.part_roots.size()==entry.prebuilt_layout.parts.size())
	preview.queue_free()
	for i in 4: await get_tree().process_frame
	print("STARTER DRAFTS PASS: all four editable copies, safe Save As, exact save/load, invalid-load preservation, cargo snap, shipwright preview")
	get_tree().quit()
