extends Control

## Minimal load / unload / stop panel for CraneOperatorNpc.

signal request_load
signal request_unload
signal request_stop
signal request_close

var _status: Label
var _btn_load: Button
var _btn_unload: Button
var _btn_stop: Button
var _title: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(400, 260)
	offset_left = -200
	offset_right = 200
	offset_top = -140
	offset_bottom = 140

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_title = Label.new()
	_title.text = "CRANE OPERATOR"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(360, 96)
	vbox.add_child(_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	_btn_load = Button.new()
	_btn_load.text = "Load"
	_btn_load.pressed.connect(func() -> void: request_load.emit())
	row.add_child(_btn_load)

	_btn_unload = Button.new()
	_btn_unload.text = "Unload"
	_btn_unload.pressed.connect(func() -> void: request_unload.emit())
	row.add_child(_btn_unload)

	_btn_stop = Button.new()
	_btn_stop.text = "Stop"
	_btn_stop.pressed.connect(func() -> void: request_stop.emit())
	row.add_child(_btn_stop)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func() -> void: request_close.emit())
	vbox.add_child(close_btn)


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
		var lines := "Berth  %s\nShip   %s\nJob    %s" % [berth_id, ship_id, job_line]
		if not hint.is_empty():
			lines += "\n%s" % hint
		_status.text = lines
	if _btn_load != null:
		_btn_load.disabled = not can_load
	if _btn_unload != null:
		_btn_unload.disabled = not can_unload
