class_name RainField
extends Node3D

## World-space rain. Velocity-aligned optical streaks share the scene lighting;
## one quad per drop, no glowing rigid boxes or camera-relative falling motion.
@export var max_amount: int = 6000
@export var field_extents := Vector3(24.0, 2.0, 24.0)
@export var height_above_camera := 8.0

# Only weather particles receive this local collision field. Other effects
# keep their own contact policy. All ordinary opaque meshes can shelter rain.
const RAIN_COLLISION_LAYER := 1 << 19
const SHELTER_INTERVAL := 0.125

var _particles: GPUParticles3D
var _process_material: ParticleProcessMaterial
var _shelter: GPUParticlesCollisionHeightField3D
var _shelter_timer := 0.0
var _shelter_lifetime := 0.0


func _ready() -> void:
	_build_particles()
	_build_shelter()
	var weather := get_node_or_null("/root/WeatherLighting")
	if weather != null:
		weather.state_changed.connect(_apply_weather)
	_apply_weather()


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position + Vector3.UP * height_above_camera
		# Stop all height-map work once the last wet-weather drops have expired.
		_shelter_lifetime = _particles.lifetime if _particles.emitting else maxf(0.0, _shelter_lifetime - delta)
		_shelter.visible = _shelter_lifetime > 0.0
		_shelter_timer -= delta
		if _shelter.visible and _shelter_timer <= 0.0:
			_shelter_timer = SHELTER_INTERVAL
			_shelter.global_position = camera.global_position.snapped(Vector3(4,4,4))
			# Ships/doors can move while the camera stays inside a snapped cell.
			RenderingServer.particles_collision_height_field_update(_shelter.get_base())


func _build_shelter() -> void:
	_shelter = GPUParticlesCollisionHeightField3D.new()
	_shelter.name = "RainShelter"
	_shelter.size = Vector3(80,64,80)
	_shelter.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_shelter.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_shelter.cull_mask = RAIN_COLLISION_LAYER
	_shelter.visible = false
	add_child(_shelter)
	# The emitter follows every frame; the collision field updates at most 8Hz.
	_shelter.top_level = true


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "RainParticles"
	_particles.amount = max_amount
	_particles.lifetime = 2.0
	_particles.preprocess = 2.0
	_particles.local_coords = false
	_particles.fixed_fps = 60
	_particles.layers = 1 | RAIN_COLLISION_LAYER
	# Include the optical half-streak, not just its microscopic physical radius,
	# so its tail cannot flash through thin roofs between particle steps.
	_particles.collision_base_size = 0.12
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
	_process_material.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
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
