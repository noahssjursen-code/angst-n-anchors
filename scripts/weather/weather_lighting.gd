class_name WeatherLightingState
extends Node

## Smoothed local projection of WorldWeather. This autoload is a presentation
## facade, never an independent weather authority. Consumers subscribe to
## `state_changed`; AtmosphericEffects is the sole runtime writer.
##
## `wind_force` is air severity; `sea_state` is the local built-wave envelope.
## `wind_speed_ms` (0→30 m/s) is the actual wind hitting the hull — drives ship aerodynamics.
## These are correlated but separable: a fresh squall hits the hull before waves build.
## cloud_cover (0→1) is independent: overcast sky without necessarily any rain.
## visibility (0→1) is independent: 0 = pea-soup fog, 1 = crystal clear.
## time_of_day (0→1) is also independent: 0/1 = midnight, 0.5 = noon.

signal state_changed

## Suppress per-property state_changed emits and wave-intensity resyncs while a
## bulk update is in flight (apply_weather_state, blend_towards). Each setter
## still updates its field; the caller is responsible for emitting once and
## resyncing once after all fields are set. Drops 4 emits → 1 per blend tick,
## which used to fan out into 4 full shader-uniform re-applies in WorldRenderer.
var _suppress_emit:      bool = false
var _suppress_wave_sync: bool = false

const WIND_SPEED_MAX     : float = 30.0  # m/s. ~58 knots, Beaufort 10/11

# --- Axis 0 : time of day ---
@export_range(0.0, 1.0, 0.001) var time_of_day: float = 0.42:
	set(v):
		var next := wrapf(v, 0.0, 1.0)
		var visual_delta := absf(wrapf(next - time_of_day, -0.5, 0.5))
		time_of_day = next
		# WorldClock updates every frame; weather rendering only needs a refresh
		# after a visually meaningful sun movement (~0.02 degrees).
		if not _suppress_emit and visual_delta >= 0.00005:
			state_changed.emit()

# --- Independent: cloud cover (0 clear sky → 1 fully overcast, no rain required) ---
@export_range(0.0, 1.0, 0.001) var cloud_cover: float = 0.0:
	set(v):
		cloud_cover = clampf(v, 0.0, 1.0)
		if not _suppress_emit:
			state_changed.emit()

# --- Independent: precipitation (0 clear → 1 downpour). Controlled via Ctrl+←/→ ---
@export_range(0.0, 1.0, 0.001) var precipitation: float = 0.0:
	set(v):
		precipitation = clampf(v, 0.0, 1.0)
		if not _suppress_emit:
			state_changed.emit()

# --- Axis Y : wind force (0 becalmed → 1 gale) ---
## Drives wave/storm visuals (Beaufort-scale equivalent). Independent of `wind_speed_ms`
## so an old swell (high `wind_force`, low `wind_speed_ms`) and a fresh squall (low
## `wind_force`, high `wind_speed_ms`) are both representable.
@export_range(0.0, 1.0, 0.001) var wind_force: float = 0.0:
	set(v):
		wind_force = clampf(v, 0.0, 1.0)
		if not _suppress_emit:
			state_changed.emit()

## Locally built sea/fetch. Separate from instantaneous wind so harbours can
## remain protected while an offshore front is visible.
@export_range(0.0, 1.0, 0.001) var sea_state: float = 0.0:
	set(v):
		sea_state = clampf(v, 0.0, 1.0)
		if not _suppress_wave_sync:
			_sync_wave_intensity()
		if not _suppress_emit:
			state_changed.emit()

@export_range(0.0, 12.0, 0.05) var significant_wave_height_m: float = 0.25
@export var pressure_hpa: float = 1013.0
@export var temperature_c: float = 15.0
@export_range(0.0, 1.0, 0.001) var exposure: float = 1.0
@export_range(0.0, 1.0, 0.001) var front_intensity: float = 0.0
@export_range(0.0, 1.0, 0.001) var convection_index: float = 0.0
@export_range(0.0, 1.0, 0.001) var humidity: float = 0.5
@export var weather_cell_id: String = ""
@export var component_ids: Dictionary = {}
@export var zone_label: String = "Open ocean"
@export var front_label: String = ""

# --- Axis X : wind speed in m/s (the actual aerodynamic wind on the hull) ---
## Drives aerodynamic drag on superstructure (HydrodynamicsComponent). 0–30 m/s
## covers calm to storm-force. `wind_dir` carries the direction; this is the magnitude.
@export_range(0.0, 30.0, 0.1) var wind_speed_ms: float = 0.0:
	set(v):
		wind_speed_ms = clampf(v, 0.0, WIND_SPEED_MAX)
		if not _suppress_emit:
			state_changed.emit()

