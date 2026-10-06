extends SpotLight3D

var elapsed := 1.0

func _ready() -> void:
	rotation.x = -PI*.5
	light_color = Color(1.0,.87,.68)
	light_energy = 5.0
	spot_range = 20.0
	spot_angle = 62.0
	shadow_enabled = false
	distance_fade_enabled = true
	distance_fade_begin = 100.0
	distance_fade_length = 35.0
	_update()

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < .5: return
	elapsed = 0
	_update()

func _update() -> void:
	var time: float = WeatherLighting.time_of_day
	visible = time < .27 or time > .75
