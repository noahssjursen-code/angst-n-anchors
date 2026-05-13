@tool
class_name BowThrusterComponent
extends Node3D

## Lateral thruster at the bow. Pushes the nose sideways independent of speed.
## Used for precision docking when the rudder is ineffective at low speed.
## lateral_input is set each frame by BoatController — range -1 (left) to 1 (right).

@export var max_thrust:  float = 4000.0
## Local position of the thruster (bow, at waterline).
@export var bow_offset: Vector3 = Vector3(0.0, 0.0, -5.8)

var lateral_input: float = 0.0

var _body: RigidBody3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("BowThrusterComponent must be a child of a RigidBody3D")


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or is_zero_approx(lateral_input):
		return

	var force: Vector3  = _body.global_transform.basis.x * lateral_input * max_thrust
	var offset: Vector3 = _body.to_global(bow_offset) - _body.global_position
	_body.apply_force(force, offset)
