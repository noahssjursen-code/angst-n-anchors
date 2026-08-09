extends Node

const TestReport := preload("res://tests/support/test_report.gd")
const PROFILE := preload("res://scripts/ship/hull_physics_profile.gd")


func _ready() -> void:
	var t := TestReport.new("hull_hydrostatics_smoke")
	for profile in [
		_make_profile(30.0, 24.0, 6.0, 3.0, 960.0, 0.0, 10),
		_make_profile(28.0, 10.0, 5.6, 2.8, 256.0, 0.3, 8),
	]:
		_verify_profile(t, profile)
	for entry in HullRegistry.catalog():
		var hull_id := str(entry.get("id", ""))
		var boat := HullRegistry.build_hull(hull_id)
		if not t.check("Registered hull must build: %s" % hull_id, boat != null):
			continue
		var target_volume := boat.displacement_t * 1000.0 / 1025.0
		var actual_volume := boat.hull_stations.volume_below(boat.draft_m)
		t.check(
			"Registered hull design volume mismatch: %s" % hull_id,
			absf(actual_volume - target_volume) / target_volume < 0.015,
		)
		boat.free()
	t.finish(get_tree())


func _make_profile(
	length: float,
	beam: float,
	depth: float,
	draft: float,
	displacement: float,
	bow_taper: float,
	station_count: int,
) -> HullPhysicsProfile:
	var profile := PROFILE.new() as HullPhysicsProfile
	profile.length_m = length
	profile.beam_m = beam
	profile.depth_m = depth
	profile.design_draft_m = draft
	profile.design_displacement_t = displacement
	profile.bow_taper_fraction = bow_taper
	profile.station_count = station_count
	return profile


func _verify_profile(t: TestReport, profile: HullPhysicsProfile) -> void:
	var stations := profile.make_stations()
	var target_volume := profile.design_mass_kg() / profile.water_density
	var actual_volume := stations.volume_below(profile.design_draft_m)
	var relative_error := absf(actual_volume - target_volume) / target_volume
	t.check("Design volume error %.4f for %.1fm hull" % [
		relative_error, profile.length_m,
	], relative_error < 0.001)
	t.check(
		"waterplane area at design draft is non-zero",
		absf(stations.waterplane_area_at(profile.design_draft_m)) > 0.01,
	)
	t.check("section fullness exponent is positive", stations.section_fullness_exponent > 0.05)
