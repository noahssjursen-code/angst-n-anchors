class_name WeatherLightingState
extends Node

## Weather state: precipitation (X) × wind_force (Y), plus independent cloud_cover, fog, and time.
##
## Political-compass axes:
##   X=0,Y=0 → clear calm  (perfect sailing day)
##   X=1,Y=0 → heavy rain, flat sea  (grey drizzle)
##   X=0,Y=1 → dry squall  (fast, tall seas, clear sky)
##   X=1,Y=1 → full gale  (dark, violent)
##
## cloud_cover (0→1) is independent: overcast sky without necessarily any rain.
## visibility (0→1) is independent: 0 = pea-soup fog, 1 = crystal clear.
## time_of_day (0→1) is also independent: 0/1 = midnight, 0.5 = noon.

signal state_changed

# --- Rates for keyboard scrubbing ---
const TIME_RATE          : float = 0.22
const PRECIP_RATE        : float = 0.40
const WIND_RATE          : float = 0.40
const VIS_RATE           : float = 0.35
const CLOUD_RATE         : float = 0.40
const WAVE_RATE          : float = 1.0

# --- Axis 0 : time of day ---
@export_range(0.0, 1.0, 0.001) var time_of_day: float = 0.42:
	set(v):
		time_of_day = wrapf(v, 0.0, 1.0)
		state_changed.emit()

# --- Independent: cloud cover (0 clear sky → 1 fully overcast, no rain required) ---
@export_range(0.0, 1.0, 0.001) var cloud_cover: float = 0.0:
	set(v):
		cloud_cover = clampf(v, 0.0, 1.0)
		state_changed.emit()

# --- Axis X : precipitation (0 clear → 1 downpour) ---
@export_range(0.0, 1.0, 0.001) var precipitation: float = 0.0:
	set(v):
		precipitation = clampf(v, 0.0, 1.0)
		_sync_wave_intensity()
		state_changed.emit()

# --- Axis Y : wind force (0 becalmed → 1 gale) ---
@export_range(0.0, 1.0, 0.001) var wind_force: float = 0.0:
	set(v):
		wind_force = clampf(v, 0.0, 1.0)
		_sync_wave_intensity()
		state_changed.emit()

# --- Axis Z : visibility (1 crystal-clear → 0 pea-soup fog) ---
@export_range(0.0, 1.0, 0.001) var visibility: float = 1.0:
	set(v):
		visibility = clampf(v, 0.0, 1.0)
		state_changed.emit()

# --- Derived convenience getters ---
## Cloud coverage 0–1: cloud_cover is the primary dial; rain and wind add on top.
var cloud_coverage: float:
	get: return clampf(maxf(cloud_cover, precipitation * 0.65 + wind_force * 0.25), 0.0, 1.0)

## Rain visual amount 0–1: only appears past the first 30% precipitation.
var rain_amount: float:
	get: return smoothstep(0.30, 1.0, precipitation)

## Gale darkness 0–1: extra sky darkening on high wind + precipitation.
var storm_intensity: float:
	get: return clampf(precipitation * wind_force, 0.0, 1.0)

## Fog density 0–1 (inverted visibility).
var fog_density: float:
	get: return 1.0 - visibility

# --- Automatic time progression ---
@export var automatic_time_enabled: bool = false
@export var day_length_seconds: float = 900.0

# --- Wave coupling ---
@export var weather_drives_waves: bool = true
@export var calm_wave_intensity: float  = 0.55
@export var gale_wave_intensity: float  = 3.40

# --- Control mode (L to toggle) ---
const MODE_WEATHER : String = "weather"
const MODE_WAVES   : String = "waves"
@export_enum("weather", "waves") var control_mode: String = MODE_WEATHER

# --- Keyboard axis being dragged in weather mode ---
# Up/Down = wind, Left/Right = precipitation by default.
# Holding SHIFT swaps: Up/Down = time, Left/Right = fog.


func _ready() -> void:
	_sync_wave_intensity()


func _process(delta: float) -> void:
	if automatic_time_enabled and day_length_seconds > 0.0:
		time_of_day += delta / day_length_seconds
	if Engine.is_editor_hint():
		return
	_apply_held_controls(delta)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.physical_keycode:
		KEY_L:
			control_mode = MODE_WAVES if control_mode == MODE_WEATHER else MODE_WEATHER
			get_viewport().set_input_as_handled()
		_:
			pass


func _apply_held_controls(delta: float) -> void:
	var h     := int(Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_LEFT))
	var v     := int(Input.is_key_pressed(KEY_UP))    - int(Input.is_key_pressed(KEY_DOWN))
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var ctrl  := Input.is_key_pressed(KEY_CTRL)

	# Ctrl+Up/Down — wave height; Ctrl+Left/Right — cloud cover. Always available.
	if ctrl:
		if v != 0:
			WaveSurface.bump_wave_intensity(float(v) * WAVE_RATE * delta)
		if h != 0:
			cloud_cover = clampf(cloud_cover + float(h) * CLOUD_RATE * delta, 0.0, 1.0)
		return

	if control_mode == MODE_WAVES:
		if v != 0:
			WaveSurface.bump_wave_intensity(float(v) * WAVE_RATE * delta)
		return

	# Weather mode:
	if shift:
		# Shift: horizontal = time of day, vertical = fog/visibility
		if h != 0:
			time_of_day += float(h) * TIME_RATE * delta
		if v != 0:
			visibility = clampf(visibility + float(v) * VIS_RATE * delta, 0.0, 1.0)
			state_changed.emit()
	else:
		# Plain: RIGHT = more rain, LEFT = less rain.
		# UP = calmer (less wind, dot moves toward calm corner at top),
		# DOWN = more wind/gale (dot moves toward storm corner at bottom).
		if h != 0:
			precipitation = clampf(precipitation + float(h) * PRECIP_RATE * delta, 0.0, 1.0)
		if v != 0:
			wind_force = clampf(wind_force - float(v) * WIND_RATE * delta, 0.0, 1.0)


func _sync_wave_intensity() -> void:
	if not weather_drives_waves:
		return
	var intensity := lerpf(calm_wave_intensity, gale_wave_intensity, wind_force)
	WaveSurface.wave_intensity = clampf(
		intensity,
		WaveSurface.WAVE_INTENSITY_MIN,
		WaveSurface.WAVE_INTENSITY_MAX
	)


# --- Legacy compat shims so old callers don't break ---

## Read-only: returns the heavier of precipitation/wind for backward compat.
var weather_amount: float:
	get: return cloud_coverage

func bump_time(delta: float) -> void:
	time_of_day += delta

func bump_weather(delta: float) -> void:
	precipitation = clampf(precipitation + delta, 0.0, 1.0)

func bump_waves(delta: float) -> void:
	WaveSurface.bump_wave_intensity(delta)

func set_weather_drives_waves(enabled: bool) -> void:
	weather_drives_waves = enabled

func toggle_control_mode() -> void:
	control_mode = MODE_WAVES if control_mode == MODE_WEATHER else MODE_WEATHER
