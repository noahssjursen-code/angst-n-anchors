class_name PlayerCamera
extends Node

## Standard third-person orbit camera + first-person toggle (V).

enum CameraMode { FIRST_PERSON, THIRD_PERSON }

signal mode_changed(mode: CameraMode)

const FP_MAX_PITCH := deg_to_rad(88.0)
const TP_MIN_PITCH := deg_to_rad(-20.0)
const TP_MAX_PITCH := deg_to_rad(72.0)

@export_group("Third Person")
@export var tp_pivot_y: float = 1.45
@export var tp_distance: float = 4.2
@export var tp_min_distance: float = 1.0
@export var tp_collision_margin: float = 0.3
@export var default_mode: CameraMode = CameraMode.THIRD_PERSON

@export_group("First Person")
@export var fp_height: float = 1.6

@export_group("Feel")
@export var mouse_sensitivity: float = 0.0015
@export var base_fov: float = 90.0
@export var sprint_fov_multiplier: float = 1.08
@export var strafe_tilt_angle: float = 1.8
@export var head_bob_frequency: float = 10.0
@export var head_bob_amplitude: float = 0.055
@export var walk_speed_ref: float = 4.5

var _player: CharacterBody3D = null
var _camera: Camera3D = null
var _body_mesh: NpcBase = null

var _mode: CameraMode = CameraMode.THIRD_PERSON
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = deg_to_rad(18.0)
var _fp_pitch: float = 0.0
var _bob_time: float = 0.0
var _camera_y_offset: float = 0.0


func bind(player: CharacterBody3D, camera: Camera3D, body_mesh: NpcBase = null) -> void:
	_player = player
	_camera = camera
	_body_mesh = body_mesh
	_mode = default_mode
	_orbit_yaw = player.rotation.y
	_orbit_pitch = deg_to_rad(18.0)
	_fp_pitch = 0.0
	if _camera != null:
		_camera.fov = base_fov
	_apply_mode()


func get_mode() -> CameraMode:
	return _mode


func is_third_person() -> bool:
	return _mode == CameraMode.THIRD_PERSON


## Yaw replicated to other clients — third-person sends visible mesh heading,
## first-person sends the player root (look direction).
func get_replication_yaw() -> float:
	if _player == null:
		return 0.0
	if _mode == CameraMode.THIRD_PERSON and _body_mesh != null:
		return _body_mesh.global_rotation.y
	return _player.rotation.y


## Camera-relative movement basis (XZ). Third-person walks away from the orbit camera.
func get_flat_basis() -> Basis:
	if _player == null:
		return Basis.IDENTITY
	if _mode == CameraMode.FIRST_PERSON:
		var fwd := -_player.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.0001:
			return _player.global_transform.basis
		return Basis.looking_at(fwd.normalized(), Vector3.UP)

	var offset := _orbit_offset(_orbit_yaw, _orbit_pitch, 1.0)
	var fwd := Vector3(-offset.x, 0.0, -offset.z)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0.0, 0.0, -1.0)
	return Basis.looking_at(fwd.normalized(), Vector3.UP)


func handle_input(event: InputEvent) -> bool:
	if _player == null or _camera == null:
		return false
	if not _camera.current:
		return false

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * _settings_sens_multiplier()
		var invert := _settings_invert_y()
		var dy: float = event.relative.y * sens * (-1.0 if invert else 1.0)

		if _mode == CameraMode.THIRD_PERSON:
			_orbit_yaw -= event.relative.x * sens
			_orbit_pitch = clampf(_orbit_pitch - dy, TP_MIN_PITCH, TP_MAX_PITCH)
		else:
			_player.rotate_y(-event.relative.x * sens)
			_fp_pitch = clampf(_fp_pitch - dy, -FP_MAX_PITCH, FP_MAX_PITCH)
		return true

	if event.is_action_pressed("toggle_camera"):
		_toggle_mode()
		return true

	return false


func notify_landing(velocity_y: float) -> void:
	if _mode == CameraMode.FIRST_PERSON:
		_camera_y_offset = clampf(velocity_y * 0.045, -0.45, 0.0)


