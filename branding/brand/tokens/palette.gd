# Angst 'n Anchors - bound colour map
# Generated from brand/tokens/design-tokens.json. Do not hand-edit.
# Usage: Palette.SEA  /  Palette.get_color("SEA")
class_name Palette
extends RefCounted

# PAPER - backgrounds, panels, chart land
const PAPER := Color("#ECE5D3")  ## screen background, chart land
const PAPER_HIGH := Color("#F3EEE1")  ## raised cards, fields
const PAPER_LOW := Color("#E4DCC7")  ## recessed wells, tracks
const SURFACE := Color("#DFD6C0")  ## panels, inactive tabs
const SURFACE_EDGE := Color("#B5AB92")  ## borders, dividers
const SURFACE_LINE := Color("#C9BFA8")  ## hairlines, table rules

# INK - text and icons on paper
const INK := Color("#1B242C")  ## primary text, icons
const INK_BODY := Color("#3D4650")  ## body copy, secondary
const INK_MUTED := Color("#7A7052")  ## labels, units, hints
const INK_FAINT := Color("#988D70")  ## disabled, placeholders
const INK_INVERSE := Color("#ECE5D3")  ## text on sea and ink
const INK_INVERSE_DIM := Color("#9FB3BD")  ## secondary text on dark

# SEA - interactive, dark panels
const SEA_DEEP := Color("#0F2530")  ## pressed states
const SEA := Color("#163440")  ## buttons, dark panels
const SEA_RAISED := Color("#1E4657")  ## hover on dark
const SEA_LIGHT := Color("#3F6377")  ## dark panel highlight
const SEA_TINT := Color("#9FC0CD")  ## text/icons on sea
const SEA_LINE := Color("#2C3A46")  ## borders on dark
const SCRIM := Color("#10151A")  ## modal scrim, capsule fade
const SHADOW := Color("#0A0E12")  ## drop shadow, night base

# BRASS - accent, selection, one loud action
const BRASS := Color("#D99A1F")  ## selection, rules, loud action
const BRASS_LIGHT := Color("#EFBB55")  ## brass hover, glow
const BRASS_DEEP := Color("#A8701C")  ## brass text on paper
const BRASS_SHADE := Color("#7A5214")  ## brass pressed, engraved
const BRASS_TINT := Color("#F7E3BC")  ## text on brass fills
const AMBER := Color("#F2B233")  ## marketing only - not in build

# STATUS - state, never decoration
const ALERT := Color("#B23A2A")  ## collision, debt, failure
const ALERT_DEEP := Color("#8A2A1D")  ## alert pressed, hull damage
const ALERT_TINT := Color("#F2D2CC")  ## text on alert fills
const WARN := Color("#C9791C")  ## caution, low fuel, overdue
const WARN_TINT := Color("#F7DCB4")  ## text on warn fills
const OK := Color("#4F7D5E")  ## stable, moored, paid
const OK_LIGHT := Color("#7FC48E")  ## zones, OK text on dark
const OK_TINT := Color("#D6EEDB")  ## text on OK fills
const INFO := Color("#3E6E86")  ## neutral notice, tooltips
const IDLE := Color("#6F7B84")  ## offline, unknown, no signal

# WATER - sea surface and depth
const WATER_ABYSS := Color("#0B1E27")  ## deepest water
const WATER_DEEP := Color("#123240")  ## open sea
const WATER_MID := Color("#1B4A5C")  ## coastal water
const WATER_SHALLOW := Color("#2E6E7E")  ## shallows, harbour basin
const WATER_SHOAL := Color("#4C93A0")  ## sandbanks, hazard shallows
const WATER_FOAM := Color("#D7E6E9")  ## wake, whitecaps, spray
const WATER_WAKE := Color("#8FB6BE")  ## wake trails, ripples
const WATER_SUBSURFACE := Color("#1F5866")  ## underwater fog, hull below

