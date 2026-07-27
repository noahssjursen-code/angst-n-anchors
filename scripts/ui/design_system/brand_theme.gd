class_name BrandTheme
extends RefCounted

## Single theme authority for every game and authoring UI surface.

const FONT_DIR := "res://resources/fonts/brand/"
const FONT_DISPLAY_BOLD := FONT_DIR + "SairaCondensed-Bold.ttf"
const FONT_DISPLAY_SEMIBOLD := FONT_DIR + "SairaCondensed-SemiBold.ttf"
const FONT_UI := FONT_DIR + "Saira-Variable.ttf"
const FONT_DATA := FONT_DIR + "JetBrainsMono-Variable.ttf"
const FONT_CYRILLIC_UI := FONT_DIR + "PTSans-Regular.ttf"
const FONT_CYRILLIC_UI_BOLD := FONT_DIR + "PTSans-Bold.ttf"
const FONT_CYRILLIC_DISPLAY := FONT_DIR + "PTSansNarrow-Bold.ttf"

static var _theme: Theme
static var _display: Font
static var _display_semibold: Font
static var _ui: Font
static var _data: Font


static func shared() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


static func invalidate() -> void:
	_theme = null


static func apply_display_font(
		label: Label,
		size: int,
		color: Color = BrandTokens.INK
	) -> void:
	label.add_theme_font_override(&"font", font_display())
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)


static func apply_body_font(
		control: Control,
		size: int,
		color: Color = BrandTokens.INK_BODY,
		bold: bool = false
	) -> void:
	control.add_theme_font_override(&"font", font_display_semibold() if bold else font_ui())
	control.add_theme_font_size_override(&"font_size", size)
	control.add_theme_color_override(&"font_color", color)


static func ruled_panel_style(dark: bool = false) -> StyleBox:
	var type_name := &"BrandDarkRuledPanel" if dark else &"BrandRuledPanel"
	return shared().get_stylebox(&"panel", type_name).duplicate()


static func font_display() -> Font:
	if _display == null:
		_display = _load_font(FONT_DISPLAY_BOLD, FONT_CYRILLIC_DISPLAY)
	return _display


static func font_display_semibold() -> Font:
	if _display_semibold == null:
		_display_semibold = _load_font(FONT_DISPLAY_SEMIBOLD, FONT_CYRILLIC_UI_BOLD)
	return _display_semibold


static func font_ui() -> Font:
	if _ui == null:
		_ui = _load_font(FONT_UI, FONT_CYRILLIC_UI)
	return _ui


static func font_body() -> Font:
	return font_ui()


static func font_medium() -> Font:
	return font_ui()


static func font_bold() -> Font:
	return font_display_semibold()


static func font_data() -> Font:
	if _data == null:
		_data = _load_font(FONT_DATA)
	return _data


static func _load_font(path: String, fallback_path: String = "") -> Font:
	var resource := load(path) as Font
	if resource == null:
		push_error("BrandTheme: font missing at %s" % path)
		return ThemeDB.fallback_font
	if not fallback_path.is_empty():
		var fallback := load(fallback_path) as Font
		if fallback == null:
			push_error("BrandTheme: fallback font missing at %s" % fallback_path)
		else:
			resource.set_fallbacks([fallback])
	return resource


static func _build_theme() -> Theme:
	var theme := Theme.new()
	theme.set_default_font(font_ui())
	theme.set_default_font_size(BrandTokens.BODY)

	_define_type_variations(theme)
	_style_labels(theme)
	_style_panels(theme)
	_style_buttons(theme)
	_style_fields(theme)
	_style_tabs(theme)
	_style_lists(theme)
	_style_ranges(theme)
	_style_separators(theme)
	_style_misc(theme)
	return theme


