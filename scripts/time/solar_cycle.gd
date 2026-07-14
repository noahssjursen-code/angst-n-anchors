class_name SolarCycle
extends RefCounted

## Shared maritime summer solar model. Every presentation system must derive
## sun position and daylight from this class so the disk, shadows, sky,
## exposure, and artificial lights cannot drift apart.
##
## Local solar times target a Norwegian coastal summer: long evenings and
## nautical twilight through most of the night.

const SUNRISE_HOUR := 4.5
const SOLAR_NOON_HOUR := 13.25
const SUNSET_HOUR := 22.0
const MAX_ELEVATION_DEG := 52.0

const _DAY_HALF_HOURS := (SUNSET_HOUR - SUNRISE_HOUR) * 0.5
const _HORIZON_RAW := -0.6593458


static func sample(time_of_day: float) -> Dictionary:
	var hour := wrapf(time_of_day, 0.0, 1.0) * 24.0
	var from_noon := wrapf(hour - SOLAR_NOON_HOUR, -12.0, 12.0)
	var raw_elevation := cos(from_noon / 12.0 * PI)
	var height_norm := (raw_elevation - _HORIZON_RAW) / (1.0 - _HORIZON_RAW)
	var altitude_degrees := height_norm * MAX_ELEVATION_DEG
	var altitude := deg_to_rad(altitude_degrees)

	## +X east, -Z north, +Z south. Summer sunrise/sunset naturally land
	## north-east/north-west while solar noon points south.
	var azimuth := from_noon / 24.0 * TAU
	var horizontal := cos(altitude)
	var sun_direction := Vector3(
		-sin(azimuth) * horizontal,
		sin(altitude),
		cos(azimuth) * horizontal,
	).normalized()

	## Direct shadows begin around sunrise and build smoothly over ~90 minutes.
	## Ambient/sky daylight includes nautical twilight well below the horizon.
	var direct_light := smoothstep(-1.5, 10.0, altitude_degrees)
	var daylight := smoothstep(-10.0, 14.0, altitude_degrees)
	var moonlight := smoothstep(1.0, 9.0, -altitude_degrees)

	return {
		"hour": hour,
		"altitude_degrees": altitude_degrees,
		"sun_direction": sun_direction,
		"moon_direction": -sun_direction,
		"direct_light": direct_light,
		"daylight": daylight,
		"moonlight": moonlight,
	}


static func daylight_factor(time_of_day: float) -> float:
	return float(sample(time_of_day)["daylight"])


static func direct_light_factor(time_of_day: float) -> float:
	return float(sample(time_of_day)["direct_light"])
