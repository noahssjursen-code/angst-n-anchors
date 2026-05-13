@tool
class_name RudderComponent
extends Node3D

## Applies yaw torque to steer the boat.
## Effectiveness scales with **speed through water** (forward + sideslip). Near-zero
## when dead in the water; floor only kicks in once there is measurable flow.
## rudder_input is set each frame by BoatController — range -1 (hard left) to 1 (hard right).

@export var max_torque:    float = 15000.0
## How quickly effectiveness builds with speed.
## Lower values = rudder bites earlier / at slower speeds.
@export var speed_factor:  float = 0.32
@export var max_effectiveness: float = 1.0
## Rudder still bites when sliding sideways with low forward speed (real helm needs flow).
@export var min_effectiveness_floor: float = 0.18
## Minimum planar speed (m/s) before the floor applies — avoids helm torque at rest.
@export var rudder_flow_gate: float = 0.38
@export var sideslip_rudder_weight: float = 0.55

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
	var fwd_speed: float = -_body.linear_velocity.dot(_body.global_transform.basis.z)
	var basis_inv: Basis = _body.global_transform.basis.inverse()
	var local_vel: Vector3 = basis_inv * _body.linear_velocity
	var horiz_body: float = sqrt(local_vel.x * local_vel.x + local_vel.z * local_vel.z)
	var speed_for_rudder: float = maxf(absf(fwd_speed), horiz_body * sideslip_rudder_weight)
	var raw_eff: float = speed_for_rudder * speed_factor
	var effectiveness: float = clampf(raw_eff, 0.0, max_effectiveness)
	if effectiveness < min_effectiveness_floor and speed_for_rudder > rudder_flow_gate:
		effectiveness = min_effectiveness_floor

	# Flip torque sign when reversing so the helm still feels natural
	var direction: float = signf(fwd_speed) if not is_zero_approx(fwd_speed) else 1.0
	var torque: Vector3  = Vector3.UP * rudder_input * max_torque * effectiveness * direction
	_body.apply_torque(torque)