static func _define_type_variations(theme: Theme) -> void:
	theme.set_type_variation(&"BrandDisplayLarge", &"Label")
	theme.set_type_variation(&"BrandDisplayMedium", &"Label")
	theme.set_type_variation(&"BrandDisplaySmall", &"Label")
	theme.set_type_variation(&"BrandBody", &"Label")
	theme.set_type_variation(&"BrandBodyMuted", &"Label")
	theme.set_type_variation(&"BrandData", &"Label")
	theme.set_type_variation(&"BrandDataMuted", &"Label")
	theme.set_type_variation(&"BrandMicroData", &"Label")
	theme.set_type_variation(&"BrandInverseBody", &"Label")
	theme.set_type_variation(&"BrandInverseData", &"Label")
	theme.set_type_variation(&"BrandSectionLabel", &"Label")
	theme.set_type_variation(&"BrandStatusOk", &"Label")
	theme.set_type_variation(&"BrandStatusWarn", &"Label")
	theme.set_type_variation(&"BrandStatusAlert", &"Label")

	theme.set_type_variation(&"BrandSurfacePanel", &"PanelContainer")
	theme.set_type_variation(&"BrandRaisedPanel", &"PanelContainer")
	theme.set_type_variation(&"BrandRuledPanel", &"PanelContainer")
	theme.set_type_variation(&"BrandDarkPanel", &"PanelContainer")
	theme.set_type_variation(&"BrandDarkRuledPanel", &"PanelContainer")
	theme.set_type_variation(&"BrandBand", &"PanelContainer")
	theme.set_type_variation(&"BrandToolbarPanel", &"PanelContainer")

	theme.set_type_variation(&"BrandPrimaryButton", &"Button")
	theme.set_type_variation(&"BrandSecondaryButton", &"Button")
	theme.set_type_variation(&"BrandLoudButton", &"Button")
	theme.set_type_variation(&"BrandQuietButton", &"Button")
	theme.set_type_variation(&"BrandDangerButton", &"Button")
	theme.set_type_variation(&"BrandChipButton", &"Button")
	theme.set_type_variation(&"BrandMenuButton", &"Button")


static func _style_labels(theme: Theme) -> void:
	theme.set_font(&"font", &"Label", font_ui())
	theme.set_font_size(&"font_size", &"Label", BrandTokens.BODY)
	theme.set_color(&"font_color", &"Label", BrandTokens.INK_BODY)

	_label(theme, &"BrandDisplayLarge", font_display(), BrandTokens.DISPLAY_L, BrandTokens.INK)
	_label(theme, &"BrandDisplayMedium", font_display(), BrandTokens.DISPLAY_M, BrandTokens.INK)
	_label(theme, &"BrandDisplaySmall", font_display(), BrandTokens.DISPLAY_S, BrandTokens.INK)
	_label(theme, &"BrandBody", font_ui(), BrandTokens.BODY, BrandTokens.INK_BODY)
	_label(theme, &"BrandBodyMuted", font_ui(), BrandTokens.BODY, BrandTokens.INK_MUTED)
	_label(theme, &"BrandData", font_data(), BrandTokens.DATA_MONO, BrandTokens.INK)
	_label(theme, &"BrandDataMuted", font_data(), BrandTokens.LABEL_MONO, BrandTokens.INK_MUTED)
	_label(theme, &"BrandMicroData", font_data(), BrandTokens.MICRO_MONO, BrandTokens.INK_MUTED)
	_label(theme, &"BrandInverseBody", font_ui(), BrandTokens.BODY, BrandTokens.INK_INVERSE)
	_label(theme, &"BrandInverseData", font_data(), BrandTokens.DATA_MONO, BrandTokens.BRASS)
	_label(theme, &"BrandSectionLabel", font_data(), BrandTokens.LABEL_MONO, BrandTokens.INK_MUTED)
	_label(theme, &"BrandStatusOk", font_data(), BrandTokens.LABEL_MONO, BrandTokens.OK)
	_label(theme, &"BrandStatusWarn", font_data(), BrandTokens.LABEL_MONO, BrandTokens.WARN)
	_label(theme, &"BrandStatusAlert", font_data(), BrandTokens.LABEL_MONO, BrandTokens.ALERT)


