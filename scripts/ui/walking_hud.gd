class_name WalkingHud
extends Control

## Persistent on-foot HUD — marks balance, top-left corner.
## Shown when the player is on foot; hidden by GameMenu when helming a ship.

var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font        = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return

	var marks_str := "ℳ  %d" % session.get_marks()
	var fs        := 17
	var tw        := _font.get_string_size(marks_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad_h     := 14.0
	var pad_v     := 10.0
	var pw        := tw + pad_h * 2.0
	var ph        := float(fs) + pad_v * 2.0
	var ox        := 14.0
	var oy        := 14.0

	draw_rect(Rect2(ox, oy, pw, ph), Color(0.04, 0.06, 0.14, 0.88))
	draw_rect(Rect2(ox, oy, pw, ph), Color(0.30, 0.44, 0.68, 0.55), false, 1.2)
	draw_string(_font, Vector2(ox + pad_h, oy + pad_v + fs - 2),
				marks_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0.96, 0.82, 0.28, 0.95))

	# Active contract summary below marks
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	var contracts: Array[Contract] = registry.get_accepted_contracts()
	if contracts.is_empty():
		return

	var cfs   := 12
	var cph   := float(cfs) + 8.0
	var cy    := oy + ph + 6.0
	var c_pad := 10.0

	for contract in contracts:
		var dest: String = registry.get_port_display_name(contract.destination_port_id)
		var remain    := contract.quantity - contract.delivered_count
		var c_str     := "%s → %s  (%d/%d)" % [contract.display_name, dest, remain, contract.quantity]
		var c_tw      := _font.get_string_size(c_str, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var c_pw      := c_tw + c_pad * 2.0
		draw_rect(Rect2(ox, cy, c_pw, cph), Color(0.04, 0.06, 0.14, 0.80))
		draw_rect(Rect2(ox, cy, c_pw, cph), Color(1.0, 0.58, 0.06, 0.45), false, 1.0)
		draw_string(_font, Vector2(ox + c_pad, cy + cph - 5.0),
					c_str, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs,
					Color(1.0, 0.75, 0.30, 0.90))
		cy += cph + 3.0
