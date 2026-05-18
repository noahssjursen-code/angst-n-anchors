class_name Season
extends RefCounted

## Year-scale modulation envelope for the weather field.
##
## Calendar (per the design): one real week == one season, four real weeks ==
## one game year. WorldClock runs 1 real minute = 1 game hour, so:
##     1 real week  = 10 080 game-hours  = 1 season
##     1 game year  = 40 320 game-hours  = 4 seasons
##
## `Season.modifiers(game_time)` returns a small dict the field uses to bias
## pressure amplitude, baseline wind, temperature offset, and humidity. The
## phase is a smooth angle 0..TAU around the year (so cross-fades between
## seasons happen naturally; no hard jumps).
##
## Year-phase convention:
##     0.00  →  midwinter (cold, stormy, low visibility)
##     0.25  →  spring    (warming, transitional)
##     0.50  →  midsummer (warm, calm, clear)
##     0.75  →  autumn    (cooling, breezy)

const SEASON_LENGTH_GAME_HOURS : float = 10080.0          # 1 real week
const YEAR_LENGTH_GAME_HOURS   : float = 40320.0          # 4 seasons
const SEASON_COUNT             : int   = 4

enum Kind { WINTER = 0, SPRING = 1, SUMMER = 2, AUTUMN = 3 }
const NAMES : Array[String] = ["Winter", "Spring", "Summer", "Autumn"]


## 0..1 position through the current game year.
static func year_phase(game_time_h: float) -> float:
	return fposmod(game_time_h, YEAR_LENGTH_GAME_HOURS) / YEAR_LENGTH_GAME_HOURS


## Which season we are *currently* in (integer 0..3).
static func current(game_time_h: float) -> int:
	var p := year_phase(game_time_h)
	return int(p * SEASON_COUNT) % SEASON_COUNT


## Human-readable name of the current season.
static func current_name(game_time_h: float) -> String:
	return NAMES[current(game_time_h)]


## How far into the current season we are (0..1).
static func progress_within_current(game_time_h: float) -> float:
	var p := year_phase(game_time_h) * SEASON_COUNT
	return p - floor(p)


## Returns a dict of modulators consumed by `WeatherField.sample`.
##
##   pressure_amplitude_mul : 0.6 (summer) .. 1.4 (winter)
##                            — winter has bigger highs and lows → more storms
##   baseline_wind_mul      : 0.7 (summer) .. 1.4 (winter)
##                            — winter trades are stronger
##   temperature_offset_c   : −8.0 (midwinter) .. +8.0 (midsummer)
##   cloud_bias             : +0.15 (winter) .. −0.10 (summer)
##                            — overcast more common in winter
##
## The shape is `cos(year_phase * TAU)` so all four numbers vary smoothly and
## are bit-identical on any client running the same WorldClock.
static func modifiers(game_time_h: float) -> Dictionary:
	var cos_y := cos(year_phase(game_time_h) * TAU)  # +1 at winter, −1 at summer
	return {
		"pressure_amplitude_mul": 1.0 + 0.40 * cos_y,
		"baseline_wind_mul":      1.0 + 0.40 * cos_y,
		"temperature_offset_c":  -8.0 * cos_y,
		"cloud_bias":             0.025 + 0.125 * cos_y,
	}
