class_name WalkingHud
extends Control

## Persistent on-foot HUD — marks balance and active contracts, top-left corner.
## Shown when the player is on foot; hidden by GameMenu when helming a ship.
##
## Redraws only on state changes (PlayerSession.marks_changed,
## ContractRegistry.contract_accepted / _completed). Pre-overhaul this
## hit queue_redraw() every frame — wasted CPU when nothing changed.

var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font        = ThemeDB.fallback_font

	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		if session.has_signal("marks_changed") and not session.marks_changed.is_connected(_refresh_arg):
			session.marks_changed.connect(_refresh_arg)
		if session.has_signal("data_loaded") and not session.data_loaded.is_connected(_refresh_arg):
			session.data_loaded.connect(_refresh_arg)

	var registry := get_node_or_null("/root/ContractRegistry")
	if registry != null:
		if registry.has_signal("contract_accepted") and not registry.contract_accepted.is_connected(_refresh_two):
			registry.contract_accepted.connect(_refresh_two)
		if registry.has_signal("contract_completed") and not registry.contract_completed.is_connected(_refresh_arg):
			registry.contract_completed.connect(_refresh_arg)
		if registry.has_signal("unit_delivered") and not registry.unit_delivered.is_connected(_refresh_two):
			registry.unit_delivered.connect(_refresh_two)

	# One redraw at start so the panel doesn't appear blank on first frame.
	queue_redraw()


# Helpers — accept the signal args (we ignore them and just redraw).
func _refresh_arg(_arg: Variant = null) -> void:
	queue_redraw()


func _refresh_two(_a: Variant = null, _b: Variant = null) -> void:
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
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
