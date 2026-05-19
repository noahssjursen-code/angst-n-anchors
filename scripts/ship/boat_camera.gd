@tool
class_name BoatCamera
extends Camera3D

## Third-person camera that follows and orbits the boat.
## Mouse left/right orbits horizontally. Does not roll with the boat —
## always stays upright so the horizon is readable.

@export var follow_distance: float = 12.0
@export var follow_height:   float = 5.0
@export var follow_speed:    float = 6.0
@export var orbit_speed:     float = 0.0022
## Point the camera looks toward — slightly above the boat centre
@export var look_height_offset: float = 1.5
@export var zoom_step:       float = 3.0
@export var min_distance:    float = 4.0
@export var max_distance:    float = 200.0

var _yaw:          float  = 0.0
var _zoom_target:  float  = 12.0
var _target: Node3D = null


func _ready() -> void:
	_target = get_parent()
	_zoom_target = follow_distance
	# Start the orbit angle on the bow side so the bow is the first thing
	# the player sees after boarding. Boat local +Z is the bow direction;
	# atan2 maps that world direction into the initial yaw offset.
	if _target != null:
		var bz: Vector3 = _target.global_transform.basis.z
		_yaw = atan2(bz.x, bz.z)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * orbit_speed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_target = clampf(_zoom_target - zoom_step, min_distance, max_distance)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_target = clampf(_zoom_target + zoom_step, min_distance, max_distance)


func _process(delta: float) -> void:
	if not current or _target == null:
		return

	follow_distance = lerpf(follow_distance, _zoom_target, 1.0 - exp(-follow_speed * delta))

	var target_pos: Vector3 = _target.global_position

	var offset := Vector3(
		sin(_yaw) * follow_distance,
		follow_height,
		cos(_yaw) * follow_distance
	)

	global_position = global_position.lerp(
		target_pos + offset,
		1.0 - exp(-follow_speed * delta)
	)

	look_at(target_pos + Vector3.UP * look_height_offset, Vector3.UP)
