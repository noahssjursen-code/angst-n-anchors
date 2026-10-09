class_name RainField
extends Node3D

## World-space rain. Velocity-aligned optical streaks share the scene lighting;
## one quad per drop, no glowing rigid boxes or camera-relative falling motion.
@export var max_amount: int = 6000
@export var field_extents := Vector3(24.0, 8.0, 24.0)
@export var height_above_camera := 6.0

var _particles: GPUParticles3D
var _process_material: ParticleProcessMaterial


func _ready() -> void:
	_build_particles()
	var weather := get_node_or_null("/root/WeatherLighting")
	if weather != null:
		weather.state_changed.connect(_apply_weather)
	_apply_weather()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position + Vector3.UP * height_above_camera


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "RainParticles"
	_particles.amount = max_amount
	_particles.lifetime = 2.0
	_particles.preprocess = 2.0
	_particles.local_coords = false
	_particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.visibility_aabb = AABB(Vector3(-45, -32, -45), Vector3(90, 48, 90))
	_particles.emitting = false
	add_child(_particles)
	_process_material = ParticleProcessMaterial.new()
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_material.emission_box_extents = field_extents
	_process_material.direction = Vector3.DOWN
	_process_material.spread = 3.0
	# Drops already fall at terminal speed; don't accelerate through the ground.
	_process_material.gravity = Vector3.ZERO
	_process_material.scale_min = 0.65
	_process_material.scale_max = 1.25
	_particles.process_material = _process_material
	var streak := QuadMesh.new()
	streak.size = Vector2(0.010, 0.20)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://resources/shaders/rain_streak.gdshader")
	streak.material = mat
	_particles.draw_pass_1 = streak


func _apply_weather() -> void:
	if _particles == null:
		return
	var weather := get_node_or_null("/root/WeatherLighting")
	var rain := float(weather.get("rain_amount")) if weather else 0.0
	_particles.emitting = rain > 0.01
	_particles.amount_ratio = rain
	var velocity := Vector3.DOWN * lerpf(6.0, 10.0, rain)
	if weather:
		velocity += (weather.get("wind_dir") as Vector3) * float(weather.get("wind_speed_ms")) * 0.45
	_process_material.direction = velocity.normalized()
	_process_material.initial_velocity_min = velocity.length() * 0.9
	_process_material.initial_velocity_max = velocity.length() * 1.1
