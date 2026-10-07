extends CharacterBody3D

# ── Movement ──────────────────────────────────────────────────────────────────
@export_group("Movement")
@export var walk_speed:          float = 1.8
@export var sprint_speed:        float = 3.8
@export var precision_speed: float = 0.75
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
@export var jump_peak_height:           float = 0.55
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
var _free_cam: PlayerFreeCam = null
var _body_npc: NpcBase = null

const WALK_ANIM_MIN_SPEED := 0.15

var _smoothed_input:   Vector2 = Vector2.ZERO
var _current_speed:    float   = 0.0
var _was_on_floor:     bool    = true
var _stepped_last_frame: bool = false
var _last_safe_position: Vector3 = Vector3.ZERO
var _water_submerge_time: float = 0.0
var _vehicle_occupied: bool = false
var _safe_support: WeakRef
var _safe_local_position := Vector3.ZERO
var _jump_buffer := 0.0
var _coyote_time := 0.0
var _landing_speed := 0.0
var _air_deck: WeakRef
var _air_deck_transform := Transform3D.IDENTITY
var _air_deck_time := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = LAYER_PLAYER
	## World (1) for terrain / quay / asphalt; boat_walk (4) for ship decks.
	collision_mask |= 1 | LAYER_BOAT_WALK
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_current_speed = walk_speed
	_last_safe_position = global_position

	# Snap to floor when descending small steps so we don't go briefly airborne.
	floor_snap_length = floor_snap_distance
	floor_stop_on_slope = true
	platform_floor_layers = 1
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	floor_max_angle = deg_to_rad(48.0)

	_player_camera = PlayerCamera.new()
	_player_camera.name = "PlayerCamera"
	add_child(_player_camera)

	_build_body_mesh()

	_free_cam = PlayerFreeCam.new()
	_free_cam.name = "PlayerFreeCam"
	add_child(_free_cam)

	_player_camera.bind(self, camera, _body_npc)
	_free_cam.bind(self, camera, _player_camera, _body_npc)
	# Match boat camera: default Godot far (4000 m) black-clips the mainland.
	camera.far = 40000.0
	camera.near = 0.08


