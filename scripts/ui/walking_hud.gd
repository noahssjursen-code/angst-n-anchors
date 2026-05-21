class_name WalkingHud
extends Control

## Persistent on-foot HUD — marks balance and active contracts, top-left corner.
## Shown when the player is on foot; hidden by GameMenu when helming a ship.
##
## Reads through LocalPlayerView so the same code works in single-player
## (today) and multiplayer (future). Redraws only on state changes —
## per-frame redraw was wasted CPU when nothing actually changed.

var _font: Font
const PlayerSessionScript := preload("res://scripts/player/player_session.gd")


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
	var player_id := _resolve_local_player_id()

	var marks_str := PlayerSessionScript.format_money(view.get_marks())
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
	if not player_id.is_empty():
		var id_fs := 11
		var id_pad_h := 10.0
		var id_pad_v := 6.0
		var id_str := "Player: %s" % player_id
		var id_tw := _font.get_string_size(id_str, HORIZONTAL_ALIGNMENT_LEFT, -1, id_fs).x
		var id_pw := id_tw + id_pad_h * 2.0
		var id_ph := float(id_fs) + id_pad_v * 2.0
		var id_y := oy + ph + 4.0
		draw_rect(Rect2(ox, id_y, id_pw, id_ph), HudStyle.C_BG)
		draw_rect(Rect2(ox, id_y, id_pw, id_ph), HudStyle.C_BRASS, false, 1.0)
		draw_string(
			_font,
			Vector2(ox + id_pad_h, id_y + id_pad_v + id_fs - 2.0),
			id_str,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			id_fs,
			HudStyle.C_TEXT
		)

	# Player-local data (active contracts) goes through the view.
	# World-state lookups (port display names) still use the registry —
	# port catalog isn't player-specific so it stays globally accessible.
	var contracts: Array = view.get_active_contracts()
	if contracts.is_empty():
		return
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return

	var cfs   := 12
	var cph   := float(cfs) + 8.0
	var cy    := oy + ph + 6.0
	if not player_id.is_empty():
		cy += float(11) + 6.0 * 2.0 + 4.0
	var c_pad := 10.0

	for raw in contracts:
		var contract := raw as Contract
		if contract == null:
			continue
		var dest: String = registry.get_port_display_name(contract.destination_port_id)
		var in_transit: int = contract.taken_count - contract.delivered_count
		var c_str  := "%s  →  %s   ×%d" % [contract.display_name, dest, in_transit]
		var c_tw   := _font.get_string_size(c_str, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		var c_pw   := c_tw + c_pad * 2.0
		draw_rect(Rect2(ox, cy, c_pw, cph), HudStyle.C_BG)
		draw_rect(Rect2(ox, cy, c_pw, cph), HudStyle.C_BRASS, false, 1.0)
		draw_string(_font, Vector2(ox + c_pad, cy + cph - 5.0),
					c_str, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, HudStyle.C_TEXT)
		cy += cph + 3.0


func _resolve_local_player_id() -> String:
	var players := get_tree().get_nodes_in_group("player")
	for node in players:
		if node != null and node.has_method("get_network_player_id"):
			return String(node.call("get_network_player_id"))
	return ""
