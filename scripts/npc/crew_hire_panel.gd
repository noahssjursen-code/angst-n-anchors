class_name CrewHirePanel
extends PanelContainer

## Pick a generated crew candidate for an open slot.

signal candidate_selected(candidate: Dictionary)
signal cancelled

var _title_lbl: Label
var _list: VBoxContainer


func _init() -> void:
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = HudStyle.C_BG
	sb.border_color = HudStyle.C_AMBER
	sb.set_border_width_all(2)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(360.0, 420.0)
	set_anchors_preset(Control.PRESET_CENTER)
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	_title_lbl = Label.new()
	_title_lbl.text = "HIRE CREW"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 16)
	_title_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	v.add_child(_title_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(320.0, 280.0)
	v.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var cancel_btn := UiBuilder.button("Cancel")
	cancel_btn.pressed.connect(func() -> void:
		hide_panel()
		cancelled.emit()
	)
	v.add_child(cancel_btn)


func open_for_slot(slot_index: int, candidates: Array) -> void:
	_title_lbl.text = "HIRE CREW — SLOT %d" % (slot_index + 1)
	for child in _list.get_children():
		child.queue_free()
	for raw in candidates:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var candidate := raw as Dictionary
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = "%s\n%s — %s/day" % [
			str(candidate.get("name", "Sailor")),
			str(candidate.get("role", "Crew")),
			PlayerData.format_money(int(candidate.get("wage_per_day", 0))),
		]
		var picked := candidate.duplicate()
		btn.pressed.connect(func() -> void:
			candidate_selected.emit(picked)
			hide_panel()
		)
		_list.add_child(btn)
	visible = true


func hide_panel() -> void:
	visible = false