func _unhandled_input(event: InputEvent) -> void:
	if _free_cam != null and _free_cam.handle_input(event):
		return

	if _player_camera != null and _player_camera.handle_input(event):
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		# Wheel buttons are not real clicks — do not recapture the cursor (breaks NPC UIs).
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_sync_deck_capsule()
	if _free_cam != null and _free_cam.is_active():
		velocity = Vector3.ZERO
		return

	_update_deck_frame(delta)
	var on_floor := is_on_floor()
	if not on_floor:
		_landing_speed = velocity.y

	# Landing — dip the camera slightly on impact, recover smoothly
	if on_floor and not _was_on_floor:
		if _player_camera != null:
			_player_camera.notify_landing(_landing_speed)
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
	_coyote_time = 0.10 if on_floor else maxf(0.0, _coyote_time - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if inputs_active and Input.is_action_just_pressed("jump"):
		_jump_buffer = 0.12
	if not inputs_active:
		_jump_buffer = 0.0
	if _jump_buffer > 0.0 and _coyote_time > 0.0:
		velocity.y = sqrt(2.0 * BASE_GRAVITY * jump_peak_height)
		_jump_buffer = 0.0
		_coyote_time = 0.0

	# Smooth raw input on the forward axis — strafe stays immediate
	var raw := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if inputs_active else Vector2.ZERO
	var blend := 1.0 - exp(-input_smoothness * delta)
	_smoothed_input.x = raw.x
	_smoothed_input.y = lerpf(_smoothed_input.y, raw.y, blend)

	var wish := _movement_basis() * Vector3(_smoothed_input.x, 0.0, _smoothed_input.y)
	var has_input := wish.length_squared() > 0.0004

	if has_input and _player_camera != null and _player_camera.is_third_person():
		# CharacterVisual faces local -Z. Convert the desired world direction to
		# the yaw that points -Z along it (the previous formula was 180 degrees
		# reversed and only appeared correct while the legacy body was flipped).
		var face_yaw := atan2(-wish.x, -wish.z)
		var turn_rate := 1.0 - exp(-14.0 * delta)
		rotation.y = lerp_angle(rotation.y, face_yaw, turn_rate)

	var accel   := ground_acceleration if on_floor else air_acceleration
	var friction := ground_friction    if on_floor else air_friction

	# Speed ramps up/down smoothly so shift feels like breaking into a run
	var target_speed := sprint_speed if (inputs_active and Input.is_action_pressed("player_jog")) else walk_speed
	if inputs_active and Input.is_action_pressed("player_precision"):
		target_speed = precision_speed
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
	var may_step := on_floor or _was_on_floor or _stepped_last_frame
	_stepped_last_frame = false
	if may_step and pre_velocity.y <= 0.5 and max_step_height > 0.0:
		var intended := Vector3(pre_velocity.x, 0.0, pre_velocity.z) * delta
		if intended.length_squared() > 0.000001:
			var actual := global_position - pre_move_pos
			actual.y = 0.0
			if actual.length() < intended.length() * 0.6:
				if _try_step_up(intended):
					_stepped_last_frame = true
					velocity.x = pre_velocity.x
					velocity.z = pre_velocity.z

	var waterline := WaveSurface.get_buoyancy_surface_height_at(global_position.x, global_position.z) if is_instance_valid(WaveSurface.fft_system) else water_surface_y
	if global_position.y < waterline and not is_on_floor():
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
			recover_to_safety()
			_water_submerge_time = 0.0
			return
	else:
		_water_submerge_time = 0.0

	if global_position.y < abyss_reset_y:
		recover_to_safety()
		return

	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0
	if is_on_floor() and global_position.y > waterline + 0.1:
		_remember_safe_footing()

	_update_walk_animation(delta)


func _process(delta: float) -> void:
	if _free_cam != null and _free_cam.is_active():
		_free_cam.update(delta)
		return

	if _player_camera == null:
		return
	var inputs_active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_player_camera.update(delta, velocity, _smoothed_input, is_on_floor(), inputs_active)


func set_vehicle_occupied(occupied: bool) -> void:
	_vehicle_occupied = occupied
	set_meta("vehicle_occupied", occupied)
	if _player_camera != null:
		_player_camera.set_vehicle_occupied(occupied)
	elif _body_npc != null:
		_body_npc.visible = not occupied


func is_vehicle_occupied() -> bool:
	return _vehicle_occupied


# ── Step climb (ghost-cast probe) ─────────────────────────────────────────────

## Probe whether the player can mount a low obstacle by moving up by
## max_step_height, then forward by `horizontal_motion`, then back down to find
## a walkable surface. Commits the new position if all three probes succeed.
## Returns true on a successful step.
func _try_step_up(horizontal_motion: Vector3) -> bool:
	var motion := Vector3(horizontal_motion.x, 0.0, horizontal_motion.z)
	if motion.length_squared() < 0.000001:
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
		# A capsule touching a tread's nosing produces a diagonal contact normal,
		# even when the actual tread is flat. Check the surface just inside that
		# contact before rejecting it as a steep slope. Full capsule casts above
		# still enforce ceiling, forward clearance and the maximum step height.
		var sample := down_result.get_collision_point() + motion.normalized() * .025
		var query := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * .08,sample - Vector3.UP * .12,collision_mask,[rid])
		var surface := get_world_3d().direct_space_state.intersect_ray(query)
		if surface.is_empty() or surface.normal.dot(Vector3.UP) < cos(floor_max_angle):
			return false

	var old_y := global_position.y
	global_position = raised_fwd.origin + down_result.get_travel()
	if _player_camera != null:
		_player_camera.notify_step(global_position.y - old_y)
	return true


func _build_body_mesh() -> void:
	# Visible character body for third-person view (and future MP). Mirrors the
	# captain's CharacterAppearance from PlayerData so the figure on screen is
	# the one the player tuned in the creator.
	_body_npc = NpcBase.new()
	_body_npc.name = "BodyMesh"
	_body_npc.visible = false
	# CharacterVisual and gameplay both use local -Z as forward.
	_body_npc.rotation.y = 0.0
	add_child(_body_npc)
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


func _update_walk_animation(delta: float) -> void:
	if _body_npc == null:
		return

	var flat_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	if is_on_floor() and flat_speed > WALK_ANIM_MIN_SPEED:
		_body_npc.set_motion_speed(flat_speed, delta)
	else:
		_body_npc.set_idle()


