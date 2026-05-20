class_name RainField
extends Node3D

## Camera-following rain volume driven by `precipitation` / `rain_amount` on WeatherLighting.
## Uses procedural streak meshes only: no imported textures or VFX assets.

@export_range(0.0, 1.0, 0.001) var rain_start: float = 0.58
@export var max_amount: int = 1800
@export var field_extents: Vector3 = Vector3(34.0, 12.0, 34.0)
@export var height_above_camera: float = 7.0
@export var fall_speed_clear: float = 11.0
@export var fall_speed_storm: float = 19.0
## Per-axis wind multipliers applied to `WeatherLighting.wind_dir` when
## tilting rain streaks. Magnitude is the rain-space horizontal speed at
## `wind_force == 0` / `== 1` respectively, in roughly m/s.
@export var wind_tilt_calm:  float = 1.8
@export var wind_tilt_storm: float = 6.5

var _particles: GPUParticles3D
var _process_material: ParticleProcessMaterial


func _ready() -> void:
	_build_particles()
	_connect_weather_lighting()
	_apply_weather()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	global_position = camera.global_position + Vector3.UP * height_above_camera


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "RainParticles"
	_particles.amount = max_amount
	_particles.lifetime = 1.2
	_particles.preprocess = 1.2
	_particles.visibility_aabb = AABB(-field_extents, field_extents * 2.0)
	_particles.emitting = false
	add_child(_particles)

	_process_material = ParticleProcessMaterial.new()
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_material.emission_box_extents = field_extents
	_process_material.direction = Vector3.DOWN
	_process_material.spread = 4.0
	_process_material.gravity = Vector3(0.0, -22.0, 0.0)
	_process_material.initial_velocity_min = fall_speed_clear
	_process_material.initial_velocity_max = fall_speed_storm
	_process_material.scale_min = 0.7
	_process_material.scale_max = 1.25
	_process_material.color = Color(0.62, 0.72, 0.82, 0.55)
	_particles.process_material = _process_material

	var streak := BoxMesh.new()
	streak.size = Vector3(0.018, 0.42, 0.018)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.72, 0.82, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.18
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = mat
	_particles.draw_pass_1 = streak


func _connect_weather_lighting() -> void:
	var weather := _weather_lighting()
	if weather == null:
		return
	var callable := Callable(self, "_apply_weather")
	if not weather.is_connected("state_changed", callable):
		weather.connect("state_changed", callable)


func _apply_weather() -> void:
	if _particles == null or _process_material == null:
		return

	var precip   := 0.0
	var wind     := 0.0
	var wind_dir := Vector3(-1.0, 0.0, 0.0)
	var weather  := _weather_lighting()
	if weather != null:
		precip   = float(weather.get("precipitation"))
		wind     = float(weather.get("wind_force"))
		wind_dir = weather.get("wind_dir") as Vector3

	var rain_amount := smoothstep(rain_start, 1.0, precip)
	_particles.emitting = rain_amount > 0.01
	_particles.amount_ratio = rain_amount

	_process_material.initial_velocity_min = lerpf(fall_speed_clear, fall_speed_storm, rain_amount)
	_process_material.initial_velocity_max = lerpf(
		fall_speed_clear * 1.25,
		fall_speed_storm,
		rain_amount
	)
	_process_material.gravity = Vector3(0.0, lerpf(-16.0, -30.0, rain_amount), 0.0)

	# Wind tilt: direction from WeatherLighting.wind_dir (geostrophic gradient,
	# smoothed in AtmosphericEffects); magnitude scales with wind_force so
	# calm days have a gentle drift and storms shear hard sideways.
	var tilt_mag := lerpf(wind_tilt_calm, wind_tilt_storm, wind)
	_process_material.direction = (Vector3.DOWN + wind_dir * tilt_mag).normalized()


func _weather_lighting() -> Node:
	return get_node_or_null("/root/WeatherLighting")
