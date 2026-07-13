class_name WeatherState
extends Resource

## Serializable weather snapshot for presentation, missions, and scripts.
## Use `WeatherLighting.get_weather_state()` / `apply_weather_state()` at runtime —
## no need to reach into individual floats on the autoload.
##
## Orthogonal knobs not on `WeatherState`:
## — `WeatherLighting.time_of_day` (globe-wide clock)
## — manual wave overrides if `weather_drives_waves == false`

@export_range(0.0, 1.0, 0.001) var precipitation: float = 0.0
@export_range(0.0, 1.0, 0.001) var wind_force: float = 0.0

## Actual wind speed (m/s) — drives ship aerodynamic drag. Separable from `wind_force`,
## which is the sea-state / Beaufort lever for waves and storm visuals.
@export_range(0.0, 30.0, 0.1) var wind_speed_ms: float = 0.0

## 1 = crystal clear, 0 = pea-soup (matches WeatherLighting.visibility).
@export_range(0.0, 1.0, 0.001) var visibility: float = 1.0

## Sky overcast dial; rain still stacks via `precipitation` → `cloud_coverage` merge on the server.
@export_range(0.0, 1.0, 0.001) var cloud_cover: float = 0.0
## -1 means "legacy caller: derive sea state from wind_force".
@export var sea_state: float = -1.0
@export_range(0.0, 12.0, 0.05) var significant_wave_height_m: float = 0.25
@export var wind_direction: Vector3 = Vector3(-1.0, 0.0, 0.0)
@export var wind_velocity_ms: Vector3 = Vector3.ZERO
@export var pressure_hpa: float = 1013.0
@export var temperature_c: float = 15.0
@export_range(0.0, 1.0, 0.001) var exposure: float = 1.0
@export_range(0.0, 1.0, 0.001) var front_intensity: float = 0.0
@export var zone_label: String = "Open ocean"
@export var front_label: String = ""


## Shortcut for sliders / debug: xyz = precipitation, wind, fog density (1 − visibility).
var as_vector: Vector3:
	get:
		return Vector3(precipitation, wind_force, fog_density)
	set(v):
		precipitation = clampf(v.x, 0.0, 1.0)
		wind_force = clampf(v.y, 0.0, 1.0)
		var fd := clampf(v.z, 0.0, 1.0)
		visibility = clampf(1.0 - fd, 0.0, 1.0)


var fog_density: float:
	get:
		return clampf(1.0 - visibility, 0.0, 1.0)


static func create_clear_calm() -> WeatherState:
	var s := WeatherState.new()
	s.precipitation = 0.0
	s.wind_force = 0.0
	s.wind_speed_ms = 0.0
	s.visibility = 1.0
	s.cloud_cover = 0.0
	s.sea_state = 0.0
	s.significant_wave_height_m = 0.25
	return s


static func lerp_states(a: WeatherState, b: WeatherState, t: float) -> WeatherState:
	t = clampf(t, 0.0, 1.0)
	var o := WeatherState.new()
	o.precipitation = lerpf(a.precipitation, b.precipitation, t)
	o.wind_force = lerpf(a.wind_force, b.wind_force, t)
	o.wind_speed_ms = lerpf(a.wind_speed_ms, b.wind_speed_ms, t)
	o.visibility = lerpf(a.visibility, b.visibility, t)
	o.cloud_cover = lerpf(a.cloud_cover, b.cloud_cover, t)
	var a_sea := a.sea_state if a.sea_state >= 0.0 else a.wind_force
	var b_sea := b.sea_state if b.sea_state >= 0.0 else b.wind_force
	o.sea_state = lerpf(a_sea, b_sea, t)
	o.significant_wave_height_m = lerpf(a.significant_wave_height_m, b.significant_wave_height_m, t)
	o.wind_direction = a.wind_direction.slerp(b.wind_direction, t).normalized()
	o.wind_velocity_ms = a.wind_velocity_ms.lerp(b.wind_velocity_ms, t)
	o.pressure_hpa = lerpf(a.pressure_hpa, b.pressure_hpa, t)
	o.temperature_c = lerpf(a.temperature_c, b.temperature_c, t)
	o.exposure = lerpf(a.exposure, b.exposure, t)
	o.front_intensity = lerpf(a.front_intensity, b.front_intensity, t)
	o.zone_label = b.zone_label if t >= 0.5 else a.zone_label
	o.front_label = b.front_label if t >= 0.5 else a.front_label
	return o