func _movement_basis() -> Basis:
	if _player_camera != null:
		return _player_camera.get_flat_basis()
	return global_transform.basis


## Keep the collision capsule in the deck frame inside tight imported doorways.
## Character movement/camera remain world-upright; only the collision shape leans.
func _sync_deck_capsule() -> void:
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is CapsuleShape3D:
		return
	var deck_up := Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * .25,
		global_position - Vector3.UP * (floor_snap_distance + .15),
		LAYER_BOAT_WALK
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and bool(hit.collider.get_meta("align_player_capsule", false)) and hit.normal.dot(Vector3.UP) > cos(floor_max_angle):
		var boat: Node3D = hit.collider.get_meta("_boat_owner")
		if is_instance_valid(boat):
			deck_up = boat.global_basis.y.normalized()
	var forward := -global_basis.z
	forward = (forward - deck_up * forward.dot(deck_up)).normalized()
	collision.global_transform = Transform3D(
		Basis.looking_at(forward, deck_up),
		global_position + deck_up * (collision.shape.height * .5)
	)


## Remember a deck-local point, so recovery follows a moving vessel.
func _remember_safe_footing() -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * .15,
		global_position - Vector3.UP * .6, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider is Node3D and hit.normal.dot(Vector3.UP) > cos(floor_max_angle):
		_last_safe_position = global_position
		_safe_support = weakref(hit.collider)
		_safe_local_position = hit.collider.to_local(global_position)


func recover_to_safety() -> void:
	var target := _last_safe_position
	if _safe_support != null:
		var support := _safe_support.get_ref() as Node3D
		if is_instance_valid(support):
			target = support.to_global(_safe_local_position)
	global_position = target + Vector3.UP * .08
	_air_deck = null
	velocity = Vector3.ZERO
	_smoothed_input = Vector2.ZERO
	_water_submerge_time = 0.0
	reset_physics_interpolation()


## Resolve a standing position around a station with floor and full-body clearance.
## Leave the player seated if every candidate is blocked.
func try_leave_station(station: Node3D, preferred: Vector3) -> bool:
	var shape_node := get_node("CollisionShape3D") as CollisionShape3D
	for offset: Vector3 in [preferred, Vector3(-1, .15, .6), Vector3(1, .15, .6), Vector3(0, .15, 1.8)]:
		var point := station.to_global(offset)
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .6,
			point - Vector3.UP * 1.2, collision_mask, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.dot(Vector3.UP) < cos(floor_max_angle):
			continue
		var feet: Vector3 = hit.position + Vector3.UP * .04
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = Transform3D(shape_node.global_basis, feet + shape_node.global_basis.y * (shape_node.shape.height * .5))
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		global_position = feet
		velocity = Vector3.ZERO
		_smoothed_input = Vector2.ZERO
		_remember_safe_footing()
		reset_physics_interpolation()
		return true
	return false


## Follow imported decks on foot and during short jumps. Their colliders are
## explicitly synchronized transforms, so keep one frame delta rather than also
## relying on inferred platform velocity. Carry is swept against world collision.
func _update_deck_frame(delta: float) -> void:
	if _air_deck != null:
		var deck := _air_deck.get_ref() as Node3D
		_air_deck_time = 0.0 if is_on_floor() else _air_deck_time + delta
		if is_instance_valid(deck) and _air_deck_time < 1.5:
			var frame_delta := deck.global_transform * _air_deck_transform.affine_inverse()
			var carry := frame_delta * global_position - global_position
			if carry.length() < 3.0:
				move_and_collide(carry)
				var yaw := frame_delta.basis.get_euler().y
				rotation.y += yaw
				if _player_camera != null:
					_player_camera._orbit_yaw += yaw
				velocity = Basis(Vector3.UP, yaw) * velocity
				_air_deck_transform = deck.global_transform
			else:
				_air_deck = null
		else:
			_air_deck = null
	if not is_on_floor():
		return
	# Probe after carrying: slide contacts may be absent while standing still.
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * .2,
		global_position - Vector3.UP * .6, collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.has_meta("_boat_owner"):
		_air_deck = weakref(hit.collider)
		_air_deck_transform = hit.collider.global_transform
		_air_deck_time = 0.0
	else:
		_air_deck = null
