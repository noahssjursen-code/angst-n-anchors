class_name UiThemeBuilder
extends RefCounted

## Builds the single project Theme (`resources/ui/angst_theme.tres`).
##
## Every Control in the game — HUDs, menus, editors, showcases — inherits this
## through `gui/theme/custom`, so stock Godot widgets already wear the quayside
## look. Named type variations (`Ui.*` factories set them) cover signage
## headings, keycaps, instrument readouts and the different panel weights.
## Regenerate with `tests/ui_theme_generate.tscn` after changing tokens.

const THEME_PATH := "res://resources/ui/angst_theme.tres"

const P := preload("res://scripts/ui/kit/ui_palette.gd")


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = P.body()
	t.default_font_size = P.SIZE_BODY
	_labels(t)
	_panels(t)
	_buttons(t)
	_inputs(t)
	_choices(t)
	_ranges(t)
	_lists(t)
	_containers(t)
	_windows(t)
	return t


static func save(path: String = THEME_PATH) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return ResourceSaver.save(build(), path)


# ── Style primitives ─────────────────────────────────────────────────────────

static func box(bg: Color, border: Color = Color(0, 0, 0, 0), width: int = 0,
		margin_h: float = 12.0, margin_v: float = 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(P.RADIUS)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	sb.anti_aliasing = false
	return sb


static func edge_box(bg: Color, edge: Color, side: int = SIDE_LEFT,
		margin_h: float = 14.0, margin_v: float = 10.0) -> StyleBoxFlat:
	var sb := box(bg, Color(0, 0, 0, 0), 0, margin_h, margin_v)
	sb.border_color = edge
	match side:
		SIDE_LEFT:   sb.border_width_left = P.EDGE
		SIDE_RIGHT:  sb.border_width_right = P.EDGE
		SIDE_TOP:    sb.border_width_top = P.EDGE
		SIDE_BOTTOM: sb.border_width_bottom = P.EDGE
	if side == SIDE_LEFT:
		sb.content_margin_left = margin_h + P.EDGE
	return sb


static func empty(margin_h: float = 0.0, margin_v: float = 0.0) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	return sb


static func line(color: Color, thickness: int = 1, vertical: bool = false) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = color
	sb.thickness = thickness
	sb.vertical = vertical
	return sb


static func spaced(font: Font, glyph_spacing: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = font
	fv.spacing_glyph = glyph_spacing
	return fv


# ── Sections ─────────────────────────────────────────────────────────────────

static func _label_variation(t: Theme, name: String, font: Font, size: int,
		color: Color, outline: int = 0) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)
	if outline > 0:
		t.set_constant("outline_size", name, outline)
		t.set_color("font_outline_color", name, Color(0, 0, 0, 0.75))


static func _labels(t: Theme) -> void:
	t.set_font("font", "Label", P.body())
	t.set_font_size("font_size", "Label", P.SIZE_BODY)
	t.set_color("font_color", "Label", P.PAINT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("line_spacing", "Label", 2)

	var sign_spaced := spaced(P.sign(), 2)
	var sign_wide := spaced(P.sign_bold(), 1)
	_label_variation(t, "Hero", sign_wide, P.SIZE_HERO, P.PAINT)
	_label_variation(t, "Display", sign_wide, P.SIZE_DISPLAY, P.PAINT)
	_label_variation(t, "Heading", P.sign(), P.SIZE_HEADING, P.PAINT)
	_label_variation(t, "Title", P.strong(), P.SIZE_TITLE, P.PAINT)
	_label_variation(t, "Lead", P.medium(), P.SIZE_LEAD, P.PAINT)
	_label_variation(t, "Body", P.body(), P.SIZE_BODY, P.PAINT)
	_label_variation(t, "Muted", P.body(), P.SIZE_BODY, P.PAINT_MUTED)
	_label_variation(t, "Caption", P.medium(), P.SIZE_CAPTION, P.PAINT_MUTED)
	_label_variation(t, "Eyebrow", sign_spaced, P.SIZE_CAPTION, P.CRANE)
	_label_variation(t, "FieldLabel", sign_spaced, P.SIZE_MICRO + 1, P.PAINT_FAINT)
	_label_variation(t, "Value", P.strong(), P.SIZE_BODY, P.PAINT)
	_label_variation(t, "Metric", P.mono(), 28, P.PAINT)
	_label_variation(t, "MetricSmall", P.mono(), P.SIZE_BODY, P.PAINT)
	_label_variation(t, "HudText", P.medium(), P.SIZE_BODY, P.PAINT, 3)
	_label_variation(t, "HudSign", sign_spaced, P.SIZE_LEAD, P.PAINT, 4)

	_label_variation(t, "Keycap", P.sign_bold(), 15, P.ON_CRANE)
	t.set_stylebox("normal", "Keycap", box(P.CRANE, Color(0, 0, 0, 0), 0, 7.0, 1.0))
	_label_variation(t, "Badge", sign_spaced, P.SIZE_MICRO + 1, P.PAINT)
	t.set_stylebox("normal", "Badge", box(Color(0, 0, 0, 0), P.KERB_STRONG, 1, 7.0, 1.0))

	t.set_font("normal_font", "RichTextLabel", P.body())
	t.set_font("bold_font", "RichTextLabel", P.strong())
	t.set_font("italics_font", "RichTextLabel", P.medium())
	t.set_font("mono_font", "RichTextLabel", P.mono())
	t.set_font_size("normal_font_size", "RichTextLabel", P.SIZE_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", P.SIZE_BODY)
	t.set_font_size("mono_font_size", "RichTextLabel", P.SIZE_BODY - 1)
	t.set_color("default_color", "RichTextLabel", P.PAINT)
	t.set_color("selection_color", "RichTextLabel", P.with_alpha(P.CRANE, 0.35))
	t.set_stylebox("normal", "RichTextLabel", empty())
	t.set_stylebox("focus", "RichTextLabel", empty())


static func _panel_variation(t: Theme, name: String, base: String, sb: StyleBox) -> void:
	t.set_type_variation(name, base)
	t.set_stylebox("panel", name, sb)


static func _panels(t: Theme) -> void:
	t.set_stylebox("panel", "Panel", box(P.ASPHALT, P.KERB, 1))
	t.set_stylebox("panel", "PanelContainer", box(P.ASPHALT, P.KERB, 1, 18.0, 16.0))

	_panel_variation(t, "Sheet", "PanelContainer", box(P.ASPHALT, P.KERB, 1, 28.0, 24.0))
	_panel_variation(t, "Card", "PanelContainer", box(P.ASPHALT_RAISED, Color(0, 0, 0, 0), 0, 16.0, 12.0))
	_panel_variation(t, "Inset", "PanelContainer", box(P.ASPHALT_DEEP, P.KERB, 1, 12.0, 10.0))
	_panel_variation(t, "Plate", "PanelContainer", box(P.HUD_GLASS, Color(0, 0, 0, 0), 0, 12.0, 7.0))
	_panel_variation(t, "Bare", "PanelContainer", empty())
	_panel_variation(t, "SignalCard", "PanelContainer", edge_box(P.ASPHALT_RAISED, P.CRANE))
	_panel_variation(t, "InfoCard", "PanelContainer", edge_box(P.ASPHALT_RAISED, P.FJORD))
	_panel_variation(t, "OkCard", "PanelContainer", edge_box(P.ASPHALT_RAISED, P.STARBOARD))
	_panel_variation(t, "DangerCard", "PanelContainer", edge_box(P.ASPHALT_RAISED, P.PORT_RED))
	_panel_variation(t, "CautionCard", "PanelContainer", edge_box(P.ASPHALT_RAISED, P.ORE))
	_panel_variation(t, "Toast", "PanelContainer", edge_box(P.ASPHALT_DEEP, P.CRANE, SIDE_LEFT, 16.0, 10.0))
	_panel_variation(t, "Rail", "PanelContainer", box(P.ASPHALT_DEEP, Color(0, 0, 0, 0), 0, 0.0, 0.0))
	_panel_variation(t, "Scrim", "Panel", box(P.SCRIM))

	var header := box(P.ASPHALT_DEEP, P.KERB, 0, 28.0, 14.0)
	header.border_width_bottom = 1
	_panel_variation(t, "SheetHeader", "PanelContainer", header)

	t.set_stylebox("separator", "HSeparator", line(P.KERB, 1))
	t.set_constant("separation", "HSeparator", 10)
	t.set_stylebox("separator", "VSeparator", line(P.KERB, 1, true))
	t.set_constant("separation", "VSeparator", 10)


static func _button_states(t: Theme, name: String, normal: StyleBox, hover: StyleBox,
		pressed: StyleBox, disabled: StyleBox, font: Font, size: int,
		text: Color, text_hover: Color, text_pressed: Color, text_disabled: Color) -> void:
	t.set_stylebox("normal", name, normal)
	t.set_stylebox("hover", name, hover)
	t.set_stylebox("pressed", name, pressed)
	t.set_stylebox("hover_pressed", name, pressed)
	t.set_stylebox("disabled", name, disabled)
	var focus := box(Color(0, 0, 0, 0), P.CRANE, 2)
	focus.draw_center = false
	t.set_stylebox("focus", name, focus)
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, text)
	t.set_color("font_hover_color", name, text_hover)
	t.set_color("font_focus_color", name, text_hover)
	t.set_color("font_pressed_color", name, text_pressed)
	t.set_color("font_hover_pressed_color", name, text_pressed)
	t.set_color("font_disabled_color", name, text_disabled)
	t.set_color("icon_normal_color", name, text)
	t.set_color("icon_hover_color", name, text_hover)
	t.set_color("icon_pressed_color", name, text_pressed)
	t.set_color("icon_disabled_color", name, text_disabled)
	t.set_constant("h_separation", name, 8)


static func _buttons(t: Theme) -> void:
	_button_states(t, "Button",
		box(P.ASPHALT_RAISED, P.KERB_STRONG, 1, 14.0, 7.0),
		box(P.ASPHALT_HOVER, P.CRANE, 1, 14.0, 7.0),
		box(P.CRANE_DEEP, P.CRANE, 1, 14.0, 7.0),
		box(P.with_alpha(P.ASPHALT_RAISED, 0.5), P.KERB, 1, 14.0, 7.0),
		P.strong(), P.SIZE_BODY, P.PAINT, P.CRANE_HOVER, P.PAINT, P.PAINT_FAINT)

	t.set_type_variation("PrimaryButton", "Button")
	var sign_btn := spaced(P.sign_bold(), 1)
	_button_states(t, "PrimaryButton",
		box(P.CRANE, Color(0, 0, 0, 0), 0, 22.0, 9.0),
		box(P.CRANE_HOVER, Color(0, 0, 0, 0), 0, 22.0, 9.0),
		box(P.CRANE_DEEP, Color(0, 0, 0, 0), 0, 22.0, 9.0),
		box(P.with_alpha(P.CRANE_DEEP, 0.45), Color(0, 0, 0, 0), 0, 22.0, 9.0),
		sign_btn, P.SIZE_LEAD + 1, P.ON_CRANE, P.ON_CRANE, P.PAINT, P.with_alpha(P.ON_CRANE, 0.6))

	t.set_type_variation("GhostButton", "Button")
	_button_states(t, "GhostButton",
		empty(10.0, 6.0),
		box(P.ASPHALT_HOVER, Color(0, 0, 0, 0), 0, 10.0, 6.0),
		box(P.CRANE_DEEP, Color(0, 0, 0, 0), 0, 10.0, 6.0),
		empty(10.0, 6.0),
		P.medium(), P.SIZE_BODY, P.PAINT_MUTED, P.PAINT, P.PAINT, P.PAINT_FAINT)

	t.set_type_variation("DangerButton", "Button")
	_button_states(t, "DangerButton",
		box(Color(0, 0, 0, 0), P.PORT_RED, 1, 14.0, 7.0),
		box(P.PORT_RED, P.PORT_RED, 1, 14.0, 7.0),
		box(P.with_alpha(P.PORT_RED, 0.7), P.PORT_RED, 1, 14.0, 7.0),
		box(Color(0, 0, 0, 0), P.KERB, 1, 14.0, 7.0),
		P.strong(), P.SIZE_BODY, P.PORT_RED, P.PAINT, P.PAINT, P.PAINT_FAINT)

	# Main-menu / list rows: a quay-edge bar lights up on hover.
	t.set_type_variation("RowButton", "Button")
	_button_states(t, "RowButton",
		edge_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), SIDE_LEFT, 16.0, 10.0),
		edge_box(P.ASPHALT_HOVER, P.CRANE, SIDE_LEFT, 16.0, 10.0),
		edge_box(P.ASPHALT_RAISED, P.CRANE, SIDE_LEFT, 16.0, 10.0),
		edge_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), SIDE_LEFT, 16.0, 10.0),
		spaced(P.sign(), 2), P.SIZE_TITLE, P.PAINT, P.CRANE_HOVER, P.CRANE, P.PAINT_FAINT)
	t.set_constant("align_to_largest_stylebox", "RowButton", 1)

	# Tabs: the selected tab carries a crane-yellow kerb underline.
	t.set_type_variation("TabButton", "Button")
	var tab_n := empty(14.0, 9.0)
	var tab_h := box(P.with_alpha(P.ASPHALT_HOVER, 0.6), Color(0, 0, 0, 0), 0, 14.0, 9.0)
	var tab_p := edge_box(Color(0, 0, 0, 0), P.CRANE, SIDE_BOTTOM, 14.0, 9.0)
	_button_states(t, "TabButton", tab_n, tab_h, tab_p, tab_n,
		spaced(P.sign(), 2), P.SIZE_LEAD - 1, P.PAINT_MUTED, P.PAINT, P.PAINT, P.PAINT_FAINT)

	# Selectable cards (starter vessels, captains, offers): crane border when chosen.
	t.set_type_variation("SelectCard", "Button")
	var sel_n := box(P.ASPHALT_RAISED, P.KERB, 1, 18.0, 16.0)
	var sel_h := box(P.ASPHALT_HOVER, P.KERB_STRONG, 1, 18.0, 16.0)
	var sel_p := box(P.ASPHALT_RAISED, P.CRANE, 2, 18.0, 16.0)
	sel_p.border_width_left = P.EDGE + 2
	_button_states(t, "SelectCard", sel_n, sel_h, sel_p, sel_n,
		P.medium(), P.SIZE_BODY, P.PAINT_MUTED, P.PAINT, P.PAINT, P.PAINT_FAINT)

	t.set_type_variation("ChipButton", "Button")
	_button_states(t, "ChipButton",
		box(Color(0, 0, 0, 0), P.KERB_STRONG, 1, 10.0, 3.0),
		box(P.ASPHALT_HOVER, P.CRANE, 1, 10.0, 3.0),
		box(P.CRANE, P.CRANE, 1, 10.0, 3.0),
		box(Color(0, 0, 0, 0), P.KERB, 1, 10.0, 3.0),
		P.medium(), P.SIZE_CAPTION, P.PAINT_MUTED, P.PAINT, P.ON_CRANE, P.PAINT_FAINT)

	for menu: String in ["MenuButton", "OptionButton"]:
		_button_states(t, menu,
			box(P.ASPHALT_DEEP, P.KERB_STRONG, 1, 12.0, 7.0),
			box(P.ASPHALT_HOVER, P.CRANE, 1, 12.0, 7.0),
			box(P.ASPHALT_RAISED, P.CRANE, 1, 12.0, 7.0),
			box(P.ASPHALT_DEEP, P.KERB, 1, 12.0, 7.0),
			P.medium(), P.SIZE_BODY, P.PAINT, P.PAINT, P.PAINT, P.PAINT_FAINT)
	t.set_icon("arrow", "OptionButton", _chevron_texture())
	t.set_constant("arrow_margin", "OptionButton", 8)

	t.set_color("font_color", "LinkButton", P.FJORD)
	t.set_color("font_hover_color", "LinkButton", P.CRANE)
	t.set_font("font", "LinkButton", P.medium())


