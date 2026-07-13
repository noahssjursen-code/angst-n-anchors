@tool
class_name BowThrusterComponent
extends Node3D

## Lateral thrust at the bow. With `crab_mode`, the **same** body-X force is also applied at
## `stern_offset` so bow and stern push together → mostly sideways drift with little yaw torque.
## Without crab mode (helm sailing), lateral thrust is intentionally off — see BoatController.
## lateral_input is set each frame by BoatController — range -1 (port) to 1 (starboard).

@export var max_thrust: float = 4000.0
## Local bore of the bow tunnel thruster (negative Z = bow in body space).
@export var bow_offset: Vector3 = Vector3(0.0, 0.0, -5.8)
## Local bore of the stern tunnel thruster; used only when `crab_mode` is true.
@export var stern_offset: Vector3 = Vector3(0.0, -1.3, 11.0)

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
	var force_scale := 1.0
	if _body.has_method("get_physics_force_scale_for_tick"):
		force_scale = float(_body.call("get_physics_force_scale_for_tick"))
	if force_scale <= 0.0:
		return

	if crab_mode:
		# Mix bow/stern force around the live centre of mass. Equal force at
		# symmetric hull stations still yaws an aft-heavy vessel; crab mode means
		# commanded sway, so distribute thrust to cancel that yaw moment.
		var f := _body.global_transform.basis.x * lateral_input * max_thrust * 2.0 * force_scale
		var com_z := _body.center_of_mass.z
		var split := crab_force_split(bow_offset.z, stern_offset.z, com_z)
		_body.apply_force(
			f * split.x, _body.to_global(bow_offset) - _body.global_position
		)
		_body.apply_force(
			f * split.y, _body.to_global(stern_offset) - _body.global_position
		)
	else:
		# Bow-only: force at bow offset creates yaw torque — swings the bow.
		var f := _body.global_transform.basis.x * lateral_input * max_thrust * force_scale
		var bow_app := _body.to_global(bow_offset) - _body.global_position
		_body.apply_force(f, bow_app)


## Bow/stern shares whose lateral forces sum to one and produce zero yaw
## moment around com_z. Falls back to an even split for invalid geometry.
static func crab_force_split(bow_z: float, stern_z: float, com_z: float) -> Vector2:
	var bow_arm := bow_z - com_z
	var stern_arm := stern_z - com_z
	var span := stern_arm - bow_arm
	if absf(span) < 0.001 or bow_arm >= 0.0 or stern_arm <= 0.0:
		return Vector2(0.5, 0.5)
	var bow_share := clampf(stern_arm / span, 0.0, 1.0)
	return Vector2(bow_share, 1.0 - bow_share)
