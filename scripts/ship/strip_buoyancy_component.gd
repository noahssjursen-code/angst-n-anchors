@tool
class_name StripBuoyancyComponent
extends Node3D

## Distributed strip-theory lift. Every half-section uses one timestamped water
## sample and applies Archimedes lift at its submerged centroid.

@export var hull_stations: HullStations
@export var mesh_scale: float = 1.0 ## Deprecated; stations are metres.
@export var water_density: float = 1025.0
@export var gravity: float = 9.81
@export_range(0.5, 2.0, 0.01) var buoyancy_multiplier: float = 1.0
@export var heave_damping_per_m2: float = 11000.0 ## Legacy fallback only.
@export var hull_center_x_m: float = 0.0
@export_range(0.1, 1.0, 0.05) var damping_mass_fraction: float = 1.0

var _body: RigidBody3D

var submerged_volume_m3: float = 0.0
var current_draft_m: float = 0.0
var waterplane_area_m2: float = 0.0
var center_of_buoyancy_world: Vector3 = Vector3.ZERO
var total_lift_n: float = 0.0
var total_damping_n: float = 0.0
var effective_damping_ratio: float = 0.0
var water_snapshot_age_s: float = INF
var stale_sample_count: int = 0
var cpu_time_ms: float = 0.0


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if _body == null:
		push_error("StripBuoyancyComponent must be a child of a RigidBody3D")
		return
	if not Engine.is_editor_hint():
		WaveSurface.set_coupled_vessel(_body)


func _exit_tree() -> void:
	if _body != null and not Engine.is_editor_hint():
		WaveSurface.clear_coupled_vessel_if(_body)


func _physics_process(_delta: float) -> void:
	if (
		Engine.is_editor_hint()
		or _body == null
		or hull_stations == null
		or hull_stations.stations.is_empty()
	):
		return
	var force_scale := 1.0
	if _body.has_method("get_physics_force_scale_for_tick"):
		force_scale = float(_body.call("get_physics_force_scale_for_tick"))
	if force_scale <= 0.0:
		return
	var cpu_begin := Time.get_ticks_usec()
	var samples := _gather_samples()
	_measure_hydrostatics(samples)
	_apply_forces(samples, force_scale)
	cpu_time_ms = float(Time.get_ticks_usec() - cpu_begin) / 1000.0


func _gather_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	var stride := 1
	if _body.has_method("get_physics_station_stride"):
		stride = maxi(int(_body.call("get_physics_station_stride")), 1)
	for i in range(0, hull_stations.stations.size(), stride):
		var station: Dictionary = hull_stations.stations[i]
		var z_local := float(station["z"])
		var station_length := hull_stations.station_length(i) * float(stride)
		var half_beam := hull_stations.half_beam_at(i, hull_stations.deck_y)
		if station_length <= 0.0 or half_beam <= 0.001:
			continue
		for side_sign in [-1.0, 1.0]:
			var sample := _build_side_sample(
				i, z_local, half_beam * 0.5 * side_sign, station_length, side_sign
			)
			if not sample.is_empty():
				samples.append(sample)
	return samples


func _build_side_sample(
	station_idx: int,
	z_local: float,
	x_proxy: float,
	station_length: float,
	side_sign: float,
) -> Dictionary:
	var proxy_world := _body.to_global(Vector3(
		hull_center_x_m + x_proxy, hull_stations.design_draft_m, z_local
	))
	var water := WaveSurface.sample_at(proxy_world.x, proxy_world.z)
	var water_local := _body.to_local(Vector3(
		proxy_world.x, water.height, proxy_world.z
	))
	var waterline_y := water_local.y
	var half_area := hull_stations.half_section_area_below(station_idx, waterline_y)
	if half_area <= 0.0:
		return {}
	var centroid_x := hull_stations.half_section_centroid_x_below(
		station_idx, waterline_y
	) * side_sign
	var centroid_y := hull_stations.half_section_centroid_y_below(
		station_idx, waterline_y
	)
	return {
		"force_point": _body.to_global(Vector3(
			hull_center_x_m + centroid_x, centroid_y, z_local
		)),
		"volume": half_area * station_length,
		"waterplane_area": hull_stations.half_beam_at(
			station_idx, waterline_y
		) * station_length,
		"draft": maxf(waterline_y - hull_stations.keel_y, 0.0),
		"water": water,
	}


func _measure_hydrostatics(samples: Array[Dictionary]) -> void:
	submerged_volume_m3 = 0.0
	waterplane_area_m2 = 0.0
	current_draft_m = 0.0
	center_of_buoyancy_world = Vector3.ZERO
	stale_sample_count = 0
	water_snapshot_age_s = 0.0
	for data in samples:
		var volume := float(data["volume"])
		var wp_area := float(data["waterplane_area"])
		submerged_volume_m3 += volume
		waterplane_area_m2 += wp_area
		center_of_buoyancy_world += (data["force_point"] as Vector3) * volume
		current_draft_m += float(data["draft"]) * wp_area
		var water := data["water"] as WaterSample
		water_snapshot_age_s = maxf(water_snapshot_age_s, water.age_seconds)
		if water.stale:
			stale_sample_count += 1
	if submerged_volume_m3 > 1e-6:
		center_of_buoyancy_world /= submerged_volume_m3
	if waterplane_area_m2 > 1e-6:
		current_draft_m /= waterplane_area_m2


func _apply_forces(samples: Array[Dictionary], force_scale: float = 1.0) -> void:
	total_lift_n = 0.0
	total_damping_n = 0.0
	var target_ratio := 0.85
	var max_damping_accel := 6.0
	if _body is BoatBody and (_body as BoatBody).physics_profile != null:
		var profile := (_body as BoatBody).physics_profile
		target_ratio = profile.heave_damping_ratio
		max_damping_accel = profile.max_heave_damping_accel
	var stiffness := water_density * gravity * waterplane_area_m2
	var critical_damping := 2.0 * sqrt(maxf(
		_body.mass * damping_mass_fraction * stiffness,
		0.0
	))
	var damping_coefficient := target_ratio * critical_damping
	effective_damping_ratio = (
		damping_coefficient / critical_damping if critical_damping > 1e-6 else 0.0
	)
	var world_com := _body.to_global(_body.center_of_mass)
	for data in samples:
		var force_point := data["force_point"] as Vector3
		var offset_from_com := force_point - world_com
		var area_fraction := (
			float(data["waterplane_area"]) / waterplane_area_m2
			if waterplane_area_m2 > 1e-6 else 0.0
		)
		var water := data["water"] as WaterSample
		var point_velocity := (
			_body.linear_velocity + _body.angular_velocity.cross(offset_from_com)
		)
		var lift_n := (
			water_density * gravity * buoyancy_multiplier * float(data["volume"])
		)
		var damping_n := (
			-(point_velocity.y - water.velocity.y)
			* damping_coefficient
			* area_fraction
		)
		var force_limit := (
			_body.mass * max_damping_accel * maxf(area_fraction, 0.02)
		)
		if water.stale:
			damping_n *= 0.5
		damping_n = clampf(damping_n, -force_limit, force_limit)
		_body.apply_force(
			Vector3(0.0, (lift_n + damping_n) * force_scale, 0.0),
			force_point - _body.global_position
		)
		total_lift_n += lift_n * force_scale
		total_damping_n += damping_n * force_scale
