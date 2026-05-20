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

const ZONE_TICK     : float = 0.5    # seconds between zone polls
## Lerp weight per tick. ~0.006 = ≈60s half-life on wind_force, so a calm-to-
## storm transition takes minutes of real time even if the underlying noise
## sample changes abruptly (e.g. when the boat sails into a new pressure
## system). Higher values feel jittery; lower than this feels laggy.
const ZONE_WEIGHT   : float = 0.006
## Wind-direction lerp. Slightly faster than wind_force so big rotations
## feel responsive; still smooth enough to never look like a snap.
const WIND_DIR_LERP : float = 0.035
## When the boat is hugging the shore the field can step hard (you cross
## the harbour edge and shelter goes 1→0). Cap how much faster lerping gets.
const SHORE_LERP_BOOST : float = 0.025
var _zone_timer     : float = 0.0


func _ready() -> void:
	_spawn_rain_field()
	_spawn_lightning_system()
	_spawn_weather_audio()
	_spawn_weather_hud()


func _process(delta: float) -> void:
	_update_lightning(delta)
	_zone_timer += delta
	if _zone_timer >= ZONE_TICK:
		_zone_timer = 0.0
		_tick_zone_weather()


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


func _tick_zone_weather() -> void:
	if WorldWeather.is_blend_to_lighting_paused():
		return
	if not WorldWeather.is_initialized():
		return
	var boat_pos := _get_boat_position()
	if boat_pos.x == INF:
		return
	var target := WorldWeather.get_state_at(boat_pos) as WeatherState

	# Harbour shelter: scale the wave-driving wind_force by distance-to-land
	# (LandField SDF). Open ocean is unchanged; near shore even a storm gets
	# its wave amplitude knocked down, which kills the old "waves clipping
	# through islands" bug PORT_CALM was a hack-fix for.
	var shelter := LandField.shore_shelter(boat_pos)
	target.wind_force = target.wind_force * lerpf(0.15, 1.0, shelter)
	# Slight precip dampening near shore too — looks better, and matches
	# real-world lee-side calm.
	target.precipitation = target.precipitation * lerpf(0.55, 1.0, shelter)

	# Slight boost to lerp weight near land so the shore transition isn't laggy,
	# but capped at SHORE_LERP_BOOST so even at the shoreline it stays smooth.
	var weight := lerpf(ZONE_WEIGHT, SHORE_LERP_BOOST, 1.0 - shelter)
	WeatherLighting.blend_towards(target, weight)

	# Wind direction: same geostrophic vector that drove `target.wind_force`,
	# blended toward smoothly so direction shifts feel natural.
	var wind_vec   := WeatherField.sample_wind(boat_pos) * lerpf(0.15, 1.0, shelter)
	WeatherLighting.wind_dir = WeatherLighting.wind_dir.lerp(wind_vec, WIND_DIR_LERP)


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
