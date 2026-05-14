class_name WeatherLightingState
extends Node

signal state_changed
signal control_mode_changed(mode: String)

const TIME_RATE: float = 0.22
const WEATHER_RATE: float = 0.45
const WAVE_RATE: float = 1.0
const MODE_WEATHER: String = "weather"
const MODE_WAVES: String = "waves"

@export_range(0.0, 1.0, 0.001) var time_of_day: float = 0.42:
	set(v):
		time_of_day = wrapf(v, 0.0, 1.0)
		state_changed.emit()

@export_range(0.0, 1.0, 0.001) var weather_amount: float = 0.0:
	set(v):
		weather_amount = clampf(v, 0.0, 1.0)
		_apply_wave_weather()
		state_changed.emit()

@export_enum("weather", "waves") var control_mode: String = MODE_WEATHER:
	set(v):
		var next_mode := MODE_WAVES if v == MODE_WAVES else MODE_WEATHER
		if control_mode == next_mode:
			return
		control_mode = next_mode
		control_mode_changed.emit(control_mode)

@export var automatic_time_enabled: bool = false
@export var day_length_seconds: float = 900.0
@export var weather_drives_waves: bool = false:
	set(v):
		weather_drives_waves = v
		_apply_wave_weather()

@export var clear_wave_intensity: float = 0.65:
	set(v):
		clear_wave_intensity = v
		_apply_wave_weather()

@export var storm_wave_intensity: float = 3.25:
	set(v):
		storm_wave_intensity = v
		_apply_wave_weather()


func _ready() -> void:
	_apply_wave_weather()


func _process(delta: float) -> void:
	if automatic_time_enabled and day_length_seconds > 0.0:
		time_of_day += delta / day_length_seconds
	if Engine.is_editor_hint():
		return
	_apply_held_arrow_controls(delta)


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
			toggle_control_mode()
			get_viewport().set_input_as_handled()
		_:
			pass


func toggle_control_mode() -> void:
	control_mode = MODE_WAVES if control_mode == MODE_WEATHER else MODE_WEATHER


func bump_time(delta: float) -> void:
	time_of_day += delta


func bump_weather(delta: float) -> void:
	weather_amount += delta


func bump_waves(delta: float) -> void:
	WaveSurface.bump_wave_intensity(delta)


func set_weather_drives_waves(enabled: bool) -> void:
	weather_drives_waves = enabled


func _apply_held_arrow_controls(delta: float) -> void:
	var horizontal := int(Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_LEFT))
	var vertical := int(Input.is_key_pressed(KEY_UP)) - int(Input.is_key_pressed(KEY_DOWN))

	if control_mode == MODE_WEATHER:
		if horizontal != 0:
			bump_time(float(horizontal) * TIME_RATE * delta)
		if vertical != 0:
			bump_weather(float(vertical) * WEATHER_RATE * delta)
	elif control_mode == MODE_WAVES and vertical != 0:
		bump_waves(float(vertical) * WAVE_RATE * delta)


func _apply_wave_weather() -> void:
	if not weather_drives_waves:
		return
	var wave_value := lerpf(clear_wave_intensity, storm_wave_intensity, weather_amount)
	WaveSurface.wave_intensity = clampf(
		wave_value,
		WaveSurface.WAVE_INTENSITY_MIN,
		WaveSurface.WAVE_INTENSITY_MAX
	)
