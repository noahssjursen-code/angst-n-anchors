@tool
class_name RudderComponent
extends Node3D

## Applies yaw torque to steer the boat.
## Effectiveness scales with **speed through water** (forward + sideslip). Near-zero
## when dead in the water; floor only kicks in once there is measurable flow.
## rudder_input is set each frame by BoatController — range -1 (hard left) to 1 (hard right).

@export var max_torque:    float = 15000.0
## How quickly effectiveness builds with speed.
## Lower values = rudder bites earlier / at slower speeds.
@export var speed_factor:  float = 0.32
@export var max_effectiveness: float = 1.0
## Rudder still bites when sliding sideways with low forward speed (real helm needs flow).
@export var min_effectiveness_floor: float = 0.18
## Minimum planar speed (m/s) before the floor applies — avoids helm torque at rest.
@export var rudder_flow_gate: float = 0.45
@export var sideslip_rudder_weight: float = 0.22
@export var rudder_area_m2: float = 1.6
@export var rudder_position: Vector3 = Vector3(0.0, 0.0, 5.8)
@export var max_rudder_angle_deg: float = 28.0
@export var lift_slope: float = 2.8
@export var stall_angle_deg: float = 20.0
@export var prop_wash_speed_ms: float = 3.0
@export var water_density: float = 1025.0

var rudder_input: float = 0.0
var lateral_force_n: float = 0.0
var inflow_speed_ms: float = 0.0

var _body: RigidBody3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("RudderComponent must be a child of a RigidBody3D")
	elif _body is BoatBody and (_body as BoatBody).physics_profile != null:
		var profile := (_body as BoatBody).physics_profile
		rudder_area_m2 = profile.rudder_area_m2
		rudder_position = profile.rudder_position
		max_rudder_angle_deg = profile.max_rudder_angle_deg
		lift_slope = profile.rudder_lift_slope
		stall_angle_deg = profile.rudder_stall_angle_deg
		prop_wash_speed_ms = profile.prop_wash_speed_ms


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or is_zero_approx(rudder_input):
		lateral_force_n = 0.0
		return
	var force_scale := 1.0
	if _body.has_method("get_physics_force_scale_for_tick"):
		force_scale = float(_body.call("get_physics_force_scale_for_tick"))
	if force_scale <= 0.0:
		return
	var force_world_position := _body.to_global(rudder_position)
	var world_com := _body.to_global(_body.center_of_mass)
	var point_velocity := (
		_body.linear_velocity
		+ _body.angular_velocity.cross(force_world_position - world_com)
	)
	var water := WaveSurface.sample_at(
		force_world_position.x, force_world_position.z
	)
	var local_flow := (
		_body.global_transform.basis.inverse() * (point_velocity - water.velocity)
	)
	var propulsion := _body.get_node_or_null("PropulsionComponent") as PropulsionComponent
	var prop_throttle := propulsion.throttle if propulsion != null else 0.0
	var ahead_flow := (
		-local_flow.z
		+ (-prop_throttle) * prop_wash_speed_ms * sqrt(absf(prop_throttle))
	)
	inflow_speed_ms = sqrt(
		ahead_flow * ahead_flow
		+ local_flow.x * local_flow.x * sideslip_rudder_weight
	)
	if inflow_speed_ms < rudder_flow_gate:
		lateral_force_n = 0.0
		return
	var rudder_angle := deg_to_rad(max_rudder_angle_deg) * rudder_input
	var stall_angle := deg_to_rad(stall_angle_deg)
	var effective_angle := clampf(rudder_angle, -stall_angle, stall_angle)
	var lift_coeff := lift_slope * effective_angle
	var force_magnitude := (
		0.5 * water_density * inflow_speed_ms * inflow_speed_ms
		* rudder_area_m2 * absf(lift_coeff)
	)
	var flow_direction := signf(ahead_flow)
	if is_zero_approx(flow_direction):
		flow_direction = 1.0
	var local_force_x := -signf(lift_coeff) * flow_direction * force_magnitude
	local_force_x *= force_scale
	var force_world := _body.global_transform.basis * Vector3(local_force_x, 0.0, 0.0)
	_body.apply_force(force_world, force_world_position - _body.global_position)
	lateral_force_n = absf(local_force_x)
