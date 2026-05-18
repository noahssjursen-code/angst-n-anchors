class_name WeatherSample
extends Resource

## Per-position weather snapshot — the result of `WeatherField.sample(pos, time)`.
##
## Superset of WeatherState that adds the things the overhaul will need:
##   wind        — full velocity vector (XZ plane); length is the scalar wind_force
##   pressure    — synoptic pressure in hPa (1013 = standard mean sea level)
##   temperature — ambient °C
##
## Phase 1 is wiring: every field exists, but only the 4 legacy knobs are
## populated. Phase 2 starts feeding real noise into wind / pressure;
## Phase 4 starts feeding seasonal modulation into temperature.

@export_range(0.0, 1.0, 0.001) var precipitation: float = 0.0
@export_range(0.0, 1.0, 0.001) var wind_force:    float = 0.0  ## kept for back-compat; same as wind.length()
@export_range(0.0, 1.0, 0.001) var visibility:    float = 1.0
@export_range(0.0, 1.0, 0.001) var cloud_cover:   float = 0.0

## Horizontal wind in world units. Y component is always 0.
@export var wind: Vector3 = Vector3.ZERO
## Mean sea-level pressure (hPa). 1013 = standard, < 1000 = stormy low, > 1025 = high.
@export var pressure:    float = 1013.0
## Ambient air temperature (°C).
@export var temperature: float = 15.0


var fog_density: float:
	get:
		return clampf(1.0 - visibility, 0.0, 1.0)


## Down-convert to the legacy WeatherState (for code paths not yet migrated).
func to_weather_state() -> WeatherState:
	var s := WeatherState.new()
	s.precipitation = precipitation
	s.wind_force    = wind_force
	s.visibility    = visibility
	s.cloud_cover   = cloud_cover
	return s


## Up-convert a WeatherState into a Sample (wind/pressure/temperature stay at defaults).
static func from_weather_state(state: WeatherState) -> WeatherSample:
	var s := WeatherSample.new()
	if state == null:
		return s
	s.precipitation = state.precipitation
	s.wind_force    = state.wind_force
	s.visibility    = state.visibility
	s.cloud_cover   = state.cloud_cover
	return s
