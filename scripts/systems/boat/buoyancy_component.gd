@tool
class_name BuoyancyComponent
extends Node3D

## Applies true Archimedes buoyancy based on displaced water volume.
## Uses the parent's hull_size to estimate the hull's total area, divided among
## the sample points. Force = Displaced Volume * Water Density * Gravity.

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

@export var water_density: float = 1000.0
@export var gravity: float = 9.8
## How "blocky" the hull is. 1.0 = perfect box. Cargo ships are ~0.7 to 0.8.
@export var block_coefficient: float = 0.75
## Resists heave relative to the *water surface* (not world). Too strong or world-
## relative kills riding over waves.
@export var vertical_damping: float = 2800.0
## Per-column lift caps once ~fully submerged (linear depth model would diverge).
@export var lift_depth_hull_scale: float = 1.15

var _body: RigidBody3D

func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("BuoyancyComponent must be a child of a RigidBody3D")
	else:
		if not Engine.is_editor_hint():
			WaveSurface.set_coupled_vessel(_body)


func _exit_tree() -> void:
	if _body and not Engine.is_editor_hint():
		WaveSurface.clear_coupled_vessel_if(_body)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null:
		return

	# Estimate total footprint area of the hull
	var area := 10.0
	if "hull_size" in _body:
		area = _body.get("hull_size").x * _body.get("hull_size").z * block_coefficient

	# Base buoyant force per meter of depth for a single point
	var area_per_point := area / maxf(sample_points.size(), 1.0)
	var base_force := area_per_point * water_density * gravity
	
	var hull_bottom_y := 0.0
	var hull_h: float = 2.0
	if "hull_size" in _body:
		var hs: Vector3 = _body.get("hull_size")
		hull_bottom_y = -hs.y * 0.5
		hull_h = hs.y

	var max_lift_depth: float = minf(hull_h * lift_depth_hull_scale, 5.0)

	var active: int = 0
	for local_pt: Vector3 in sample_points:
		# Shift the sample point to the bottom of the hull so buoyancy starts 
		# applying as soon as the hull touches water.
		var actual_local_pt := local_pt
		actual_local_pt.y = hull_bottom_y
		
		var world_pt: Vector3 = _body.to_global(actual_local_pt)
		var water_y: float    = WaveSurface.get_height_at(world_pt.x, world_pt.z)
		var depth: float      = water_y - world_pt.y

		if depth <= 0.0:
			continue

		active += 1
		var lift_depth: float = minf(depth, max_lift_depth)

		# Archimedes' principle: upward force = weight of displaced fluid
		var lift := Vector3.UP * (lift_depth * base_force)

		# Damp heave relative to the wave (world-only damping fights following the surface).
		var world_offset: Vector3 = world_pt - _body.global_position
		var point_vel: Vector3    = _body.linear_velocity + _body.angular_velocity.cross(world_offset)
		var water_vy: float       = WaveSurface.get_vertical_velocity_at(world_pt.x, world_pt.z)
		var rel_vy: float         = point_vel.y - water_vy
		var damp_scale: float     = minf(depth, 1.2) / 1.2
		var vert_damp := Vector3(0.0, -rel_vy * vertical_damping * damp_scale, 0.0)

		_body.apply_force(lift + vert_damp, world_offset)

	# Discrete keel samples can all sit in a sharp wave trough (mathematical air gap);
	# add weak central support when still near the free surface.
	if active == 0:
		var keel_c: float = _body.to_global(Vector3(0.0, hull_bottom_y, 0.0)).y
		var surf_c: float = WaveSurface.get_height_at(_body.global_position.x, _body.global_position.z)
		var gap: float = surf_c - keel_c
		if gap > -hull_h * 1.35:
			var pseudo_depth: float = clampf(gap + hull_h * 0.4, 0.0, max_lift_depth)
			if pseudo_depth > 0.0:
				var assist: float = (
					pseudo_depth * base_force * float(mini(sample_points.size(), 6)) * 0.2
				)
				_body.apply_central_force(Vector3.UP * assist)
