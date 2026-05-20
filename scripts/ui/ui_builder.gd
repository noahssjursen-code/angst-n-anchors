class_name UiBuilder
extends RefCounted

## Factory helpers for building maritime-styled UI fragments. All output
## uses HudStyle (warm hull-black + brass + amber) so panels, buttons,
## dialog screens, and debug overlays read as the same product.
##
## Replaces ad-hoc StyleBoxFlat construction scattered across game_menu,
## debug_draw, and dialogue panels — single source of truth for the
## visual language.

# ── Panels ───────────────────────────────────────────────────────────────────

## Build a panel-container with the maritime palette. Pass
## `min_size = Vector2(w, h)` for a fixed-size pop-up; pass Vector2.ZERO
## for "size to children".
static func panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	if min_size != Vector2.ZERO:
		p.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color     = HudStyle.C_BG
	sb.border_color = HudStyle.C_BRASS
	sb.set_border_width_all(1)
	sb.content_margin_left   = 18.0
	sb.content_margin_right  = 18.0
	sb.content_margin_top    = 14.0
	sb.content_margin_bottom = 14.0
	p.add_theme_stylebox_override("panel", sb)
	return p


## A second-tier panel — slightly lifted background for nested elements
## (status boxes, inset cards inside the main panel).
static func inner_panel(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	if min_size != Vector2.ZERO:
		p.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color     = HudStyle.C_BG_INNER
	sb.border_color = HudStyle.C_BRASS
	sb.set_border_width_all(1)
	sb.content_margin_left   = 10.0
	sb.content_margin_right  = 10.0
	sb.content_margin_top    = 6.0
	sb.content_margin_bottom = 6.0
	p.add_theme_stylebox_override("panel", sb)
	return p


# ── Text ─────────────────────────────────────────────────────────────────────

## A title — large amber centered text, used for modal headers.
static func title_label(text: String, font_size: int = 22) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl


## A small subtitle / status line under a title — dim, centred.
static func subtitle_label(text: String, font_size: int = 11) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl


## A section header — used to introduce groups of rows in a panel.
static func section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	return lbl


## A label / value row — label on the left in dim text, value on the
## right in primary colour. Use for status boxes and key/value lists.
static func key_value_row(label: String, value: String,
		value_color: Color = HudStyle.C_TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 12)
	val.add_theme_color_override("font_color", value_color)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return row


## Body text — primary palette colour, plain label.
static func body_label(text: String, font_size: int = 13) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	return lbl


# ── Buttons ──────────────────────────────────────────────────────────────────

## Maritime-styled button. `min_size` controls the button footprint;
## pass Vector2.ZERO to let the content size it.
##
## Connect the resulting button's `pressed` signal yourself; this stays
## a factory without lifecycle assumptions.
static func button(text: String, min_size: Vector2 = Vector2(264, 42)) -> Button:
	var btn := Button.new()
	btn.text = text
	if min_size != Vector2.ZERO:
		btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 14)

	btn.add_theme_stylebox_override("normal",   _btn_sb(HudStyle.C_BG_INNER,
													     HudStyle.C_BRASS, 1))
	btn.add_theme_stylebox_override("hover",    _btn_sb(Color(0.15, 0.12, 0.09, 0.92),
													     HudStyle.C_AMBER, 1))
	btn.add_theme_stylebox_override("pressed",  _btn_sb(Color(0.18, 0.15, 0.11, 0.96),
													     HudStyle.C_AMBER, 2))
	btn.add_theme_stylebox_override("focus",    _btn_sb(Color(0.15, 0.12, 0.09, 0.92),
													     HudStyle.C_AMBER, 1))
	btn.add_theme_stylebox_override("disabled", _btn_sb(Color(0.07, 0.06, 0.05, 0.70),
													     HudStyle.C_SEP, 1))
	btn.add_theme_color_override("font_color",         HudStyle.C_TEXT)
	btn.add_theme_color_override("font_hover_color",   HudStyle.C_AMBER)
	btn.add_theme_color_override("font_pressed_color", HudStyle.C_AMBER)
	btn.add_theme_color_override("font_disabled_color", HudStyle.C_LABEL)
	return btn


# ── Separators ───────────────────────────────────────────────────────────────

## Thin horizontal separator in the maritime palette.
static func separator() -> HSeparator:
	var sep := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = HudStyle.C_SEP
	sb.content_margin_top    = 3.0
	sb.content_margin_bottom = 3.0
	sep.add_theme_stylebox_override("separator", sb)
	return sep


# ── Internals ────────────────────────────────────────────────────────────────

static func _btn_sb(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color     = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin(SIDE_LEFT,   12)
	sb.set_content_margin(SIDE_RIGHT,  12)
	sb.set_content_margin(SIDE_TOP,     6)
	sb.set_content_margin(SIDE_BOTTOM,  6)
	return sb
