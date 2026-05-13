@tool
class_name RudderComponent
extends Node3D

## Applies yaw torque to steer the boat.
## Effectiveness scales with forward speed — a rudder does nothing when stopped.
## rudder_input is set each frame by BoatController — range -1 (hard left) to 1 (hard right).

@export var max_torque:    float = 15000.0
## How quickly effectiveness builds with speed.
## Lower values = rudder bites earlier / at slower speeds.
@export var speed_factor:  float = 0.25
@export var max_effectiveness: float = 1.0

var rudder_input: float = 0.0

var _body: RigidBody3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("RudderComponent must be a child of a RigidBody3D")


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or is_zero_approx(rudder_input):
		return

	# Forward speed: positive = moving ahead
	var fwd_speed: float    = -_body.linear_velocity.dot(_body.global_transform.basis.z)
	var effectiveness: float = clampf(absf(fwd_speed) * speed_factor, 0.0, max_effectiveness)

	# Flip torque sign when reversing so the helm still feels natural
	var direction: float = signf(fwd_speed) if not is_zero_approx(fwd_speed) else 1.0
	var torque: Vector3  = Vector3.UP * rudder_input * max_torque * effectiveness * direction
	_body.apply_torque(torque)
