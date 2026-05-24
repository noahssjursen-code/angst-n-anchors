class_name PlayerFreeCam
extends Node

## Detached fly camera — toggle with F3 held + P.

signal toggled(active: bool)

const GROUP := "player_free_cam"

@export var move_speed: float = 18.0
@export var fast_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.002
@export var min_pitch: float = deg_to_rad(-89.0)
@export var max_pitch: float = deg_to_rad(89.0)

var _player: CharacterBody3D
var _camera: Camera3D
var _player_camera: PlayerCamera
var _body_mesh: NpcBase

var _active: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _saved_camera_local: Transform3D = Transform3D.IDENTITY
var _saved_body_visible: bool = false


func bind(
	player: CharacterBody3D,
	camera: Camera3D,
	player_camera: PlayerCamera,
	body_mesh: NpcBase = null,
) -> void:
	_player = player
	_camera = camera
	_player_camera = player_camera
	_body_mesh = body_mesh
	add_to_group(GROUP)


func is_active() -> bool:
	return _active


func handle_input(event: InputEvent) -> bool:
	if _is_toggle_shortcut(event):
		toggle()
		if _player != null and _player.get_viewport() != null:
			_player.get_viewport().set_input_as_handled()
		return true

	if not _active:
		return false

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := mouse_sensitivity * _settings_sens_multiplier()
		var invert := _settings_invert_y()
		var dy: float = event.relative.y * sens * (-1.0 if invert else 1.0)
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - dy, min_pitch, max_pitch)
		if _player != null and _player.get_viewport() != null:
			_player.get_viewport().set_input_as_handled()
		return true

	if event.is_action_pressed("ui_cancel"):
		deactivate()
		if _player != null and _player.get_viewport() != null:
			_player.get_viewport().set_input_as_handled()
		return true

	return false


func toggle() -> void:
	if _active:
		deactivate()
	else:
		activate()


func activate() -> void:
	if _camera == null or _player == null:
		return
	_active = true
	_saved_camera_local = _camera.transform
	var euler := _camera.global_transform.basis.get_euler()
	_yaw = euler.y
	_pitch = euler.x
	_camera.top_level = true
	_camera.global_transform = _camera.global_transform
	_camera.current = true
	if _body_mesh != null:
		_saved_body_visible = _body_mesh.visible
		_body_mesh.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(true)


func deactivate() -> void:
	if not _active:
		return
	_active = false
	if _camera != null:
		_camera.top_level = false
		_camera.transform = _saved_camera_local
		_camera.current = true
	if _body_mesh != null:
		_body_mesh.visible = _saved_body_visible
	if _player_camera != null:
		_player_camera.call("_apply_mode")
	if _player != null:
		_player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(false)


func update(delta: float) -> void:
	if not _active or _camera == null:
		return

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier

	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	if Input.is_key_pressed(KEY_E):
		input.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		input.y -= 1.0

	if input.length_squared() > 0.0:
		input = input.normalized()

	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var motion := basis * input * speed * delta
	_camera.global_position += motion

	var rot := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	_camera.global_transform = Transform3D(rot, _camera.global_position)


func blocks_player_control() -> bool:
	return _active


static func _is_toggle_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var ke := event as InputEventKey
	if not ke.pressed or ke.echo:
		return false
	if ke.physical_keycode != KEY_P:
		return false
	return Input.is_key_pressed(KEY_F3)


func _settings_sens_multiplier() -> float:
	var s := get_node_or_null("/root/GameSettings")
	return float(s.mouse_sensitivity) if s != null else 1.0


func _settings_invert_y() -> bool:
	var s := get_node_or_null("/root/GameSettings")
	return bool(s.invert_mouse_y) if s != null else false
