class_name HudStyle
extends RefCounted

## Shared UI palette and theme helpers.
## Maritime / weathered-steel aesthetic pulled directly from game materials.
## Dark hull-black backgrounds, brass borders, warm amber for active state.
## No blue. No sci-fi glow.

# ── Palette ───────────────────────────────────────────────────────────────────

## Hull-dark — near-black with warm undertone, like painted steel interior
const C_BG        := Color(0.08, 0.07, 0.06, 0.92)
## Slightly lifted for nested elements
const C_BG_INNER  := Color(0.13, 0.11, 0.09, 0.90)
## Weathered brass — borders, rings, fittings
const C_BRASS     := Color(0.32, 0.27, 0.19, 0.80)
## Very subtle warm separator
const C_SEP       := Color(0.20, 0.17, 0.13, 0.55)

## Primary text — aged off-white parchment
const C_TEXT      := Color(0.88, 0.84, 0.74, 0.95)
## Dim label — stencilled steel, small captions
const C_LABEL     := Color(0.48, 0.44, 0.36, 0.70)

## Warm amber — cabin window light, active state
const C_AMBER     := Color(0.96, 0.76, 0.28, 0.95)
## Muted starboard green — maritime, not neon
const C_GREEN     := Color(0.34, 0.64, 0.38, 0.90)
## Anti-fouling hull red — port nav, danger
const C_RED       := Color(0.76, 0.24, 0.16, 0.90)

## Inactive segment fills
const C_GREEN_DIM := Color(0.08, 0.20, 0.10, 0.65)
const C_RED_DIM   := Color(0.24, 0.07, 0.05, 0.60)
const C_GREY_DIM  := Color(0.18, 0.16, 0.14, 0.55)


# ── Godot Theme ───────────────────────────────────────────────────────────────

## Returns a Theme that can be assigned to any Panel-based NPC or menu UI.
## Child Labels, Buttons, and HSeparators inherit the style automatically.
static func make_theme() -> Theme:
	var t := Theme.new()

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color     = C_BG
	panel_sb.border_color = C_BRASS
	panel_sb.set_border_width_all(1)
	t.set_stylebox("panel", "Panel", panel_sb)

	t.set_color("font_color", "Label", C_TEXT)

	t.set_stylebox("normal",   "Button", _btn_sb(C_BG_INNER,                            C_BRASS, 1))
	t.set_stylebox("hover",    "Button", _btn_sb(Color(0.15, 0.12, 0.09, 0.92), C_AMBER, 1))
	t.set_stylebox("pressed",  "Button", _btn_sb(Color(0.18, 0.15, 0.11, 0.95), C_AMBER, 2))
	t.set_stylebox("disabled", "Button", _btn_sb(Color(0.07, 0.06, 0.05, 0.70), C_SEP,   1))
	t.set_stylebox("focus",    "Button", _btn_sb(Color(0.15, 0.12, 0.09, 0.92), C_AMBER, 1))
	t.set_color("font_color",          "Button", C_TEXT)
	t.set_color("font_hover_color",    "Button", C_AMBER)
	t.set_color("font_pressed_color",  "Button", C_AMBER)
	t.set_color("font_disabled_color", "Button", C_LABEL)

	var sep_sb := StyleBoxFlat.new()
	sep_sb.bg_color = C_SEP
	sep_sb.set_content_margin_all(0)
	t.set_stylebox("separator", "HSeparator", sep_sb)
	t.set_constant("separation", "HSeparator", 1)

	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	return t


static func _btn_sb(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color   = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin(SIDE_LEFT,   10)
	sb.set_content_margin(SIDE_RIGHT,  10)
	sb.set_content_margin(SIDE_TOP,     6)
	sb.set_content_margin(SIDE_BOTTOM,  6)
	return sb
