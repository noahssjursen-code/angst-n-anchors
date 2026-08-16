extends Node

## Hydrostatics smoke test: every hull the game offers must displace what its
## record says it displaces.
##
## ## Why the fleet is DECLARED and not just walked (REALITY.md §4f)
##
## The per-hull arm is a `t.check()` inside a `for` over `HullRegistry.catalog()`
## — a collection this file DISCOVERS, half of it read out of a shipped JSON
## file. That is the vanishing-check shape exactly. Measured 2026-08-16 by
## deleting `hull_100x24` from `resources/data/vessels/hulls/catalog.json`: this
## unit went from **PASS (24) to PASS (22)** and said nothing. Two checks did not
## fail. They stopped existing, and the verdict line cannot tell the difference.
##
## `EXPECTED_HULL_IDS` is what closes that, and it is the first of §4f's four
## shapes rather than the last: the fleet is a small, stable, shipped set, so it
## can be a literal, and a literal names the hull that went missing instead of
## reporting a number that moved.
##
## It is compared against the discovered catalogue rather than walked in its
## place, deliberately. `HullRegistry.get_by_id()` falls back to
## `FISHING_TRAWLER_SMALL` for an id it does not know, so a test that iterated
## this literal directly would quietly measure the trawler twice for a deleted
## hull and stay green — §4c, a check that passes BECAUSE something is broken.
## Comparing the two lists catches both a hull that vanished and a hull that was
## substituted.
##
## Re-freeze this list in the same commit that adds or removes a hull, never
## after the fact.

const TestReport := preload("res://tests/support/test_report.gd")
const PROFILE := preload("res://scripts/ship/hull_physics_profile.gd")

## The fleet `HullRegistry.catalog()` returns, in its own `loa_m`-ascending
## order: `FISHING_TRAWLER_SMALL` and `PASSENGER_CATAMARAN` from the registry
## itself, plus the seven hulls of `resources/data/vessels/hulls/catalog.json`.
## Measured against the shipped catalogue 2026-08-16.
const EXPECTED_HULL_IDS := [
	"hull_15x5",
	"hull_28x10",
	"hull_45x16_cat",
	"hull_70x18",
	"hull_90x24",
	"hull_100x24",
	"hull_120x28",
	"hull_130x28",
	"hull_150x32",
]


func _ready() -> void:
	var t := TestReport.new("hull_hydrostatics_smoke")
	for profile in [
		_make_profile(30.0, 24.0, 6.0, 3.0, 960.0, 0.0, 10),
		_make_profile(28.0, 10.0, 5.6, 2.8, 256.0, 0.3, 8),
	]:
		_verify_profile(t, profile)

	var fleet := HullRegistry.catalog()
	_check_fleet_population(t, fleet)

	for entry in fleet:
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


## The declared population. Every check below this one is inside a loop over the
## fleet, so if the fleet shrinks they do not fail — they cease to exist. This is
## the only check in the file that can see that happen.
func _check_fleet_population(t: TestReport, fleet: Array) -> void:
	var found: Array = []
	for entry in fleet:
		found.append(str(entry.get("id", "")))
	found.sort()
	var declared: Array = EXPECTED_HULL_IDS.duplicate()
	declared.sort()
	if found == declared:
		t.check("the catalogue offers exactly the %d declared hulls" % declared.size(), true)
		return
	var missing: Array = []
	for id in declared:
		if not found.has(id):
			missing.append(id)
	var unexpected: Array = []
	for id in found:
		if not declared.has(id):
			unexpected.append(id)
	t.check(
		"the catalogue offers exactly the %d declared hulls" % declared.size()
			+ " (missing %s, unexpected %s — re-freeze EXPECTED_HULL_IDS in the"
			% [missing, unexpected]
			+ " commit that changes the fleet, never after the fact)",
		false,
	)


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
