class_name CatchLibrary
extends Control

signal close_requested
var hold_id := ""
var data: Dictionary = {}
var _list: ItemList
var _preview: FishPreview
var _name: Label
var _stats: Label
var _description: Label
var _summary: Label
var _elapsed := 0.0
var _selected_id := ""
var _signature := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme=VoyageStyle.theme()
	var shade:=ColorRect.new();shade.color=Color(0,.025,.035,.55);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left=-480;panel.offset_right=480;panel.offset_top=-295;panel.offset_bottom=295
	panel.add_theme_stylebox_override("panel",VoyageStyle.box(Color("17252b"),18));add_child(panel)
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,24)
	panel.add_child(margin)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",14);margin.add_child(body)
	var heading:=HBoxContainer.new();body.add_child(heading)
	var title:=VoyageStyle.label("CATCH CRATE",24,Color("eee9dc"));title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title)
	var close:=Button.new();close.text="Close  ·  Esc";close.pressed.connect(func():close_requested.emit());heading.add_child(close)
	_summary=VoyageStyle.label("",16,Color("a9c4c8"));body.add_child(_summary)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",22);row.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(row)
	var left:=VBoxContainer.new();left.custom_minimum_size.x=270;row.add_child(left)
	left.add_child(VoyageStyle.label("INDIVIDUAL CATCHES",14,Color("a9c4c8")))
	_list=ItemList.new();_list.size_flags_vertical=Control.SIZE_EXPAND_FILL;_list.custom_minimum_size=Vector2(270,350);_list.add_theme_font_size_override("font_size",17);left.add_child(_list)
	_list.item_selected.connect(_select)
	var right:=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.add_theme_constant_override("separation",10);row.add_child(right)
	_name=VoyageStyle.label("Your crate is empty",27,Color("eee9dc"));right.add_child(_name)
	_preview=FishPreview.new();_preview.custom_minimum_size=Vector2(550,270);_preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;right.add_child(_preview)
	_stats=VoyageStyle.label("",19,Color("bcdcb7"));right.add_child(_stats)
	_description=VoyageStyle.label("Catch a fish from the deck. Its model and measurements will appear here.",16,Color("c1cacc"));_description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_description.custom_minimum_size.y=64;right.add_child(_description)
	body.add_child(VoyageStyle.label("Drag the fish to rotate  ·  Scroll to zoom  ·  Catch value is paid when landed at a fish quay",14,Color("94aeb5")))
	refresh()

func _process(delta: float) -> void:
	_elapsed+=delta
	if _elapsed>=.5:_elapsed=0;refresh()

func refresh() -> void:
	data=LocalPlayerView.get_catch_library(hold_id)
	if data.is_empty():close_requested.emit();return
	var signature:=JSON.stringify(data)
	if signature==_signature:return
	_signature=signature
	_summary.text="%d %s   ·   %.1f / %.0f kg   ·   Estimated landing value: %s"%[data.items.size(),"catch" if data.items.size()==1 else "catches",data.mass_kg,data.capacity_kg,PlayerData.format_money(int(data.value_marks))]
	_list.clear()
	var selected:=0
	for i in data.items.size():
		var item:Dictionary=data.items[i]
		_list.add_item("%s · %.2f kg"%[item.name.trim_prefix("Atlantic "),item.mass_kg] if item.specimen else "%s · %.1f kg bulk"%[item.name,item.mass_kg])
		_list.set_item_tooltip(i,"%s · %.2f kg · %.1f cm"%[item.name,item.mass_kg,item.length_cm])
		if item.lot_id==_selected_id:selected=i
	if not data.items.is_empty():_list.select(selected);_select(selected)
	else:
		_name.text="Your crate is empty";_stats.text="";_description.text="Catch a fish from the deck. Its model and measurements will appear here."
		if is_instance_valid(_preview.fish):_preview.fish.queue_free()

func _select(index: int) -> void:
	var item:Dictionary=data.items[index];_selected_id=item.lot_id
	_name.text=item.name+"  /  "+item.norwegian_name
	_preview.show_species(item.species_id)
	_stats.text="%.2f kg    %.1f cm    %s\n%s  ·  %s"%[item.mass_kg,item.length_cm,PlayerData.format_money(int(item.value_marks)),item.rarity,item.size_grade] if item.specimen else "%.1f kg bulk catch  ·  %s"%[item.mass_kg,PlayerData.format_money(int(item.value_marks))]
	_description.text=item.description