# TERRAIN - ground and rock
const GRASS_LIGHT := Color("#A3B48F")  ## sunlit meadow, cliff top
const GRASS := Color("#8BA08C")  ## default ground cover
const GRASS_DARK := Color("#6A8272")  ## shaded slopes
const HEATH := Color("#7C7A5C")  ## scrub, moorland
const ROCK_LIGHT := Color("#9A9A94")  ## exposed granite
const ROCK := Color("#7A7C7C")  ## cliffs, boulders
const ROCK_DARK := Color("#565A5C")  ## wet rock, crevices
const SAND := Color("#CBBE9C")  ## beaches, dunes
const SHINGLE := Color("#A9A392")  ## gravel shore, ballast
const MUD := Color("#6B5D48")  ## tidal flats, tracks
const SNOW := Color("#E8EDEF")  ## peaks, winter cover
const SNOW_SHADE := Color("#BFCBD1")  ## snow in shadow

# FOLIAGE - trees and growth
const CONIFER_DARK := Color("#24352B")  ## spruce, dense forest
const CONIFER := Color("#33503C")  ## pine canopy
const CONIFER_LIGHT := Color("#456A4C")  ## sunlit canopy
const BIRCH := Color("#7E9A63")  ## deciduous, summer
const BIRCH_AUTUMN := Color("#B08A3C")  ## deciduous, autumn
const SHRUB := Color("#5C6B4A")  ## bushes, hedges
const KELP := Color("#2F4A3C")  ## seaweed, wet growth
const LICHEN := Color("#9AA88A")  ## rock growth, old timber
const TIMBER_RAW := Color("#6E5638")  ## logs, cut wood
const TIMBER_DEAD := Color("#8A7F6A")  ## driftwood, dead trees

# SKY - atmosphere and weather
const SKY_ZENITH := Color("#5E8FB0")  ## clear sky, overhead
const SKY_HORIZON := Color("#AEBFC4")  ## clear sky, at horizon
const SKY_OVERCAST := Color("#9FA9AC")  ## grey day, upper
const SKY_OVERCAST_LOW := Color("#C0C6C6")  ## grey day, horizon
const SKY_DAWN := Color("#D9A78A")  ## sunrise band
const SKY_DUSK := Color("#B8735C")  ## sunset band
const SKY_NIGHT := Color("#16202C")  ## night sky
const SKY_NIGHT_HORIZON := Color("#2A3A48")  ## night horizon glow
const CLOUD_LIGHT := Color("#EDF1F2")  ## cumulus lit face
const CLOUD := Color("#C4CCCE")  ## cloud body
const CLOUD_DARK := Color("#8D979B")  ## storm cloud, rain base
const FOG := Color("#C8D2D4")  ## fog, haze, distance fade
const RAIN := Color("#DCE6E8")  ## rain streaks, sleet
const STAR := Color("#F2F5EE")  ## stars, aurora highlight

# BUILT - harbour structures and materials
const QUAY := Color("#262B31")  ## asphalt, quay surface
const QUAY_EDGE := Color("#171B1F")  ## quay lip, expansion joints
const CONCRETE_LIGHT := Color("#C3C2BB")  ## new concrete, bollard base
const CONCRETE := Color("#9C9B94")  ## walls, piers, ramps
const CONCRETE_STAINED := Color("#7B7A72")  ## weathered concrete
const DECK_TIMBER := Color("#7A5F3E")  ## wooden decks, jetties
const DECK_TIMBER_WORN := Color("#5E4A31")  ## worn planking, pilings
const STEEL_LIGHT := Color("#B7BEC2")  ## galvanised rail, ladders
const STEEL := Color("#8A8F96")  ## cranes, machinery, gantry
const STEEL_DARK := Color("#5B6167")  ## structure shadow, engine
const RUST := Color("#8C5230")  ## corrosion, old fittings
const RUST_DEEP := Color("#5E3520")  ## heavy rust, bilge
const CRANE_YELLOW := Color("#CFA235")  ## cranes, plant, hi-vis kit
const ROOF_TILE := Color("#8E4B39")  ## town roofs
const WALL_WHITE := Color("#E2E0D6")  ## harbour buildings
const WALL_RED := Color("#A34F3A")  ## boathouses, sheds

