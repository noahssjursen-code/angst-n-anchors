extends Node

const TRAWLER := preload("res://scripts/ship/vessels/fishing_trawler_small.gd")
const CATAMARAN := preload("res://scripts/ship/vessels/passenger_catamaran.gd")

class FakeFFT:
	extends Node
	var physics_query_data: Array[PackedFloat32Array] = []
	var physics_query_snapshot_time: float = 10.0
	var length_scales := Vector4(256.0, 64.0, 16.0, 4.0)
	var age_seconds: float = 0.01

	func get_physics_query_age_seconds() -> float:
		return age_seconds


var _failures: PackedStringArray = []


func _ready() -> void:
	_test_hydrostatic_profiles()
	await _test_mass_and_moments()
	await _test_heave_free_decay()
	await _test_dynamic_cruise_acceleration()
	_test_water_query_and_staleness()
	_test_handling_targets()
	_test_mooring_and_query_budget()
	WaveSurface.fft_system = null
	WaveSurface.clear_sample_cache()
	if _failures.is_empty():
		print("Boat physics validation: all deterministic checks passed")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error("Boat physics validation: " + failure)
		get_tree().quit(1)


func _profile(
	length: float,
	beam: float,
	depth: float,
	draft: float,
	displacement_t: float,
	bow_taper: float,
	shaft_kw: float,
) -> HullPhysicsProfile:
	var profile := HullPhysicsProfile.new()
	profile.length_m = length
	profile.beam_m = beam
	profile.depth_m = depth
	profile.design_draft_m = draft
	profile.design_displacement_t = displacement_t
	profile.bow_taper_fraction = bow_taper
	profile.station_count = 10
	profile.hull_center_of_mass = Vector3(0.0, 0.8, 0.0)
	profile.engine_mass_kg = displacement_t * 8.0
	profile.engine_position = Vector3(0.0, 0.9, length * 0.3)
	profile.ballast_mass_kg = displacement_t * 16.0
	profile.ballast_position = Vector3(0.0, 0.2, 0.0)
	profile.full_stores_mass_kg = displacement_t * 4.0
	profile.stores_position = Vector3(0.0, 1.0, length * 0.15)
	profile.shaft_power_kw = shaft_kw
	profile.calibrate_longitudinal_mass_center()
	return profile


func _test_hydrostatic_profiles() -> void:
	for profile in [
		_profile(30.0, 24.0, 6.0, 3.0, 960.0, 0.0, 350.0),
		_profile(28.0, 10.0, 5.6, 2.8, 256.0, 0.3, 180.0),
		CATAMARAN.make_physics_profile(),
	]:
		var typed_profile := profile as HullPhysicsProfile
		var stations: HullStations = typed_profile.make_stations()
		var target: float = typed_profile.design_mass_kg() / typed_profile.water_density
		var actual: float = stations.volume_below(typed_profile.design_draft_m)
		_check(absf(actual - target) / target < 0.001, "station-volume calibration")
		var solved_draft := _solve_draft(stations, target)
		_check(
			absf(solved_draft - typed_profile.design_draft_m) < 0.05,
			"still-water draft tolerance"
		)
		_check(
			stations.half_section_centroid_x_below(5, typed_profile.design_draft_m) > 0.0,
			"submerged half-section centroid"
		)
	var cat_entry := HullRegistry.get_by_id(CATAMARAN.VESSEL_ID)
	_check(int(cat_entry.get("price_marks", -1)) == 0, "catamaran hull costs zero")
	for entry in HullRegistry.catalog():
		var hull_id := str(entry.get("id", ""))
		var boat := HullRegistry.build_hull(hull_id)
		_check(boat != null, "registered hull builds: %s" % hull_id)
		if boat == null:
			continue
		var target := boat.displacement_t * 1000.0 / 1025.0
		var actual := boat.hull_stations.volume_below(boat.draft_m)
		_check(
			absf(actual - target) / maxf(target, 0.001) < 0.015,
			"registered hull draft calibration: %s" % hull_id
		)
		boat.free()


