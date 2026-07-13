class_name MenuBackdrop
extends Node3D

## Calm ocean/sky menu presentation. No fake ports, no orphan captain.

var camera: Camera3D

var orbit_angle := 0.0
var orbit_speed := 0.018
var orbit_radius := 48.0
var orbit_height := 14.0
var look_at := Vector3(0.0, 1.2, 0.0)
var _target_radius := 48.0
var _target_height := 14.0
var _target_look_at := Vector3(0.0, 1.2, 0.0)


func _ready() -> void:
	_configure_weather()
	var renderer_script := load("res://scripts/world/world_renderer.gd")
	if renderer_script != null:
		var renderer: Node3D = renderer_script.new()
		renderer.name = "BackgroundWorldRenderer"
		add_child(renderer)

	camera = Camera3D.new()
	camera.name = "BackgroundCamera"
	camera.current = true
	camera.far = 40000.0
	add_child(camera)


func _process(delta: float) -> void:
	orbit_radius = lerpf(orbit_radius, _target_radius, 4.0 * delta)
	orbit_height = lerpf(orbit_height, _target_height, 4.0 * delta)
	look_at = look_at.lerp(_target_look_at, 4.0 * delta)
	orbit_angle += orbit_speed * delta
	if camera == null or not is_instance_valid(camera):
		return
	var offset := Vector3(
		cos(orbit_angle) * orbit_radius,
		orbit_height + sin(orbit_angle * 0.5) * 1.8,
		sin(orbit_angle) * orbit_radius,
	)
	camera.global_position = look_at + offset
	camera.look_at(look_at, Vector3.UP)


func set_cinematic(page_name: String) -> void:
	match page_name:
		"multiplayer":
			_target_radius = 36.0
			_target_height = 10.0
			_target_look_at = Vector3(0.0, 1.4, 0.0)
		"creator":
			_target_radius = 42.0
			_target_height = 12.0
			_target_look_at = Vector3(0.0, 1.2, 0.0)
		_:
			_target_radius = 48.0
			_target_height = 14.0
			_target_look_at = Vector3(0.0, 1.2, 0.0)


func _configure_weather() -> void:
	var weather_lighting := get_node_or_null("/root/WeatherLighting")
	if weather_lighting == null:
		return
	randomize()
	weather_lighting.set("time_of_day", randf_range(0.22, 0.72))
	weather_lighting.set("cloud_cover", randf_range(0.18, 0.45))
	weather_lighting.set("precipitation", 0.0)
	var breeze := randf_range(0.08, 0.28)
	weather_lighting.set("wind_force", breeze)
	weather_lighting.set("sea_state", breeze * 0.5)
	weather_lighting.set("visibility", 1.0)
