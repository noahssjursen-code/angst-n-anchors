extends SceneTree

## Headless: LodProfiles load + LodService.tier_at hysteresis.

const TestReport := preload("res://tests/support/test_report.gd")
const LOD_PROFILES := preload("res://scripts/core/lod_profiles.gd")
const LOD_SERVICE := preload("res://scripts/core/lod_service.gd")


func _initialize() -> void:
	var t := TestReport.new("lod_profiles_test")
	LOD_PROFILES.reload()
	var default_p: Dictionary = LOD_PROFILES.get_profile(&"default")
	t.check("default detailed_m", is_equal_approx(float(default_p["detailed_m"]), 280.0))
	t.check("default impostor_m", is_equal_approx(float(default_p["impostor_m"]), 2200.0))
	var tall: Dictionary = LOD_PROFILES.get_profile(&"tall")
	t.check("tall detailed_m", is_equal_approx(float(tall["detailed_m"]), 560.0))

	var service = LOD_SERVICE.new()
	t.check(
		"near = detailed",
		service.tier_at(100.0, &"default", 1.0, "k", service.Tier.CULLED) == service.Tier.DETAILED,
	)
	## Without bake, mid band stays detailed rather than impostor.
	t.check(
		"missing impostor keeps detailed until cull",
		service.tier_at(500.0, &"default", 1.0, "missing", service.Tier.DETAILED)
		== service.Tier.DETAILED,
	)
	t.check(
		"far = culled",
		service.tier_at(3000.0, &"default", 1.0, "missing", service.Tier.DETAILED)
		== service.Tier.CULLED,
	)
	## Downgrade hysteresis: still detailed just past impostor/cull band.
	t.check(
		"hysteresis holds detailed",
		service.tier_at(2250.0, &"default", 1.0, "missing", service.Tier.DETAILED)
		== service.Tier.DETAILED,
	)
	t.finish(self)
