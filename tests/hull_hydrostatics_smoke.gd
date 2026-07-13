extends SceneTree

const PROFILE := preload("res://scripts/ship/hull_physics_profile.gd")


func _initialize() -> void:
	for profile in [
		_make_profile(30.0, 24.0, 6.0, 3.0, 960.0, 0.0, 10),
		_make_profile(28.0, 10.0, 5.6, 2.8, 256.0, 0.3, 8),
	]:
		_verify_profile(profile)
	print("Hull hydrostatics smoke: design volumes and drafts are coherent")
	quit()


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


func _verify_profile(profile: HullPhysicsProfile) -> void:
	var stations := profile.make_stations()
	var target_volume := profile.design_mass_kg() / profile.water_density
	var actual_volume := stations.volume_below(profile.design_draft_m)
	var relative_error := absf(actual_volume - target_volume) / target_volume
	assert(relative_error < 0.001, "Design volume error %.4f for %.1fm hull" % [
		relative_error, profile.length_m,
	])
	assert(absf(stations.waterplane_area_at(profile.design_draft_m)) > 0.01)
	assert(stations.section_fullness_exponent > 0.05)