static func _style_panels(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"Panel", _box(BrandTokens.PAPER, BrandTokens.SURFACE_EDGE, 1, 0))
	theme.set_stylebox(&"panel", &"PanelContainer", _box(
		BrandTokens.PAPER, BrandTokens.SURFACE_EDGE, 1, BrandTokens.PANEL_PADDING
	))
	theme.set_stylebox(&"panel", &"BrandSurfacePanel", _box(
		BrandTokens.SURFACE, BrandTokens.SURFACE_EDGE, 1, BrandTokens.CARD_PADDING
	))
	theme.set_stylebox(&"panel", &"BrandRaisedPanel", _box(
		BrandTokens.PAPER_HIGH, BrandTokens.SURFACE_EDGE, 1, BrandTokens.CARD_PADDING
	))
	theme.set_stylebox(&"panel", &"BrandRuledPanel", _ruled_box(
		BrandTokens.PAPER, BrandTokens.SURFACE_EDGE, BrandTokens.BRASS, BrandTokens.PANEL_PADDING
	))
	theme.set_stylebox(&"panel", &"BrandDarkPanel", _box(
		BrandTokens.SEA, BrandTokens.SEA_LINE, 1, BrandTokens.PANEL_PADDING
	))
	theme.set_stylebox(&"panel", &"BrandDarkRuledPanel", _ruled_box(
		BrandTokens.SEA, BrandTokens.SEA_LINE, BrandTokens.BRASS, BrandTokens.PANEL_PADDING
	))
	theme.set_stylebox(&"panel", &"BrandBand", _box(
		BrandTokens.INK, BrandTokens.INK, 0, BrandTokens.SPACE_SM
	))
	theme.set_stylebox(&"panel", &"BrandToolbarPanel", _box(
		BrandTokens.PAPER, BrandTokens.SURFACE_EDGE, 1, BrandTokens.SPACE_SM
	))


static func _style_buttons(theme: Theme) -> void:
	_button_type(
		theme, &"Button", BrandTokens.PAPER_HIGH, BrandTokens.INK_BODY,
		BrandTokens.SURFACE_EDGE, BrandTokens.PAPER_LOW, BrandTokens.INK,
		BrandTokens.BRASS
	)
	_button_type(
		theme, &"BrandPrimaryButton", BrandTokens.SEA, BrandTokens.INK_INVERSE,
		BrandTokens.SEA, BrandTokens.SEA_RAISED, BrandTokens.INK_INVERSE,
		BrandTokens.BRASS
	)
	_button_type(
		theme, &"BrandSecondaryButton", BrandTokens.PAPER_HIGH, BrandTokens.INK_BODY,
		BrandTokens.SURFACE_EDGE, BrandTokens.PAPER_LOW, BrandTokens.INK,
		BrandTokens.BRASS
	)
	_button_type(
		theme, &"BrandLoudButton", BrandTokens.BRASS, BrandTokens.INK,
		BrandTokens.BRASS, BrandTokens.BRASS_LIGHT, BrandTokens.INK,
		BrandTokens.BRASS_SHADE
	)
	_button_type(
		theme, &"BrandDangerButton", BrandTokens.ALERT, BrandTokens.INK_INVERSE,
		BrandTokens.ALERT, BrandTokens.ALERT_DEEP, BrandTokens.INK_INVERSE,
		BrandTokens.ALERT_DEEP
	)
	_button_type(
		theme, &"BrandChipButton", BrandTokens.PAPER_HIGH, BrandTokens.INK_MUTED,
		BrandTokens.SURFACE_EDGE, BrandTokens.SEA, BrandTokens.INK_INVERSE,
		BrandTokens.BRASS
	)
	_button_type(
		theme, &"BrandQuietButton", Color.TRANSPARENT, BrandTokens.INK_BODY,
		Color.TRANSPARENT, BrandTokens.PAPER_LOW, BrandTokens.INK,
		BrandTokens.BRASS
	)

	var menu_empty := StyleBoxEmpty.new()
	menu_empty.content_margin_left = BrandTokens.SPACE_LG
	menu_empty.content_margin_right = BrandTokens.SPACE_SM
	menu_empty.content_margin_top = BrandTokens.SPACE_SM
	menu_empty.content_margin_bottom = BrandTokens.SPACE_SM
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		theme.set_stylebox(state, &"BrandMenuButton", menu_empty)
	theme.set_font(&"font", &"BrandMenuButton", font_ui())
	theme.set_font_size(&"font_size", &"BrandMenuButton", BrandTokens.BODY)
	theme.set_color(&"font_color", &"BrandMenuButton", BrandTokens.INK_INVERSE)
	theme.set_color(&"font_hover_color", &"BrandMenuButton", BrandTokens.BRASS_LIGHT)
	theme.set_color(&"font_pressed_color", &"BrandMenuButton", BrandTokens.BRASS)
	theme.set_color(&"font_focus_color", &"BrandMenuButton", BrandTokens.BRASS_LIGHT)
	theme.set_color(&"font_disabled_color", &"BrandMenuButton", BrandTokens.INK_INVERSE_DIM)


