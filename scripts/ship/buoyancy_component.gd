@tool
class_name BuoyancyComponent
extends Node3D

## Applies true Archimedes buoyancy based on displaced water volume.
## Uses the parent's hull_size to estimate the hull's total area, divided among
## the sample points. Force = Displaced Volume * Water Density * Gravity.

## Normalized hull footprint samples. X/Z are fractions of half-width/half-length.
## These scale from the actual mesh-derived `hull_size`, so a larger boat does not
## keep sampling buoyancy from the old small-boat footprint.
@export var footprint_samples: Array[Vector2] = [
	Vector2(-0.82,  0.82), # stern port
	Vector2( 0.82,  0.82), # stern starboard
	Vector2(-0.82, -0.82), # bow port
	Vector2( 0.82, -0.82), # bow starboard
	Vector2(-0.82,  0.0),  # mid port
	Vector2( 0.82,  0.0),  # mid starboard
	Vector2( 0.0,   0.62), # stern centre
	Vector2( 0.0,  -0.62), # bow centre
	Vector2( 0.0,   0.0),  # centre
]

@export var water_density: float = 1000.0
@export var gravity: float = 9.8
## Multiplier on computed lift (Archimedes column model undershoots heavy hulls vs mass).
## Tune per vessel so hull_mass * gravity ≈ equilibrium buoyancy at operational draft.
@export var buoyancy_multiplier: float = 1.0
## How "blocky" the hull is. 1.0 = perfect box. Cargo ships are ~0.7 to 0.8.
@export var block_coefficient: float = 0.75

## Resists heave relative to the *water surface* (not world). Too strong or world-
## relative kills riding over waves.
@export var vertical_damping: float = 65000.0
## Per-column lift caps once ~fully submerged (linear depth model would diverge).
@export var lift_depth_hull_scale: float = 1.15
## Scales wave-relative vertical damping. Lower = hull moves more independently of the
## surface; higher = hull snaps tightly to wave contour. Match with HydrodynamicsComponent.wave_influence_scale.
@export_range(0.0, 2.0, 0.01) var wave_influence_scale: float = 0.55

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

	var hull_bottom_y := 0.0
	var hull_h: float = 2.0
	var hull_w: float = 5.0
	var hull_l: float = 12.0
	var hull_center := Vector3.ZERO
	if "hull_size" in _body:
		var hs: Vector3 = _body.get("hull_size")
		hull_h = hs.y
		hull_w = hs.x
		hull_l = hs.z
	if "hull_center" in _body:
		hull_center = _body.get("hull_center")
	hull_bottom_y = hull_center.y - hull_h * 0.5

	# Base buoyant force per meter of draft for a single sample column.
	var area_per_point := area / maxf(footprint_samples.size(), 1.0)
	var base_force := area_per_point * water_density * gravity * buoyancy_multiplier

	var max_lift_depth: float = minf(hull_h * lift_depth_hull_scale, 5.0)

	var active: int = 0
	for sample: Vector2 in footprint_samples:
		# Shift the sample point to the bottom of the hull so buoyancy starts 
		# applying as soon as the hull touches water.
		var actual_local_pt := Vector3(
			hull_center.x + sample.x * hull_w * 0.5,
			hull_bottom_y,
			hull_center.z + sample.y * hull_l * 0.5
		)
		
		var world_pt: Vector3 = _body.to_global(actual_local_pt)
		# Undisturbed wave height — NOT `get_height_at()`. Including the hull dip there
		# couples buoyancy to the boat's own depression and kills fluid-like heave.
		var water_y: float = WaveSurface.get_buoyancy_surface_height_at(world_pt.x, world_pt.z)
		var depth: float = water_y - world_pt.y

		if depth <= 0.0:
			continue

		active += 1

		# Limit max buoyancy so we don't get infinite lift if completely swallowed by a huge wave
		var lift_depth: float = minf(depth, max_lift_depth)
		var raw_lift: float = lift_depth * base_force

		# Damp heave relative to the wave
		var world_offset: Vector3 = world_pt - _body.global_position
		var angular_point_vel: Vector3 = _body.angular_velocity.cross(world_offset)
		var point_vel: Vector3 = _body.linear_velocity + angular_point_vel
		
		# Limit water vertical velocity readings so spikes in the wave math don't cause explosive damping
		var water_vy: float = clampf(WaveSurface.get_vertical_velocity_at(world_pt.x, world_pt.z), -8.0, 8.0)
		var rel_vy: float = point_vel.y - water_vy
		
		# Damping scales with immersion. Even if barely touching, apply some resistance.
		var damp_scale: float = clampf(depth / maxf(hull_h, 1.0), 0.2, 1.0)
		
		# Mix of linear and quadratic damping for realistic fluid resistance.
		# Quadratic drag gives massive resistance to plunging/jumping, but low resistance to gentle bobbing.
		var linear_damp: float = rel_vy * vertical_damping
		var quad_damp: float = sign(rel_vy) * (rel_vy * rel_vy) * (vertical_damping * 1.5)
		var damp_force_y: float = -(linear_damp + quad_damp) * damp_scale * wave_influence_scale
		
		# CRITICAL PHYSICS STABILITY FIX:
		# If the damping force is too high, it applies an impulse larger than the boat's momentum,
		# causing the physics engine to elastically bounce the boat OUT of the water.
		# We clamp the damping force so it can never remove more than 98% of the relative velocity in a single frame.
		var mass_per_point: float = _body.mass / maxf(footprint_samples.size(), 1.0)
		var max_damp_force: float = (mass_per_point * absf(rel_vy) / _delta) * 0.98
		
		damp_force_y = clampf(damp_force_y, -max_damp_force, max_damp_force)
		
		var total_y_force: float = raw_lift + damp_force_y
		
		_body.apply_force(Vector3(0.0, total_y_force, 0.0), world_offset)

	# Discrete keel samples can all sit in a sharp wave trough (mathematical air gap);
	# add weak central support when still near the free surface.
	if active == 0:
		var keel_c: float = _body.to_global(Vector3(hull_center.x, hull_bottom_y, hull_center.z)).y
		var surf_c: float = WaveSurface.get_buoyancy_surface_height_at(
			_body.global_position.x,
			_body.global_position.z
		)
		var gap: float = surf_c - keel_c
		if gap > -hull_h * 1.35:
			var pseudo_depth: float = clampf(gap + hull_h * 0.4, 0.0, 5.0)
			if pseudo_depth > 0.0:
				var assist: float = (
					pseudo_depth * base_force * float(mini(footprint_samples.size(), 6)) * 0.2
				)
				# Cap assist so it can't launch the boat
				var weight_per_point: float = (_body.mass * gravity) / maxf(footprint_samples.size(), 1.0)
				assist = minf(assist, weight_per_point * float(footprint_samples.size()) * 0.8)
				_body.apply_central_force(Vector3.UP * assist)
