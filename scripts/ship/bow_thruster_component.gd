@tool
class_name BowThrusterComponent
extends Node3D

## Lateral thrust at the bow. With `crab_mode`, the **same** body-X force is also applied at
## `stern_offset` so bow and stern push together → mostly sideways drift with little yaw torque.
## Without crab mode (helm sailing), lateral thrust is intentionally off — see BoatController.
## lateral_input is set each frame by BoatController — range -1 (port) to 1 (starboard).

@export var max_thrust: float = 4000.0
## Local bore of the bow tunnel thruster (positive Z = bow).
@export var bow_offset: Vector3 = Vector3(0.0, 0.0, 5.8)
## Local bore of the stern tunnel thruster; used only when `crab_mode` is true.
@export var stern_offset: Vector3 = Vector3(0.0, -1.3, -11.0)

var lateral_input: float = 0.0
## When true, apply equal parallel force bow + stern (docking crab). BoatController owns this flag.
var crab_mode: bool = false

var _body: RigidBody3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("BowThrusterComponent must be a child of a RigidBody3D")


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or is_zero_approx(lateral_input):
		return

	if crab_mode:
		# Pure sideways translation: central force means no torque, guaranteed lateral drift.
		# Scale by 2 to approximate the combined output of both tunnel thrusters.
		var f := _body.global_transform.basis.x * -lateral_input * max_thrust * 2.0
		_body.apply_central_force(f)
	else:
		# Bow-only: force at bow offset creates yaw torque — swings the bow.
		var f := _body.global_transform.basis.x * -lateral_input * max_thrust
		var bow_app := _body.to_global(bow_offset) - _body.global_position
		_body.apply_force(f, bow_app)