static func _style_fields(theme: Theme) -> void:
	for type_name in [&"LineEdit", &"TextEdit"]:
		theme.set_font(&"font", type_name, font_ui())
		theme.set_font_size(&"font_size", type_name, BrandTokens.BUTTON)
		theme.set_color(&"font_color", type_name, BrandTokens.INK)
		theme.set_color(&"font_placeholder_color", type_name, BrandTokens.INK_FAINT)
		theme.set_color(&"caret_color", type_name, BrandTokens.BRASS)
		theme.set_color(&"selection_color", type_name, BrandTokens.SEA_TINT)
		theme.set_stylebox(&"normal", type_name, _box(
			BrandTokens.PAPER_HIGH, BrandTokens.SURFACE_EDGE, 1, BrandTokens.SPACE_MD
		))
		theme.set_stylebox(&"focus", type_name, _box(
			BrandTokens.PAPER_HIGH, BrandTokens.BRASS, 2, BrandTokens.SPACE_MD
		))
		theme.set_stylebox(&"read_only", type_name, _box(
			BrandTokens.PAPER_LOW, BrandTokens.SURFACE_LINE, 1, BrandTokens.SPACE_MD
		))

	_button_type(
		theme, &"OptionButton", BrandTokens.PAPER_HIGH, BrandTokens.INK_BODY,
		BrandTokens.SURFACE_EDGE, BrandTokens.PAPER_LOW, BrandTokens.INK,
		BrandTokens.BRASS
	)
	theme.set_font(&"font", &"CheckBox", font_ui())
	theme.set_font_size(&"font_size", &"CheckBox", BrandTokens.BUTTON)
	theme.set_color(&"font_color", &"CheckBox", BrandTokens.INK_BODY)
	theme.set_color(&"font_hover_color", &"CheckBox", BrandTokens.INK)
	theme.set_color(&"font_pressed_color", &"CheckBox", BrandTokens.INK)
	theme.set_color(&"font_focus_color", &"CheckBox", BrandTokens.INK)


static func _style_tabs(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"TabContainer", _box(
		BrandTokens.PAPER, BrandTokens.SURFACE_EDGE, 1, BrandTokens.CARD_PADDING
	))
	theme.set_stylebox(&"tab_unselected", &"TabBar", _box(
		BrandTokens.PAPER_HIGH, BrandTokens.SURFACE_EDGE, 1, BrandTokens.SPACE_SM
	))
	theme.set_stylebox(&"tab_hovered", &"TabBar", _box(
		BrandTokens.PAPER_LOW, BrandTokens.BRASS, 1, BrandTokens.SPACE_SM
	))
	theme.set_stylebox(&"tab_selected", &"TabBar", _box(
		BrandTokens.SEA, BrandTokens.SEA, 1, BrandTokens.SPACE_SM
	))
	theme.set_font(&"font", &"TabBar", font_data())
	theme.set_font_size(&"font_size", &"TabBar", BrandTokens.LABEL_MONO)
	theme.set_color(&"font_unselected_color", &"TabBar", BrandTokens.INK_MUTED)
	theme.set_color(&"font_hovered_color", &"TabBar", BrandTokens.INK)
	theme.set_color(&"font_selected_color", &"TabBar", BrandTokens.INK_INVERSE)


