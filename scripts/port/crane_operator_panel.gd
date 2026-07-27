extends Control

## Compact dispatch sheet for CraneOperatorNpc.

signal request_load
signal request_unload
signal request_stop
signal request_close

var _status: BrandLabel
var _btn_load: BrandButton
var _btn_unload: BrandButton
var _btn_stop: BrandButton
var _title: BrandLabel


func _ready() -> void:
	theme = BrandTheme.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = BrandTokens.SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := BrandPanel.new(BrandPanel.Variant.RULED)
	panel.custom_minimum_size = Vector2(480, 0)
	centre.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", BrandTokens.SPACE_LG)
	panel.add_child(vbox)

	var eyebrow := BrandLabel.new("PORT OPERATIONS / CARGO HANDLING", BrandLabel.Role.SECTION)
	vbox.add_child(eyebrow)

	_title = BrandLabel.new("CRANE OPERATOR", BrandLabel.Role.DISPLAY_MEDIUM)
	vbox.add_child(_title)

	var status_panel := BrandPanel.new(BrandPanel.Variant.RAISED)
	vbox.add_child(status_panel)
	_status = BrandLabel.new("", BrandLabel.Role.DATA)
	_status.custom_minimum_size = Vector2(0, 112)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_panel.add_child(_status)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	vbox.add_child(action_row)

	_btn_load = BrandButton.new("LOAD", BrandButton.Variant.PRIMARY)
	_btn_load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_load.pressed.connect(func() -> void: request_load.emit())
	action_row.add_child(_btn_load)

	_btn_unload = BrandButton.new("UNLOAD", BrandButton.Variant.SECONDARY)
	_btn_unload.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_unload.pressed.connect(func() -> void: request_unload.emit())
	action_row.add_child(_btn_unload)

	_btn_stop = BrandButton.new("STOP", BrandButton.Variant.DANGER)
	_btn_stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_stop.pressed.connect(func() -> void: request_stop.emit())
	action_row.add_child(_btn_stop)

	var close_btn := BrandButton.new("CLOSE", BrandButton.Variant.QUIET)
	close_btn.pressed.connect(func() -> void: request_close.emit())
	vbox.add_child(close_btn)

	BrandMotion.panel_in(panel)


func set_title(value: String) -> void:
	if _title != null:
		_title.text = value.strip_edges().to_upper()


func set_status(
		berth_id: String,
		ship_id: String,
		job_line: String,
		has_ship: bool,
		can_load: bool = false,
		can_unload: bool = false,
		hint: String = "",
	) -> void:
	if _status != null:
		var ship_value := ship_id if has_ship else "NO VESSEL ALONGSIDE"
		var lines := "BERTH    %s\nVESSEL   %s\nJOB      %s" % [berth_id, ship_value, job_line]
		if not hint.is_empty():
			lines += "\n\n%s" % hint.to_upper()
		_status.text = lines
	if _btn_load != null:
		_btn_load.disabled = not can_load
	if _btn_unload != null:
		_btn_unload.disabled = not can_unload
