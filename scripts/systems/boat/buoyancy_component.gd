@tool
class_name BuoyancyComponent
extends Node3D

## Applies upward buoyancy forces at N sample points on the hull.
## Each point checks the wave height at its world position and pushes
## up proportionally to how deep it is submerged.
## Adding more points gives a wider, more stable hull the same way a
## real displacement hull works.

@export var sample_points: Array[Vector3] = [
	Vector3(-2.0, 0.0,  5.0),   # stern port
	Vector3( 2.0, 0.0,  5.0),   # stern starboard
	Vector3(-2.0, 0.0, -5.0),   # bow port
	Vector3( 2.0, 0.0, -5.0),   # bow starboard
	Vector3(-2.0, 0.0,  0.0),   # mid port
	Vector3( 2.0, 0.0,  0.0),   # mid starboard
	Vector3( 0.0, 0.0,  3.0),   # stern centre
	Vector3( 0.0, 0.0, -3.0),   # bow centre
]

@export var force_per_point:   float = 15000.0
@export var damping_per_point: float = 350.0

var _body: RigidBody3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("BuoyancyComponent must be a child of a RigidBody3D")


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null:
		return

	for local_pt: Vector3 in sample_points:
		var world_pt: Vector3 = _body.to_global(local_pt)
		var water_y: float    = WaveSurface.get_height_at(world_pt.x, world_pt.z)
		var depth: float      = water_y - world_pt.y

		if depth <= 0.0:
			continue

		# Buoyant lift — proportional to submersion depth
		var lift := Vector3.UP * depth * force_per_point

		# Vertical damping — kills the perpetual bob without killing lateral motion
		var world_offset: Vector3 = world_pt - _body.global_position
		var point_vel: Vector3    = _body.linear_velocity + _body.angular_velocity.cross(world_offset)
		var vert_damp := Vector3(0.0, -point_vel.y * damping_per_point * minf(depth, 1.0), 0.0)

		_body.apply_force(lift + vert_damp, world_offset)
