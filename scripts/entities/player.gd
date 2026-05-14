extends CharacterBody3D

# ── Movement ──────────────────────────────────────────────────────────────────
@export_group("Movement")
@export var walk_speed:          float = 4.5
@export var sprint_speed:        float = 8.5
@export var ground_acceleration: float = 20.0
@export var ground_friction:     float = 24.0
@export var air_acceleration:    float = 10.0
@export var air_friction:        float = 5.0
@export var input_smoothness:     float = 8.0
@export var speed_blend_sharpness: float = 6.0

# ── Jump ──────────────────────────────────────────────────────────────────────
@export_group("Jump")
@export var jump_peak_height:           float = 0.9
@export var fall_gravity_multiplier:    float = 1.4
@export var jump_cut_gravity_multiplier: float = 3.0

# ── Camera & Feel ─────────────────────────────────────────────────────────────
@export_group("Camera")
@export var mouse_sensitivity:    float = 0.0015
@export var base_fov:             float = 90.0
@export var sprint_fov_multiplier: float = 1.08
@export var strafe_tilt_angle:    float = 1.8
@export var head_bob_frequency:   float = 10.0
@export var head_bob_amplitude:   float = 0.055

const MAX_PITCH  := deg_to_rad(88.0)
const BASE_GRAVITY := 20.0   # stronger than real-world 9.8 — keeps feet planted
const LAYER_PLAYER := 8
const LAYER_BOAT_WALK := 4

@onready var camera: Camera3D = $Camera3D

var _pitch:            float   = 0.0
var _smoothed_input:   Vector2 = Vector2.ZERO
var _current_speed:    float   = 0.0
var _bob_time:         float   = 0.0
var _camera_y_offset:  float   = 0.0
var _was_on_floor:     bool    = true
var _camera_base_y:    float   = 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = LAYER_PLAYER
	collision_mask |= LAYER_BOAT_WALK
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_camera_base_y = camera.position.y
	_current_speed = walk_speed
	camera.fov = base_fov


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -MAX_PITCH, MAX_PITCH)
		camera.rotation.x = _pitch

	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# Landing — dip the camera slightly on impact, recover smoothly
	if on_floor and not _was_on_floor:
		_camera_y_offset = clampf(velocity.y * 0.045, -0.45, 0.0)
	_was_on_floor = on_floor

	# Gravity — variable scale depending on jump state
	if not on_floor:
		var g_scale := fall_gravity_multiplier
		if velocity.y > 0.0:
			g_scale = 1.0 if Input.is_action_pressed("jump") else jump_cut_gravity_multiplier
		velocity.y -= BASE_GRAVITY * g_scale * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	# Jump impulse derived from desired peak height
	if Input.is_action_just_pressed("jump") and on_floor:
		velocity.y = sqrt(2.0 * BASE_GRAVITY * jump_peak_height)

	# Smooth raw input on the forward axis — strafe stays immediate
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var blend := 1.0 - exp(-input_smoothness * delta)
	_smoothed_input.x = raw.x
	_smoothed_input.y = lerpf(_smoothed_input.y, raw.y, blend)

	var wish := transform.basis * Vector3(_smoothed_input.x, 0.0, _smoothed_input.y)
	var has_input := wish.length_squared() > 0.0004

	var accel   := ground_acceleration if on_floor else air_acceleration
	var friction := ground_friction    if on_floor else air_friction

	# Speed ramps up/down smoothly so shift feels like breaking into a run
	# KEY_SHIFT checked directly — Shift as an input action is unreliable in Godot 4
	var target_speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	_current_speed = lerpf(_current_speed, target_speed, 1.0 - exp(-speed_blend_sharpness * delta))
	var speed := _current_speed

	# Work in local horizontal space to avoid fighting with basis changes mid-slide
	var right_h   := transform.basis.x
	var forward_h := transform.basis.z
	var vel_flat  := Vector3(velocity.x, 0.0, velocity.z)
	var local_vel := Vector2(vel_flat.dot(right_h), vel_flat.dot(forward_h))

	if has_input:
		var rate := 1.0 - exp(-accel * delta)
		local_vel = local_vel.lerp(Vector2(_smoothed_input.x, _smoothed_input.y) * speed, rate)
	else:
		var rate := 1.0 - exp(-friction * delta)
		local_vel = local_vel.lerp(Vector2.ZERO, rate)

	var new_flat  := right_h * local_vel.x + forward_h * local_vel.y
	velocity.x = new_flat.x
	velocity.z = new_flat.z

	move_and_slide()

	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0


func _process(delta: float) -> void:
	var flat_speed := Vector3(velocity.x, 0.0, velocity.z).length()

	# Head bob — scales with how fast you're moving relative to walk speed
	var bob_offset := 0.0
	if is_on_floor() and flat_speed > 1.0:
		_bob_time += delta * head_bob_frequency * (flat_speed / walk_speed)
		bob_offset = sin(_bob_time) * head_bob_amplitude
	else:
		_bob_time = lerpf(_bob_time, 0.0, delta * 5.0)

	# Camera Y — bob layered on top of landing recovery
	var recover_rate := 1.0 - exp(-12.0 * delta)
	_camera_y_offset = lerpf(_camera_y_offset, 0.0, recover_rate)
	camera.position.y = _camera_base_y + bob_offset + _camera_y_offset

	# Sprint FOV — only kicks in once actually moving at speed
	var sprinting := (
		is_on_floor()
		and Input.is_key_pressed(KEY_SHIFT)
		and flat_speed > walk_speed * 0.8
	)
	var target_fov := base_fov * sprint_fov_multiplier if sprinting else base_fov
	camera.fov = lerpf(camera.fov, target_fov, delta * 6.0)

	# Strafe tilt — subtle roll when moving sideways
	var strafe_tilt := 0.0
	if is_on_floor() and absf(_smoothed_input.x) > 0.05:
		strafe_tilt = -signf(_smoothed_input.x) * deg_to_rad(strafe_tilt_angle)
	camera.rotation.z = lerp_angle(camera.rotation.z, strafe_tilt, delta * 8.0)
