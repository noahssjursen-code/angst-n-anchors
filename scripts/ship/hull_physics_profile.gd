class_name HullPhysicsProfile
extends Resource

## Authoritative metre/SI contract for one vessel hull. Geometry, mass,
## buoyancy, resistance and controls all consume this resource so a hull cannot
## silently use one draft for lift and another for drag.

@export_group("Hydrostatics")
@export var length_m: float = 15.0
@export var beam_m: float = 5.0
@export var depth_m: float = 3.0
@export var design_draft_m: float = 1.5
@export var design_displacement_t: float = 50.0
@export_range(0.0, 0.5, 0.01) var bow_taper_fraction: float = 0.2
@export_range(5, 32, 1) var station_count: int = 10
@export var water_density: float = 1025.0
@export var hull_form: Dictionary = {}

@export_group("Mass distribution")
@export var hull_center_of_mass: Vector3 = Vector3.ZERO
@export var engine_mass_kg: float = 0.0
@export var engine_position: Vector3 = Vector3.ZERO
@export var ballast_mass_kg: float = 0.0
@export var ballast_position: Vector3 = Vector3.ZERO
@export var full_stores_mass_kg: float = 0.0
@export var stores_position: Vector3 = Vector3.ZERO
@export_range(0.05, 1.0, 0.01) var roll_gyradius_fraction: float = 0.28
@export_range(0.05, 1.0, 0.01) var pitch_gyradius_fraction: float = 0.25
@export_range(0.05, 1.0, 0.01) var yaw_gyradius_fraction: float = 0.27

@export_group("Buoyancy and resistance")
@export_range(0.2, 2.0, 0.05) var heave_damping_ratio: float = 0.85
@export var max_heave_damping_accel: float = 6.0
@export var frictional_coeff: float = 0.0025
@export var form_factor: float = 1.2
@export var wave_making_peak_coeff: float = 0.003
@export var hull_speed_fn: float = 0.4
@export var lateral_drag_coeff: float = 3.4
@export var yaw_drag_coeff: float = 9.5

@export_group("Propulsion")
@export var shaft_power_kw: float = 1000.0
@export var bollard_thrust_n: float = 100000.0
@export_range(0.0, 1.0, 0.01) var propulsive_efficiency: float = 0.62
@export_range(0.0, 1.0, 0.01) var reverse_multiplier: float = 0.45
@export var propeller_position: Vector3 = Vector3.ZERO
@export var fuel_burn_l_per_sec_full: float = 0.1

@export_group("Steering and thrusters")
@export var rudder_area_m2: float = 1.6
@export var rudder_position: Vector3 = Vector3.ZERO
@export var max_rudder_angle_deg: float = 28.0
@export var rudder_lift_slope: float = 2.8
@export var rudder_stall_angle_deg: float = 20.0
@export var prop_wash_speed_ms: float = 3.0
@export var tunnel_thruster_force_n: float = 10000.0
@export var bow_thruster_position: Vector3 = Vector3.ZERO
@export var stern_thruster_position: Vector3 = Vector3.ZERO

@export_group("Wind")
@export var wind_frontal_area_m2: float = 20.0
@export var wind_lateral_area_m2: float = 70.0
@export var wind_center_of_effort: Vector3 = Vector3(0.0, 3.0, 0.0)
@export var wind_drag_coeff: float = 0.85


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if length_m <= 0.0 or beam_m <= 0.0 or depth_m <= 0.0:
		errors.append("Hull dimensions must be positive")
	if design_draft_m <= 0.0 or design_draft_m >= depth_m:
		errors.append("Design draft must be between keel and deck")
	if design_displacement_t <= 0.0:
		errors.append("Design displacement must be positive")
	var envelope_t := length_m * beam_m * design_draft_m * water_density / 1000.0
	if design_displacement_t >= envelope_t:
		errors.append("Design displacement exceeds the rectangular draft envelope")
	return errors


func make_stations() -> HullStations:
	var errors := validate()
	assert(errors.is_empty(), "Invalid HullPhysicsProfile: %s" % "; ".join(errors))
	if not hull_form.is_empty():
		return HullStations.from_form(
			length_m,
			beam_m,
			depth_m,
			design_draft_m,
			design_displacement_t,
			hull_form,
			water_density,
			length_m * bow_taper_fraction,
			station_count
		)
	return HullStations.from_design(
		length_m,
		beam_m,
		depth_m,
		design_draft_m,
		design_displacement_t,
		water_density,
		bow_taper_fraction,
		station_count
	)


func design_mass_kg() -> float:
	return design_displacement_t * 1000.0


func design_draft_fraction() -> float:
	return design_draft_m / maxf(depth_m, 0.001)


## Align longitudinal mass center with design-draft buoyancy while preserving
## the configured vertical hull mass center.
func calibrate_longitudinal_mass_center() -> void:
	var stations := make_stations()
	var buoyancy_z := stations.center_of_buoyancy_z_below(design_draft_m)
	var full_stores := maxf(full_stores_mass_kg, 0.0)
	var residual_hull := maxf(
		design_mass_kg()
		- maxf(engine_mass_kg, 0.0)
		- maxf(ballast_mass_kg, 0.0)
		- full_stores,
		1.0
	)
	var fixed_moment := (
		engine_position.z * maxf(engine_mass_kg, 0.0)
		+ ballast_position.z * maxf(ballast_mass_kg, 0.0)
		+ stores_position.z * full_stores
	)
	hull_center_of_mass.z = (
		design_mass_kg() * buoyancy_z - fixed_moment
	) / residual_hull
