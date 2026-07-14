class_name AtmosphericEffects
extends Node3D
signal lightning_strike(intensity: float, distance_m: float)


## Runtime-only atmospheric layer: rain particles, lightning, weather audio, and debug HUD.
## Reads weather state from the WeatherLighting autoload. No world or port knowledge.

const RAIN_FIELD_SCRIPT    := preload("res://scripts/weather/rain_field.gd")
const WEATHER_HUD_SCRIPT   := preload("res://scripts/weather/weather_hud.gd")
const WEATHER_AUDIO_SCRIPT := preload("res://scripts/weather/weather_audio_system.gd")

var _lightning_light:      DirectionalLight3D
var _lightning_flash_rect: ColorRect
var _lightning_phase:      int   = 0   # 0=idle  1=flash1  2=gap  3=flash2
var _lightning_phase_t:    float = 0.0
var _active_bolt:          float = 0.0
var _last_lightning_window := -9223372036854775808

const PRESENTATION_TICK: float = 1.0
## Steady blend toward the composed sample. No harbour-specific grace ramp —
## join snaps to the live sample on the first tick.
const PRESENTATION_WEIGHT: float = 0.08
## Skip lighting/VFX fan-out when the blend moved less than this.
const PRESENTATION_EMIT_EPSILON := 0.004
var _presentation_timer: float = 0.0
var _presentation_primed: bool = false


func _ready() -> void:
	_spawn_rain_field()
	_spawn_lightning_system()
	_spawn_weather_audio()
	_spawn_weather_hud()


func _process(delta: float) -> void:
	_update_lightning(delta)
	_presentation_timer += delta
	if _presentation_timer >= PRESENTATION_TICK:
		_presentation_timer = 0.0
		_tick_local_presentation()


func _spawn_rain_field() -> void:
	var rain := RAIN_FIELD_SCRIPT.new() as Node3D
	rain.name = "RainField"
	add_child(rain)


func _spawn_lightning_system() -> void:
	var ll := DirectionalLight3D.new()
	_lightning_light    = ll
	ll.name             = "LightningLight"
	ll.light_color      = Color(0.80, 0.88, 1.0)
	ll.light_energy     = 0.0
	ll.shadow_enabled   = false
	ll.sky_mode         = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	ll.rotation_degrees = Vector3(-55.0, 0.0, 0.0)
	add_child(ll)

	var canvas      := CanvasLayer.new()
	canvas.layer    = 20
	add_child(canvas)
	var rect        := ColorRect.new()
	_lightning_flash_rect = rect
	rect.color      = Color(0.82, 0.90, 1.0, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(rect)


func _spawn_weather_audio() -> void:
	var audio      := WEATHER_AUDIO_SCRIPT.new()
	audio.name     = "WeatherAudio"
	add_child(audio)
	if audio.has_method("_on_lightning_strike"):
		lightning_strike.connect(Callable(audio, "_on_lightning_strike"))


func _spawn_weather_hud() -> void:
	var hud    := WEATHER_HUD_SCRIPT.new()
	hud.name   = "WeatherHUD"
	add_child(hud)


func _update_lightning(delta: float) -> void:
	var daylight := 0.5
	var w := _get_weather()
	if w != null:
		if w.has_method("daylight_factor"):
			daylight = float(w.call("daylight_factor"))
	var convection := float(w.get("convection_index")) if w != null else 0.0
	if convection < 0.22:
		if _lightning_light:      _lightning_light.light_energy = 0.0
		if _lightning_flash_rect: _lightning_flash_rect.color.a = 0.0
		_lightning_phase    = 0
		_active_bolt = 0.0
		return

	if _lightning_phase == 0:
		var game_hours := WeatherField.current_game_time()
		var window := WeatherEventClock.window_at(game_hours)
		if window == _last_lightning_window:
			return
		_last_lightning_window = window
		var cell_id := str(w.get("weather_cell_id"))
		var event := WeatherEventClock.lightning_for_window(
			WeatherField.world_seed,
			cell_id,
			window,
			convection,
		)
		if not bool(event.get("occurs", false)):
			return
		_active_bolt = float(event.get("intensity", 0.0)) * lerpf(0.35, 1.0, daylight)
		if _lightning_light:
			_lightning_light.rotation_degrees = Vector3(
				-50.0,
				float(event.get("bearing_degrees", 0.0)),
				0.0,
			)
		_lightning_phase = 1
		_lightning_phase_t = 0.0
		lightning_strike.emit(
			_active_bolt,
			float(event.get("distance_m", 1000.0)),
		)
		return

	_lightning_phase_t += delta

	match _lightning_phase:
		1: # First flash — sharp spike, quick fade.
			var fade := 1.0 - minf(_lightning_phase_t / 0.07, 1.0)
			if _lightning_light:      _lightning_light.light_energy = fade * 9.0 * _active_bolt
			if _lightning_flash_rect: _lightning_flash_rect.color.a = fade * 0.40 * _active_bolt
			if _lightning_phase_t > 0.07:
				_lightning_phase   = 2
				_lightning_phase_t = 0.0
		2: # Brief dark gap.
			if _lightning_light:      _lightning_light.light_energy = 0.0
			if _lightning_flash_rect: _lightning_flash_rect.color.a = 0.0
			if _lightning_phase_t > 0.05:
				_lightning_phase   = 3
				_lightning_phase_t = 0.0
		3: # Second flash — dimmer, slightly longer.
			var fade := 1.0 - minf(_lightning_phase_t / 0.10, 1.0)
			if _lightning_light:      _lightning_light.light_energy = fade * 5.5 * _active_bolt
			if _lightning_flash_rect: _lightning_flash_rect.color.a = fade * 0.24 * _active_bolt
			if _lightning_phase_t > 0.10:
				if _lightning_light:      _lightning_light.light_energy = 0.0
				if _lightning_flash_rect: _lightning_flash_rect.color.a = 0.0
				_lightning_phase = 0


func _tick_local_presentation() -> void:
	if WorldWeather.is_blend_to_lighting_paused():
		return
	if not WorldWeather.is_initialized():
		return
	var boat_pos := _get_boat_position()
	if boat_pos.x == INF:
		return
	var target := WorldWeather.sample_at(boat_pos).to_weather_state()
	# First live sample snaps — avoid the old clear→weather / weather→harbour-clear
	# grace fade that made ports look artificially fair for the first minute.
	if not _presentation_primed:
		WeatherLighting.apply_weather_state(target)
		_presentation_primed = true
		return
	WeatherLighting.blend_towards(target, PRESENTATION_WEIGHT, PRESENTATION_EMIT_EPSILON)


func _get_boat_position() -> Vector3:
	for n in get_tree().get_nodes_in_group("player_boat"):
		var rb := n as RigidBody3D
		if rb != null:
			return rb.global_position
	for n in get_tree().get_nodes_in_group("player"):
		var cb := n as CharacterBody3D
		if cb != null:
			return cb.global_position
	return Vector3(INF, INF, INF)


func _get_weather() -> Node:
	return get_node_or_null("/root/WeatherLighting")