# HULL - player-chosen paint - never in UI
const HULL_WHITE := Color("#E8E6DD")  ## superstructure white
const HULL_GREY := Color("#98A0A6")  ## working grey
const HULL_BLACK := Color("#22262A")  ## classic black hull
const HULL_NAVY := Color("#1F3550")  ## navy blue
const HULL_TEAL := Color("#1D5A5E")  ## teal
const HULL_GREEN := Color("#2C5138")  ## bottle green
const HULL_RED := Color("#9E3628")  ## signal red
const HULL_ORANGE := Color("#C9601F")  ## rescue orange
const HULL_YELLOW := Color("#D2A62C")  ## workboat yellow
const HULL_BLUE := Color("#2C6595")  ## mid blue
const HULL_CREAM := Color("#D8CDAE")  ## cream, older vessels
const ANTIFOUL := Color("#7A2B24")  ## below waterline, boot top

# CARGO - containers, goods, hold
const CARGO_BLUE := Color("#2B5F8C")  ## containers, general
const CARGO_RED := Color("#993B2E")  ## containers
const CARGO_GREEN := Color("#356248")  ## containers
const CARGO_GREY := Color("#7E858A")  ## containers, refrigerated
const CARGO_ORANGE := Color("#C0651F")  ## hazardous, priority
const CRATE := Color("#9A7A4E")  ## timber crates, pallets
const SACK := Color("#C0B48C")  ## sacks, grain, bulk bags
const BARREL := Color("#4E5A47")  ## drums, fuel barrels
const FISH := Color("#A8B6BA")  ## catch, ice, trays
const NET := Color("#3C5A4E")  ## nets, trawl gear, rope

# LIGHTS - emissive - nav, work, signals
const NAV_PORT := Color("#E23B2E")  ## port sidelight (red)
const NAV_STARBOARD := Color("#31C25C")  ## starboard sidelight (green)
const NAV_STERN := Color("#FBF3E2")  ## stern and masthead white
const WORK_LIGHT := Color("#FFE9B0")  ## deck floods, work lamps
const WORK_LIGHT_COOL := Color("#DDEAF5")  ## LED floods, modern plant
const LANTERN := Color("#F2B95C")  ## lanterns, warm cabin light
const CABIN_GLOW := Color("#C98F3E")  ## windows seen from outside
const BEACON := Color("#F2CE3A")  ## flashing plant beacon
const STROBE := Color("#FFFFFF")  ## strobes, camera flash
const BUOY_RED := Color("#C6382C")  ## port-hand mark
const BUOY_GREEN := Color("#2E9B4E")  ## starboard-hand mark
const BUOY_YELLOW := Color("#D9B429")  ## special mark, cardinal
const LIGHTHOUSE := Color("#FFF6DC")  ## lighthouse sector light
const SIGNAL_BLUE := Color("#3F8FD6")  ## emergency, pilot vessel

# CHART - AIS and navigation overlay
const CHART_LAND := Color("#ECE5D3")  ## land fill (= PAPER)
const CHART_SEA := Color("#163440")  ## water fill (= SEA)
const CHART_DEPTH_1 := Color("#2A4F61")  ## shallow depth band
const CHART_DEPTH_2 := Color("#1E4152")  ## mid depth band
const CHART_DEPTH_3 := Color("#132C38")  ## deep band
const CHART_CONTOUR := Color("#7FA8B8")  ## depth contour lines
const CHART_GRID := Color("#3E5A66")  ## graticule, scale bar
const CHART_ROUTE := Color("#D99A1F")  ## own course, waypoints
const CHART_TRAFFIC := Color("#ECE5D3")  ## other vessels
const CHART_TRAFFIC_SELF := Color("#D99A1F")  ## own vessel wedge
const CHART_ZONE_FISH := Color("#7FC48E")  ## fishing ground overlay
const CHART_ZONE_WEATHER := Color("#8AA9C4")  ## weather cell overlay
const CHART_ZONE_RESTRICT := Color("#B23A2A")  ## restricted, hazard area
const CHART_PORT_MARK := Color("#1B242C")  ## harbour glyphs, labels

