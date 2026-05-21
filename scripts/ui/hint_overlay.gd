class_name HintOverlay
extends Control

## Centered, fading hint banner. Subscribes to Tutorial.hint_requested
## and renders one hint at a time — newer hints replace older ones so
## the player can't get buried under a stack.

const FADE_IN_S  : float = 0.25
const FADE_OUT_S : float = 0.6
const PANEL_MIN_W: float = 480.0
const PANEL_PAD  : float = 16.0

var _text: String = ""
var _remaining_s: float = 0.0
var _total_s:     float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 6
	var tut := get_node_or_null("/root/Tutorial")
	if tut != null and tut.has_signal("hint_requested"):
		tut.hint_requested.connect(_on_hint_requested)


func _on_hint_requested(text: String, duration_s: float) -> void:
	_text = text
	_total_s = duration_s
	_remaining_s = duration_s
	queue_redraw()


func _process(delta: float) -> void:
	if _remaining_s <= 0.0:
		return
	_remaining_s -= delta
	queue_redraw()


func _draw() -> void:
	if _remaining_s <= 0.0 or _text.is_empty():
		return

	var alpha := 1.0
	var elapsed := _total_s - _remaining_s
	if elapsed < FADE_IN_S:
		alpha = elapsed / FADE_IN_S
	elif _remaining_s < FADE_OUT_S:
		alpha = clampf(_remaining_s / FADE_OUT_S, 0.0, 1.0)

	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var font_size := 14
	var text_size := font.get_multiline_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER,
		PANEL_MIN_W - PANEL_PAD * 2.0, font_size)
	var panel_w := maxf(text_size.x + PANEL_PAD * 2.0, PANEL_MIN_W)
	var panel_h := text_size.y + PANEL_PAD * 2.0
	var origin := Vector2((vp.x - panel_w) * 0.5, vp.y * 0.18)

	var bg := HudStyle.C_BG
	bg.a *= alpha
	var border := HudStyle.C_AMBER
	border.a *= alpha
	var fg := HudStyle.C_TEXT
	fg.a *= alpha

	draw_rect(Rect2(origin, Vector2(panel_w, panel_h)), bg, true)
	draw_rect(Rect2(origin, Vector2(panel_w, panel_h)), border, false, 1.5)
	draw_multiline_string(font, origin + Vector2(PANEL_PAD, PANEL_PAD + font_size),
		_text, HORIZONTAL_ALIGNMENT_CENTER, panel_w - PANEL_PAD * 2.0, font_size, -1, fg)
