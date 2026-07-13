class_name WeatherComposer
extends RefCounted

## Composes raw synoptic weather with geographic exposure and deterministic
## fronts. This is the single authoritative gameplay weather calculation.

const COASTAL_WIND_FLOOR := 0.16
const COASTAL_RAIN_FLOOR := 0.18
const COASTAL_CLOUD_FLOOR := 0.28
const CLEAR_COASTAL_VISIBILITY := 0.94


static func sample(world_pos: Vector3, game_hours: float = -1.0) -> WeatherSample:
	if game_hours < 0.0:
		game_hours = WeatherField.current_game_time()
	var base := WeatherField.sample(world_pos, game_hours)
	var front_data := WeatherFrontField.sample_at(world_pos, game_hours)
	var front_intensity := float(front_data.get("intensity", 0.0))
	var base_direction := base.wind.normalized()
	if base_direction.length_squared() < 0.25:
		base_direction = Vector3(0.95, 0.0, 0.30).normalized()
	var exposure := _exposure_at(world_pos, base_direction)
	var offshore := smoothstep(0.08, 0.95, exposure)
	var storm_access := pow(exposure, 0.72)

	var sample := WeatherSample.new()
	sample.pressure = base.pressure - front_intensity * 13.0
	sample.temperature = base.temperature - front_intensity * 2.5
	sample.exposure = exposure
	sample.front_intensity = front_intensity

	var front: WeatherFront = front_data.get("front") as WeatherFront
	var front_direction := base_direction
	if front != null and front.velocity_m_per_game_hour.length_squared() > 0.01:
		front_direction = Vector3(
			front.velocity_m_per_game_hour.x, 0.0, front.velocity_m_per_game_hour.y
		).normalized()
	var wind_direction := base_direction.slerp(front_direction, front_intensity * 0.4)

	# Common coast: light/moderate. Dangerous values require both exposure and
	# a coherent front, so a noisy pressure sample alone cannot create a gale.
	var sheltered_base := base.wind_force * lerpf(COASTAL_WIND_FLOOR, 1.0, offshore)
	var front_wind := front_intensity * 0.82 * storm_access
	sample.wind_force = clampf(sheltered_base + front_wind, 0.0, 1.0)
	sample.wind_speed_ms = clampf(
		base.wind_speed_ms * lerpf(0.22, 1.0, offshore)
		+ front_intensity * 18.0 * storm_access,
		0.0,
		30.0
	)
	sample.wind = wind_direction * sample.wind_force
	sample.wind_velocity_ms = wind_direction * sample.wind_speed_ms

	var coastal_cloud := lerpf(0.16, base.cloud_cover, lerpf(COASTAL_CLOUD_FLOOR, 1.0, offshore))
	sample.cloud_cover = clampf(
		coastal_cloud + front_intensity * 0.52 * storm_access,
		0.0,
		1.0
	)
	sample.precipitation = clampf(
		base.precipitation * lerpf(COASTAL_RAIN_FLOOR, 1.0, offshore)
		+ front_intensity * front_intensity * 0.78 * storm_access,
		0.0,
		1.0
	)
	var weather_visibility := minf(base.visibility, 1.0 - sample.precipitation * 0.58)
	sample.visibility = clampf(
		lerpf(CLEAR_COASTAL_VISIBILITY, weather_visibility, offshore)
		- front_intensity * 0.28 * storm_access,
		0.12,
		1.0
	)

	# Sea state needs fetch. A front visible over the horizon does not create
	# harbour waves until the local exposure opens up.
	var wind_sea := sample.wind_force * lerpf(0.12, 1.0, exposure)
	var front_sea := front_intensity * pow(exposure, 1.25)
	sample.sea_state = clampf(maxf(wind_sea, front_sea), 0.0, 1.0)
	sample.significant_wave_height_m = lerpf(
		0.25,
		10.0,
		pow(sample.sea_state, 1.65)
	)
	sample.zone_label = _zone_label(exposure, front_intensity, sample.sea_state)
	sample.front_label = str(front_data.get("label", ""))
	return sample


static func _exposure_at(world_pos: Vector3, wind_direction: Vector3) -> float:
	if not LandField.is_initialized():
		return 1.0
	var regional := LandField.coastal_exposure(world_pos)
	var upwind := -Vector2(wind_direction.x, wind_direction.z)
	var wind_fetch := LandField.directional_fetch(world_pos, upwind)
	return clampf(regional * lerpf(0.55, 1.0, wind_fetch), 0.0, 1.0)


static func _zone_label(exposure: float, front: float, sea_state: float) -> String:
	if front > 0.72 and exposure > 0.65:
		return "Gale core"
	if front > 0.35 and exposure > 0.45:
		return "Squall line"
	if exposure < 0.12:
		return "Harbour calm"
	if exposure < 0.42:
		return "Coastal breeze"
	if exposure < 0.78:
		return "Exposed coastal water"
	if sea_state > 0.65:
		return "Open-ocean gale"
	return "Open ocean"
