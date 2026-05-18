class_name FogHorn
extends AudioStreamPlayer3D

@export var min_fog_density_to_play: float = 0.20

var _is_active: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	# 3D Audio setup
	max_distance = 10000.0
	unit_size = 80.0       # Increased from 50.0 to carry much further without falling off
	volume_db = 12.0       # Boosted base volume
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	bus = &"Master"
	
	# Load the audio.
	stream = load("res://resources/audio/looped/foghorns/fog_horn_1.wav")


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or stream == null:
		return

	var fog      := _sample_fog_density()
	var should_play := fog >= min_fog_density_to_play

	if should_play and not _is_active:
		_is_active = true
		play()
	elif not should_play and _is_active:
		_is_active = false
		stop()


func _sample_fog_density() -> float:
	var ww := get_node_or_null("/root/WorldWeather")
	if ww != null and ww.is_initialized():
		# Sample own position + 4 cardinal points 220 m out.
		# Use the worst fog found so the horn reacts to fog approaching
		# from sea even though the port calm zone shelters the horn itself.
		var worst := 0.0
		for offset in [Vector3.ZERO,
				Vector3(220, 0, 0), Vector3(-220, 0, 0),
				Vector3(0, 0, 220), Vector3(0, 0, -220)]:
			var fd: float = ww.get_state_at(global_position + offset).fog_density
			if fd > worst:
				worst = fd
		return worst
	# Fallback to player's current weather if WorldWeather isn't up yet.
	var weather := get_node_or_null("/root/WeatherLighting")
	if weather != null:
		return float(weather.get("fog_density"))
	return 0.0
