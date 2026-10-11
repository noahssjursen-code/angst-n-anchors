class_name UiPalette
extends RefCounted

## Design tokens for the quayside UI.
##
## Derived from the world itself: quay asphalt and road paint, safety-yellow
## crane steel with hazard chevrons, deep fjord water, ore-heap rust, white
## superstructures and overcast sky. Every colour, size and font used by game
## UI comes from here; screens never invent their own.

# Surfaces — wet asphalt under an overcast sky.
const SCRIM          := Color(0.031, 0.039, 0.047, 0.72)
const ASPHALT_DEEP   := Color(0.055, 0.063, 0.071, 0.97)
const ASPHALT        := Color(0.086, 0.098, 0.110, 0.95)
const ASPHALT_RAISED := Color(0.125, 0.141, 0.157, 0.97)
const ASPHALT_HOVER  := Color(0.165, 0.184, 0.204, 1.0)
const HUD_GLASS      := Color(0.055, 0.063, 0.071, 0.80)

# Lines — kerb edges and painted dividers.
const KERB        := Color(0.231, 0.259, 0.282, 1.0)
const KERB_STRONG := Color(0.361, 0.396, 0.427, 1.0)

# Text — road paint.
const PAINT       := Color(0.949, 0.945, 0.925, 1.0)
const PAINT_MUTED := Color(0.678, 0.702, 0.710, 1.0)
const PAINT_FAINT := Color(0.447, 0.478, 0.494, 1.0)

# Signal colours.
const CRANE       := Color(0.949, 0.765, 0.165, 1.0)   # crane steel — anything you act on
const CRANE_HOVER := Color(1.0, 0.835, 0.322, 1.0)
const CRANE_DEEP  := Color(0.541, 0.427, 0.098, 1.0)
const ON_CRANE    := Color(0.067, 0.071, 0.078, 1.0)
const FJORD       := Color(0.208, 0.529, 0.761, 1.0)   # information, water, routes
const FJORD_DEEP  := Color(0.078, 0.192, 0.278, 1.0)
const STARBOARD   := Color(0.271, 0.690, 0.431, 1.0)   # healthy, confirmed, profit
const PORT_RED    := Color(0.851, 0.314, 0.231, 1.0)   # danger, loss, failure
const ORE         := Color(0.894, 0.502, 0.255, 1.0)   # caution, wear, pending
const HULL_WHITE  := Color(0.910, 0.925, 0.933, 1.0)

# Type scale (px at 1080p reference).
const SIZE_MICRO   := 11
const SIZE_CAPTION := 13
const SIZE_BODY    := 15
const SIZE_LEAD    := 18
const SIZE_TITLE   := 24
const SIZE_HEADING := 34
const SIZE_DISPLAY := 64
const SIZE_HERO    := 112

# Spacing.
const GAP_XS := 4
const GAP_S  := 8
const GAP_M  := 12
const GAP_L  := 20
const GAP_XL := 32

# Signage corners: square, with a small chamfer feel.
const RADIUS := 2
const EDGE   := 4   # signal edge-bar width (quay-edge marking)

const FONT_BODY      := "res://resources/fonts/ui/Barlow-Regular.ttf"
const FONT_MEDIUM    := "res://resources/fonts/ui/Barlow-Medium.ttf"
const FONT_STRONG    := "res://resources/fonts/ui/Barlow-SemiBold.ttf"
const FONT_SIGN      := "res://resources/fonts/ui/BarlowCondensed-SemiBold.ttf"
const FONT_SIGN_BOLD := "res://resources/fonts/ui/BarlowCondensed-Bold.ttf"
const FONT_SIGN_MED  := "res://resources/fonts/ui/BarlowCondensed-Medium.ttf"
const FONT_MONO      := "res://resources/fonts/ui/JetBrainsMono.ttf"

static var _fonts: Dictionary = {}


static func font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path] as Font
	var loaded: Font = null
	if ResourceLoader.exists(path):
		loaded = load(path) as Font
	if loaded == null:
		loaded = ThemeDB.fallback_font
	_fonts[path] = loaded
	return loaded


static func body() -> Font:
	return font(FONT_BODY)


static func medium() -> Font:
	return font(FONT_MEDIUM)


static func strong() -> Font:
	return font(FONT_STRONG)


static func sign() -> Font:
	return font(FONT_SIGN)


static func sign_bold() -> Font:
	return font(FONT_SIGN_BOLD)


static func mono() -> Font:
	return font(FONT_MONO)


## Tone name → colour. Tones are the only vocabulary screens use for status.
static func tone(name: String) -> Color:
	match name:
		"signal", "action": return CRANE
		"info", "route":    return FJORD
		"ok", "profit":     return STARBOARD
		"danger", "loss":   return PORT_RED
		"caution", "wear":  return ORE
		"muted":            return PAINT_MUTED
		"faint":            return PAINT_FAINT
	return PAINT


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
