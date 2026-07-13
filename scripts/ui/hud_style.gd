class_name HudStyle
extends RefCounted

## Shared UI palette, fonts, and theme helpers.
## Brand: cold North-Sea harbour desk — ink panels, chart rules, weathered
## copper, buoy-signal orange. Not fantasy brass / parchment gold.
## No purple. No sci-fi glow. Ocean backdrop always remains visible.

# ── Palette ───────────────────────────────────────────────────────────────────

## Translucent fjord ink — panels sit on the water, never brick walls.
const C_BG        := Color(0.035, 0.055, 0.065, 0.72)
## Slightly lifted inset wells
const C_BG_INNER  := Color(0.06, 0.09, 0.10, 0.82)
## Chart rule — cold green-grey hairlines
const C_BRASS     := Color(0.52, 0.60, 0.56, 0.55)
## Quiet divider
const C_SEP       := Color(0.28, 0.34, 0.32, 0.45)

## Foam / instrument white — titles and primary copy
const C_TEXT      := Color(0.90, 0.93, 0.91, 0.96)
## Muted chart annotation
const C_LABEL     := Color(0.55, 0.62, 0.60, 0.78)

## Buoy signal — primary CTA / active selection (was warm amber)
const C_AMBER     := Color(0.93, 0.45, 0.18, 0.96)
## Weathered copper — secondary accent, brand underline
const C_COPPER    := Color(0.70, 0.46, 0.30, 0.92)
## Starboard / ok
const C_GREEN     := Color(0.28, 0.62, 0.48, 0.90)
## Port / danger
const C_RED       := Color(0.78, 0.26, 0.20, 0.90)

const C_GREEN_DIM := Color(0.06, 0.18, 0.14, 0.65)
const C_RED_DIM   := Color(0.22, 0.07, 0.06, 0.60)
const C_GREY_DIM  := Color(0.14, 0.16, 0.16, 0.55)

const FONT_DISPLAY_PATH := "res://resources/fonts/BebasNeue-Regular.ttf"
const FONT_BODY_PATH := "res://resources/fonts/IBMPlexSans-Regular.ttf"
const FONT_MEDIUM_PATH := "res://resources/fonts/IBMPlexSans-Medium.ttf"
const FONT_BOLD_PATH := "res://resources/fonts/IBMPlexSans-SemiBold.ttf"

static var _font_display: Font
static var _font_body: Font
static var _font_medium: Font
static var _font_bold: Font


static func font_display() -> Font:
	if _font_display == null:
		_font_display = _load_font(FONT_DISPLAY_PATH)
	return _font_display


static func font_body() -> Font:
	if _font_body == null:
		_font_body = _load_font(FONT_BODY_PATH)
	return _font_body


static func font_medium() -> Font:
	if _font_medium == null:
		_font_medium = _load_font(FONT_MEDIUM_PATH)
	return _font_medium


static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = _load_font(FONT_BOLD_PATH)
	return _font_bold


static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var font := load(path) as Font
		if font != null:
			return font
	return ThemeDB.fallback_font


# ── Godot Theme ───────────────────────────────────────────────────────────────

## Returns a Theme that can be assigned to any Panel-based NPC or menu UI.
static func make_theme() -> Theme:
	var t := Theme.new()
	var body := font_body()
	var medium := font_medium()
	if body != null:
		t.set_default_font(body)
	t.set_default_font_size(14)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = C_BG
	panel_sb.border_color = C_BRASS
	panel_sb.set_border_width_all(1)
	panel_sb.content_margin_left = 18
	panel_sb.content_margin_right = 18
	panel_sb.content_margin_top = 16
	panel_sb.content_margin_bottom = 16
	t.set_stylebox("panel", "Panel", panel_sb)
	t.set_stylebox("panel", "PanelContainer", panel_sb)

	t.set_color("font_color", "Label", C_TEXT)
	if body != null:
		t.set_font("font", "Label", body)

	t.set_stylebox("normal", "Button", _btn_sb(C_BG_INNER, C_BRASS, 1))
	t.set_stylebox("hover", "Button", _btn_sb(Color(0.10, 0.14, 0.15, 0.92), C_AMBER, 1))
	t.set_stylebox("pressed", "Button", _btn_sb(Color(0.12, 0.16, 0.17, 0.95), C_AMBER, 2))
	t.set_stylebox("disabled", "Button", _btn_sb(Color(0.05, 0.06, 0.07, 0.55), C_SEP, 1))
	t.set_stylebox("focus", "Button", _btn_sb(Color(0.10, 0.14, 0.15, 0.92), C_COPPER, 1))
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_AMBER)
	t.set_color("font_pressed_color", "Button", C_AMBER)
	t.set_color("font_disabled_color", "Button", C_LABEL)
	if medium != null:
		t.set_font("font", "Button", medium)

	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = C_SEP
	sep_sb.set_content_margin_all(0)
	t.set_stylebox("separator", "HSeparator", sep_sb)
	t.set_constant("separation", "HSeparator", 1)

	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t


## Title-screen panel: more transparent, copper outer rule.
static func make_title_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.06, 0.55)
	sb.border_color = C_COPPER
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	return sb


static func apply_display_font(label: Label, size: int, color: Color = C_TEXT) -> void:
	var font := font_display()
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


static func apply_body_font(control: Control, size: int, color: Color = C_TEXT, bold: bool = false) -> void:
	var font := font_bold() if bold else font_body()
	if font != null:
		control.add_theme_font_override("font", font)
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)


static func _btn_sb(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin(SIDE_LEFT, 14)
	sb.set_content_margin(SIDE_RIGHT, 14)
	sb.set_content_margin(SIDE_TOP, 8)
	sb.set_content_margin(SIDE_BOTTOM, 8)
	return sb
