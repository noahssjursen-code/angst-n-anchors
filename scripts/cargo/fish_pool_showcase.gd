extends Node
func _ready()->void:
	var ui:=CanvasLayer.new();add_child(ui)
	var bg:=ColorRect.new();bg.color=Color("12232c");bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.add_child(bg)
	var grid:=GridContainer.new();grid.columns=3;grid.position=Vector2(24,24);grid.add_theme_constant_override("h_separation",20);grid.add_theme_constant_override("v_separation",20);ui.add_child(grid)
	for id in FishCatalog.fish_ids():
		var box:=VBoxContainer.new();grid.add_child(box)
		var label:=Label.new();var entry:=FishCatalog.species(id);label.text=entry.name+" / "+entry.norwegian_name;label.add_theme_font_size_override("font_size",23);box.add_child(label)
		var preview:=FishPreview.new();preview.custom_minimum_size=Vector2(478,310);box.add_child(preview);preview.show_species(id)
		var info:=Label.new();info.text="%s  ·  %s/kg  ·  %d–%d cm"%[entry.rarity,PlayerData.format_money(int(entry.marks_per_kg)),entry.length_cm[0],entry.length_cm[1]];info.add_theme_font_size_override("font_size",17);box.add_child(info)
	if OS.get_cmdline_user_args().has("--capture"):
		for i in 15:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path:="C:/Users/noahs/Pictures/machinescreenshots/fish-pool-%d.png"%Time.get_unix_time_from_system()
		DirAccess.make_dir_recursive_absolute(path.get_base_dir());get_viewport().get_texture().get_image().save_png(path);print("CAPTURE ",path);get_tree().quit()
