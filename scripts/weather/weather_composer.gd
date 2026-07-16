class_name WeatherComposer
extends RefCounted

## Composes raw synoptic weather with geographic exposure and deterministic
## fronts. This is the single authoritative gameplay weather calculation.
##
## Exposure shelters the built sea so docks stay workable. It does **not** clear
## sky, rain, fog, or convection — ports keep authentic local weather.


## Chart / overlay path — skips kilometre-scale coastal_exposure (16 fetch rays).
## Gameplay must keep calling `sample()`; this is presentation-only.
static func sample_chart(world_pos: Vector3, game_hours: float = -1.0) -> WeatherSample:
	if game_hours < 0.0:
		game_hours = WeatherField.current_game_time()
	var base := WeatherField.sample(world_pos, game_hours)
	var front_data := WeatherFrontField.sample_at(world_pos, game_hours)
	var front_intensity := float(front_data.get("intensity", 0.0))
	var base_direction := base.wind.normalized()
	if base_direction.length_squared() < 0.25:
		base_direction = Vector3(0.95, 0.0, 0.30).normalized()
	## Chart: open-sea assumption. Skip wave_shelter too — dock calm is
	## invisible at chart scale and was still per-cell LandField work.
	var exposure := 1.0
	var storm_access := 1.0
	var local_sea_access := 1.0
	return _compose_from_parts(
		base, front_data, front_intensity, base_direction, exposure, storm_access, local_sea_access
	)


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
	## Front gale boost needs open fetch; dock wave calm uses local shelter only.
	var storm_access := pow(exposure, 0.72)
	var local_sea_access := _local_sea_access(world_pos)
	return _compose_from_parts(
		base, front_data, front_intensity, base_direction, exposure, storm_access, local_sea_access
	)


static func _compose_from_parts(
		base: WeatherSample,
		front_data: Dictionary,
		front_intensity: float,
		base_direction: Vector3,
		exposure: float,
		storm_access: float,
		local_sea_access: float,
) -> WeatherSample:

	var sample := WeatherSample.new()
	sample.pressure = base.pressure - front_intensity * 13.0
	sample.temperature = base.temperature - front_intensity * 2.5
	sample.exposure = exposure
	sample.front_intensity = front_intensity
	sample.weather_cell_id = base.weather_cell_id
	sample.component_ids = base.component_ids.duplicate()
	sample.humidity = base.humidity

	var front: WeatherFront = front_data.get("front") as WeatherFront
	var front_direction := base_direction
	if front != null and front.velocity_m_per_game_hour.length_squared() > 0.01:
		front_direction = Vector3(
			front.velocity_m_per_game_hour.x, 0.0, front.velocity_m_per_game_hour.y
		).normalized()
	var wind_direction := base_direction.slerp(front_direction, front_intensity * 0.4)

	# Air wind stays authentic. Only the gale boost from a front needs fetch so
	# a harbour does not invent a hurricane from an offshore squall line.
	sample.wind_force = clampf(base.wind_force + front_intensity * 0.42 * storm_access, 0.0, 1.0)
	sample.wind_speed_ms = clampf(
		base.wind_speed_ms + front_intensity * 18.0 * storm_access,
		0.0,
		30.0
	)
	sample.wind = wind_direction * sample.wind_force
	sample.wind_velocity_ms = wind_direction * sample.wind_speed_ms

	sample.cloud_cover = clampf(base.cloud_cover + front_intensity * 0.18 * storm_access, 0.0, 1.0)
	var front_rain_support := (
		front_intensity * front_intensity
		* storm_access
		* smoothstep(0.42, 0.82, sample.cloud_cover)
	)
	sample.precipitation = clampf(base.precipitation + front_rain_support * 0.22, 0.0, 1.0)

	# Fog stays an independent selected dimension. Light wind can disperse a little.
	var fog_density := 1.0 - base.visibility
	var wind_dispersion := sample.wind_force * 0.22
	sample.visibility = 1.0 - clampf(fog_density * (1.0 - wind_dispersion), 0.0, 0.88)

	# Sea state uses local shore shelter only (hundreds of metres). Kilometre-scale
	# coastal fetch used to crush swell across entire fjord routes and left the
	# chart looking permanently flat.
	var swell := base.sea_state * local_sea_access
	var wind_sea := sample.wind_force * local_sea_access * 0.55
	var front_sea := front_intensity * local_sea_access * storm_access * 0.55
	sample.sea_state = clampf(maxf(swell, maxf(wind_sea, front_sea)), 0.0, 1.0)
	sample.significant_wave_height_m = lerpf(
		0.25,
		10.0,
		pow(sample.sea_state, 1.35)
	)

	sample.convection_index = clampf(
		base.convection_index
		* smoothstep(0.48, 0.82, sample.cloud_cover)
		* smoothstep(0.38, 0.78, sample.precipitation)
		* lerpf(0.65, 1.0, front_intensity),
		0.0,
		1.0,
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


## 1 = full seas, 0 = at the quay / inside land. Tight falloff so only docks
## and immediate shore stay calm — not the whole coastal sailing belt.
static func _local_sea_access(world_pos: Vector3) -> float:
	if not LandField.is_initialized():
		return 1.0
	return clampf(LandField.wave_shelter(world_pos), 0.0, 1.0)


static func _zone_label(exposure: float, front: float, sea_state: float) -> String:
	if front > 0.72 and exposure > 0.65:
		return "Gale core"
	if front > 0.35 and exposure > 0.45:
		return "Squall line"
	if exposure < 0.12:
		return "Sheltered harbour"
	if exposure < 0.42:
		return "Coastal water"
	if exposure < 0.78:
		return "Exposed coastal water"
	if sea_state > 0.65:
		return "Open-ocean gale"
	return "Open ocean"
