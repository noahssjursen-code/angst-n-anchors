class_name WalkingHud
extends Control

## Persistent on-foot HUD — marks balance and active contracts, top-left corner.
## Shown when the player is on foot; hidden by GameMenu when helming a ship.
##
## Reads through LocalPlayerView so the same code works in single-player
## (today) and multiplayer (future). Redraws only on state changes —
## per-frame redraw was wasted CPU when nothing actually changed.

var _font: Font
var _autopilot_refresh_s := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font        = ThemeDB.fallback_font

	# Subscribe to the local player view's signals — single subscription
	# point covers marks, contracts, and helm changes.
	var view := get_node_or_null("/root/LocalPlayerView")
	if view != null:
		if not view.marks_changed.is_connected(_refresh_arg):
			view.marks_changed.connect(_refresh_arg)
		if not view.contracts_changed.is_connected(_refresh_arg):
			view.contracts_changed.connect(_refresh_arg)
		if not view.helm_changed.is_connected(_refresh_arg):
			view.helm_changed.connect(_refresh_arg)

	# One redraw at start so the panel doesn't appear blank on first frame.
	queue_redraw()


func _refresh_arg(_arg: Variant = null) -> void:
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_autopilot_refresh_s += delta
	if _autopilot_refresh_s < 0.5:
		return
	_autopilot_refresh_s = 0.0
	var view := get_node_or_null("/root/LocalPlayerView")
	if view != null:
		var snapshot: Dictionary = view.get_autopilot_snapshot()
		if bool(snapshot.get("active", false)):
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		queue_redraw()


func _draw() -> void:
	var view := get_node_or_null("/root/LocalPlayerView")
	if view == null:
		return

	var marks_str := PlayerSession.format_money(view.get_marks())
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

	var autopilot: Dictionary = view.get_autopilot_snapshot()
	if bool(autopilot.get("active", false)):
		var destination_id := str(autopilot.get("destination_port_id", ""))
		var destination: String = str(view.get_port_display_name(destination_id)).to_upper()
		var remaining_nm := float(autopilot.get("remaining_distance_m", 0.0)) / 1852.0
		var ap_text := "AUTOPILOT · %s · %.1f nm" % [destination, remaining_nm]
		var watch := autopilot.get("bridge_watch", {}) as Dictionary
		if bool(watch.get("alarm_active", false)):
			ap_text = "BRIDGE WATCH ALARM · RETURN TO BRIDGE"
		var ap_w := maxf(_font.get_string_size(ap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 20.0, pw)
		var ap_rect := Rect2(ox, oy + ph + 5.0, ap_w, 30.0)
		draw_rect(ap_rect, HudStyle.C_BG)
		var ap_color := HudStyle.C_RED if bool(watch.get("alarm_active", false)) else HudStyle.C_GREEN
		draw_rect(ap_rect, ap_color, false, 1.0)
		draw_string(_font, ap_rect.position + Vector2(10.0, 20.0), ap_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ap_color)

	var contracts: Array = view.get_active_contracts()
	if contracts.is_empty():
		return
