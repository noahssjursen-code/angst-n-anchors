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
var _delete_confirmation: ConfirmationDialog
var _pending_delete_id := ""


func _ready() -> void:
	add_theme_constant_override("separation", UiPalette.GAP_M)
	add_child(Ui.eyebrow("Captains"))

	var scroll := Ui.scroll()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_list = Ui.vbox(6)
	scroll.add_child(_list)

	_hint = Ui.caption("")
	add_child(_hint)

	var row := Ui.hbox(10)
	add_child(row)
	_sail_btn = Ui.button("Sail voyage", "primary")
	_sail_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sail_btn.disabled = true
	_sail_btn.pressed.connect(func() -> void:
		if not selected_id.is_empty():
			sail_pressed.emit(selected_id))
	row.add_child(_sail_btn)
	row.add_child(Ui.button("New captain", "secondary", func() -> void: create_pressed.emit()))
	_delete_confirmation = ConfirmationDialog.new()
	_delete_confirmation.title = "Delete captain"
	_delete_confirmation.ok_button_text = "Delete save"
	_delete_confirmation.confirmed.connect(func() -> void:
		var id := _pending_delete_id
		_pending_delete_id = ""
		if not id.is_empty():
			delete_pressed.emit(id))
	_delete_confirmation.canceled.connect(func() -> void: _pending_delete_id = "")
	add_child(_delete_confirmation)


func configure(show_seed: bool = true, allow_debug_marks: bool = false, on_debug_marks: Callable = Callable()) -> void:
	_show_seed = show_seed
	_allow_debug_marks = allow_debug_marks
	_on_debug_marks = on_debug_marks


func set_entries(entries: Array, selected: String = "") -> void:
	selected_id = selected
	Ui.clear(_list)
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
	var row := Ui.card("signal" if active else "")
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(row)

	var inner := Ui.hbox(10)
	row.add_child(inner)
	var text_col := Ui.vbox(2)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(text_col)
	var pick := Button.new()
	pick.theme_type_variation = "GhostButton"
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.text = str(entry.get("display_name", "Captain"))
	pick.add_theme_font_override("font", UiPalette.strong())
	pick.add_theme_font_size_override("font_size", UiPalette.SIZE_LEAD)
	if active:
		pick.add_theme_color_override("font_color", UiPalette.CRANE)
	text_col.add_child(pick)

	var meta_bits: PackedStringArray = []
	if _show_seed and int(entry.get("world_seed", 0)) > 0:
		meta_bits.append("seed %d" % int(entry.get("world_seed", 0)))
	if not str(entry.get("home_port_id", "")).is_empty():
		meta_bits.append(str(entry.get("home_port_id", "")))
	var company_name := str(entry.get("company_name", "")).strip_edges()
	if not company_name.is_empty():
		meta_bits.append(company_name)
	meta_bits.append(PlayerSession.format_money(int(entry.get("marks", 0))))
	text_col.add_child(Ui.caption(" · ".join(meta_bits)))

	if _allow_debug_marks and _on_debug_marks.is_valid():
		var cheat := Ui.button("+1M", "chip")
		cheat.toggle_mode = false
		cheat.pressed.connect(func() -> void: _on_debug_marks.call(entry))
		inner.add_child(cheat)

	var del := Ui.button("Delete", "ghost")
	del.pressed.connect(func() -> void:
		_pending_delete_id = id
		_delete_confirmation.dialog_text = "Delete %s and this captain's saved company and vessels?\nThis cannot be undone." % str(entry.get("display_name", "Captain"))
		_delete_confirmation.popup_centered(Vector2i(460, 180)))
	inner.add_child(del)

	var select := func() -> void:
		selected_id = id
		selected.emit(id)
	pick.pressed.connect(select)
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			select.call())
