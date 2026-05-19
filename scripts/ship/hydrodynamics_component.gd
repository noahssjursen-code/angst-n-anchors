@tool
class_name HydrodynamicsComponent
extends Node3D

## Principled ship hydrodynamics:
##   * Frictional drag (ITTC-style) over wetted surface area, multiplied by a form factor.
##   * Froude-based wave-making resistance — creates a soft "hull speed" ceiling.
##   * Lateral & yaw drag (cross-flow + rotational damping).
##   * Wind force on superstructure (aerodynamic drag with apparent wind).
##
## Sea-state coupling is no longer here — StripBuoyancyComponent's per-station water
## sampling produces wave-driven drag naturally (the ship's pitch/heave through waves
## costs energy via the heave damping). The slip-grip / orbital-flow hacks are gone.

## Hull station table (shared with StripBuoyancyComponent). Used to derive wetted surface
## area and the length scale for Froude calculations. Set by ShipBuilder.
@export var hull_stations: HullStations
@export var mesh_scale: float = 1.0
@export var water_density: float = 1025.0
@export var gravity: float = 9.81

@export_group("Hull drag")
## ITTC-style frictional drag coefficient over the wetted hull surface. Real-world cargo
## ships sit around 0.002–0.003. Includes biofouling / roughness in practice.
@export_range(0.0, 0.02, 0.0001) var frictional_coeff: float = 0.0025
## Form factor (1+k). Multiplies frictional drag. ≈ 1.15–1.30 for cargo hulls.
@export_range(1.0, 2.0, 0.01) var form_factor: float = 1.20
## Wave-making peak coefficient — controls how strong the hull-speed wall is.
## 0.003 is typical for a displacement cargo ship; higher = stronger wall.
@export_range(0.0, 0.05, 0.0001) var wave_making_peak_coeff: float = 0.003
## Froude number above which wave-making drag rises sharply (the hull speed knee).
## Displacement hulls hit a wall around Fn = 0.4; sleeker hulls push to 0.45+.
@export_range(0.2, 0.6, 0.01) var hull_speed_fn: float = 0.40

@export_group("Lateral / yaw")
## Cross-flow drag coefficient. Ships are flat plates edge-on — values 1.5–3.0 typical.
@export_range(0.0, 5.0, 0.05) var lateral_drag_coeff: float = 2.0
## Yaw damping coefficient (rotational drag).
@export_range(0.0, 20.0, 0.1) var yaw_drag_coeff: float = 5.0

@export_group("Wind / aerodynamics")
@export var air_density: float = 1.225
@export var wind_frontal_area: float = 20.0
@export var wind_lateral_area: float = 70.0
@export_range(0.0, 2.0, 0.01) var wind_drag_coeff: float = 0.85

var _body: RigidBody3D
# Cached at runtime once mesh_scale + hull_stations are known.
var _wetted_area_m2: float = 0.0
var _length_world_m: float = 0.0
var _draft_m: float = 0.0


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("HydrodynamicsComponent must be a child of a RigidBody3D")
		return
	_recompute_geometry()


