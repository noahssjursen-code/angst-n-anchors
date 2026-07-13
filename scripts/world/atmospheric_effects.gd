class_name AtmosphericEffects
extends Node3D

## Runtime-only atmospheric layer: rain particles, lightning, weather audio, and debug HUD.
## Reads weather state from the WeatherLighting autoload. No world or port knowledge.

const RAIN_FIELD_SCRIPT    := preload("res://scripts/weather/rain_field.gd")
const WEATHER_HUD_SCRIPT   := preload("res://scripts/weather/weather_hud.gd")
const WEATHER_AUDIO_SCRIPT := preload("res://scripts/weather/weather_audio_system.gd")

var _lightning_light:      DirectionalLight3D
var _lightning_flash_rect: ColorRect
var _lightning_cooldown:   float = 2.0
var _lightning_phase:      int   = 0   # 0=idle  1=flash1  2=gap  3=flash2
var _lightning_phase_t:    float = 0.0

const PRESENTATION_TICK: float = 0.5
## Time-domain hysteresis: roughly 19 seconds half-life at the normal cadence,
## faster near land so entering/leaving shelter remains legible.
const PRESENTATION_WEIGHT: float = 0.018
## When the boat is hugging the shore the field can step hard (you cross
## the harbour edge and shelter goes 1→0). Cap how much faster lerping gets.
const SHORE_LERP_BOOST : float = 0.035
var _presentation_timer: float = 0.0


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


func _spawn_weather_hud() -> void:
	var hud    := WEATHER_HUD_SCRIPT.new()
	hud.name   = "WeatherHUD"
	add_child(hud)


func _update_lightning(delta: float) -> void:
	var thunder := 0.0
	var daylight := 0.5
	var w := _get_weather()
	if w:
		thunder = float(w.get("thunder_intensity"))
		var tod := float(w.get("time_of_day"))
		var elev_norm := -cos(tod * TAU)
		daylight = smoothstep(-0.18, 0.55, elev_norm)

	var bolt := thunder * lerpf(0.12, 1.0, daylight)

	# Slightly lower than the old 0.08 floor — pairs with the new wider
	# thunder formula so distant squalls still get the occasional flicker
	# instead of being totally silent.
	if bolt < 0.05:
		if _lightning_light:      _lightning_light.light_energy = 0.0
		if _lightning_flash_rect: _lightning_flash_rect.color.a = 0.0
		_lightning_phase    = 0
		_lightning_cooldown = randf_range(3.0, 8.0)
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
			# Cooldown is inversely proportional to bolt strength, with a
			# 3 s floor so peak storms flicker like a real thunderstorm
			# instead of strobing. Light storms get a long quiet between
			# strikes; heavy storms still feel active.
			_lightning_cooldown = maxf(3.0, randf_range(4.0, 14.0) / maxf(bolt, 0.05))
		return

	_lightning_phase_t += delta

	match _lightning_phase:
		1: # First flash — sharp spike, quick fade.
			var fade := 1.0 - minf(_lightning_phase_t / 0.07, 1.0)
			if _lightning_light:      _lightning_light.light_energy = fade * 9.0 * bolt
			if _lightning_flash_rect: _lightning_flash_rect.color.a = fade * 0.40 * bolt
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
			if _lightning_light:      _lightning_light.light_energy = fade * 5.5 * bolt
			if _lightning_flash_rect: _lightning_flash_rect.color.a = fade * 0.24 * bolt
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
	var exposure := target.exposure

	# Composition is authoritative; this node only time-smooths the local view.
	var weight := lerpf(PRESENTATION_WEIGHT, SHORE_LERP_BOOST, 1.0 - exposure)
	WeatherLighting.blend_towards(target, weight)


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
