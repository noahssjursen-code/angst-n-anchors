class_name WalkingHud
extends Control

## Persistent on-foot HUD — marks balance and active contracts, top-left corner.
## Shown when the player is on foot; hidden by GameMenu when helming a ship.
##
## Reads through LocalPlayerView so the same code works in single-player
## (today) and multiplayer (future). Redraws only on state changes —
## per-frame redraw was wasted CPU when nothing actually changed.

var _font: Font


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

	# Player-local contracts deferred until trade rewrite.
	var contracts: Array = view.get_active_contracts()
	if contracts.is_empty():
		return