## Recompute cached geometry from hull_stations + mesh_scale. Call after changing either.
func _recompute_geometry() -> void:
	if hull_stations == null:
		return
	var s := mesh_scale
	_length_world_m = hull_stations.length_m * s
	# Use design draft assumption: 50% of hull height. Good enough for cached drag —
	# StripBuoyancy will settle the actual draft from mass balance.
	_draft_m = (hull_stations.height_m * 0.5) * s
	# Wetted surface area approximation: sum over stations of (perimeter at waterline × length).
	# Perimeter on each side ≈ 2*draft (vertical) + half_beam (bottom horizontal).
	# Full beam: 2 * (2*draft + half_beam).
	var waterline_local: float = hull_stations.keel_y + (hull_stations.height_m * 0.5)
	var total_S: float = 0.0
	for i in range(hull_stations.stations.size()):
		var hb_wl: float = hull_stations.half_beam_at(i, waterline_local) * s
		var hb_keel: float = hull_stations.half_beam_at(i, hull_stations.keel_y) * s
		if hb_wl <= 0.001:
			continue
		var st_len: float = hull_stations.station_length(i) * s
		# Per-side wetted perimeter at this station ≈ draft (vertical) + (half_beam at keel for bottom run)
		var side_perim: float = _draft_m + hb_keel
		var ring_perim: float = 2.0 * side_perim  # both sides
		total_S += ring_perim * st_len
	_wetted_area_m2 = total_S


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _body == null or hull_stations == null:
		return
	if _wetted_area_m2 <= 0.0:
		_recompute_geometry()
		if _wetted_area_m2 <= 0.0:
			return

	var basis: Basis = _body.global_transform.basis
	var basis_inv: Basis = basis.inverse()
	var v_world: Vector3 = _body.linear_velocity
	var v_local: Vector3 = basis_inv * v_world
	var omega_y_local: float = (basis_inv * _body.angular_velocity).y

	# --- FORWARD DRAG: frictional × form factor + wave-making ---
	var v_fwd: float = v_local.z
	var v_fwd_mag: float = absf(v_fwd)
	if v_fwd_mag > 0.01:
		var q: float = 0.5 * water_density * v_fwd_mag * v_fwd_mag
		var Cf: float = frictional_coeff * form_factor
		var Cw: float = _wave_making_coefficient(v_fwd_mag)
		var F_fwd: float = q * _wetted_area_m2 * (Cf + Cw)
		# Sign: opposes motion along the forward axis.
		var f_local := Vector3(0.0, 0.0, -signf(v_fwd) * F_fwd)
		_body.apply_central_force(basis * f_local)

	# --- LATERAL DRAG (cross-flow): high coefficient, hull side as flat plate ---
	var v_lat: float = v_local.x
	var v_lat_mag: float = absf(v_lat)
	if v_lat_mag > 0.01:
		var q_lat: float = 0.5 * water_density * v_lat_mag * v_lat_mag
		var side_area: float = _length_world_m * _draft_m
		var F_lat: float = q_lat * side_area * lateral_drag_coeff
		var f_local := Vector3(-signf(v_lat) * F_lat, 0.0, 0.0)
		_body.apply_central_force(basis * f_local)

	# --- YAW DAMPING ---
	var om_mag: float = absf(omega_y_local)
	if om_mag > 0.001:
		# Yaw torque ∝ ω² · ρ · L³ · draft · Cyaw  (L³ from torque arm² × velocity_at_tip)
		var L: float = _length_world_m
		var T_yaw: float = 0.5 * water_density * om_mag * om_mag * L * L * L * _draft_m * yaw_drag_coeff * 0.01
		# Sign opposes spin.
		var t_local := Vector3(0.0, -signf(omega_y_local) * T_yaw, 0.0)
		_body.apply_torque(basis * t_local)

	# --- WIND FORCE on superstructure ---
	var wind_speed: float = float(WeatherLighting.wind_speed_ms)
	if wind_speed > 0.1 and wind_drag_coeff > 0.0:
		var wind_dir3: Vector3 = WeatherLighting.wind_dir
		wind_dir3.y = 0.0
		var wind_vel: Vector3 = wind_dir3 * wind_speed
		var ship_horiz: Vector3 = Vector3(v_world.x, 0.0, v_world.z)
		var apparent_wind: Vector3 = wind_vel - ship_horiz
		var local_wind: Vector3 = basis_inv * apparent_wind
		var fw_x: float = 0.5 * air_density * local_wind.x * absf(local_wind.x) * wind_lateral_area * wind_drag_coeff
		var fw_z: float = 0.5 * air_density * local_wind.z * absf(local_wind.z) * wind_frontal_area * wind_drag_coeff
		var wind_local := Vector3(fw_x, 0.0, fw_z)
		_body.apply_central_force(basis * wind_local)


## Empirical wave-making resistance coefficient as a function of forward speed.
## Below Fn = 0.15, near zero. Rises with (Fn - 0.15)². Above hull_speed_fn, rises
## sharply (quadratic kick) to create the hull-speed soft wall.
func _wave_making_coefficient(v_fwd_mag: float) -> float:
	if _length_world_m <= 0.1:
		return 0.0
	var Fn: float = v_fwd_mag / sqrt(gravity * _length_world_m)
	if Fn < 0.15:
		return 0.0
	# Smooth ramp from 0 at Fn=0.15 to peak at Fn=hull_speed_fn.
	var ramp_t: float = clampf((Fn - 0.15) / maxf(hull_speed_fn - 0.15, 0.01), 0.0, 1.0)
	var Cw: float = wave_making_peak_coeff * ramp_t * ramp_t
	if Fn > hull_speed_fn:
		# Above the knee, wave-making rises sharply — soft wall behaviour.
		var over: float = Fn - hull_speed_fn
		Cw += wave_making_peak_coeff * 8.0 * over * over
	return Cw
