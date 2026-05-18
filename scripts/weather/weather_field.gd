class_name WeatherField
extends RefCounted

## Pure-function entry point for weather queries.
##
## `sample(world_pos, game_time)` returns a `WeatherSample` derived
## ONLY from `world_seed` + `game_time` + `world_pos`. No state, no replication,
## no per-frame sync needed — two clients with the same seed + clock produce
## bit-identical samples.
##
## Phase 2 (this file): layered FastNoiseLite drives pressure, cloud, and a
##                       local jitter band. Wind falls out of the pressure
##                       gradient. WorldWeather still post-processes PORT_CALM
##                       until Phase 2.5 replaces it with a land SDF.
## Phase 3: starts wiring `WeatherSample.wind` through downstream consumers
##           (rain tilt, sails, flags).
## Phase 4: seasons modulate noise params via game_time (year-scale envelope).

## World generation seed — set once at world init, identical on every client.
static var world_seed: int = 0

# ── Tuning ────────────────────────────────────────────────────────────────────
# Pressure: large slow synoptic-scale lows / highs.
# Feature scale is BIG so a sailing boat doesn't cross a whole pressure system
# in a minute. Time scale is generous so weather evolves over real-world
# minutes, not seconds, even when the boat sits still.
const PRESSURE_FEATURE_SCALE_M := 8000.0   ## metres per pressure "cell"
const PRESSURE_TIME_SCALE_H    := 18.0     ## game-hours for a cell to evolve
const PRESSURE_BASE_HPA        := 1013.0
const PRESSURE_AMPLITUDE_HPA   := 28.0     ## ±28 hPa gives 985–1041, realistic

# Cloud: mid-scale cover field.
const CLOUD_FEATURE_SCALE_M := 2800.0
const CLOUD_TIME_SCALE_H    := 6.0

# Local: small fast band — used ONLY for visibility / precip jitter, never wind.
const LOCAL_FEATURE_SCALE_M := 900.0
const LOCAL_TIME_SCALE_H    := 1.5

# Wind: derived from pressure gradient via central differences.
# Stencil is wide (≈ 1/16 of a pressure cell) so the gradient is essentially a
# low-pass of the pressure field — boat motion can't snap-flip the wind by
# walking across a tiny noise wiggle.
const WIND_GRADIENT_EPS_M    := 350.0
## Maps pressure gradient (hPa/m) to wind force [0..1].
## Rebalanced for the wider stencil + larger features (smaller gradients).
const WIND_GRADIENT_GAIN     := 220.0
## Baseline easterly trade so wind is never exactly zero in dead-flat pressure.
const BASELINE_WIND          := Vector3(0.12, 0.0, 0.04)

# Temperature: seasonal envelope arrives in Phase 4. For now a flat constant.
const TEMPERATURE_BASE_C := 15.0

# ── Lazy-init noise generators ───────────────────────────────────────────────
static var _pressure_noise: FastNoiseLite = null
static var _cloud_noise:    FastNoiseLite = null
static var _local_noise:    FastNoiseLite = null
static var _noise_seed_cached: int = 0x7FFFFFFF  # sentinel "not built yet"


static func _ensure_noise() -> void:
	if _pressure_noise != null and _noise_seed_cached == world_seed:
		return
	_noise_seed_cached = world_seed
	_pressure_noise = FastNoiseLite.new()
	_pressure_noise.seed       = world_seed ^ 0x50525353  # 'PRSS'
	_pressure_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_pressure_noise.frequency  = 1.0  # we normalise coords ourselves
	# Single dominant octave — the wind gradient is derived from this field
	# and any high-frequency wiggle becomes a sharp wind shear under
	# finite differences. Keep the pressure field clean and smooth.
	_pressure_noise.fractal_octaves     = 1
	_pressure_noise.fractal_gain        = 0.55
	_pressure_noise.fractal_lacunarity  = 2.1

	_cloud_noise = FastNoiseLite.new()
	_cloud_noise.seed       = world_seed ^ 0x434C4F44  # 'CLOD'
	_cloud_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_cloud_noise.frequency  = 1.0
	_cloud_noise.fractal_octaves    = 4
	_cloud_noise.fractal_gain       = 0.5
	_cloud_noise.fractal_lacunarity = 2.0

	_local_noise = FastNoiseLite.new()
	_local_noise.seed       = world_seed ^ 0x4C4F434C  # 'LOCL'
	_local_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_local_noise.frequency  = 1.0
	_local_noise.fractal_octaves    = 2
	_local_noise.fractal_gain       = 0.5
	_local_noise.fractal_lacunarity = 2.0