func _test_mass_and_moments() -> void:
	var profile := _profile(30.0, 24.0, 6.0, 3.0, 960.0, 0.0, 350.0)
	var boat := BoatBody.new()
	boat.name = "ValidationBoat"
	boat.automatic_physics_lod = false
	boat.physics_profile = profile
	boat.hull_stations = profile.make_stations()
	boat.length_m = profile.length_m
	boat.beam_m = profile.beam_m
	boat.depth_m = profile.depth_m
	boat.displacement_t = profile.design_displacement_t
	boat.fuel_capacity_l = 1000.0
	boat.fuel_l = 1000.0
	add_child(boat)
	await get_tree().process_frame
	_check(absf(boat.mass - profile.design_mass_kg()) < 1.0, "design mass ledger")
	var base_com := boat.center_of_mass
	boat.set_mass_entry("cargo:test", 20000.0, Vector3(4.0, 4.0, -8.0), "cargo")
	_check(boat.center_of_mass.x > base_com.x, "cargo-induced heel moment")
	_check(boat.center_of_mass.z < base_com.z, "cargo-induced trim moment")
	var loaded_mass := boat.mass
	boat.fuel_l = 500.0
	_check(boat.mass < loaded_mass, "fuel burn reduces vessel mass")
	_check(boat.inertia.x > 0.0 and boat.inertia.y > 0.0 and boat.inertia.z > 0.0, "custom inertia")
	boat.set_physics_quality(BoatBody.PhysicsQuality.MEDIUM)
	_check(boat.get_physics_station_stride() == 2, "medium physics station tier")
	boat.set_physics_quality(BoatBody.PhysicsQuality.SLEEP)
	_check(boat.freeze and boat.get_physics_quality_name() == "SLEEP", "authority-safe sleep tier")
	boat.set_physics_quality(BoatBody.PhysicsQuality.FULL)
	_check(not boat.freeze, "full physics wake tier")
	boat.free()


func _test_water_query_and_staleness() -> void:
	var fake := FakeFFT.new()
	fake.physics_query_data.resize(4)
	var count := FFTWaterSystem.PHYSICS_QUERY_RESOLUTION
	count *= count * 4
	for cascade in range(4):
		var layer := PackedFloat32Array()
		layer.resize(count)
		layer.fill(0.0)
		fake.physics_query_data[cascade] = layer
	for texel in range(count / 4):
		var idx := texel * 4
		fake.physics_query_data[0][idx] = 1.0
		fake.physics_query_data[0][idx + 1] = 2.0
		fake.physics_query_data[0][idx + 2] = 3.0
		fake.physics_query_data[0][idx + 3] = 4.0
	add_child(fake)
	WaveSurface.fft_system = fake
	WaveSurface.wave_intensity = 1.0
	var scale := WaveSurface.get_wave_energy_multiplier() * 0.42
	var sample := WaveSurface.sample_at(3.2, 7.1)
	var expected_height := WaveSurface.WATER_LEVEL + scale + 3.0 * scale * fake.age_seconds
	_check(absf(sample.height - expected_height) < 0.001, "macro-water parity")
	_check(sample.velocity.distance_to(Vector3(2.0, 3.0, 4.0) * scale) < 0.001, "water velocity decode")
	fake.age_seconds = 1.0
	var stale := WaveSurface.sample_at(4.4, 8.3)
	_check(stale.stale and stale.velocity == Vector3.ZERO, "bounded stale-water fallback")
	fake.free()


func _test_heave_free_decay() -> void:
	WaveSurface.fft_system = null
	WaveSurface.clear_sample_cache()
	var profile := _profile(28.0, 10.0, 5.6, 2.8, 256.0, 0.3, 180.0)
	var boat := BoatBody.new()
	boat.name = "HeaveDecayBoat"
	boat.automatic_physics_lod = false
	boat.physics_profile = profile
	boat.hull_stations = profile.make_stations()
	boat.length_m = profile.length_m
	boat.beam_m = profile.beam_m
	boat.depth_m = profile.depth_m
	boat.displacement_t = profile.design_displacement_t
	boat.fuel_capacity_l = 1000.0
	boat.fuel_l = 1000.0
	var equilibrium_y := WaveSurface.WATER_LEVEL - profile.design_draft_m
	boat.position = Vector3(0.0, equilibrium_y, 0.0)
	var buoyancy := StripBuoyancyComponent.new()
	buoyancy.name = "StripBuoyancyComponent"
	buoyancy.hull_stations = boat.hull_stations
	boat.add_child(buoyancy)
	add_child(boat)
	for _frame in range(60):
		await get_tree().physics_frame
	_check(
		absf(boat.rotation.x) < deg_to_rad(0.25),
		"symmetric trim stability (%.3f°, LCG %.3f, LCB %.3f, live %.3f)" % [
			rad_to_deg(boat.rotation.x),
			boat.center_of_mass.z,
			boat.hull_stations.center_of_buoyancy_z_below(profile.design_draft_m),
			boat.to_local(buoyancy.center_of_buoyancy_world).z,
		]
	)
	_check(
		absf(boat.rotation.z) < deg_to_rad(0.25),
		"symmetric heel stability (%.3f°)" % rad_to_deg(boat.rotation.z)
	)
	boat.position.y = equilibrium_y + 0.4
	boat.rotation = Vector3.ZERO
	boat.linear_velocity = Vector3.ZERO
	boat.angular_velocity = Vector3.ZERO
	var max_speed := 0.0
	for _frame in range(240):
		await get_tree().physics_frame
		max_speed = maxf(max_speed, absf(boat.linear_velocity.y))
	_check(max_speed < 4.0, "bounded heave free-decay velocity")
	_check(absf(boat.position.y - equilibrium_y) < 0.18, "heave free-decay convergence")
	boat.free()


