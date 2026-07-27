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
	theme = BrandTheme.shared()
	add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "CAPTAINS"
	BrandTheme.apply_body_font(title, BrandTokens.LABEL_MONO, BrandTokens.INK_MUTED, true)
	add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_hint = Label.new()
	BrandTheme.apply_body_font(_hint, BrandTokens.BUTTON, BrandTokens.INK_MUTED)
	add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	_sail_btn = BrandButton.new("", BrandButton.Variant.LOUD)
	_sail_btn.text = "Sail voyage"
	_sail_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sail_btn.disabled = true
	_sail_btn.pressed.connect(func() -> void:
		if not selected_id.is_empty():
			sail_pressed.emit(selected_id)
	)
	row.add_child(_sail_btn)

	var create_btn := BrandButton.new("", BrandButton.Variant.SECONDARY)
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
	var active := id == selected_id
	var row := BrandPanel.new(
		BrandPanel.Variant.RULED if active else BrandPanel.Variant.RAISED
	)
	_list.add_child(row)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	row.add_child(inner)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	inner.add_child(text_col)

	var pick := BrandButton.new("", BrandButton.Variant.QUIET)
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.text = str(entry.get("display_name", "Captain"))
	BrandTheme.apply_body_font(
		pick, BrandTokens.BUTTON, BrandTokens.BRASS_DEEP if active else BrandTokens.INK, true
	)
	text_col.add_child(pick)

	var meta_bits: PackedStringArray = []
	if _show_seed and int(entry.get("world_seed", 0)) > 0:
		meta_bits.append("seed %d" % int(entry.get("world_seed", 0)))
	if not str(entry.get("home_port_id", "")).is_empty():
		meta_bits.append(str(entry.get("home_port_id", "")))
	var company_name := str(entry.get("company_name", "")).strip_edges()
	if not company_name.is_empty():
		meta_bits.append(company_name)
	meta_bits.append(BrandFormat.money_text(int(entry.get("marks", 0))))
	var meta := Label.new()
	meta.text = " · ".join(meta_bits)
	BrandTheme.apply_body_font(meta, BrandTokens.LABEL_MONO, BrandTokens.INK_MUTED)
	text_col.add_child(meta)

	if _allow_debug_marks and _on_debug_marks.is_valid():
		var cheat := BrandButton.new("+1M", BrandButton.Variant.QUIET)
		cheat.pressed.connect(func() -> void: _on_debug_marks.call(entry))
		inner.add_child(cheat)

	var del := BrandButton.new("DELETE", BrandButton.Variant.QUIET)
	BrandTheme.apply_body_font(del, BrandTokens.LABEL_MONO, BrandTokens.ALERT)
	del.pressed.connect(func() -> void: delete_pressed.emit(id))
	inner.add_child(del)

	var select := func() -> void:
		selected_id = id
		selected.emit(id)
	pick.pressed.connect(select)
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			select.call()
	)
