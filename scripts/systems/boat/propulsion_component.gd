@tool
class_name PropulsionComponent
extends Node3D

## Engine / propeller. Applies a forward or reverse thrust force at the stern.
## throttle is set each frame by BoatController — range -1 (full reverse) to 1 (full ahead).

@export var max_thrust:          float = 24000.0
@export var reverse_multiplier:  float = 0.45   # reverse is weaker than ahead
## Local position of the propeller (stern centre, at waterline).
@export var stern_offset: Vector3 = Vector3(0.0, 0.0, 5.8)

var throttle: float = 0.0

var _body: RigidBody3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("PropulsionComponent must be a child of a RigidBody3D")


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or is_zero_approx(throttle):
		return

	var magnitude: float = throttle * max_thrust
	if throttle < 0.0:
		magnitude *= reverse_multiplier

	# Forward is -Z in Godot's convention
	var force: Vector3   = -_body.global_transform.basis.z * magnitude
	var offset: Vector3  = _body.to_global(stern_offset) - _body.global_position
	_body.apply_force(force, offset)
