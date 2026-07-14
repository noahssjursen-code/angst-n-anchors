extends Node

## World-authoritative weather facade.
##
## Call `initialize(seed, port_positions)` once after world generation. From
## then on `get_state_at(pos)` delegates to `WeatherField.sample()` — a pure
## function of (seed, game_time, pos), so every client with the same seed +
## WorldClock sees bit-identical weather without any replication.
##
## Harbour wave shelter comes from composed `LandField` exposure on sea state
## only — sky/rain/fog stay authentic. No local scene node can override the
## deterministic weather authority.

var _initialized: bool = false
var _blend_to_lighting_paused: bool = false
var _sample_cache: Dictionary = {}
var _cache_hits: int = 0
var _cache_misses: int = 0
var _last_sample_usec: int = 0
const CACHE_POSITION_M := 125.0
## Presentation only needs a fresh compose a few times per game-hour. The old
## 0.10 bucket expired every ~6 real seconds and forced LandField fetch rays
## on the gameplay thread — the hitch cadence players were feeling.
const CACHE_TIME_HOURS := 0.5
const CACHE_LIMIT := 4096
const WEATHER_GENERATION_VERSION := 3


func set_blend_to_lighting_paused(paused: bool) -> void:
	_blend_to_lighting_paused = paused


func is_blend_to_lighting_paused() -> bool:
	return _blend_to_lighting_paused


func initialize(
		seed: int,
		_port_positions: Array[Vector3],
		weather_generation_version: int = WEATHER_GENERATION_VERSION,
) -> void:
	# Seed the deterministic noise field — every client with this seed gets
	# bit-identical weather from WeatherField.sample().
	WeatherField.world_seed = seed
	if weather_generation_version != WEATHER_GENERATION_VERSION:
		push_error(
			"WorldWeather: generation version mismatch (requested %d, runtime %d)"
			% [weather_generation_version, WEATHER_GENERATION_VERSION]
		)
	WeatherFrontField.initialize(seed)
	WeatherProfileCatalog.clear_cache()
	WeatherCellSampler.clear_cache()
	_sample_cache.clear()
	_initialized = true


func is_initialized() -> bool:
	return _initialized


func get_state_at(world_pos: Vector3) -> WeatherState:
	return sample_at(world_pos).to_weather_state()


## Stable authoritative API: deterministic composed weather at position/time.
func sample_at(world_pos: Vector3, game_hours: float = -1.0) -> WeatherSample:
	if game_hours < 0.0:
		game_hours = WeatherField.current_game_time()
	var key := Vector3i(
		roundi(world_pos.x / CACHE_POSITION_M),
		roundi(world_pos.z / CACHE_POSITION_M),
		roundi(game_hours / CACHE_TIME_HOURS),
	)
	if _sample_cache.has(key):
		_cache_hits += 1
		return _sample_cache[key] as WeatherSample
	var started := Time.get_ticks_usec()
	var sample := WeatherComposer.sample(world_pos, game_hours)
	_last_sample_usec = Time.get_ticks_usec() - started
	_cache_misses += 1
	if _sample_cache.size() >= CACHE_LIMIT:
		_sample_cache.clear()
	_sample_cache[key] = sample
	return sample


func sample_route(points: PackedVector3Array, spacing_m: float = 500.0,
		game_hours: float = -1.0) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	if points.is_empty():
		return samples
	if game_hours < 0.0:
		game_hours = WeatherField.current_game_time()
	var distance_along := 0.0
	samples.append({
		"position": points[0],
		"distance_m": 0.0,
		"weather": sample_at(points[0], game_hours),
	})
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var segment_length := a.distance_to(b)
		var count := maxi(1, ceili(segment_length / maxf(spacing_m, 50.0)))
		for step in range(1, count + 1):
			var t := float(step) / float(count)
			var position := a.lerp(b, t)
			samples.append({
				"position": position,
				"distance_m": distance_along + segment_length * t,
				"weather": sample_at(position, game_hours),
			})
		distance_along += segment_length
	return samples


## Batched canonical sampling for chart rasters and forecast grids.
func sample_batch(points: PackedVector3Array, game_hours: float = -1.0) -> Array[WeatherSample]:
	var result: Array[WeatherSample] = []
	result.resize(points.size())
	for i in range(points.size()):
		result[i] = sample_at(points[i], game_hours)
	return result


func active_fronts(bounds: Rect2, game_hours: float = -1.0) -> Array[Dictionary]:
	if game_hours < 0.0:
		game_hours = WeatherField.current_game_time()
	return WeatherFrontField.fronts_in_bounds(bounds, game_hours)


var local_presentation: WeatherState:
	get:
		var lighting := get_node_or_null("/root/WeatherLighting")
		if lighting != null and lighting.has_method("get_weather_state"):
			return lighting.call("get_weather_state") as WeatherState
		return WeatherState.create_clear_calm()


func get_debug_metrics() -> Dictionary:
	return {
		"sample_usec": _last_sample_usec,
		"cache_entries": _sample_cache.size(),
		"cache_hits": _cache_hits,
		"cache_misses": _cache_misses,
		"front_count": WeatherFrontField.active_fronts().size(),
		"weather_generation_version": WEATHER_GENERATION_VERSION,
	}
