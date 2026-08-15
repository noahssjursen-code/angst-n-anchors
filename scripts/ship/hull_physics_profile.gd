class_name HullPhysicsProfile
extends Resource

## Authoritative metre/SI contract for one vessel hull. Geometry, mass,
## buoyancy, resistance and controls all consume this resource so a hull cannot
## silently use one draft for lift and another for drag.

## Bounds used only by `stations_geometry()` to substitute a floatable hull for
## one `validate()` has rejected. They are deliberately generous: the point is a
## hull that produces finite buoyancy forces, not a plausible one — a profile
## that reaches them is already being reported as invalid.
const MIN_HULL_DIMENSION_M := 0.5
const MIN_DRAFT_FRACTION := 0.05
const MAX_DRAFT_FRACTION := 0.9
const MIN_BLOCK_COEFFICIENT := 0.05
const MAX_BLOCK_COEFFICIENT := 0.9

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
	## Was `assert(errors.is_empty(), ...)` — a genuine invariant (the whole point
	## of `validate()` is that a hull cannot use one draft for lift and another
	## for drag) held by the wrong tool, in both builds:
	##
	##  - DEBUG, measured against the pre-guard file: the assert fires and aborts
	##    `make_stations`, which then returns **null**. Its three production
	##    callers (`catalog_hull_vessel`, `fishing_trawler_small`,
	##    `passenger_catamaran`) and `calibrate_longitudinal_mass_center` all
	##    dereference the result on the next line.
	##  - RELEASE: `assert` is compiled out, so the invalid numbers go straight
	##    into `HullStations` — a draft past the depth puts the waterline above
	##    the deck, a displacement past the rectangular envelope asks for a hull
	##    denser than the box it fits in. Silently wrong buoyancy, which is the
	##    failure mode `assert` is least able to catch.
	##
	## So: report the errors by name, then build from CLAMPED geometry. Measured
	## on a 28x10 hull given draft 9.0 (depth 5.6) and 9000 t: pre-guard
	## `make_stations()` -> null; with the guard -> draft 5.04, 1301.832 t,
	## `volume_below` 1151.6 m3, finite and positive.
	##
	## Valid profiles take the path they always did: `stations_geometry()`
	## returns the authored numbers untouched when `validate()` is empty, and the
	## control in the probe confirms it — 28x10 trawler, `volume_below(2.4)` =
	## 249.756097587721 m3 before and after, to the last digit.
	var errors := validate()
	var g := stations_geometry()
	if not errors.is_empty():
		push_error(
			"HullPhysicsProfile (%s): %s — building stations from clamped geometry L=%.3f B=%.3f D=%.3f draft=%.3f disp=%.3f t" % [
				resource_path if resource_path != "" else "<unsaved>",
				"; ".join(errors),
				g["length_m"], g["beam_m"], g["depth_m"], g["draft_m"], g["displacement_t"],
			]
		)
	if not hull_form.is_empty():
		return HullStations.from_form(
			g["length_m"],
			g["beam_m"],
			g["depth_m"],
			g["draft_m"],
			g["displacement_t"],
			hull_form,
			water_density,
			float(g["length_m"]) * bow_taper_fraction,
			station_count
		)
	return HullStations.from_design(
		g["length_m"],
		g["beam_m"],
		g["depth_m"],
		g["draft_m"],
		g["displacement_t"],
		water_density,
		bow_taper_fraction,
		station_count
	)


## The five hydrostatic numbers `make_stations` actually builds from.
##
## With `validate()` empty this is the authored profile, returned unchanged —
## the clamping below only ever runs on a profile that has already been
## rejected, so no valid hull's stations move by a single float.
func stations_geometry() -> Dictionary:
	if validate().is_empty():
		return {
			"length_m": length_m,
			"beam_m": beam_m,
			"depth_m": depth_m,
			"draft_m": design_draft_m,
			"displacement_t": design_displacement_t,
			"clamped": false,
		}
	var length := maxf(length_m, MIN_HULL_DIMENSION_M)
	var beam := maxf(beam_m, MIN_HULL_DIMENSION_M)
	var depth := maxf(depth_m, MIN_HULL_DIMENSION_M)
	## Strictly between keel and deck, which is exactly what `validate()` demands.
	var draft := clampf(design_draft_m, depth * MIN_DRAFT_FRACTION, depth * MAX_DRAFT_FRACTION)
	## And strictly inside the rectangular draft envelope, likewise.
	var envelope_t := length * beam * draft * water_density / 1000.0
	return {
		"length_m": length,
		"beam_m": beam,
		"depth_m": depth,
		"draft_m": draft,
		"displacement_t": clampf(
			design_displacement_t,
			envelope_t * MIN_BLOCK_COEFFICIENT,
			envelope_t * MAX_BLOCK_COEFFICIENT,
		),
		"clamped": true,
	}


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
