extends SceneTree

const DOCUMENTED_TAGS := [
	"weathered_wood", "dark_wood", "aged_wood_plank", "structured_timber",
	"polished_wood", "teak_wood", "weathered_iron", "forged_iron",
	"railing_steel", "polished_chrome", "dark_steel", "hull_paint_black",
	"keel_anti_fouling", "superstructure_paint", "deck_steel", "concrete",
	"concrete_dark", "concrete_painted", "steel_frame", "cladding",
	"roofing_panels", "reinforced_glass", "emission_glass",
	"weathered_granite", "mossy_turf", "cold_sand", "skin", "rough_cloth",
	"worn_trousers", "face_ink", "fuel_tank_steel", "industrial_yellow",
	"safety_stripe", "iron_pipe",
]


func _initialize() -> void:
	Palette.clear_cache()
	for tag in DOCUMENTED_TAGS:
		assert(Palette.has_tag(tag), "Missing documented material tag: %s" % tag)
		assert(not Palette.preset_for_tag(tag).is_empty())

	var exposed_a := Palette.make(Palette.PAINTED_STEEL, false, true)
	var exposed_b := Palette.make(Palette.PAINTED_STEEL, false, true)
	var interior := Palette.make(Palette.PAINTED_STEEL, false, false)
	assert(exposed_a == exposed_b, "Identical palette materials must be shared")
	assert(exposed_a != interior, "Interior and weather-exposed variants must differ")
	assert(Palette.cached_material_count() == 2)
	var beacon := Palette.make_tagged("emission_glass")
	assert(beacon.emission_enabled)
	assert(beacon.emission_energy_multiplier > 1.0)
	assert(not bool(beacon.get_meta("palette_exposed")))

	var dry_color := exposed_a.albedo_color
	var dry_roughness := exposed_a.roughness
	var interior_color := interior.albedo_color
	var interior_roughness := interior.roughness
	Palette.set_wetness(1.0)
	assert(exposed_a.albedo_color.get_luminance() < dry_color.get_luminance())
	assert(exposed_a.roughness < dry_roughness)
	assert(interior.albedo_color == interior_color)
	assert(is_equal_approx(interior.roughness, interior_roughness))

	Palette.set_wetness(0.0)
	assert(exposed_a.albedo_color == dry_color)
	assert(is_equal_approx(exposed_a.roughness, dry_roughness))
	Palette.clear_cache()
	print("LightingMaterial tests: palette tags, cache, and wetness passed")
	quit()