func _test_handling_targets() -> void:
	for profile in [
		_profile(30.0, 24.0, 6.0, 3.0, 960.0, 0.0, 350.0),
		_profile(28.0, 10.0, 5.6, 2.8, 256.0, 0.3, 180.0),
	]:
		var typed_profile := profile as HullPhysicsProfile
		var terminal := _estimate_terminal_speed(typed_profile)
		_check(terminal >= 4.0 and terminal <= 7.0, "terminal-speed target")
		var rudder_force: float = (
			0.5 * typed_profile.water_density * 5.0 * 5.0
			* typed_profile.rudder_area_m2
			* typed_profile.rudder_lift_slope
			* deg_to_rad(typed_profile.max_rudder_angle_deg)
		)
		_check(rudder_force > 0.0, "rudder force authority")
		_check(typed_profile.prop_wash_speed_ms > 0.0, "bounded low-speed prop wash")
	for vessel_profile in [
		TRAWLER.make_physics_profile(),
		CATAMARAN.make_physics_profile(),
	]:
		var profile := vessel_profile as HullPhysicsProfile
		var thrust_at_cruise := minf(
			profile.bollard_thrust_n,
			profile.shaft_power_kw * 1000.0 * profile.propulsive_efficiency / 5.0
		)
		_check(
			thrust_at_cruise >= profile.bollard_thrust_n * 0.99,
			"scaled engine preserves thrust through cruise"
		)


func _test_dynamic_cruise_acceleration() -> void:
	WaveSurface.fft_system = null
	WaveSurface.clear_sample_cache()
	var vessels: Array[BoatBody] = [
		TRAWLER.new() as BoatBody,
	]
	for i in range(vessels.size()):
		var boat := vessels[i]
		boat.name = "ValidationTrawler%d" % i
		boat.automatic_physics_lod = false
		boat.position = Vector3(float(i) * 100.0, 0.0, 0.0)
		add_child(boat)
		boat.place_at_waterline(WaveSurface.WATER_LEVEL)
		var propulsion := boat.get_node("PropulsionComponent") as PropulsionComponent
		propulsion.throttle = -1.0
	for _frame in range(360):
		await get_tree().physics_frame
	for boat in vessels:
		var speed_knots := (
			absf(boat.linear_velocity.dot(-boat.global_transform.basis.z)) * 1.94384
		)
		print("%s acceleration: %.2f kn after 6 s" % [boat.name, speed_knots])
		_check(
			speed_knots > 5.0,
			"%s exceeds 3-knot regression (%.2f kn)" % [boat.name, speed_knots]
		)
		boat.free()
	vessels.clear()
	WaveSurface.clear_sample_cache()
	for _frame in range(3):
		await get_tree().process_frame


func _test_mooring_and_query_budget() -> void:
	var mooring := MooringComponent.new()
	_check(
		mooring.mooring_heave_damping < mooring.mooring_lin_damping,
		"mooring permits wave heave"
	)
	_check(
		mooring.mooring_tilt_damping < mooring.mooring_ang_damping,
		"mooring permits roll and pitch"
	)
	var bytes_per_second := (
		FFTWaterSystem.PHYSICS_QUERY_RESOLUTION
		* FFTWaterSystem.PHYSICS_QUERY_RESOLUTION
		* 16 * 4 * 30
	)
	_check(
		float(bytes_per_second) / (1024.0 * 1024.0) < 31.0,
		"physics-query readback bandwidth"
	)
	mooring.free()


func _solve_draft(stations: HullStations, target_volume: float) -> float:
	var low := stations.keel_y
	var high := stations.deck_y
	for _iteration in range(40):
		var mid := (low + high) * 0.5
		if stations.volume_below(mid) < target_volume:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5


func _estimate_terminal_speed(profile: HullPhysicsProfile) -> float:
	var stations := profile.make_stations()
	var waterline := stations.keel_y + profile.design_draft_m
	var wetted := 0.0
	for i in range(stations.stations.size()):
		var hb := stations.half_beam_at(i, waterline)
		wetted += (
			2.0 * sqrt(profile.design_draft_m * profile.design_draft_m + hb * hb)
			* stations.station_length(i)
		)
	for step in range(1, 151):
		var speed := float(step) * 0.1
		var fn := speed / sqrt(9.81 * profile.length_m)
		var ramp := clampf((fn - 0.15) / maxf(profile.hull_speed_fn - 0.15, 0.01), 0.0, 1.0)
		var cw := profile.wave_making_peak_coeff * ramp * ramp if fn >= 0.15 else 0.0
		if fn > profile.hull_speed_fn:
			var over := fn - profile.hull_speed_fn
			cw += profile.wave_making_peak_coeff * 8.0 * over * over
		var drag := (
			0.5 * profile.water_density * speed * speed * wetted
			* (profile.frictional_coeff * profile.form_factor + cw)
		)
		var thrust := minf(
			profile.bollard_thrust_n,
			profile.shaft_power_kw * 1000.0 * profile.propulsive_efficiency / speed
		)
		if drag >= thrust:
			return speed
	return 15.0


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)
