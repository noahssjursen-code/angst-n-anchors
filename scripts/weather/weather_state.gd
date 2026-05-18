class_name WeatherState
extends Resource

## Serializable weather snapshot for zones, missions, and scripts.
## Use `WeatherLighting.get_weather_state()` / `apply_weather_state()` at runtime —
## no need to reach into individual floats on the autoload.
##
## Orthogonal knobs not on `WeatherState`:
## — `WeatherLighting.time_of_day` (globe-wide clock)
## — manual wave overrides if `weather_drives_waves == false`

@export_range(0.0, 1.0, 0.001) var precipitation: float = 0.0
@export_range(0.0, 1.0, 0.001) var wind_force: float = 0.0

## 1 = crystal clear, 0 = pea-soup (matches WeatherLighting.visibility).
@export_range(0.0, 1.0, 0.001) var visibility: float = 1.0

## Sky overcast dial; rain still stacks via `precipitation` → `cloud_coverage` merge on the server.
@export_range(0.0, 1.0, 0.001) var cloud_cover: float = 0.0


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
	s.visibility = 1.0
	s.cloud_cover = 0.0
	return s


static func lerp_states(a: WeatherState, b: WeatherState, t: float) -> WeatherState:
	t = clampf(t, 0.0, 1.0)
	var o := WeatherState.new()
	o.precipitation = lerpf(a.precipitation, b.precipitation, t)
	o.wind_force = lerpf(a.wind_force, b.wind_force, t)
	o.visibility = lerpf(a.visibility, b.visibility, t)
	o.cloud_cover = lerpf(a.cloud_cover, b.cloud_cover, t)
	return o
