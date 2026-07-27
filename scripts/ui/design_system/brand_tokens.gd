class_name BrandTokens
extends RefCounted

## Runtime binding for the generated brand palette.
##
## `branding/brand/tokens/palette.json` is the generated source of truth. This
## class deliberately does not duplicate hex literals: UI, charts, and later
## world-material adapters all resolve named tokens from the same file.

const PALETTE_PATH := "res://branding/brand/tokens/palette.json"

const SPACE_XS := 4
const SPACE_SM := 8
const SPACE_MD := 12
const SPACE_LG := 16
const SPACE_XL := 24
const SPACE_XXL := 32
const SPACE_XXXL := 48
const SPACE_HUGE := 64

const PANEL_PADDING := 24
const CARD_PADDING := 18
const GROUP_GAP := 12
const SECTION_GAP := 32
const HAIRLINE := 1
const RULE_WIDTH := 5
const MIN_HIT_TARGET := 44
const MIN_ICON_BOX := 20

const DISPLAY_L := 44
const DISPLAY_M := 32
const DISPLAY_S := 24
const BODY := 18
const BUTTON := 16
const LABEL_MONO := 14
const DATA_MONO := 17
const MICRO_MONO := 12

const MOTION_MICRO_MS := 90
const MOTION_CONTROL_MS := 160
const MOTION_PANEL_MS := 240
const MOTION_SCREEN_MS := 320

static var _colors: Dictionary = _load_palette()

static var PAPER: Color = color(&"PAPER")
static var PAPER_HIGH: Color = color(&"PAPER_HIGH")
static var PAPER_LOW: Color = color(&"PAPER_LOW")
static var SURFACE: Color = color(&"SURFACE")
static var SURFACE_EDGE: Color = color(&"SURFACE_EDGE")
static var SURFACE_LINE: Color = color(&"SURFACE_LINE")

static var INK: Color = color(&"INK")
static var INK_BODY: Color = color(&"INK_BODY")
static var INK_MUTED: Color = color(&"INK_MUTED")
static var INK_FAINT: Color = color(&"INK_FAINT")
static var INK_INVERSE: Color = color(&"INK_INVERSE")
static var INK_INVERSE_DIM: Color = color(&"INK_INVERSE_DIM")

static var SEA_DEEP: Color = color(&"SEA_DEEP")
static var SEA: Color = color(&"SEA")
static var SEA_RAISED: Color = color(&"SEA_RAISED")
static var SEA_LIGHT: Color = color(&"SEA_LIGHT")
static var SEA_TINT: Color = color(&"SEA_TINT")
static var SEA_LINE: Color = color(&"SEA_LINE")
static var SCRIM: Color = color(&"SCRIM")
static var SHADOW: Color = color(&"SHADOW")

static var BRASS: Color = color(&"BRASS")
static var BRASS_LIGHT: Color = color(&"BRASS_LIGHT")
static var BRASS_DEEP: Color = color(&"BRASS_DEEP")
static var BRASS_SHADE: Color = color(&"BRASS_SHADE")
static var BRASS_TINT: Color = color(&"BRASS_TINT")

static var ALERT: Color = color(&"ALERT")
static var ALERT_DEEP: Color = color(&"ALERT_DEEP")
static var ALERT_TINT: Color = color(&"ALERT_TINT")
static var WARN: Color = color(&"WARN")
static var WARN_TINT: Color = color(&"WARN_TINT")
static var OK: Color = color(&"OK")
static var OK_LIGHT: Color = color(&"OK_LIGHT")
static var OK_TINT: Color = color(&"OK_TINT")
static var INFO: Color = color(&"INFO")
static var IDLE: Color = color(&"IDLE")

static var CHART_LAND: Color = color(&"CHART_LAND")
static var CHART_SEA: Color = color(&"CHART_SEA")
static var CHART_DEPTH_1: Color = color(&"CHART_DEPTH_1")
static var CHART_DEPTH_2: Color = color(&"CHART_DEPTH_2")
static var CHART_DEPTH_3: Color = color(&"CHART_DEPTH_3")
static var CHART_CONTOUR: Color = color(&"CHART_CONTOUR")
static var CHART_GRID: Color = color(&"CHART_GRID")
static var CHART_ROUTE: Color = color(&"CHART_ROUTE")
static var CHART_TRAFFIC: Color = color(&"CHART_TRAFFIC")
static var CHART_TRAFFIC_SELF: Color = color(&"CHART_TRAFFIC_SELF")
static var CHART_ZONE_FISH: Color = color(&"CHART_ZONE_FISH")
static var CHART_ZONE_WEATHER: Color = color(&"CHART_ZONE_WEATHER")
static var CHART_ZONE_RESTRICT: Color = color(&"CHART_ZONE_RESTRICT")
static var CHART_PORT_MARK: Color = color(&"CHART_PORT_MARK")

static var WATER_MID: Color = color(&"WATER_MID")
static var WATER_SHALLOW: Color = color(&"WATER_SHALLOW")
static var CLOUD_LIGHT: Color = color(&"CLOUD_LIGHT")
static var CLOUD_DARK: Color = color(&"CLOUD_DARK")
static var FOG: Color = color(&"FOG")
static var RAIN: Color = color(&"RAIN")
static var QUAY: Color = color(&"QUAY")
static var QUAY_EDGE: Color = color(&"QUAY_EDGE")
static var CONCRETE_LIGHT: Color = color(&"CONCRETE_LIGHT")
static var CONCRETE: Color = color(&"CONCRETE")
static var CONCRETE_STAINED: Color = color(&"CONCRETE_STAINED")
static var SAND: Color = color(&"SAND")


static func color(token: StringName) -> Color:
	var key := String(token)
	if _colors.has(key):
		return _colors[key] as Color
	push_error("BrandTokens: unknown colour token '%s'" % key)
	return Color.MAGENTA


static func has_color(token: StringName) -> bool:
	return _colors.has(String(token))


static func all_colors() -> Dictionary:
	return _colors.duplicate()


static func alpha(base: Color, amount: float) -> Color:
	return Color(base.r, base.g, base.b, clampf(amount, 0.0, 1.0))


static func _load_palette() -> Dictionary:
	if not FileAccess.file_exists(PALETTE_PATH):
		push_error("BrandTokens: generated palette is missing at %s" % PALETTE_PATH)
		return {}
	var file := FileAccess.open(PALETTE_PATH, FileAccess.READ)
	if file == null:
		push_error("BrandTokens: could not open %s" % PALETTE_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BrandTokens: palette JSON root must be a dictionary")
		return {}
	var result: Dictionary = {}
	for key_raw in (parsed as Dictionary):
		var key := str(key_raw)
		result[key] = Color(str((parsed as Dictionary)[key_raw]))
	return result