static func _style_lists(theme: Theme) -> void:
	for type_name in [&"Tree", &"ItemList"]:
		theme.set_font(&"font", type_name, font_ui())
		theme.set_font_size(&"font_size", type_name, BrandTokens.BUTTON)
		theme.set_color(&"font_color", type_name, BrandTokens.INK_BODY)
		theme.set_color(&"font_selected_color", type_name, BrandTokens.INK)
		theme.set_stylebox(&"panel", type_name, _box(
			BrandTokens.PAPER_HIGH, BrandTokens.SURFACE_EDGE, 1, BrandTokens.SPACE_SM
		))
		theme.set_stylebox(&"selected", type_name, _box(
			BrandTokens.BRASS_TINT, BrandTokens.BRASS, 1, BrandTokens.SPACE_XS
		))
		theme.set_stylebox(&"selected_focus", type_name, _box(
			BrandTokens.BRASS_TINT, BrandTokens.BRASS, 2, BrandTokens.SPACE_XS
		))
		theme.set_stylebox(&"cursor", type_name, _box(
			Color.TRANSPARENT, BrandTokens.BRASS, 1, 0
		))
	theme.set_constant(&"h_separation", &"Tree", BrandTokens.SPACE_SM)
	theme.set_constant(&"v_separation", &"Tree", BrandTokens.SPACE_XS)


static func _style_ranges(theme: Theme) -> void:
	for type_name in [&"HSlider", &"VSlider"]:
		theme.set_stylebox(&"slider", type_name, _box(
			BrandTokens.SURFACE_LINE, BrandTokens.SURFACE_LINE, 0, 2
		))
		theme.set_stylebox(&"grabber_area", type_name, _box(
			BrandTokens.SEA, BrandTokens.SEA, 0, 2
		))
		theme.set_stylebox(&"grabber_area_highlight", type_name, _box(
			BrandTokens.BRASS, BrandTokens.BRASS, 0, 2
		))
	theme.set_stylebox(&"background", &"ProgressBar", _box(
		BrandTokens.PAPER_LOW, BrandTokens.SURFACE_EDGE, 1, 0
	))
	theme.set_stylebox(&"fill", &"ProgressBar", _box(
		BrandTokens.SEA, BrandTokens.SEA, 0, 0
	))
	theme.set_font(&"font", &"ProgressBar", font_data())
	theme.set_font_size(&"font_size", &"ProgressBar", BrandTokens.LABEL_MONO)
	theme.set_color(&"font_color", &"ProgressBar", BrandTokens.INK_INVERSE)


static func _style_separators(theme: Theme) -> void:
	var horizontal := StyleBoxLine.new()
	horizontal.color = BrandTokens.SURFACE_LINE
	horizontal.thickness = 1
	theme.set_stylebox(&"separator", &"HSeparator", horizontal)
	var vertical := StyleBoxLine.new()
	vertical.color = BrandTokens.SURFACE_LINE
	vertical.thickness = 1
	vertical.vertical = true
	theme.set_stylebox(&"separator", &"VSeparator", vertical)
	theme.set_constant(&"separation", &"HSeparator", BrandTokens.SPACE_SM)
	theme.set_constant(&"separation", &"VSeparator", BrandTokens.SPACE_SM)