const ALL := {
	"PAPER": Color("#ECE5D3"),
	"PAPER_HIGH": Color("#F3EEE1"),
	"PAPER_LOW": Color("#E4DCC7"),
	"SURFACE": Color("#DFD6C0"),
	"SURFACE_EDGE": Color("#B5AB92"),
	"SURFACE_LINE": Color("#C9BFA8"),
	"INK": Color("#1B242C"),
	"INK_BODY": Color("#3D4650"),
	"INK_MUTED": Color("#7A7052"),
	"INK_FAINT": Color("#988D70"),
	"INK_INVERSE": Color("#ECE5D3"),
	"INK_INVERSE_DIM": Color("#9FB3BD"),
	"SEA_DEEP": Color("#0F2530"),
	"SEA": Color("#163440"),
	"SEA_RAISED": Color("#1E4657"),
	"SEA_LIGHT": Color("#3F6377"),
	"SEA_TINT": Color("#9FC0CD"),
	"SEA_LINE": Color("#2C3A46"),
	"SCRIM": Color("#10151A"),
	"SHADOW": Color("#0A0E12"),
	"BRASS": Color("#D99A1F"),
	"BRASS_LIGHT": Color("#EFBB55"),
	"BRASS_DEEP": Color("#A8701C"),
	"BRASS_SHADE": Color("#7A5214"),
	"BRASS_TINT": Color("#F7E3BC"),
	"AMBER": Color("#F2B233"),
	"ALERT": Color("#B23A2A"),
	"ALERT_DEEP": Color("#8A2A1D"),
	"ALERT_TINT": Color("#F2D2CC"),
	"WARN": Color("#C9791C"),
	"WARN_TINT": Color("#F7DCB4"),
	"OK": Color("#4F7D5E"),
	"OK_LIGHT": Color("#7FC48E"),
	"OK_TINT": Color("#D6EEDB"),
	"INFO": Color("#3E6E86"),
	"IDLE": Color("#6F7B84"),
	"WATER_ABYSS": Color("#0B1E27"),
	"WATER_DEEP": Color("#123240"),
	"WATER_MID": Color("#1B4A5C"),
	"WATER_SHALLOW": Color("#2E6E7E"),
	"WATER_SHOAL": Color("#4C93A0"),
	"WATER_FOAM": Color("#D7E6E9"),
	"WATER_WAKE": Color("#8FB6BE"),
	"WATER_SUBSURFACE": Color("#1F5866"),
	"GRASS_LIGHT": Color("#A3B48F"),
	"GRASS": Color("#8BA08C"),
	"GRASS_DARK": Color("#6A8272"),
	"HEATH": Color("#7C7A5C"),
	"ROCK_LIGHT": Color("#9A9A94"),
	"ROCK": Color("#7A7C7C"),
	"ROCK_DARK": Color("#565A5C"),
	"SAND": Color("#CBBE9C"),
	"SHINGLE": Color("#A9A392"),
	"MUD": Color("#6B5D48"),
	"SNOW": Color("#E8EDEF"),
	"SNOW_SHADE": Color("#BFCBD1"),
	"CONIFER_DARK": Color("#24352B"),
	"CONIFER": Color("#33503C"),
	"CONIFER_LIGHT": Color("#456A4C"),
	"BIRCH": Color("#7E9A63"),
	"BIRCH_AUTUMN": Color("#B08A3C"),
	"SHRUB": Color("#5C6B4A"),
	"KELP": Color("#2F4A3C"),
	"LICHEN": Color("#9AA88A"),
	"TIMBER_RAW": Color("#6E5638"),
	"TIMBER_DEAD": Color("#8A7F6A"),
	"SKY_ZENITH": Color("#5E8FB0"),
	"SKY_HORIZON": Color("#AEBFC4"),
	"SKY_OVERCAST": Color("#9FA9AC"),
	"SKY_OVERCAST_LOW": Color("#C0C6C6"),
	"SKY_DAWN": Color("#D9A78A"),
	"SKY_DUSK": Color("#B8735C"),
	"SKY_NIGHT": Color("#16202C"),
	"SKY_NIGHT_HORIZON": Color("#2A3A48"),
	"CLOUD_LIGHT": Color("#EDF1F2"),
	"CLOUD": Color("#C4CCCE"),
	"CLOUD_DARK": Color("#8D979B"),
	"FOG": Color("#C8D2D4"),
	"RAIN": Color("#DCE6E8"),
	"STAR": Color("#F2F5EE"),
	"QUAY": Color("#262B31"),
	"QUAY_EDGE": Color("#171B1F"),
	"CONCRETE_LIGHT": Color("#C3C2BB"),
	"CONCRETE": Color("#9C9B94"),
	"CONCRETE_STAINED": Color("#7B7A72"),
	"DECK_TIMBER": Color("#7A5F3E"),
	"DECK_TIMBER_WORN": Color("#5E4A31"),
	"STEEL_LIGHT": Color("#B7BEC2"),
	"STEEL": Color("#8A8F96"),
	"STEEL_DARK": Color("#5B6167"),
	"RUST": Color("#8C5230"),
	"RUST_DEEP": Color("#5E3520"),
	"CRANE_YELLOW": Color("#CFA235"),
	"ROOF_TILE": Color("#8E4B39"),
	"WALL_WHITE": Color("#E2E0D6"),
	"WALL_RED": Color("#A34F3A"),
	"HULL_WHITE": Color("#E8E6DD"),
	"HULL_GREY": Color("#98A0A6"),
	"HULL_BLACK": Color("#22262A"),
	"HULL_NAVY": Color("#1F3550"),
	"HULL_TEAL": Color("#1D5A5E"),
	"HULL_GREEN": Color("#2C5138"),
	"HULL_RED": Color("#9E3628"),
	"HULL_ORANGE": Color("#C9601F"),
	"HULL_YELLOW": Color("#D2A62C"),
	"HULL_BLUE": Color("#2C6595"),
	"HULL_CREAM": Color("#D8CDAE"),
	"ANTIFOUL": Color("#7A2B24"),
	"CARGO_BLUE": Color("#2B5F8C"),
	"CARGO_RED": Color("#993B2E"),
	"CARGO_GREEN": Color("#356248"),
	"CARGO_GREY": Color("#7E858A"),
	"CARGO_ORANGE": Color("#C0651F"),
	"CRATE": Color("#9A7A4E"),
	"SACK": Color("#C0B48C"),
	"BARREL": Color("#4E5A47"),
	"FISH": Color("#A8B6BA"),
	"NET": Color("#3C5A4E"),
	"NAV_PORT": Color("#E23B2E"),
	"NAV_STARBOARD": Color("#31C25C"),
	"NAV_STERN": Color("#FBF3E2"),
	"WORK_LIGHT": Color("#FFE9B0"),
	"WORK_LIGHT_COOL": Color("#DDEAF5"),
	"LANTERN": Color("#F2B95C"),
	"CABIN_GLOW": Color("#C98F3E"),
	"BEACON": Color("#F2CE3A"),
	"STROBE": Color("#FFFFFF"),
	"BUOY_RED": Color("#C6382C"),
	"BUOY_GREEN": Color("#2E9B4E"),
	"BUOY_YELLOW": Color("#D9B429"),
	"LIGHTHOUSE": Color("#FFF6DC"),
	"SIGNAL_BLUE": Color("#3F8FD6"),
	"CHART_LAND": Color("#ECE5D3"),
	"CHART_SEA": Color("#163440"),
	"CHART_DEPTH_1": Color("#2A4F61"),
	"CHART_DEPTH_2": Color("#1E4152"),
	"CHART_DEPTH_3": Color("#132C38"),
	"CHART_CONTOUR": Color("#7FA8B8"),
	"CHART_GRID": Color("#3E5A66"),
	"CHART_ROUTE": Color("#D99A1F"),
	"CHART_TRAFFIC": Color("#ECE5D3"),
	"CHART_TRAFFIC_SELF": Color("#D99A1F"),
	"CHART_ZONE_FISH": Color("#7FC48E"),
	"CHART_ZONE_WEATHER": Color("#8AA9C4"),
	"CHART_ZONE_RESTRICT": Color("#B23A2A"),
	"CHART_PORT_MARK": Color("#1B242C"),
}

static func get_color(token: String) -> Color:
	if not ALL.has(token):
		push_error("Unknown palette token: %s" % token)
		return Color.MAGENTA
	return ALL[token]
