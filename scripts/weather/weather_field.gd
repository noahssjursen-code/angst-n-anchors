class_name WeatherField
extends RefCounted

## Pure-function entry point for weather queries.
##
## `sample(world_pos, game_time)` returns a `WeatherSample` derived
## ONLY from `world_seed` + `game_time` + `world_pos`. No state, no replication,
## no per-frame sync needed — two clients with the same seed + clock produce
## bit-identical samples.
##
## Phase 1 (this file): delegates to the existing zone system so every caller
##                       can migrate to WeatherField without behavior change.
## Phase 2: replaces the zone delegation with layered noise.
## Phase 3: starts populating WeatherSample.wind from pressure gradient.
## Phase 4: seasons modulate noise params via game_time.

## World generation seed — set once at world init, identical on every client.
static var world_seed: int = 0


## Sample the weather field at `world_pos` for `game_time` (in game-hours since
## the world epoch). Pass a negative `game_time` (the default) to use the
## current value of `/root/WorldClock`.
static func sample(world_pos: Vector3, game_time: float = -1.0) -> WeatherSample:
	if game_time < 0.0:
		game_time = current_game_time()
	# Phase 1: delegate to WorldWeather zone blend. Phases 2+ replace this.
	var state := _zone_state_at(world_pos)
	var s := WeatherSample.from_weather_state(state)
	# wind_force is a scalar today; expose it as a flat vector pointing along
	# +X so downstream consumers can already read wind.length() / wind.normalized()
	# without breaking. Phase 3 swaps this for a real pressure-gradient wind.
	s.wind = Vector3(s.wind_force, 0.0, 0.0)
	# pressure / temperature stay at their resource defaults until phases 2 + 4.
	return s


## Current game-time in game-hours since the world epoch. Reads `/root/WorldClock`;
## returns 0.0 if the clock isn't loaded (editor, tests, headless scripts).
static func current_game_time() -> float:
	var clock := _world_clock()
	if clock == null:
		return 0.0
	return float(clock.call("get_game_hours_elapsed"))


## Convenience: same as `sample(pos).wind`. Cheap because Phase-1 wind is
## derived in one line — once Phase 3 lands this becomes the canonical way
## for non-weather systems (sails, flags, rain tilt) to query wind direction.
static func sample_wind(world_pos: Vector3, game_time: float = -1.0) -> Vector3:
	return sample(world_pos, game_time).wind


# ── Internals ─────────────────────────────────────────────────────────────────

static func _world_clock() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("WorldClock")


static func _zone_state_at(world_pos: Vector3) -> WeatherState:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return WeatherState.new()
	var ww := loop.root.get_node_or_null("WorldWeather")
	if ww == null:
		return WeatherState.new()
	return ww.call("get_state_at", world_pos) as WeatherState
