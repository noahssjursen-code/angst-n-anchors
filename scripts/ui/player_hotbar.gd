class_name PlayerHotbar
extends HBoxContainer
var preview_mode:=false
var preview_inventory:Dictionary={}
var slots:Array[Button]=[]
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left=-276;offset_right=276;offset_top=-81;offset_bottom=-13
	add_theme_constant_override("separation",8)
	for i in 6:
		var button:=Button.new();button.custom_minimum_size=Vector2(84,68)
		button.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_theme_font_size_override("font_size",13)
		add_child(button);slots.append(button)
	if not preview_mode:PersonalInventory.changed.connect(refresh)
	refresh()
func refresh()->void:
	if slots.is_empty():return
	var state:=preview_inventory if preview_mode else LocalPlayerView.get_personal_inventory()
	for i in 6:
		var item:Dictionary=state.slots[i]
		var title := ""
		if not item.is_empty():
			match str(item.item_id):
				"fishing_rod": title = "Ocean rod"
				"harpe": title = "Harpe"
				"build_tool": title = "Build tool"
				_: title = str(item.item_id).replace("_", " ").capitalize()
		slots[i].text=str(i+1)+"\n"+title
		var box:=VoyageStyle.box(Color("19272ee8"),7);box.set_border_width_all(2);box.border_color=Color("99d6bf") if int(state.selected_slot)==i else Color("48575e")
		slots[i].add_theme_stylebox_override("normal",box);slots[i].add_theme_color_override("font_color",Color("eef1ec"))