static func _inputs(t: Theme) -> void:
	for kind: String in ["LineEdit", "TextEdit", "CodeEdit"]:
		t.set_stylebox("normal", kind, box(P.ASPHALT_DEEP, P.KERB_STRONG, 1, 10.0, 7.0))
		t.set_stylebox("focus", kind, box(P.ASPHALT_DEEP, P.CRANE, 1, 10.0, 7.0))
		t.set_stylebox("read_only", kind, box(P.with_alpha(P.ASPHALT_DEEP, 0.6), P.KERB, 1, 10.0, 7.0))
		t.set_font("font", kind, P.medium())
		t.set_font_size("font_size", kind, P.SIZE_BODY)
		t.set_color("font_color", kind, P.PAINT)
		t.set_color("font_placeholder_color", kind, P.PAINT_FAINT)
		t.set_color("font_readonly_color", kind, P.PAINT_MUTED)
		t.set_color("caret_color", kind, P.CRANE)
		t.set_color("selection_color", kind, P.with_alpha(P.CRANE, 0.35))
		t.set_color("font_selected_color", kind, P.PAINT)
	t.set_constant("caret_width", "LineEdit", 2)


static func _choices(t: Theme) -> void:
	var off := _check_texture(false, false)
	var on := _check_texture(true, false)
	var radio_off := _check_texture(false, true)
	var radio_on := _check_texture(true, true)
	for kind: String in ["CheckBox", "CheckButton"]:
		_button_states(t, kind, empty(4.0, 4.0),
			box(P.with_alpha(P.ASPHALT_HOVER, 0.5), Color(0, 0, 0, 0), 0, 4.0, 4.0),
			empty(4.0, 4.0), empty(4.0, 4.0),
			P.medium(), P.SIZE_BODY, P.PAINT, P.PAINT, P.PAINT, P.PAINT_FAINT)
		t.set_constant("h_separation", kind, 10)
	t.set_icon("checked", "CheckBox", on)
	t.set_icon("unchecked", "CheckBox", off)
	t.set_icon("radio_checked", "CheckBox", radio_on)
	t.set_icon("radio_unchecked", "CheckBox", radio_off)
	t.set_icon("checked_disabled", "CheckBox", on)
	t.set_icon("unchecked_disabled", "CheckBox", off)
	var sw_on := _switch_texture(true)
	var sw_off := _switch_texture(false)
	t.set_icon("checked", "CheckButton", sw_on)
	t.set_icon("unchecked", "CheckButton", sw_off)
	t.set_icon("checked_disabled", "CheckButton", sw_on)
	t.set_icon("unchecked_disabled", "CheckButton", sw_off)


