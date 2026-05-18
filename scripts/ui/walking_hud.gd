class_name WalkingHud
extends Control

## Persistent on-foot HUD — marks balance and active contracts, top-left corner.
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

	draw_rect(Rect2(ox, oy, pw, ph), HudStyle.C_BG)
	draw_rect(Rect2(ox, oy, pw, ph), HudStyle.C_BRASS, false, 1.2)
	draw_string(_font, Vector2(ox + pad_h, oy + pad_v + fs - 2),
				marks_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.C_AMBER)

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
		var in_transit := contract.taken_count - contract.delivered_count
		var c_str  := "%s  →  %s   ×%d" % [contract.display_name, dest, in_transit]
		var c_tw   := _font.get_string_size(c_str, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var c_pw   := c_tw + c_pad * 2.0
		draw_rect(Rect2(ox, cy, c_pw, cph), HudStyle.C_BG)
		draw_rect(Rect2(ox, cy, c_pw, cph), HudStyle.C_BRASS, false, 1.0)
		draw_string(_font, Vector2(ox + c_pad, cy + cph - 5.0),
					c_str, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, HudStyle.C_TEXT)
		cy += cph + 3.0
