@tool
class_name PropulsionComponent
extends Node3D

## Engine / propeller. Applies thrust at the stern.
## throttle is set each frame by BoatController — range -1..1.
## Negative throttle = ahead; positive throttle = astern (reduced by reverse_multiplier).
## BoatController sends negated stage values so the stage table stays sign-intuitive
## (positive stage = ahead intent) while this component receives the inverted value.

@export var max_thrust:          float = 24000.0
@export var reverse_multiplier:  float = 0.45
@export var shaft_power_kw: float = 1000.0
@export_range(0.0, 1.0, 0.01) var propulsive_efficiency: float = 0.62
## Local position of the propeller (stern centre, at or below waterline).
@export var stern_offset: Vector3 = Vector3(0.0, 0.0, -5.8)

## Litres of fuel burned per second at FULL throttle (|throttle| == 1.0).
## Linear with throttle magnitude. Tuned so a 400 L tank lasts ~13 real
## minutes at full ahead, longer at cruise stages.
@export var fuel_burn_l_per_sec_full: float = 0.5

var throttle: float = 0.0
var delivered_thrust_n: float = 0.0
var advance_speed_ms: float = 0.0

var _body: BoatBody = null
var _wake_field: OceanWakeField = null


func _ready() -> void:
	_body = get_parent() as BoatBody
	if _body == null:
		push_error("PropulsionComponent must be a child of a BoatBody (RigidBody3D)")
	elif _body.physics_profile != null:
		shaft_power_kw = _body.physics_profile.shaft_power_kw
		propulsive_efficiency = _body.physics_profile.propulsive_efficiency


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or is_zero_approx(throttle):
		delivered_thrust_n = 0.0
		return

	# Burn fuel proportional to throttle magnitude. If the tank is dry,
	# clamp magnitude to zero — engine stalls. Rudder still works because
	# this component only owns propulsion.
	var fuel_pct := _body.get_fuel_fraction()
	if fuel_pct <= 0.0:
		return

	var burn := absf(throttle) * fuel_burn_l_per_sec_full * delta
	if burn > 0.0:
		_body.consume_fuel(burn)
	var prop_world := _body.to_global(stern_offset)
	var water := WaveSurface.sample_at(prop_world.x, prop_world.z)
	var world_com := _body.get_world_center_of_mass()
	var point_velocity := (
		_body.linear_velocity
		+ _body.angular_velocity.cross(prop_world - world_com)
		- water.velocity
	)
	var local_flow := _body.global_transform.basis.inverse() * point_velocity
	advance_speed_ms = absf(local_flow.z)
	var power_limited_thrust := (
		shaft_power_kw * 1000.0 * propulsive_efficiency
		/ maxf(advance_speed_ms, 0.5)
	)
	var available_thrust := minf(max_thrust, power_limited_thrust)
	var magnitude: float = throttle * available_thrust
	if throttle > 0.0:
		magnitude *= reverse_multiplier
	delivered_thrust_n = absf(magnitude)
	_submit_wake(prop_world, water, magnitude)

	var force_scale := _body.get_physics_force_scale_for_tick()
	if force_scale <= 0.0:
		return
	magnitude *= force_scale

	# Body space: bow at −Z (Godot forward). Negative throttle = ahead; force must push toward −Z.
	var force: Vector3  = _body.global_transform.basis.z * magnitude
	var offset: Vector3 = prop_world - _body.global_position
	_body.apply_force(force, offset)


static func calculate_wake_strength(
	thrust_n: float,
	vessel_mass_kg: float,
	speed_ms: float,
	throttle_value: float,
	propeller_immersion: float,
) -> Vector2:
	return OceanWakeField.calculate_strength(
		thrust_n,
		vessel_mass_kg,
		speed_ms,
		throttle_value,
		propeller_immersion
	)


static func calculate_trailing_axis(
	body_stern_axis: Vector2, throttle_value: float
) -> Vector2:
	return OceanWakeField.calculate_trailing_axis(body_stern_axis, throttle_value)


func _submit_wake(
	prop_world: Vector3,
	water: WaterSample,
	signed_thrust_n: float,
) -> void:
	if _wake_field == null or not is_instance_valid(_wake_field):
		var tree := get_tree()
		if tree != null:
			_wake_field = tree.get_first_node_in_group(
				"ocean_wake_field"
			) as OceanWakeField
	if _wake_field == null:
		return
	var propeller_immersion := water.height - prop_world.y
	# Screw markers sit high on several hulls; if the hull is still in water,
	# treat the prop as at least partially immersed so throttle leaves a wash.
	if propeller_immersion < 0.25:
		var hull_immersion := water.height - _body.global_position.y
		propeller_immersion = maxf(
			propeller_immersion,
			hull_immersion + _body.depth_m * 0.35
		)
	var strength := OceanWakeField.calculate_strength(
		signed_thrust_n,
		_body.mass,
		advance_speed_ms,
		throttle,
		propeller_immersion
	)
	if strength.y <= 0.001 and absf(throttle) > 0.05:
		# Last-chance floor so a throttled floating boat always stamps wash.
		strength = Vector2(
			maxf(strength.x, absf(throttle) * 0.55),
			maxf(strength.y, absf(throttle) * 0.7)
		)
	if strength.y <= 0.001:
		return
	var body_stern := Vector2(
		_body.global_transform.basis.z.x,
		_body.global_transform.basis.z.z
	).normalized()
	var trailing_axis := OceanWakeField.calculate_trailing_axis(body_stern, throttle)
	var priority := (
		100.0
		if WaveSurface.is_local_visual_vessel(_body)
			or _body.is_in_group(PlayerVessel.GROUP)
		else 20.0
	)
	_wake_field.submit_emitter(
		"boat:%d" % _body.get_instance_id(),
		Vector2(prop_world.x, prop_world.z),
		trailing_axis,
		_body.get_half_beam_m(),
		advance_speed_ms,
		strength.x,
		strength.y,
		priority
	)
