@tool
class_name BoatCamera
extends Camera3D

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

func _init() -> void:
	add_to_group(VehicleGroups.SHIP_OWNER_ONLY)


## Helm camera: first-person at the wheel by default; V toggles third-person orbit.
## Does not roll with the boat in third-person — horizon stays readable.

enum Mode { FIRST_PERSON, THIRD_PERSON }

@export var follow_distance: float = 12.0
@export var follow_height: float = 5.0
@export var follow_speed: float = 6.0
@export var orbit_speed: float = 0.0022
@export var look_height_offset: float = 1.5
@export var zoom_step: float = 3.0
@export var min_distance: float = 4.0
@export var max_distance: float = 200.0
@export var mouse_sensitivity: float = 0.0022
@export var fp_yaw_limit_deg: float = 70.0
@export var fp_pitch_min_deg: float = -35.0
@export var fp_pitch_max_deg: float = 45.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _zoom_target: float = 12.0
var _target: Node3D = null
var _mode: Mode = Mode.THIRD_PERSON
var _helm_station: Node3D = null
var _fp_yaw: float = 0.0
var _fp_pitch: float = 0.0
var _helming: bool = false


func _ready() -> void:
	# Outdoor MMO sightlines: Godot's default far (4000 m) cuts the mainland
	# into a black void long before terrain streaming runs out.
	far = 40000.0
	near = 0.2
	_target = get_parent()
	_zoom_target = follow_distance
	_pitch = atan2(follow_height, follow_distance)
	if _target != null:
		var bz: Vector3 = _target.global_transform.basis.z
		_yaw = atan2(bz.x, bz.z)


func begin_helm(station: Node3D) -> void:
	_helm_station = station
	_helming = station != null
	_fp_yaw = 0.0
	_fp_pitch = 0.0
	_mode = Mode.FIRST_PERSON
	if _target != null:
		var bz: Vector3 = _target.global_transform.basis.z
		_yaw = atan2(bz.x, bz.z)
		_pitch = atan2(follow_height, follow_distance)


func end_helm() -> void:
	_helming = false
	_helm_station = null
	_mode = Mode.THIRD_PERSON


func is_first_person() -> bool:
	return _helming and _mode == Mode.FIRST_PERSON


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not current:
		return
	if _helming and event.is_action_pressed("toggle_camera"):
		_mode = Mode.THIRD_PERSON if _mode == Mode.FIRST_PERSON else Mode.FIRST_PERSON
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		if _helming and _mode == Mode.FIRST_PERSON:
			_fp_yaw -= motion.relative.x * mouse_sensitivity
			_fp_pitch -= motion.relative.y * mouse_sensitivity
			var yaw_lim := deg_to_rad(fp_yaw_limit_deg)
			_fp_yaw = clampf(_fp_yaw, -yaw_lim, yaw_lim)
			_fp_pitch = clampf(
				_fp_pitch,
				deg_to_rad(fp_pitch_min_deg),
				deg_to_rad(fp_pitch_max_deg),
			)
		else:
			_yaw -= motion.relative.x * orbit_speed
			_pitch = clampf(_pitch + motion.relative.y * orbit_speed, -0.12, 1.45)
	if event is InputEventMouseButton and (not _helming or _mode == Mode.THIRD_PERSON):
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target - zoom_step, min_distance, max_distance)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target + zoom_step, min_distance, max_distance)


func _process(delta: float) -> void:
	if not current or _target == null:
		return
	if _helming and _mode == Mode.FIRST_PERSON and _helm_station != null and is_instance_valid(_helm_station):
		_update_first_person()
		return
	_update_third_person(delta)


func _update_first_person() -> void:
	var eye := _helm_eye_node()
	var b := eye.global_transform.basis.orthonormalized()
	b = b.rotated(b.y, _fp_yaw)
	b = b.rotated(b.x, _fp_pitch)
	global_transform = Transform3D(b.orthonormalized(), eye.global_position)


func _helm_eye_node() -> Node3D:
	if _helm_station == null:
		return _target
	## Prefer authored eye on the helm brick visual.
	var visual := _helm_station.get_parent()
	if visual != null:
		var eye := visual.get_node_or_null("HelmEye") as Node3D
		if eye != null:
			return eye
	return _helm_station


func _update_third_person(delta: float) -> void:
	follow_distance = lerpf(follow_distance, _zoom_target, 1.0 - exp(-follow_speed * delta))
	var target_pos: Vector3 = _target.global_position
	var offset := Vector3(
		cos(_pitch) * sin(_yaw) * follow_distance,
		sin(_pitch) * follow_distance,
		cos(_pitch) * cos(_yaw) * follow_distance
	)
	global_position = global_position.lerp(
		target_pos + offset,
		1.0 - exp(-follow_speed * delta)
	)
	look_at(target_pos + Vector3.UP * look_height_offset, Vector3.UP)
