extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")

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
	var t := TestReport.new("lighting_material_test")
	Palette.clear_cache()
	for tag in DOCUMENTED_TAGS:
		t.check("Missing documented material tag: %s" % tag, Palette.has_tag(tag))
		t.check("preset is non-empty for tag: %s" % tag, not Palette.preset_for_tag(tag).is_empty())

	var exposed_a := Palette.make(Palette.PAINTED_STEEL, false, true)
	var exposed_b := Palette.make(Palette.PAINTED_STEEL, false, true)
	var interior := Palette.make(Palette.PAINTED_STEEL, false, false)
	t.check("Identical palette materials must be shared", exposed_a == exposed_b)
	t.check("Interior and weather-exposed variants must differ", exposed_a != interior)
	t.equal("two palette materials are cached", Palette.cached_material_count(), 2)
	var beacon := Palette.make_tagged("emission_glass")
	t.check("beacon glass emits", beacon.emission_enabled)
	t.check("beacon glass emission is boosted", beacon.emission_energy_multiplier > 1.0)
	t.check("beacon glass is not weather-exposed", not bool(beacon.get_meta("palette_exposed")))

	var dry_color := exposed_a.albedo_color
	var dry_roughness := exposed_a.roughness
	var interior_color := interior.albedo_color
	var interior_roughness := interior.roughness
	Palette.set_wetness(1.0)
	t.check("wetness darkens exposed albedo", exposed_a.albedo_color.get_luminance() < dry_color.get_luminance())
	t.check("wetness smooths exposed roughness", exposed_a.roughness < dry_roughness)
	t.equal("wetness leaves interior albedo alone", interior.albedo_color, interior_color)
	t.check("wetness leaves interior roughness alone", is_equal_approx(interior.roughness, interior_roughness))

	Palette.set_wetness(0.0)
	t.equal("drying restores exposed albedo", exposed_a.albedo_color, dry_color)
	t.check("drying restores exposed roughness", is_equal_approx(exposed_a.roughness, dry_roughness))
	Palette.clear_cache()
	t.finish(self)
