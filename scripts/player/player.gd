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

## Maximum height the player will step up over without jumping. Anything under
## this (e.g. quay lips, low platforms, kerb stones) is auto-mounted via a
## "ghost cast" probe after each slide.
@export var max_step_height:      float = 0.45
## How far below the feet the body will snap to ground when descending. Stops
## you launching off the top of small drops.
@export var floor_snap_distance:  float = 0.35

# ── Jump ──────────────────────────────────────────────────────────────────────
@export_group("Jump")
@export var jump_peak_height:           float = 0.9
@export var fall_gravity_multiplier:    float = 1.4
@export var jump_cut_gravity_multiplier: float = 3.0

# ── Camera & Feel ─────────────────────────────────────────────────────────────
# Camera behaviour lives in PlayerCamera (third-person orbit, collision, bob).

@export_group("Water")
## Temporary water interaction: player cannot walk on water.
@export var water_surface_y: float = -1.5
@export var water_horizontal_drag: float = 6.0
@export var water_sink_terminal_speed: float = -4.2
@export var water_rescue_depth: float = 1.1
@export var water_rescue_delay_s: float = 0.85
@export var abyss_reset_y: float = -25.0

const BASE_GRAVITY := 20.0   # stronger than real-world 9.8 — keeps feet planted
const LAYER_PLAYER := 8
const LAYER_BOAT_WALK := 4

@onready var camera: Camera3D = $Camera3D

var _player_camera: PlayerCamera = null
var _body_npc: NpcBase = null
var _walk_anim: WalkAnimator = null
var _walk_distance_m: float = 0.0

const WALK_ANIM_MIN_SPEED := 0.15

var _smoothed_input:   Vector2 = Vector2.ZERO
var _current_speed:    float   = 0.0
var _was_on_floor:     bool    = true
var _last_safe_position: Vector3 = Vector3.ZERO
var _water_submerge_time: float = 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = LAYER_PLAYER
	collision_mask |= LAYER_BOAT_WALK
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_current_speed = walk_speed
	_last_safe_position = global_position

	# Snap to floor when descending small steps so we don't go briefly airborne.
	floor_snap_length = floor_snap_distance
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(48.0)

	_player_camera = PlayerCamera.new()
	_player_camera.name = "PlayerCamera"
	add_child(_player_camera)

	_build_body_mesh()
	_player_camera.bind(self, camera, _body_npc)


func _unhandled_input(event: InputEvent) -> void:
	if _player_camera != null and _player_camera.handle_input(event):
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		# Wheel buttons are not real clicks — do not recapture the cursor (breaks NPC UIs).
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# Landing — dip the camera slightly on impact, recover smoothly
	if on_floor and not _was_on_floor:
		if _player_camera != null:
			_player_camera.notify_landing(velocity.y)
	_was_on_floor = on_floor

	# Gravity — variable scale depending on jump state. Always applied so the
	# player can't hover during a dialogue / pause / menu.
	if not on_floor:
		var g_scale := fall_gravity_multiplier
		if velocity.y > 0.0:
			g_scale = 1.0 if Input.is_action_pressed("jump") else jump_cut_gravity_multiplier
		velocity.y -= BASE_GRAVITY * g_scale * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	# Input is only consumed while the mouse is captured. NPC dialogues +
	# pause menu + map overlay all set `Input.mouse_mode = VISIBLE`, which
	# now also gates movement + jump — fixes "walk away mid-conversation".
	var inputs_active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	# Jump impulse derived from desired peak height
	if inputs_active and Input.is_action_just_pressed("jump") and on_floor:
		velocity.y = sqrt(2.0 * BASE_GRAVITY * jump_peak_height)

	# Smooth raw input on the forward axis — strafe stays immediate
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if inputs_active else Vector2.ZERO
	var blend := 1.0 - exp(-input_smoothness * delta)
	_smoothed_input.x = raw.x
	_smoothed_input.y = lerpf(_smoothed_input.y, raw.y, blend)

	var wish := _movement_basis() * Vector3(_smoothed_input.x, 0.0, _smoothed_input.y)
	var has_input := wish.length_squared() > 0.0004

	if has_input and _player_camera != null and _player_camera.is_third_person():
		var face_yaw := atan2(wish.x, wish.z)
		var turn_rate := 1.0 - exp(-14.0 * delta)
		rotation.y = lerp_angle(rotation.y, face_yaw, turn_rate)

	var accel   := ground_acceleration if on_floor else air_acceleration
	var friction := ground_friction    if on_floor else air_friction

	# Speed ramps up/down smoothly so shift feels like breaking into a run
	# KEY_SHIFT checked directly — Shift as an input action is unreliable in Godot 4
	var target_speed := sprint_speed if (inputs_active and Input.is_key_pressed(KEY_SHIFT)) else walk_speed
	_current_speed = lerpf(_current_speed, target_speed, 1.0 - exp(-speed_blend_sharpness * delta))
	var speed := _current_speed

	# Work in local horizontal space to avoid fighting with basis changes mid-slide
	var move_basis := _movement_basis()
	var right_h   := move_basis.x
	var forward_h := move_basis.z
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

	var pre_move_pos := global_position
	var pre_velocity := velocity

	move_and_slide()

	# Step-climb recovery: if we were grounded, intended to move horizontally,
	# but made noticeably less progress than asked, try to ghost-step over a
	# low ledge. Restores velocity so we don't lose momentum to the wall.
	if (on_floor or _was_on_floor) and pre_velocity.y <= 0.5 and max_step_height > 0.0:
		var intended := Vector3(pre_velocity.x, 0.0, pre_velocity.z) * delta
		if intended.length_squared() > 0.0001:
			var actual := global_position - pre_move_pos
			actual.y = 0.0
			if actual.length() < intended.length() * 0.6:
				if _try_step_up(intended):
					velocity.x = pre_velocity.x
					velocity.z = pre_velocity.z

	var waterline := water_surface_y
	if global_position.y < waterline:
		# In water: heavy drag and limited sink speed (not walkable, no surface clamp).
		var drag := clampf(1.0 - water_horizontal_drag * delta, 0.0, 1.0)
		velocity.x *= drag
		velocity.z *= drag
		velocity.y = maxf(velocity.y, water_sink_terminal_speed)

		if global_position.y < waterline - water_rescue_depth:
			_water_submerge_time += delta
		else:
			_water_submerge_time = 0.0
		if _water_submerge_time >= water_rescue_delay_s:
			global_position = _last_safe_position
			velocity = Vector3.ZERO
			_water_submerge_time = 0.0
			return
	else:
		_water_submerge_time = 0.0

	if global_position.y < abyss_reset_y:
		global_position = _last_safe_position
		velocity = Vector3.ZERO
		return

	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
	if is_on_floor() and global_position.y > waterline + 0.1:
		_last_safe_position = global_position

	_update_walk_animation(delta)


