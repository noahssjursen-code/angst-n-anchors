extends SceneTree

## Headless: LodProfiles load + LodService.tier_at hysteresis.

const LOD_PROFILES := preload("res://scripts/core/lod_profiles.gd")
const LOD_SERVICE := preload("res://scripts/core/lod_service.gd")


func _initialize() -> void:
	LOD_PROFILES.reload()
	var default_p: Dictionary = LOD_PROFILES.get_profile(&"default")
	assert(is_equal_approx(float(default_p["detailed_m"]), 280.0), "default detailed_m")
	assert(is_equal_approx(float(default_p["impostor_m"]), 2200.0), "default impostor_m")
	var tall: Dictionary = LOD_PROFILES.get_profile(&"tall")
	assert(is_equal_approx(float(tall["detailed_m"]), 560.0), "tall detailed_m")

	var service = LOD_SERVICE.new()
	assert(
		service.tier_at(100.0, &"default", 1.0, "k", service.Tier.CULLED) == service.Tier.DETAILED,
		"near = detailed",
	)
	## Without bake, mid band stays detailed rather than impostor.
	assert(
		service.tier_at(500.0, &"default", 1.0, "missing", service.Tier.DETAILED)
		== service.Tier.DETAILED,
		"missing impostor keeps detailed until cull",
	)
	assert(
		service.tier_at(3000.0, &"default", 1.0, "missing", service.Tier.DETAILED)
		== service.Tier.CULLED,
		"far = culled",
	)
	## Downgrade hysteresis: still detailed just past impostor/cull band.
	assert(
		service.tier_at(2250.0, &"default", 1.0, "missing", service.Tier.DETAILED)
		== service.Tier.DETAILED,
		"hysteresis holds detailed",
	)
	print("lod_profiles_test: PASS")
	quit(0)
