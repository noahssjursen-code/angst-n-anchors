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
## Local position of the propeller (stern centre, at or below waterline).
@export var stern_offset: Vector3 = Vector3(0.0, 0.0, -5.8)

## Litres of fuel burned per second at FULL throttle (|throttle| == 1.0).
## Linear with throttle magnitude. Tuned so a 400 L tank lasts ~13 real
## minutes at full ahead, longer at cruise stages.
@export var fuel_burn_l_per_sec_full: float = 0.5

var throttle: float = 0.0

var _body: BoatBody = null


func _ready() -> void:
	_body = get_parent() as BoatBody
	if _body == null:
		push_error("PropulsionComponent must be a child of a BoatBody (RigidBody3D)")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or is_zero_approx(throttle):
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

	var magnitude: float = throttle * max_thrust
	if throttle > 0.0:
		magnitude *= reverse_multiplier

	# Body space: bow at −Z (Godot forward). Negative throttle = ahead; force must push toward −Z.
	var force: Vector3  = _body.global_transform.basis.z * magnitude
	var offset: Vector3 = _body.to_global(stern_offset) - _body.global_position
	_body.apply_force(force, offset)
