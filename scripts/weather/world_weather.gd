extends Node

## World-authoritative weather facade.
##
## Call `initialize(seed, port_positions)` once after world generation. From
## then on `get_state_at(pos)` delegates to `WeatherField.sample()` — a pure
## function of (seed, game_time, pos), so every client with the same seed +
## WorldClock sees bit-identical weather without any replication.
##
## Harbour calm is no longer a special weather zone. Wave amplitude is
## dampened near land by `LandField.shore_shelter()`; see
## `atmospheric_effects.gd` for the consumer side.

var _initialized: bool = false
var _blend_to_lighting_paused: bool = false


func set_blend_to_lighting_paused(paused: bool) -> void:
	_blend_to_lighting_paused = paused


func is_blend_to_lighting_paused() -> bool:
	return _blend_to_lighting_paused


func initialize(seed: int, _port_positions: Array[Vector3]) -> void:
	# Seed the deterministic noise field — every client with this seed gets
	# bit-identical weather from WeatherField.sample().
	WeatherField.world_seed = seed
	_initialized = true


func is_initialized() -> bool:
	return _initialized


func get_state_at(world_pos: Vector3) -> WeatherState:
	return WeatherField.sample(world_pos).to_weather_state()


## Deprecated — Phase 5 will give the map a proper weather visualisation
## (pressure isobars, wind barbs, storm centres). For back-compat returns [].
func get_zones() -> Array[WeatherZone]:
	return []


## How "close to shore" we are, in 0..1 — kept for back-compat with the
## tracker / atmospheric blender. Forwards to the LandField SDF, which has
## already replaced PORT_CALM as the source of harbour shelter.
func get_port_calm_factor(world_pos: Vector3) -> float:
	return LandField.shore_proximity(world_pos)
