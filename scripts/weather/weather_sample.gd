class_name WeatherSample
extends Resource

## Per-position weather snapshot — the result of `WeatherField.sample(pos, time)`.
##
## Authoritative per-position contract. Explicit physical values live beside
## normalised presentation controls so consumers never have to invent unit
## conversions or infer coastal/front state.

@export_range(0.0, 1.0, 0.001) var precipitation: float = 0.0
@export_range(0.0, 1.0, 0.001) var wind_force:    float = 0.0  ## kept for back-compat; same as wind.length()
@export_range(0.0, 30.0, 0.1) var wind_speed_ms:  float = 0.0  ## actual m/s, drives ship aerodynamics
@export_range(0.0, 1.0, 0.001) var visibility:    float = 1.0
@export_range(0.0, 1.0, 0.001) var cloud_cover:   float = 0.0

## Normalised horizontal wind direction × severity. Kept for map/back-compat.
@export var wind: Vector3 = Vector3.ZERO
## Physical horizontal wind velocity in metres per second.
@export var wind_velocity_ms: Vector3 = Vector3.ZERO
## Mean sea-level pressure (hPa). 1013 = standard, < 1000 = stormy low, > 1025 = high.
@export var pressure:    float = 1013.0
## Ambient air temperature (°C).
@export var temperature: float = 15.0
## Local built sea, separate from instantaneous air wind.
@export_range(0.0, 1.0, 0.001) var sea_state: float = 0.0
@export_range(0.0, 12.0, 0.05) var significant_wave_height_m: float = 0.25
## Geographic/open-water and coherent-front diagnostics.
@export_range(0.0, 1.0, 0.001) var exposure: float = 1.0
@export_range(0.0, 1.0, 0.001) var front_intensity: float = 0.0
@export var zone_label: String = "Open ocean"
@export var front_label: String = ""


var fog_density: float:
	get:
		return clampf(1.0 - visibility, 0.0, 1.0)


## Down-convert to the legacy WeatherState (for code paths not yet migrated).
func to_weather_state() -> WeatherState:
	var s := WeatherState.new()
	s.precipitation = precipitation
	s.wind_force    = wind_force
	s.wind_speed_ms = wind_speed_ms
	s.visibility    = visibility
	s.cloud_cover   = cloud_cover
	s.wind_direction = wind.normalized()
	s.wind_velocity_ms = wind_velocity_ms
	s.sea_state = sea_state
	s.significant_wave_height_m = significant_wave_height_m
	s.pressure_hpa = pressure
	s.temperature_c = temperature
	s.exposure = exposure
	s.front_intensity = front_intensity
	s.zone_label = zone_label
	s.front_label = front_label
	return s


## Up-convert a WeatherState into a Sample (wind/pressure/temperature stay at defaults).
static func from_weather_state(state: WeatherState) -> WeatherSample:
	var s := WeatherSample.new()
	if state == null:
		return s
	s.precipitation = state.precipitation
	s.wind_force    = state.wind_force
	s.wind_speed_ms = state.wind_speed_ms
	s.visibility    = state.visibility
	s.cloud_cover   = state.cloud_cover
	s.wind = state.wind_direction * state.wind_force
	s.wind_velocity_ms = state.wind_velocity_ms
	s.sea_state = state.sea_state if state.sea_state >= 0.0 else state.wind_force
	s.significant_wave_height_m = state.significant_wave_height_m
	s.pressure = state.pressure_hpa
	s.temperature = state.temperature_c
	s.exposure = state.exposure
	s.front_intensity = state.front_intensity
	s.zone_label = state.zone_label
	s.front_label = state.front_label
	return s
