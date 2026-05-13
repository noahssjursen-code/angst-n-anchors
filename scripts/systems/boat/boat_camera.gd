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

var _yaw:    float  = 0.0
var _target: Node3D = null


func _ready() -> void:
	_target = get_parent()
	# Start the orbit angle directly behind the stern so the first thing
	# the player sees after boarding is the bow ahead of them.
	# Boat local +Z is the stern direction; atan2 maps that into world yaw.
	if _target != null:
		var bz: Vector3 = _target.global_transform.basis.z
		_yaw = atan2(bz.x, bz.z)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * orbit_speed


func _process(delta: float) -> void:
	if not current or _target == null:
		return

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
