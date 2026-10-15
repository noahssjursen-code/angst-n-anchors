class_name PersonalInventoryUI
extends PanelContainer
signal close_requested
signal shop_requested
var preview_mode:=false
var preview_inventory:Dictionary={}
var selected_source:=-1
var notice:=""
var grid:GridContainer
var hotbar:HBoxContainer
var feedback:Label
var slots:Array[Button]=[]
const DARK:=Color("18242b")
const TILE:=Color("26353c")
const TEXT:=Color("eef1ec")
const ACCENT:=Color("99d6bf")

func _ready()->void:
	theme=VoyageStyle.theme().duplicate()
	theme.set_color("font_color","Label",TEXT)
	add_theme_stylebox_override("panel",VoyageStyle.box(DARK,24))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left=-450;offset_right=450;offset_top=-380;offset_bottom=380
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",16);add_child(column)
	var top:=HBoxContainer.new();column.add_child(top)
	var title:=VoyageStyle.label("ON PERSON",28,TEXT);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(title)
	top.add_child(VoyageStyle.button("Close · TAB",func():close_requested.emit()))
	column.add_child(VoyageStyle.label("Click an item, then its destination. 1–6 equip; press again to stow.",18,Color("abb9b9")))
	column.add_child(VoyageStyle.label("BAG  ·  24 SLOTS",16,ACCENT))
	grid=GridContainer.new();grid.columns=6;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",10);column.add_child(grid)
	for i in range(6,30):_slot(grid,i)
	column.add_child(VoyageStyle.label("QUICK ACCESS",16,ACCENT))
	hotbar=HBoxContainer.new();hotbar.add_theme_constant_override("separation",10);column.add_child(hotbar)
	for i in 6:_slot(hotbar,i)
	feedback=VoyageStyle.label("",17,ACCENT);feedback.custom_minimum_size.y=28;column.add_child(feedback)
	column.add_child(VoyageStyle.button("Equipment shop · open tablet",func():shop_requested.emit()))
	if not preview_mode:
		PersonalInventory.changed.connect(refresh)
		PersonalInventory.finished.connect(_finished)
	refresh()

func _slot(parent:Node,index:int)->void:
	var button:=Button.new();button.name="Slot_%d"%index;button.custom_minimum_size=Vector2(128,72);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size",15)
	button.pressed.connect(func():_clicked(index));parent.add_child(button);slots.append(button)
	button.set_meta("slot",index)

func refresh()->void:
	if slots.is_empty():return
	var state:=preview_inventory if preview_mode else LocalPlayerView.get_personal_inventory()
	for button in slots:
		var index:=int(button.get_meta("slot"));var item:Dictionary=state.slots[index]
		button.text=(str(index+1)+"\n" if index<6 else "")+("—" if item.is_empty() else ("Ocean rod" if item.item_id=="fishing_rod" else "Harpe"))
		var active:=index==int(state.selected_slot) or index==selected_source
		var box:=VoyageStyle.box(TILE,8);box.set_border_width_all(2);box.border_color=ACCENT if active else Color("405159")
		button.add_theme_stylebox_override("normal",box);button.add_theme_stylebox_override("hover",VoyageStyle.box(Color("344850"),8))
		button.add_theme_color_override("font_color",TEXT)
		button.tooltip_text="Slot %d"%(index+1) if item.is_empty() else str(VesselEquipment.item(item.item_id).get("name",item.item_id))
	feedback.text=notice if not notice.is_empty() else ("Select a destination slot." if selected_source>=0 else "Your tools travel with you. Company goods remain in port storage.")

func _clicked(index:int)->void:
	var state:=preview_inventory if preview_mode else LocalPlayerView.get_personal_inventory()
	if selected_source<0:
		if state.slots[index].is_empty():return
		selected_source=index
	elif selected_source==index:
		if index<6 and not preview_mode:PersonalInventory.send("inventory.select",{"slot":-1 if int(state.selected_slot)==index else index})
		selected_source=-1
	else:
		if preview_mode:
			preview_inventory=PlayerInventoryState.change(state,"inventory.move",{"from":selected_source,"to":index}).inventory
		else:PersonalInventory.send("inventory.move",{"from":selected_source,"to":index})
		selected_source=-1
	refresh()

func _finished(result:Dictionary)->void:
	notice=("Equipment delivered to your inventory." if result.get("action","")=="inventory.purchase" else "Inventory updated.") if bool(result.get("ok",false)) else str(result.get("message","Inventory action failed."))
	refresh()
