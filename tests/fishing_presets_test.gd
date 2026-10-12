extends Node3D

func _ready()->void:
	assert(ShipyardPlaytestMode.active())
	var stock:=PrebuiltVesselCatalog.catalog_entries(true)
	assert(stock.any(func(e:Dictionary)->bool:return e.prebuilt_id=="fishing_crab"),"Crabber must be an editable preset")
	assert(not stock.any(func(e:Dictionary)->bool:return e.prebuilt_id=="fishing_trawler"),"Retired small trawler must not appear")
	assert(not PrebuiltVesselCatalog.for_sale_entries().any(func(e:Dictionary)->bool:return e.prebuilt_id=="fishing_crab"),"Do not sell unfinished trap gameplay")
	var editor:=ShipyardBrickEditor.new();editor.standalone_tool=true;add_child(editor)
	for i in 12:await get_tree().process_frame
	var parts:=editor.get("_imported_parts_editor") as ImportedShipPartsEditor
	assert(parts!=null)
	var menu:=parts.draft_menu
	var crab_id:=-1
	for i in menu.item_count:
		assert(not menu.get_item_text(i).to_lower().contains("trawler"))
		if menu.get_item_text(i).contains("Coastal Crabber"):crab_id=menu.get_item_id(i)
	assert(crab_id>=200,"Crabber must be visible in actual builder menu")
	menu.id_pressed.emit(crab_id)
	for i in 8:await get_tree().process_frame
	assert(parts.records.values().any(func(p:Dictionary)->bool:return p.asset_id=="crabber_work_shelter"))
	assert(parts.records.values().filter(func(p:Dictionary)->bool:return p.asset_id=="crab_creel").size()==12)
	if OS.get_cmdline_user_args().has("--capture"):
		menu.popup_centered()
		for i in 8:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path:="C:/Users/noahs/Pictures/machinescreenshots/crabber-builder-%d.png"%Time.get_unix_time_from_system()
		get_viewport().get_texture().get_image().save_png(path);print("CAPTURE ",path)
	print("FISHING PRESETS PASS: actual builder menu, crab load, outfit, retired stock absent")
	get_tree().quit()
