@tool
class_name HydrodynamicsComponent
extends Node3D

## Drag in hull axes plus **wave coupling**: velocity is compared to a cheap surface
## orbital flow, and **tangent slip** is damped (ice-like sliding on a curved sheet).

@export var water_density: float = 1000.0
@export var forward_drag_coeff: float = 0.08
@export var lateral_drag_coeff: float = 1.6
@export var rotational_drag_coeff: float = 4.0
## Horizontal water motion from ∂η/∂t (drag only). High values make the hull **ride
## the wave phase** with little resistance — keep modest.
@export var orbital_flow_scale: float = 0.12
## Opposes velocity tangent to the local free surface (ball-on-trampoline grip).
@export var slip_grip_coeff: float = 18000.0
@export var max_slip_grip_force: float = 450000.0
## Drains horizontal speed vs **world** (still ocean / inertia). Stops zero-throttle
## surfing on wave orbital motion forever.
@export var bulk_horizontal_drag: float = 4200.0
## Approximate operational draft used for water drag. Kept separate from buoyancy:
## buoyancy decides where the hull floats; this only estimates submerged side area.
@export var draft_fraction: float = 0.38
## Scales all wave-coupling forces (slip grip + orbital flow). Reduce toward 0.3–0.5
## for heavy vessels that should punch through waves with more inertia.
@export_range(0.0, 2.0, 0.01) var wave_influence_scale: float = 0.55

var _body: RigidBody3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("HydrodynamicsComponent must be a child of a RigidBody3D")


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null:
		return

	var basis_inv: Basis = _body.global_transform.basis.inverse()
	var cx: float = _body.global_position.x
	var cz: float = _body.global_position.z
	var v_world: Vector3 = _body.linear_velocity

	var dh_dt: float = WaveSurface.get_vertical_velocity_at(cx, cz)
	var slope: Vector2 = WaveSurface.get_surface_gradient_xz(cx, cz)
	var perp2: Vector2 = Vector2(-slope.y, slope.x)
	var pl: float = perp2.length()
	var water_horiz: Vector3 = Vector3.ZERO
	if pl > 1e-4:
		perp2 /= pl
		water_horiz = Vector3(perp2.x, 0.0, perp2.y) * (dh_dt * orbital_flow_scale * wave_influence_scale)

	var rel_world: Vector3 = v_world - water_horiz
	var local_vel: Vector3 = basis_inv * rel_world
	var local_avel: Vector3 = basis_inv * _body.angular_velocity

	var w: float = 5.0
	var l: float = 12.0
	var h: float = 2.0
	var draft: float = 1.0

	if "hull_size" in _body:
		var hs: Vector3 = _body.get("hull_size")
		w = hs.x
		l = hs.z
		h = hs.y
		draft = hs.y * draft_fraction

	var forward_area: float = w * draft
	var lateral_area: float = l * draft

	var f_x: float = (
		-0.5 * water_density * local_vel.x * absf(local_vel.x) * lateral_area * lateral_drag_coeff
	)
	var f_z: float = (
		-0.5 * water_density * local_vel.z * absf(local_vel.z) * forward_area * forward_drag_coeff
	)
	
	# --- DYNAMIC WAVE-CRASH DRAG ---
	# If the boat plunges its nose into a wave, the effective frontal area massively increases.
	# We sample the water height at the bow. If it's above the keel, we apply extra slamming drag.
	var bow_world_pt := _body.to_global(Vector3(0.0, -h * 0.5, -l * 0.5))
	var bow_water_y := WaveSurface.get_buoyancy_surface_height_at(bow_world_pt.x, bow_world_pt.z)
	var bow_immersion := clampf(bow_water_y - bow_world_pt.y, 0.0, h)
	if bow_immersion > draft:
		var extra_immersion := bow_immersion - draft
		var crash_area := w * extra_immersion
		var crash_drag_coeff := 1.8 # Very high drag for crashing into a solid wall of water
		var f_z_crash := -0.5 * water_density * local_vel.z * absf(local_vel.z) * crash_area * crash_drag_coeff
		f_z += f_z_crash * wave_influence_scale

	var local_force := Vector3(f_x, 0.0, f_z)
	var global_force: Vector3 = _body.global_transform.basis * local_force

	var t_y: float = (
		-0.5 * water_density * local_avel.y * absf(local_avel.y) * (l * l * draft)
		* rotational_drag_coeff
	)
	var local_torque := Vector3(0.0, t_y, 0.0)
	var global_torque: Vector3 = _body.global_transform.basis * local_torque

	_body.apply_central_force(global_force)
	_body.apply_torque(global_torque)

	if slip_grip_coeff > 0.0 and max_slip_grip_force > 0.0 and wave_influence_scale > 0.0:
		var n_up: Vector3 = WaveSurface.get_surface_normal_at(cx, cz)
		var v_n: float = n_up.dot(v_world)
		var v_slip: Vector3 = v_world - n_up * v_n
		var f_slip: Vector3 = -v_slip * slip_grip_coeff * wave_influence_scale
		var slip_len: float = f_slip.length()
		var scaled_max: float = max_slip_grip_force * wave_influence_scale
		if slip_len > scaled_max:
			f_slip *= scaled_max / slip_len
		_body.apply_central_force(f_slip)

	var v_hz: Vector3 = Vector3(v_world.x, 0.0, v_world.z)
	var vh_len: float = v_hz.length()
	if vh_len > 0.02:
		var f_bulk: Vector3 = -v_hz * vh_len * bulk_horizontal_drag
		_body.apply_central_force(f_bulk)