## Sample the weather field at `world_pos` for `game_time` (in game-hours since
## the world epoch). Pass a negative `game_time` (the default) to use the
## current value of `/root/WorldClock`.
static func sample(world_pos: Vector3, game_time: float = -1.0) -> WeatherSample:
	_ensure_noise()
	if game_time < 0.0:
		game_time = current_game_time()

	# Seasonal envelope — winters are stormier (bigger pressure swings, stronger
	# trades, more cloud), summers are calmer and clearer. Same on every client.
	var season := Season.modifiers(game_time)

	var s := WeatherSample.new()

	# Pressure: smooth synoptic field, hPa. Amplitude scales with season.
	var pressure_hpa := pressure_at(world_pos, game_time, float(season["pressure_amplitude_mul"]))
	s.pressure = pressure_hpa

	# Wind: geostrophic-ish — perpendicular to pressure gradient, magnitude
	# proportional to |gradient|. Plus a baseline trade wind (winter stronger).
	var wind := _wind_from_gradient(world_pos, game_time,
									 float(season["pressure_amplitude_mul"]),
									 float(season["baseline_wind_mul"]))
	s.wind        = wind
	s.wind_force  = clampf(wind.length(), 0.0, 1.0)

	# Cloud: low pressure → more cloud, plus an independent cloud noise band
	# so coverage doesn't track pressure perfectly. Winter adds an overcast bias.
	var cloud_n      := _sample3(_cloud_noise, world_pos, game_time,
								   CLOUD_FEATURE_SCALE_M, CLOUD_TIME_SCALE_H)
	var pressure_bias := clampf((PRESSURE_BASE_HPA - pressure_hpa) / PRESSURE_AMPLITUDE_HPA, -1.0, 1.0)
	var cloud := clampf(0.45 + 0.35 * cloud_n + 0.30 * pressure_bias + float(season["cloud_bias"]),
						 0.0, 1.0)
	s.cloud_cover = cloud

	# Precipitation: needs cloud cover AND low pressure. Locally jittered.
	var local_n := _sample3(_local_noise, world_pos, game_time,
							 LOCAL_FEATURE_SCALE_M, LOCAL_TIME_SCALE_H)
	var rain_drive := clampf(cloud - 0.55, 0.0, 1.0) * clampf(pressure_bias, 0.0, 1.0)
	# rain_drive is 0..~0.45; scale up and modulate with local jitter.
	var precip := clampf(rain_drive * 2.2 * (0.65 + 0.35 * local_n), 0.0, 1.0)
	s.precipitation = precip

	# Visibility: clear by default; cloud + rain + local fog band cut it.
	var fog_band := clampf((local_n - 0.25) * 0.8, 0.0, 0.5)  # only positive humps fog
	var vis := 1.0 - clampf(0.45 * precip + 0.20 * cloud + fog_band, 0.0, 0.85)
	s.visibility = clampf(vis, 0.15, 1.0)

	# Temperature: base + seasonal offset. Phase 5+ may add latitude / land bias.
	s.temperature = TEMPERATURE_BASE_C + float(season["temperature_offset_c"])

	return s


## Pressure (hPa) at a given point + time. Public so the map / debug can
## sample the raw field without paying for the full WeatherSample. Pass an
## explicit `amplitude_mul` to skip the season lookup (used internally by
## `sample()` and `_wind_from_gradient()` so the four neighbour samples share
## the same season state).
static func pressure_at(world_pos: Vector3, game_time: float = -1.0,
						 amplitude_mul: float = -1.0) -> float:
	_ensure_noise()
	if game_time < 0.0:
		game_time = current_game_time()
	if amplitude_mul < 0.0:
		amplitude_mul = float(Season.modifiers(game_time)["pressure_amplitude_mul"])
	var n := _sample3(_pressure_noise, world_pos, game_time,
					   PRESSURE_FEATURE_SCALE_M, PRESSURE_TIME_SCALE_H)
	return PRESSURE_BASE_HPA + PRESSURE_AMPLITUDE_HPA * amplitude_mul * n


## Current game-time in game-hours since the world epoch. Reads `/root/WorldClock`;
## returns 0.0 if the clock isn't loaded (editor, tests, headless scripts).
static func current_game_time() -> float:
	var clock := _world_clock()
	if clock == null:
		return 0.0
	return float(clock.call("get_game_hours_elapsed"))


## Convenience: same as `sample(pos).wind`. Once Phase 3 lands this is the
## canonical way for non-weather systems (sails, flags, rain tilt) to query wind.
static func sample_wind(world_pos: Vector3, game_time: float = -1.0) -> Vector3:
	return sample(world_pos, game_time).wind


# ── Internals ─────────────────────────────────────────────────────────────────

## 3D noise sampled at (x/feature, time/time_scale, z/feature). Returns -1..1.
static func _sample3(noise: FastNoiseLite, pos: Vector3, time_h: float,
					 feature_m: float, time_scale_h: float) -> float:
	var x := pos.x / feature_m
	var z := pos.z / feature_m
	var t := time_h / time_scale_h
	return noise.get_noise_3d(x, t, z)


static func _wind_from_gradient(pos: Vector3, time_h: float,
								 pressure_amp_mul: float,
								 baseline_wind_mul: float) -> Vector3:
	var eps := WIND_GRADIENT_EPS_M
	var p_xp := pressure_at(pos + Vector3(eps, 0.0, 0.0), time_h, pressure_amp_mul)
	var p_xm := pressure_at(pos - Vector3(eps, 0.0, 0.0), time_h, pressure_amp_mul)
	var p_zp := pressure_at(pos + Vector3(0.0, 0.0, eps), time_h, pressure_amp_mul)
	var p_zm := pressure_at(pos - Vector3(0.0, 0.0, eps), time_h, pressure_amp_mul)
	var gx := (p_xp - p_xm) / (2.0 * eps)
	var gz := (p_zp - p_zm) / (2.0 * eps)
	# Geostrophic: wind blows along the isobars (perpendicular to ∇P),
	# with low pressure on the left in the northern hemisphere.
	# Rotate gradient 90° CCW around +Y → (-gz, 0, gx).
	var dir := Vector3(-gz, 0.0, gx) * WIND_GRADIENT_GAIN
	var wind := BASELINE_WIND * baseline_wind_mul + dir
	# Clamp magnitude to [0..1] so scalar consumers stay happy.
	var mag := wind.length()
	if mag > 1.0:
		wind = wind / mag
	return wind


static func _world_clock() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("WorldClock")
