class_name AtmosphericEffects
extends Node3D

## Runtime-only atmospheric layer: rain particles, lightning, weather audio, and debug HUD.
## Reads weather state from the WeatherLighting autoload. No world or port knowledge.

const RAIN_FIELD_SCRIPT    := preload("res://scripts/systems/weather/rain_field.gd")
const WEATHER_HUD_SCRIPT   := preload("res://scripts/systems/weather/weather_hud.gd")
const WEATHER_AUDIO_SCRIPT := preload("res://scripts/systems/audio/weather_audio_system.gd")

var _lightning_light:      DirectionalLight3D
var _lightning_flash_rect: ColorRect
var _lightning_cooldown:   float = 2.0
var _lightning_phase:      int   = 0   # 0=idle  1=flash1  2=gap  3=flash2
var _lightning_phase_t:    float = 0.0


func _ready() -> void:
	_spawn_rain_field()
	_spawn_lightning_system()
	_spawn_weather_audio()
	_spawn_weather_hud()


func _process(delta: float) -> void:
	_update_lightning(delta)


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


func _spawn_weather_hud() -> void:
	var hud    := WEATHER_HUD_SCRIPT.new()
	hud.name   = "WeatherHUD"
	add_child(hud)


func _update_lightning(delta: float) -> void:
	var storm := 0.0
	var w     := _get_weather()
	if w:
		storm = float(w.get("storm_intensity"))

	if storm < 0.20:
		if _lightning_light:      _lightning_light.light_energy = 0.0
		if _lightning_flash_rect: _lightning_flash_rect.color.a = 0.0
		_lightning_phase    = 0
		_lightning_cooldown = randf_range(2.0, 6.0)
		return

	if _lightning_phase == 0:
		_lightning_cooldown -= delta
		if _lightning_cooldown <= 0.0:
			if _lightning_light:
				_lightning_light.rotation_degrees = Vector3(
					randf_range(-70.0, -30.0),
					randf_range(0.0, 360.0),
					0.0
				)
			_lightning_phase    = 1
			_lightning_phase_t  = 0.0
			_lightning_cooldown = randf_range(1.5, 10.0) / storm
		return

	_lightning_phase_t += delta

	match _lightning_phase:
		1: # First flash — sharp spike, quick fade.
			var fade := 1.0 - minf(_lightning_phase_t / 0.07, 1.0)
			if _lightning_light:      _lightning_light.light_energy = fade * 9.0 * storm
			if _lightning_flash_rect: _lightning_flash_rect.color.a = fade * 0.40 * storm
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
			if _lightning_light:      _lightning_light.light_energy = fade * 5.5 * storm
			if _lightning_flash_rect: _lightning_flash_rect.color.a = fade * 0.24 * storm
			if _lightning_phase_t > 0.10:
				if _lightning_light:      _lightning_light.light_energy = 0.0
				if _lightning_flash_rect: _lightning_flash_rect.color.a = 0.0
				_lightning_phase = 0


func _get_weather() -> Node:
	return get_node_or_null("/root/WeatherLighting")