func update(
	delta: float,
	velocity: Vector3,
	smoothed_input: Vector2,
	on_floor: bool,
	inputs_active: bool
) -> void:
	if _camera == null or not _camera.current:
		return

	var flat_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var sprinting := (
		on_floor
		and inputs_active
		and Input.is_key_pressed(KEY_SHIFT)
		and flat_speed > walk_speed_ref * 0.8
	)
	var target_fov := base_fov * sprint_fov_multiplier if sprinting else base_fov
	_camera.fov = lerpf(_camera.fov, target_fov, delta * 6.0)

	if _mode == CameraMode.THIRD_PERSON:
		_update_third_person()
		return

	_update_first_person(delta, velocity, smoothed_input, on_floor, flat_speed)


func _update_third_person() -> void:
	var pivot := _player.global_position + Vector3(0.0, tp_pivot_y, 0.0)
	var dist := _collision_distance(pivot, tp_distance)
	var offset := _orbit_offset(_orbit_yaw, _orbit_pitch, dist)
	_camera.global_position = pivot + offset
	_camera.look_at(pivot, Vector3.UP)
	_camera.rotation.z = 0.0


func _update_first_person(
	delta: float,
	_velocity: Vector3,
	smoothed_input: Vector2,
	on_floor: bool,
	flat_speed: float
) -> void:
	var bob_offset := 0.0
	if on_floor and flat_speed > 1.0:
		_bob_time += delta * head_bob_frequency * (flat_speed / walk_speed_ref)
		bob_offset = sin(_bob_time) * head_bob_amplitude
	else:
		_bob_time = lerpf(_bob_time, 0.0, delta * 5.0)

	var recover_rate := 1.0 - exp(-12.0 * delta)
	_camera_y_offset = lerpf(_camera_y_offset, 0.0, recover_rate)

	_camera.position = Vector3(0.0, fp_height + bob_offset + _camera_y_offset, 0.0)
	_camera.rotation.x = _fp_pitch

	var strafe_tilt := 0.0
	if on_floor and absf(smoothed_input.x) > 0.05:
		strafe_tilt = -signf(smoothed_input.x) * deg_to_rad(strafe_tilt_angle)
	_camera.rotation.z = lerp_angle(_camera.rotation.z, strafe_tilt, delta * 8.0)


func _orbit_offset(yaw: float, pitch: float, distance: float) -> Vector3:
	var cp := cos(pitch)
	var sp := sin(pitch)
	var sy := sin(yaw)
	var cy := cos(yaw)
	return Vector3(sy * cp * distance, sp * distance, cy * cp * distance)


func _collision_distance(pivot: Vector3, desired_distance: float) -> float:
	if _player == null:
		return desired_distance

	var space := _player.get_world_3d().direct_space_state
	if space == null:
		return desired_distance

	var offset := _orbit_offset(_orbit_yaw, _orbit_pitch, desired_distance)
	var from := pivot
	var to := pivot + offset
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return desired_distance

	var hit_distance := from.distance_to(hit.position) - tp_collision_margin
	return clampf(hit_distance, tp_min_distance, desired_distance)


func _toggle_mode() -> void:
	if _mode == CameraMode.THIRD_PERSON:
		_mode = CameraMode.FIRST_PERSON
		_player.rotation.y = _orbit_yaw
		_fp_pitch = 0.0
	else:
		_mode = CameraMode.THIRD_PERSON
		_orbit_yaw = _player.rotation.y
		_orbit_pitch = deg_to_rad(18.0)
	_apply_mode()
	mode_changed.emit(_mode)


func _apply_mode() -> void:
	if _body_mesh != null:
		_body_mesh.visible = _mode == CameraMode.THIRD_PERSON
	if _camera == null:
		return
	if _mode == CameraMode.FIRST_PERSON:
		_camera.rotation = Vector3.ZERO
		_camera.position = Vector3(0.0, fp_height, 0.0)
	else:
		_update_third_person()


func _settings_sens_multiplier() -> float:
	var s := get_node_or_null("/root/GameSettings")
	return float(s.mouse_sensitivity) if s != null else 1.0


func _settings_invert_y() -> bool:
	var s := get_node_or_null("/root/GameSettings")
	return bool(s.invert_mouse_y) if s != null else false