static func _style_misc(theme: Theme) -> void:
	theme.set_stylebox(&"panel", &"ScrollContainer", StyleBoxEmpty.new())
	for type_name in [&"HScrollBar", &"VScrollBar"]:
		theme.set_stylebox(&"scroll", type_name, _box(
			BrandTokens.PAPER_LOW, BrandTokens.PAPER_LOW, 0, 0
		))
		theme.set_stylebox(&"grabber", type_name, _box(
			BrandTokens.SEA_LIGHT, BrandTokens.SEA_LIGHT, 0, 0
		))
		theme.set_stylebox(&"grabber_highlight", type_name, _box(
			BrandTokens.BRASS, BrandTokens.BRASS, 0, 0
		))
		theme.set_stylebox(&"grabber_pressed", type_name, _box(
			BrandTokens.BRASS_DEEP, BrandTokens.BRASS_DEEP, 0, 0
		))
	theme.set_stylebox(&"panel", &"PopupMenu", _box(
		BrandTokens.PAPER_HIGH, BrandTokens.SURFACE_EDGE, 1, BrandTokens.SPACE_SM
	))
	theme.set_font(&"font", &"PopupMenu", font_ui())
	theme.set_font_size(&"font_size", &"PopupMenu", BrandTokens.BUTTON)
	theme.set_color(&"font_color", &"PopupMenu", BrandTokens.INK_BODY)
	theme.set_color(&"font_hover_color", &"PopupMenu", BrandTokens.INK)
	theme.set_stylebox(&"hover", &"PopupMenu", _box(
		BrandTokens.BRASS_TINT, BrandTokens.BRASS_TINT, 0, BrandTokens.SPACE_XS
	))
	theme.set_stylebox(&"panel", &"TooltipPanel", _ruled_box(
		BrandTokens.INK, BrandTokens.SEA_LINE, BrandTokens.BRASS, BrandTokens.SPACE_MD
	))
	theme.set_font(&"font", &"TooltipLabel", font_ui())
	theme.set_font_size(&"font_size", &"TooltipLabel", BrandTokens.BUTTON)
	theme.set_color(&"font_color", &"TooltipLabel", BrandTokens.INK_INVERSE)
	theme.set_color(&"default_color", &"RichTextLabel", BrandTokens.INK_BODY)
	theme.set_font(&"normal_font", &"RichTextLabel", font_ui())
	theme.set_font(&"bold_font", &"RichTextLabel", font_ui())
	theme.set_font(&"mono_font", &"RichTextLabel", font_data())
	theme.set_font_size(&"normal_font_size", &"RichTextLabel", BrandTokens.BODY)


static func _label(theme: Theme, type_name: StringName, font: Font, size: int, color: Color) -> void:
	theme.set_font(&"font", type_name, font)
	theme.set_font_size(&"font_size", type_name, size)
	theme.set_color(&"font_color", type_name, color)


static func _button_type(
		theme: Theme,
		type_name: StringName,
		normal_bg: Color,
		normal_text: Color,
		border: Color,
		hover_bg: Color,
		hover_text: Color,
		focus_border: Color
	) -> void:
	theme.set_font(&"font", type_name, font_display_semibold())
	theme.set_font_size(&"font_size", type_name, BrandTokens.BUTTON)
	theme.set_color(&"font_color", type_name, normal_text)
	theme.set_color(&"font_hover_color", type_name, hover_text)
	theme.set_color(&"font_pressed_color", type_name, hover_text)
	theme.set_color(&"font_focus_color", type_name, hover_text)
	theme.set_color(&"font_disabled_color", type_name, BrandTokens.INK_FAINT)
	theme.set_stylebox(&"normal", type_name, _box(normal_bg, border, 1, BrandTokens.SPACE_MD))
	theme.set_stylebox(&"hover", type_name, _box(hover_bg, border, 1, BrandTokens.SPACE_MD))
	theme.set_stylebox(&"pressed", type_name, _box(hover_bg, BrandTokens.BRASS_DEEP, 2, BrandTokens.SPACE_MD))
	theme.set_stylebox(&"focus", type_name, _box(hover_bg, focus_border, 2, BrandTokens.SPACE_MD))
	theme.set_stylebox(&"disabled", type_name, _box(
		BrandTokens.SURFACE, BrandTokens.SURFACE_LINE, 1, BrandTokens.SPACE_MD
	))


static func _box(background: Color, border: Color, width: int, padding: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.set_content_margin_all(padding)
	box.corner_radius_top_left = 0
	box.corner_radius_top_right = 0
	box.corner_radius_bottom_left = 0
	box.corner_radius_bottom_right = 0
	return box


static func _ruled_box(
		background: Color,
		border: Color,
		rule: Color,
		padding: int
	) -> StyleBoxFlat:
	var box := _box(background, border, 1, padding)
	box.border_width_top = BrandTokens.RULE_WIDTH
	box.border_color = rule
	return box
