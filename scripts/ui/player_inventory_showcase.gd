extends Control
func _ready()->void:
	var background:=ColorRect.new();background.color=Color("101b22");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var inventory:=PlayerInventoryState.empty()
	inventory=PlayerInventoryState.change(inventory,"inventory.purchase",{"item_id":"fishing_rod"},"demo-rod").inventory
	inventory=PlayerInventoryState.change(inventory,"inventory.purchase",{"item_id":"harpe"},"demo-harpe").inventory
	inventory=PlayerInventoryState.change(inventory,"inventory.purchase",{"item_id":"harpe"},"demo-bag").inventory
	inventory=PlayerInventoryState.change(inventory,"inventory.move",{"from":2,"to":7}).inventory
	inventory.selected_slot=0
	var panel:=PersonalInventoryUI.new();panel.preview_mode=true;panel.preview_inventory=inventory;add_child(panel)
	var bar:=PlayerHotbar.new();bar.preview_mode=true;bar.preview_inventory=inventory;add_child(bar)
	if OS.get_cmdline_user_args().has("--capture-inventory"):
		await get_tree().create_timer(1).timeout
		await RenderingServer.frame_post_draw
		var path:="C:/Users/noahs/Pictures/machinescreenshots/player-inventory-"+str(int(Time.get_unix_time_from_system()))+".png"
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		get_viewport().get_texture().get_image().save_png(path);print("INVENTORY_CAPTURE ",path)
		panel.hide();bar.hide()
		var tablet:=KontorTablet.new();tablet.preview_mode=true;tablet.preview_snapshot={"balance":5000,"captain":"Captain","company":{"name":"Nordlys Maritime"}}
		tablet.current_page="Equipment shop";add_child(tablet)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var shop_path:=path.replace(".png","-shop.png")
		get_viewport().get_texture().get_image().save_png(shop_path);print("INVENTORY_CAPTURE ",shop_path)
		tablet.queue_free()
		panel.queue_free();bar.queue_free()
		await get_tree().process_frame
		get_tree().quit()
