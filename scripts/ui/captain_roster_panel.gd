class_name CaptainRosterPanel
extends VBoxContainer

## Shared captain list UI for local and remote rosters.

signal sail_pressed(captain_id: String)
signal delete_pressed(captain_id: String)
signal create_pressed
signal selected(captain_id: String)

var selected_id: String = ""
var _list: VBoxContainer
var _hint: Label
var _sail_btn: Button
var _show_seed := true
var _allow_debug_marks := false
var _on_debug_marks: Callable = Callable()


func _ready() -> void:
	theme = HudStyle.make_theme()
	add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "CAPTAINS"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", HudStyle.C_LABEL)
	add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	_sail_btn = Button.new()
	_sail_btn.text = "Sail voyage"
	_sail_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sail_btn.disabled = true
	_sail_btn.pressed.connect(func() -> void:
		if not selected_id.is_empty():
			sail_pressed.emit(selected_id)
	)
	row.add_child(_sail_btn)

	var create_btn := Button.new()
	create_btn.text = "New captain"
	create_btn.pressed.connect(func() -> void: create_pressed.emit())
	row.add_child(create_btn)


func configure(show_seed: bool = true, allow_debug_marks: bool = false, on_debug_marks: Callable = Callable()) -> void:
	_show_seed = show_seed
	_allow_debug_marks = allow_debug_marks
	_on_debug_marks = on_debug_marks


func set_entries(entries: Array, selected: String = "") -> void:
	selected_id = selected
	for child in _list.get_children():
		child.queue_free()
	if entries.is_empty():
		_hint.text = "No captains yet. Create one to begin."
		_sail_btn.disabled = true
		return
	_hint.text = "Select a captain, then sail — or create another."
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		_add_row(raw as Dictionary)
	_sail_btn.disabled = selected_id.is_empty()


func set_message(text: String) -> void:
	_hint.text = text


func _add_row(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	var row := HBoxContainer.new()
	_list.add_child(row)

	var name_btn := Button.new()
	var parts: PackedStringArray = [str(entry.get("display_name", "Captain"))]
	if _show_seed and int(entry.get("world_seed", 0)) > 0:
		parts.append("seed %d" % int(entry.get("world_seed", 0)))
	if not str(entry.get("home_port_id", "")).is_empty():
		parts.append(str(entry.get("home_port_id", "")))
	parts.append(PlayerSession.format_money(int(entry.get("marks", 0))))
	name_btn.text = " · ".join(parts)
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if id == selected_id:
		name_btn.add_theme_color_override("font_color", HudStyle.C_AMBER)
	row.add_child(name_btn)

	if _allow_debug_marks and _on_debug_marks.is_valid():
		var cheat := Button.new()
		cheat.text = "+1M"
		cheat.flat = true
		cheat.pressed.connect(func() -> void: _on_debug_marks.call(entry))
		row.add_child(cheat)

	var del := Button.new()
	del.text = "Delete"
	del.flat = true
	del.pressed.connect(func() -> void: delete_pressed.emit(id))
	row.add_child(del)

	name_btn.pressed.connect(func() -> void:
		selected_id = id
		selected.emit(id)
	)