static func _ranges(t: Theme) -> void:
	for kind: String in ["HSlider", "VSlider"]:
		var track := box(P.ASPHALT_DEEP, P.KERB, 1, 0.0, 3.0)
		var fill := box(P.CRANE_DEEP, Color(0, 0, 0, 0), 0, 0.0, 3.0)
		var fill_hl := box(P.CRANE, Color(0, 0, 0, 0), 0, 0.0, 3.0)
		t.set_stylebox("slider", kind, track)
		t.set_stylebox("grabber_area", kind, fill)
		t.set_stylebox("grabber_area_highlight", kind, fill_hl)
		var grabber := _grabber_texture(kind == "VSlider", false)
		t.set_icon("grabber", kind, grabber)
		t.set_icon("grabber_highlight", kind, _grabber_texture(kind == "VSlider", true))
		t.set_icon("grabber_disabled", kind, grabber)

	t.set_stylebox("background", "ProgressBar", box(P.ASPHALT_DEEP, P.KERB, 1, 0.0, 0.0))
	t.set_stylebox("fill", "ProgressBar", box(P.CRANE, Color(0, 0, 0, 0), 0, 0.0, 0.0))
	t.set_font("font", "ProgressBar", P.mono())
	t.set_font_size("font_size", "ProgressBar", P.SIZE_MICRO)
	t.set_color("font_color", "ProgressBar", P.PAINT)

	for bar: String in ["VScrollBar", "HScrollBar"]:
		var vertical := bar == "VScrollBar"
		var track := empty(4.0 if vertical else 0.0, 0.0 if vertical else 4.0)
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("scroll_focus", bar, track)
		var g := box(P.KERB_STRONG, Color(0, 0, 0, 0), 0, 3.0, 3.0)
		var gh := box(P.CRANE, Color(0, 0, 0, 0), 0, 3.0, 3.0)
		t.set_stylebox("grabber", bar, g)
		t.set_stylebox("grabber_highlight", bar, gh)
		t.set_stylebox("grabber_pressed", bar, gh)
		var blank := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
		for icon: String in ["increment", "increment_highlight", "increment_pressed",
				"decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(icon, bar, blank)


static func _lists(t: Theme) -> void:
	var sel := edge_box(P.with_alpha(P.CRANE, 0.16), P.CRANE, SIDE_LEFT, 6.0, 4.0)
	var hov := box(P.with_alpha(P.ASPHALT_HOVER, 0.8), Color(0, 0, 0, 0), 0, 6.0, 4.0)
	for kind: String in ["ItemList", "Tree"]:
		t.set_stylebox("panel", kind, box(P.ASPHALT_DEEP, P.KERB, 1, 4.0, 4.0))
		t.set_stylebox("focus", kind, empty())
		t.set_stylebox("selected", kind, sel)
		t.set_stylebox("selected_focus", kind, sel)
		t.set_stylebox("hovered", kind, hov)
		t.set_stylebox("cursor", kind, empty())
		t.set_stylebox("cursor_unfocused", kind, empty())
		t.set_font("font", kind, P.medium())
		t.set_font_size("font_size", kind, P.SIZE_BODY)
		t.set_color("font_color", kind, P.PAINT_MUTED)
		t.set_color("font_hovered_color", kind, P.PAINT)
		t.set_color("font_selected_color", kind, P.PAINT)
		t.set_color("guide_color", kind, P.with_alpha(P.KERB, 0.5))
		t.set_constant("v_separation", kind, 6)
		t.set_constant("h_separation", kind, 8)
	t.set_stylebox("title_button_normal", "Tree", box(P.ASPHALT_RAISED, Color(0, 0, 0, 0), 0, 6.0, 4.0))
	t.set_font("title_button_font", "Tree", spaced(P.sign(), 2))
	t.set_color("title_button_color", "Tree", P.PAINT_FAINT)

	var popup := box(P.ASPHALT_RAISED, P.KERB_STRONG, 1, 6.0, 6.0)
	popup.shadow_color = Color(0, 0, 0, 0.45)
	popup.shadow_size = 10
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", box(P.with_alpha(P.CRANE, 0.18), Color(0, 0, 0, 0), 0, 6.0, 4.0))
	t.set_stylebox("separator", "PopupMenu", line(P.KERB, 1))
	t.set_font("font", "PopupMenu", P.medium())
	t.set_font_size("font_size", "PopupMenu", P.SIZE_BODY)
	t.set_color("font_color", "PopupMenu", P.PAINT_MUTED)
	t.set_color("font_hover_color", "PopupMenu", P.PAINT)
	t.set_color("font_disabled_color", "PopupMenu", P.PAINT_FAINT)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_icon("checked", "PopupMenu", _check_texture(true, false))
	t.set_icon("unchecked", "PopupMenu", _check_texture(false, false))
	t.set_icon("radio_checked", "PopupMenu", _check_texture(true, true))
	t.set_icon("radio_unchecked", "PopupMenu", _check_texture(false, true))
	t.set_stylebox("panel", "PopupPanel", popup)

	var tip := box(P.ASPHALT_DEEP, P.CRANE_DEEP, 1, 10.0, 6.0)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font("font", "TooltipLabel", P.medium())
	t.set_font_size("font_size", "TooltipLabel", P.SIZE_CAPTION)
	t.set_color("font_color", "TooltipLabel", P.PAINT)


static func _containers(t: Theme) -> void:
	t.set_constant("separation", "BoxContainer", P.GAP_S)
	t.set_constant("separation", "VBoxContainer", P.GAP_S)
	t.set_constant("separation", "HBoxContainer", P.GAP_S)
	t.set_constant("h_separation", "GridContainer", P.GAP_M)
	t.set_constant("v_separation", "GridContainer", P.GAP_S)
	t.set_constant("h_separation", "FlowContainer", P.GAP_S)
	t.set_constant("v_separation", "FlowContainer", P.GAP_S)
	t.set_constant("h_separation", "HFlowContainer", P.GAP_S)
	t.set_constant("v_separation", "HFlowContainer", P.GAP_S)
	t.set_stylebox("panel", "ScrollContainer", empty())
	t.set_stylebox("focus", "ScrollContainer", empty())
	t.set_constant("separation", "HSplitContainer", 6)
	t.set_constant("separation", "VSplitContainer", 6)

	var tab_sel := edge_box(P.ASPHALT, P.CRANE, SIDE_TOP, 16.0, 8.0)
	var tab_un := box(P.ASPHALT_DEEP, Color(0, 0, 0, 0), 0, 16.0, 8.0)
	var tab_hov := box(P.ASPHALT_HOVER, Color(0, 0, 0, 0), 0, 16.0, 8.0)
	for kind: String in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", kind, tab_sel)
		t.set_stylebox("tab_unselected", kind, tab_un)
		t.set_stylebox("tab_hovered", kind, tab_hov)
		t.set_stylebox("tab_disabled", kind, tab_un)
		t.set_stylebox("tab_focus", kind, empty())
		t.set_font("font", kind, spaced(P.sign(), 2))
		t.set_font_size("font_size", kind, P.SIZE_LEAD - 1)
		t.set_color("font_selected_color", kind, P.PAINT)
		t.set_color("font_unselected_color", kind, P.PAINT_FAINT)
		t.set_color("font_hovered_color", kind, P.PAINT)
	t.set_stylebox("panel", "TabContainer", box(P.ASPHALT, P.KERB, 1, 16.0, 14.0))
	t.set_stylebox("tabbar_background", "TabContainer", empty())


static func _windows(t: Theme) -> void:
	var frame := box(P.ASPHALT, P.KERB_STRONG, 1, 12.0, 12.0)
	frame.border_width_top = 30
	frame.border_color = P.ASPHALT_DEEP
	frame.expand_margin_top = 30
	t.set_stylebox("embedded_border", "Window", frame)
	t.set_stylebox("embedded_unfocused_border", "Window", frame)
	t.set_font("title_font", "Window", spaced(P.sign(), 2))
	t.set_font_size("title_font_size", "Window", P.SIZE_LEAD)
	t.set_color("title_color", "Window", P.PAINT)
	t.set_stylebox("panel", "AcceptDialog", box(P.ASPHALT, Color(0, 0, 0, 0), 0, 16.0, 14.0))


# ── Generated glyph textures (no imported icon art needed) ───────────────────

static func _image(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(maxi(y0, 0), mini(y1, img.get_height())):
		for x in range(maxi(x0, 0), mini(x1, img.get_width())):
			img.set_pixel(x, y, c)


static func _check_texture(checked: bool, round_mark: bool) -> ImageTexture:
	var s := 20
	var img := _image(s, s)
	if round_mark:
		var c := Vector2(s * 0.5 - 0.5, s * 0.5 - 0.5)
		for y in s:
			for x in s:
				var d := Vector2(x, y).distance_to(c)
				if d <= 8.5 and d >= 7.0:
					img.set_pixel(x, y, P.KERB_STRONG if not checked else P.CRANE)
				elif checked and d <= 4.5:
					img.set_pixel(x, y, P.CRANE)
		return ImageTexture.create_from_image(img)
	if checked:
		_rect(img, 1, 1, s - 1, s - 1, P.CRANE)
		var pts := [Vector2i(5, 10), Vector2i(6, 11), Vector2i(7, 12), Vector2i(8, 13),
			Vector2i(9, 12), Vector2i(10, 11), Vector2i(11, 10), Vector2i(12, 9),
			Vector2i(13, 8), Vector2i(14, 7), Vector2i(15, 6)]
		for p in pts:
			_rect(img, p.x, p.y - 1, p.x + 2, p.y + 1, P.ON_CRANE)
	else:
		_rect(img, 1, 1, s - 1, 2, P.KERB_STRONG)
		_rect(img, 1, s - 2, s - 1, s - 1, P.KERB_STRONG)
		_rect(img, 1, 1, 2, s - 1, P.KERB_STRONG)
		_rect(img, s - 2, 1, s - 1, s - 1, P.KERB_STRONG)
		_rect(img, 2, 2, s - 2, s - 2, P.ASPHALT_DEEP)
	return ImageTexture.create_from_image(img)


static func _switch_texture(on: bool) -> ImageTexture:
	var img := _image(38, 20)
	_rect(img, 0, 2, 38, 18, P.CRANE_DEEP if on else P.ASPHALT_DEEP)
	_rect(img, 0, 2, 38, 3, P.KERB_STRONG)
	_rect(img, 0, 17, 38, 18, P.KERB_STRONG)
	var x0 := 20 if on else 2
	_rect(img, x0, 4, x0 + 16, 16, P.CRANE if on else P.PAINT_FAINT)
	return ImageTexture.create_from_image(img)


static func _grabber_texture(vertical: bool, hot: bool) -> ImageTexture:
	var w := 18 if vertical else 10
	var h := 10 if vertical else 18
	var img := _image(w, h)
	_rect(img, 0, 0, w, h, P.CRANE_HOVER if hot else P.CRANE)
	_rect(img, 1, 1, w - 1, h - 1, P.CRANE if hot else P.with_alpha(P.CRANE, 0.92))
	if vertical:
		_rect(img, 4, 4, w - 4, 6, P.ON_CRANE)
	else:
		_rect(img, 4, 4, 6, h - 4, P.ON_CRANE)
	return ImageTexture.create_from_image(img)


static func _chevron_texture() -> ImageTexture:
	var img := _image(12, 8)
	for i in 6:
		_rect(img, i, i, i + 2, i + 2, P.CRANE)
		_rect(img, 10 - i, i, 12 - i, i + 2, P.CRANE)
	return ImageTexture.create_from_image(img)
