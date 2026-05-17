class_name FogHorn
extends AudioStreamPlayer3D

## A directional foghorn that sounds out miles away at sea when fog is present.
## Automatically selects a random tone and plays periodically during low visibility.

const HORN_SOUNDS: Array[String] = [
	"res://resources/audio/looped/foghorns/fog_horn_1.wav",
	"res://resources/audio/looped/foghorns/fog_horn_2.wav",
	"res://resources/audio/looped/foghorns/fog_horn_3.wav"
]

@export var blast_interval_seconds: float = 30.0
@export var min_fog_density_to_play: float = 0.25

var _timer: Timer

func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	# Setup audio properties for extremely long distance sound
	max_distance = 8000.0 # Heard miles away
	unit_size = 50.0      # Attenuates slowly (large source)
	bus = &"Master"       # Ensure it routes correctly (adjust if you have a specific bus)
	
	# Pick a random horn sound and stick to it forever for this port
	var sound_path = HORN_SOUNDS.pick_random()
	if ResourceLoader.exists(sound_path):
		stream = load(sound_path)
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_DISABLED # Just in case it's set to loop
	
	_timer = Timer.new()
	_timer.wait_time = blast_interval_seconds + randf_range(-5.0, 5.0) # Slight randomization to desync multiple ports
	_timer.autostart = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)


func _on_timer_timeout() -> void:
	var weather = get_node_or_null("/root/WeatherLighting")
	if weather:
		var fog = float(weather.get("fog_density"))
		if fog >= min_fog_density_to_play:
			play()