# --- Axis Z : visibility (1 crystal-clear → 0 pea-soup fog) ---
@export_range(0.0, 1.0, 0.001) var visibility: float = 1.0:
	set(v):
		visibility = clampf(v, 0.0, 1.0)
		if not _suppress_emit:
			state_changed.emit()

## Horizontal wind vector (XZ plane). Magnitude is normalised to ≤ 1 so it
## composes cleanly with `wind_force` — direction lives here, intensity in
## `wind_force`. Pumped each tick by AtmosphericEffects from
## `WeatherField.sample_wind(boat_pos)` (geostrophic pressure gradient).
## Consumers wanting wind-aware tilt (rain, smoke, flags, sails) should read
## this instead of inventing their own direction.
@export var wind_dir: Vector3 = Vector3(-1.0, 0.0, 0.0):
	set(v):
		v.y = 0.0
		var mag := v.length()
		wind_dir = v if mag <= 1.0 else (v / mag)
		if not _suppress_emit:
			state_changed.emit()

var wind_velocity_ms: Vector3:
	get:
		return wind_dir.normalized() * wind_speed_ms

# --- Derived convenience getters ---
## Effective sky cloud opacity 0–1: explicit `cloud_cover` plus rain-grey when precip is high.
## Wind does **not** add fake overcast (dry squalls stay visually clear).
var cloud_coverage: float:
	get: return cloud_cover

## Rain visual amount 0–1: only appears past the first 30% precipitation.
var rain_amount: float:
	get: return smoothstep(0.18, 1.0, precipitation)

## Thunder / lightning 0–1: driven by the *combined* storminess of the
## weather. Heavy rain alone (calm-air thunderstorm) ramps it up, but a
## strong dry squall (wind without much rain) can also flicker. Tuned for
## the Phase-2 noise field's distribution of precip/wind — the old threshold
## was 0.50 precip, which the deterministic field reaches only briefly in
## the heart of a deep low; now the gate opens earlier and tracks the joint
## storm signal.
var thunder_intensity: float:
	get: return convection_index

## Storm darkness 0–1: sky/ocean grimness driven primarily by heavy rain, allowing storms without huge waves.
var storm_intensity: float:
	get:
		var rain_darkness := smoothstep(0.48, 1.0, precipitation) * cloud_cover
		return maxf(rain_darkness, convection_index)

## Fog density 0–1 (inverted visibility).
var fog_density: float:
	get: return 1.0 - visibility

## Legacy compat: old callers expected a single “weather” scalar for VFX volume.
var weather_amount: float:
	get: return maxf(precipitation, cloud_cover * 0.35)

## Compact axes for gameplay / AI: **x** = precipitation, **y** = wind, **z** = fog density (`1 − visibility`).
## Ocean swell follows `sea_state`. **Cloud** stays on `cloud_cover`;
## **time** stays on `time_of_day` — neither is in this vector.
var weather_vector: Vector3:
	get: return Vector3(precipitation, wind_force, fog_density)

# --- Wave coupling ---
@export var weather_drives_waves: bool = true
@export var calm_wave_intensity: float  = 0.33  # was 0.55 — scaled down 40%
@export var gale_wave_intensity: float  = 1.10  # was 1.83 — scaled down 40%

func _ready() -> void:
	_sync_wave_intensity()


## Shared solar daylight used by sky, sun, exposure, and artificial lights.
## Includes long Norwegian maritime twilight instead of a fixed 06–18 day.
func daylight_factor() -> float:
	return SolarCycle.daylight_factor(time_of_day)


## Multiplier for artificial light_energy / emission. Night stays 1.0; noon
## keeps a tiny residual so deliberate daytime work lights still read as on.
func artificial_light_scale() -> float:
	return lerpf(1.0, 0.05, daylight_factor())


## Multiplier for light_volumetric_fog_energy. Clear day kills peripheral fog
## wash from fixtures; dense fog still allows a little daytime scatter.
func artificial_volumetric_scale() -> float:
	var fog_keep := smoothstep(0.25, 0.55, fog_density)
	return lerpf(1.0, fog_keep * 0.15, daylight_factor())


