class_name ContractJournalOverlay
extends Control

## Persistent top-right overlay that lists accepted contracts with progress.
## Auto-hides when the player has no active contracts; toggled by GameMenu
## via the `open_journal` action.

const PANEL_WIDTH  : float = 320.0
const ROW_HEIGHT   : float = 44.0
const ROW_PAD      : float = 6.0
const TITLE_HEIGHT : float = 22.0
const MARGIN       : float = 14.0

var _contracts: Array = []
var _user_hidden: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 5

	var view := get_node_or_null("/root/LocalPlayerView")
	if view != null and view.has_signal("contracts_changed"):
		view.contracts_changed.connect(_on_contracts_changed)
		view.helm_changed.connect(_on_helm_changed)
	_refresh()


func toggle() -> void:
	_user_hidden = not _user_hidden
	queue_redraw()


func _on_contracts_changed(_arr: Array) -> void:
	_refresh()


func _on_helm_changed(_boat: Node) -> void:
	queue_redraw()


func _refresh() -> void:
	var view := get_node_or_null("/root/LocalPlayerView")
	_contracts = view.get_active_contracts() if view != null else []
	queue_redraw()


func _draw() -> void:
	if _user_hidden or _contracts.is_empty():
		return

	var vp := get_viewport_rect().size
	var row_count := _contracts.size()
	var panel_h := TITLE_HEIGHT + ROW_PAD + row_count * (ROW_HEIGHT + ROW_PAD) + ROW_PAD
	var origin := Vector2(vp.x - PANEL_WIDTH - MARGIN, MARGIN + 140.0)

	# Panel background.
	var bg := Rect2(origin, Vector2(PANEL_WIDTH, panel_h))
	draw_rect(bg, HudStyle.C_BG, true)
	draw_rect(bg, HudStyle.C_BRASS, false, 1.0)

	# Title bar.
	var title_pos := origin + Vector2(10.0, TITLE_HEIGHT - 6.0)
	_draw_text("CARGO JOURNAL", title_pos, 11, HudStyle.C_LABEL)
	_draw_text("[ J ]", origin + Vector2(PANEL_WIDTH - 38.0, TITLE_HEIGHT - 6.0), 10, HudStyle.C_LABEL)
	draw_line(
		origin + Vector2(8.0, TITLE_HEIGHT),
		origin + Vector2(PANEL_WIDTH - 8.0, TITLE_HEIGHT),
		HudStyle.C_SEP, 1.0
	)

	# Rows.
	var y := origin.y + TITLE_HEIGHT + ROW_PAD
	for raw in _contracts:
		var c := raw as Contract
		if c == null:
			continue
		_draw_row(c, Vector2(origin.x + 8.0, y))
		y += ROW_HEIGHT + ROW_PAD


func _draw_row(c: Contract, p: Vector2) -> void:
	var view := get_node_or_null("/root/LocalPlayerView")
	var origin_name : String = view.get_port_display_name(c.origin_port_id) if view != null else c.origin_port_id
	var dest_name   : String = view.get_port_display_name(c.destination_port_id) if view != null else c.destination_port_id

	var route := "%s → %s" % [origin_name, dest_name]
	_draw_text(c.display_name, p + Vector2(0.0, 0.0), 12, HudStyle.C_TEXT)
	_draw_text(route, p + Vector2(0.0, 14.0), 10, HudStyle.C_LABEL)

	# Progress bar.
	var bar_x := p.x
	var bar_y := p.y + 26.0
	var bar_w := PANEL_WIDTH - 32.0
	var bar_h := 6.0
	var qty := maxi(c.quantity, 1)
	var delivered_frac := clampf(float(c.delivered_count) / float(qty), 0.0, 1.0)
	var taken_frac     := clampf(float(c.taken_count) / float(qty), 0.0, 1.0)

	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), HudStyle.C_BG_INNER, true)
	# In-transit (taken but not delivered) renders dim amber.
	draw_rect(Rect2(bar_x, bar_y, bar_w * taken_frac, bar_h),
		Color(HudStyle.C_AMBER.r, HudStyle.C_AMBER.g, HudStyle.C_AMBER.b, 0.45), true)
	# Delivered portion renders solid amber.
	draw_rect(Rect2(bar_x, bar_y, bar_w * delivered_frac, bar_h),
		HudStyle.C_AMBER, true)
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), HudStyle.C_BRASS, false, 1.0)

	# Numbers right-aligned.
	var counts := "%d / %d delivered" % [c.delivered_count, c.quantity]
	_draw_text(counts, Vector2(bar_x + bar_w - 100.0, p.y + 14.0), 10, HudStyle.C_LABEL)


func _draw_text(text: String, pos: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
