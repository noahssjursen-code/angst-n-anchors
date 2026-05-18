extends Node

## World-authoritative weather facade.
## Call initialize(seed, port_positions) once after world generation.
## Call get_state_at(position) from anywhere — it now delegates to
## `WeatherField.sample()`, a pure function of (seed, game_time, position),
## then applies a PORT_CALM override around harbours.
##
## Phase 2.5 plan: replace PORT_CALM with a land-distance SDF read by the
## ocean wave shader, then delete the remaining zone code in this file.

var _port_zones: Array[WeatherZone] = []
var _initialized: bool = false
var _blend_to_lighting_paused: bool = false


func set_blend_to_lighting_paused(paused: bool) -> void:
	_blend_to_lighting_paused = paused


func is_blend_to_lighting_paused() -> bool:
	return _blend_to_lighting_paused


func initialize(seed: int, port_positions: Array[Vector3]) -> void:
	# Seed the deterministic noise field — every client with this seed gets
	# bit-identical weather from WeatherField.sample().
	WeatherField.world_seed = seed

	_port_zones.clear()
	_place_port_calm_zones(port_positions)
	_initialized = true


func is_initialized() -> bool:
	return _initialized


func get_state_at(world_pos: Vector3) -> WeatherState:
	# Base weather: noise-driven, time-evolving, deterministic.
	var sample := WeatherField.sample(world_pos)
	var base := sample.to_weather_state()
	if not _initialized or _port_zones.is_empty():
		return base

	# Port calm override — strongest nearby port wins, lerped by shelter weight.
	var pos2d := Vector2(world_pos.x, world_pos.z)
	var port_w     := 0.0
	var port_state : WeatherState = null
	for zone in _port_zones:
		var dist := pos2d.distance_to(zone.center)
		if dist >= zone.outer_radius:
			continue
		var w := smoothstep(zone.outer_radius, zone.inner_radius, dist)
		if w > port_w:
			port_w     = w
			port_state = zone.state

	if port_w > 0.001 and port_state != null:
		return WeatherState.lerp_states(base, port_state, port_w)

	return base


## Returned for back-compat with `map_overlay.gd`. Today this is only the
## PORT_CALM zones — storm/fog/squall are now part of the continuous noise
## field. The map gets its weather visualisation from `WeatherField` directly.
func get_zones() -> Array[WeatherZone]:
	return _port_zones


## Returns 0–1: how much PORT_CALM influence exists at world_pos.
## Used by the tracker to lerp faster when approaching a port.
func get_port_calm_factor(world_pos: Vector3) -> float:
	var pos2d := Vector2(world_pos.x, world_pos.z)
	var total  := 0.0
	for zone in _port_zones:
		var dist := pos2d.distance_to(zone.center)
		if dist < zone.outer_radius:
			total += smoothstep(zone.outer_radius, zone.inner_radius, dist)
	return clampf(total, 0.0, 1.0)


func _place_port_calm_zones(ports: Array[Vector3]) -> void:
	for p in ports:
		var z             := WeatherZone.new()
		z.center          = Vector2(p.x, p.z)
		z.inner_radius    = 180.0
		z.outer_radius    = 600.0
		z.zone_type       = WeatherZone.ZoneType.PORT_CALM
		z.state           = WeatherState.new()
		z.state.precipitation = 0.0
		z.state.wind_force    = 0.04
		z.state.visibility    = 0.92
		z.state.cloud_cover   = 0.05
		_port_zones.append(z)
