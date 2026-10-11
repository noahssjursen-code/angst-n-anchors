class_name HudStyle
extends RefCounted

## Compatibility aliases onto the quayside palette. New screens use Ui / UiPalette.
## Remaining custom-draw HUDs still read these names; they now resolve to asphalt,
## crane yellow, fjord and starboard — not the discarded harbour-desk look.

const C_BG        := Color(0.055, 0.063, 0.071, 0.80)
const C_BG_INNER  := Color(0.125, 0.141, 0.157, 0.97)
const C_BRASS     := Color(0.231, 0.259, 0.282, 1.0)
const C_SEP       := Color(0.231, 0.259, 0.282, 1.0)
const C_TEXT      := Color(0.949, 0.945, 0.925, 1.0)
const C_LABEL     := Color(0.678, 0.702, 0.710, 1.0)
const C_AMBER     := Color(0.949, 0.765, 0.165, 1.0)
const C_COPPER    := Color(0.541, 0.427, 0.098, 1.0)
const C_GREEN     := Color(0.271, 0.690, 0.431, 1.0)
const C_RED       := Color(0.851, 0.314, 0.231, 1.0)
const C_GREEN_DIM := Color(0.271, 0.690, 0.431, 0.28)
const C_RED_DIM   := Color(0.851, 0.314, 0.231, 0.28)
const C_GREY_DIM  := Color(0.055, 0.063, 0.071, 0.65)

const FONT_DISPLAY_PATH := "res://resources/fonts/ui/BarlowCondensed-Bold.ttf"
const FONT_BODY_PATH := "res://resources/fonts/ui/Barlow-Regular.ttf"
const FONT_MEDIUM_PATH := "res://resources/fonts/ui/Barlow-Medium.ttf"
const FONT_BOLD_PATH := "res://resources/fonts/ui/Barlow-SemiBold.ttf"


static func font_display() -> Font:
	return UiPalette.sign_bold()


static func font_body() -> Font:
	return UiPalette.body()


static func font_medium() -> Font:
	return UiPalette.medium()


static func font_bold() -> Font:
	return UiPalette.strong()


static func make_theme() -> Theme:
	return UiThemeBuilder.build()


static func make_title_panel_style() -> StyleBoxFlat:
	return UiThemeBuilder.box(UiPalette.ASPHALT, UiPalette.KERB, 1, 28.0, 24.0)


static func apply_display_font(label: Label, size: int, color: Color = C_TEXT) -> void:
	label.add_theme_font_override("font", font_display())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


static func apply_body_font(control: Control, size: int, color: Color = C_TEXT, bold: bool = false) -> void:
	control.add_theme_font_override("font", font_bold() if bold else font_body())
	control.add_theme_font_size_override("font_size", size)
	control.add_theme_color_override("font_color", color)