func _sync_wave_intensity() -> void:
	if not weather_drives_waves:
		return
	var intensity := lerpf(calm_wave_intensity, gale_wave_intensity, pow(sea_state, 1.35))
	WaveSurface.wave_intensity = clampf(
		intensity,
		WaveSurface.WAVE_INTENSITY_MIN,
		WaveSurface.WAVE_INTENSITY_MAX
	)
	WaveSurface.set_weather_short_wave_factor(
		sea_state,
		precipitation,
		storm_intensity
	)


## Bulk-assign compass + fog.**z** is fog density (1 = pea soup). Leaves `cloud_cover` and `time_of_day`.
## For presets prefer `apply_weather_state(WeatherState)` so cloud + fog travel together.
func set_weather_vector(v: Vector3) -> void:
	_suppress_emit      = true
	_suppress_wave_sync = true
	precipitation = v.x
	wind_force    = v.y
	visibility    = 1.0 - clampf(v.z, 0.0, 1.0)
	_suppress_wave_sync = false
	_suppress_emit      = false
	_sync_wave_intensity()
	state_changed.emit()


func get_weather_state() -> WeatherState:
	var s := WeatherState.new()
	s.precipitation = precipitation
	s.wind_force = wind_force
	s.wind_speed_ms = wind_speed_ms
	s.visibility = visibility
	s.cloud_cover = cloud_cover
	s.sea_state = sea_state
	s.significant_wave_height_m = significant_wave_height_m
	s.wind_direction = wind_dir
	s.wind_velocity_ms = wind_velocity_ms
	s.pressure_hpa = pressure_hpa
	s.temperature_c = temperature_c
	s.exposure = exposure
	s.front_intensity = front_intensity
	s.convection_index = convection_index
	s.humidity = humidity
	s.weather_cell_id = weather_cell_id
	s.component_ids = component_ids.duplicate()
	s.zone_label = zone_label
	s.front_label = front_label
	return s


## Apply full snapshot (zones, authored `.tres`, runtime generators). Leaves `time_of_day` untouched.
## Bulk-updates all axes then emits `state_changed` once + resyncs waves
## once — without the suppression flags this fired multiple redundant emits, each
## triggering a full sky/sun/ocean shader-uniform reapply in WorldRenderer.
func apply_weather_state(next: WeatherState, emit_epsilon: float = 0.0) -> void:
	if next == null:
		return
	var next_sea := next.sea_state if next.sea_state >= 0.0 else next.wind_force
	if emit_epsilon > 0.0 and _near_weather_state(next, next_sea, emit_epsilon):
		return
	_suppress_emit      = true
	_suppress_wave_sync = true
	precipitation  = next.precipitation
	wind_force     = next.wind_force
	wind_speed_ms  = next.wind_speed_ms
	visibility     = next.visibility
	cloud_cover    = next.cloud_cover
	sea_state      = next_sea
	significant_wave_height_m = next.significant_wave_height_m
	wind_dir = next.wind_direction
	pressure_hpa = next.pressure_hpa
	temperature_c = next.temperature_c
	exposure = next.exposure
	front_intensity = next.front_intensity
	convection_index = next.convection_index
	humidity = next.humidity
	weather_cell_id = next.weather_cell_id
	component_ids = next.component_ids.duplicate()
	zone_label = next.zone_label
	front_label = next.front_label
	_suppress_wave_sync = false
	_suppress_emit      = false
	_sync_wave_intensity()
	state_changed.emit()


## Convenience for drift / biome edges: blend current weather toward target (weight 1 = adopt target).
func blend_towards(target: WeatherState, weight: float, emit_epsilon: float = 0.0) -> void:
	if target == null:
		return
	apply_weather_state(WeatherState.lerp_states(get_weather_state(), target, weight), emit_epsilon)


func _near_weather_state(next: WeatherState, next_sea: float, epsilon: float) -> bool:
	return (
		absf(precipitation - next.precipitation) < epsilon
		and absf(wind_force - next.wind_force) < epsilon
		and absf(wind_speed_ms - next.wind_speed_ms) < epsilon * 30.0
		and absf(visibility - next.visibility) < epsilon
		and absf(cloud_cover - next.cloud_cover) < epsilon
		and absf(sea_state - next_sea) < epsilon
		and absf(convection_index - next.convection_index) < epsilon
		and absf(exposure - next.exposure) < epsilon
	)

func bump_time(delta: float) -> void:
	var clock := get_node_or_null("/root/WorldClock")
	if clock != null and clock.has_method("snap_time_of_day"):
		clock.call("snap_time_of_day", wrapf(time_of_day + delta, 0.0, 1.0))

func set_weather_drives_waves(enabled: bool) -> void:
	weather_drives_waves = enabled