func _process(delta: float) -> void:
	if _player_camera == null:
		return
	var inputs_active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_player_camera.update(delta, velocity, _smoothed_input, is_on_floor(), inputs_active)


# ── Step climb (ghost-cast probe) ─────────────────────────────────────────────

## Probe whether the player can mount a low obstacle by moving up by
## max_step_height, then forward by `horizontal_motion`, then back down to find
## a walkable surface. Commits the new position if all three probes succeed.
## Returns true on a successful step.
func _try_step_up(horizontal_motion: Vector3) -> bool:
	var motion := Vector3(horizontal_motion.x, 0.0, horizontal_motion.z)
	if motion.length_squared() < 0.0001:
		return false

	var up_vec := Vector3.UP * max_step_height
	var rid    := get_rid()

	# 1. Move UP by step height (clipped if there's a low ceiling).
	var up_params  := PhysicsTestMotionParameters3D.new()
	up_params.from   = global_transform
	up_params.motion = up_vec
	var up_result   := PhysicsTestMotionResult3D.new()
	var up_blocked  := PhysicsServer3D.body_test_motion(rid, up_params, up_result)
	var actual_up   := up_result.get_travel() if up_blocked else up_vec
	if actual_up.y < 0.05:
		return false

	# 2. Move FORWARD from raised position.
	var raised := global_transform.translated(actual_up)
	var fwd_params  := PhysicsTestMotionParameters3D.new()
	fwd_params.from   = raised
	fwd_params.motion = motion
	var fwd_result := PhysicsTestMotionResult3D.new()
	var fwd_blocked := PhysicsServer3D.body_test_motion(rid, fwd_params, fwd_result)
	var actual_fwd := fwd_result.get_travel() if fwd_blocked else motion
	if actual_fwd.length() < motion.length() * 0.25:
		return false

	# 3. Drop DOWN to find the step surface.
	var raised_fwd := raised.translated(actual_fwd)
	var down_params  := PhysicsTestMotionParameters3D.new()
	down_params.from   = raised_fwd
	down_params.motion = Vector3.DOWN * (max_step_height + 0.1)
	var down_result := PhysicsTestMotionResult3D.new()
	var down_hit := PhysicsServer3D.body_test_motion(rid, down_params, down_result)
	if not down_hit:
		# Nothing to land on — would fall off, abort.
		return false

	# Reject steep surfaces — would be unwalkable.
	var normal := down_result.get_collision_normal()
	if normal.dot(Vector3.UP) < cos(floor_max_angle):
		return false

	global_position = raised_fwd.origin + down_result.get_travel()
	return true


func _build_body_mesh() -> void:
	# Visible character body for third-person view (and future MP). Mirrors the
	# captain's CharacterAppearance from PlayerData so the figure on screen is
	# the one the player tuned in the creator.
	_body_npc = NpcBase.new()
	_body_npc.name = "BodyMesh"
	_body_npc.visible = false
	_body_npc.rotation.y = PI  # mesh authored facing +Z; body forward is -Z
	add_child(_body_npc)
	_walk_anim = WalkAnimator.new()
	_walk_anim.attach(_body_npc)
	_apply_appearance_from_session()

	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_signal("data_loaded"):
		session.data_loaded.connect(_on_player_data_changed)


func _on_player_data_changed(_data: Variant) -> void:
	_apply_appearance_from_session()


func _apply_appearance_from_session() -> void:
	if _body_npc == null:
		return
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.data == null or session.data.appearance == null:
		return
	session.data.appearance.apply_to_npc(_body_npc)
	if _walk_anim != null and not _walk_anim.is_ready():
		_walk_anim.attach(_body_npc)


func _update_walk_animation(delta: float) -> void:
	if _body_npc == null or _walk_anim == null:
		return
	if not _walk_anim.is_ready():
		_walk_anim.attach(_body_npc)
		if not _walk_anim.is_ready():
			return

	var flat_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if is_on_floor() and flat_speed > WALK_ANIM_MIN_SPEED:
		_walk_distance_m += flat_speed * delta
		_walk_anim.update(_walk_distance_m)
	else:
		_walk_anim.reset()


func _movement_basis() -> Basis:
	if _player_camera != null:
		return _player_camera.get_flat_basis()
	return global_transform.basis
