class_name Palette
extends RefCounted

## Central material palette for Angst 'n Anchors.
##
## Every in-world surface type lives here as a named preset.
## Use Palette.make(SURFACE_NAME) to get a ready StandardMaterial3D,
## or read the dict constants directly if you need just color/roughness/metallic.
##
## Colours are sRGB linear (Godot Color). The goal is a coherent, slightly
## desaturated industrial maritime palette — not toy-bright, not photorealistic.

# ---------------------------------------------------------------------------
# Surface presets — [color, roughness, metallic]
# ---------------------------------------------------------------------------

## Ship hull sides — matte black anti-fouling paint.
const HULL_PAINT := {
	color    = Color(0.10, 0.10, 0.11),
	roughness = 0.82,
	metallic  = 0.0,
}

## Ship deck / working surfaces — non-slip grey.
const DECK_GREY := {
	color    = Color(0.30, 0.30, 0.32),
	roughness = 0.88,
	metallic  = 0.04,
}

## Painted steel (railings, bollards, cleats) — charcoal with a satin sheen.
const PAINTED_STEEL := {
	color    = Color(0.18, 0.18, 0.20),
	roughness = 0.62,
	metallic  = 0.35,
}

## Bare / galvanised steel — light grey, moderate sheen.
const BARE_STEEL := {
	color    = Color(0.50, 0.50, 0.54),
	roughness = 0.45,
	metallic  = 0.75,
}

## White superstructure paint — bridge, deckhouse. Off-white to avoid blow-out.
const WHITE_PAINT := {
	color    = Color(0.74, 0.74, 0.76),
	roughness = 0.72,
	metallic  = 0.0,
}

## Bridge / porthole glass — dark tinted, low roughness, non-metallic.
const GLASS_TINTED := {
	color    = Color(0.08, 0.16, 0.24),
	roughness = 0.08,
	metallic  = 0.0,
}

## Polished metal trim (antennas, radar).
const POLISHED_METAL := {
	color    = Color(0.70, 0.70, 0.72),
	roughness = 0.28,
	metallic  = 0.88,
}

## Exhaust stack — weathered, slightly warm dark grey.
const EXHAUST_STEEL := {
	color    = Color(0.18, 0.17, 0.16),
	roughness = 0.80,
	metallic  = 0.20,
}

## Concrete — weathered, high roughness, no metallic.
const CONCRETE := {
	color    = Color(0.62, 0.61, 0.58),
	roughness = 0.90,
	metallic  = 0.0,
}

## Concrete — darker / shadow underside (piers, pillars).
const CONCRETE_DARK := {
	color    = Color(0.42, 0.41, 0.39),
	roughness = 0.92,
	metallic  = 0.0,
}

## Sandy ground.
const SAND := {
	color    = Color(0.80, 0.72, 0.56),
	roughness = 0.92,
	metallic  = 0.0,
}

## Timber / wood (crates, posts).
const TIMBER := {
	color    = Color(0.50, 0.38, 0.24),
	roughness = 0.88,
	metallic  = 0.0,
}

## Timber — lighter planks / outer frame.
const TIMBER_LIGHT := {
	color    = Color(0.60, 0.48, 0.32),
	roughness = 0.82,
	metallic  = 0.0,
}

## Rope / natural fibre.
const ROPE := {
	color    = Color(0.58, 0.46, 0.28),
	roughness = 0.94,
	metallic  = 0.0,
}

## Corrugated metal / warehouse cladding — pale, slightly warm.
const CLADDING := {
	color    = Color(0.68, 0.68, 0.70),
	roughness = 0.78,
	metallic  = 0.10,
}

## Warehouse dark steel frame.
const STEEL_FRAME := {
	color    = Color(0.20, 0.20, 0.22),
	roughness = 0.55,
	metallic  = 0.60,
}

## Hull keel / anti-corrosion red (below waterline).
const KEEL_RED := {
	color    = Color(0.48, 0.08, 0.06),
	roughness = 0.84,
	metallic  = 0.0,
}

const MATERIAL_TAGS := {
	"weathered_wood": TIMBER,
	"dark_wood": {color = Color(0.35, 0.25, 0.15), roughness = 1.0, metallic = 0.0},
	"aged_wood_plank": {color = Color(0.38, 0.28, 0.20), roughness = 0.85, metallic = 0.0},
	"structured_timber": TIMBER_LIGHT,
	"polished_wood": {color = Color(0.40, 0.25, 0.15), roughness = 0.30, metallic = 0.0},
	"teak_wood": {color = Color(0.35, 0.20, 0.12), roughness = 0.30, metallic = 0.0},
	"weathered_iron": {color = Color(0.15, 0.16, 0.18), roughness = 0.78, metallic = 0.65},
	"forged_iron": {color = Color(0.20, 0.20, 0.20), roughness = 0.40, metallic = 0.80},
	"railing_steel": PAINTED_STEEL,
	"polished_chrome": {color = Color(0.80, 0.80, 0.85), roughness = 0.10, metallic = 1.0},
	"dark_steel": STEEL_FRAME,
	"hull_paint_black": HULL_PAINT,
	"keel_anti_fouling": KEEL_RED,
	"superstructure_paint": WHITE_PAINT,
	"deck_steel": DECK_GREY,
	"concrete": CONCRETE,
	"concrete_dark": CONCRETE_DARK,
	"concrete_painted": {color = Color(0.90, 0.90, 0.90), roughness = 0.40, metallic = 0.10},
	"steel_frame": STEEL_FRAME,
	"cladding": CLADDING,
	"roofing_panels": {color = Color(0.24, 0.25, 0.27), roughness = 0.84, metallic = 0.08},
	"reinforced_glass": {color = Color(0.40, 0.60, 0.70, 0.72), roughness = 0.10, metallic = 0.0},
	"emission_glass": {
		color = Color(1.0, 0.30, 0.10), roughness = 0.10, metallic = 0.0,
		emission = Color(1.0, 0.18, 0.04), emission_energy = 2.0,
	},
	"weathered_granite": {color = Color(0.32, 0.34, 0.38), roughness = 0.85, metallic = 0.10},
	"mossy_turf": {color = Color(0.18, 0.28, 0.15), roughness = 0.95, metallic = 0.0},
	"cold_sand": {color = Color(0.55, 0.52, 0.48), roughness = 1.0, metallic = 0.0},
	"skin": {color = Color(0.72, 0.55, 0.40), roughness = 0.60, metallic = 0.0},
	"rough_cloth": {color = Color(0.18, 0.20, 0.30), roughness = 0.90, metallic = 0.0},
	"worn_trousers": {color = Color(0.18, 0.18, 0.20), roughness = 0.88, metallic = 0.0},
	"face_ink": {color = Color(0.05, 0.04, 0.04), roughness = 0.80, metallic = 0.0},
	"fuel_tank_steel": {color = Color(0.42, 0.08, 0.06), roughness = 0.72, metallic = 0.35},
	"industrial_yellow": {color = Color(0.78, 0.66, 0.08), roughness = 0.68, metallic = 0.08},
	"safety_stripe": {color = Color(0.95, 0.75, 0.05), roughness = 0.65, metallic = 0.05},
	"iron_pipe": {color = Color(0.18, 0.18, 0.20), roughness = 0.62, metallic = 0.55},
}

static var _material_cache: Dictionary = {}
static var _wetness := 0.0

# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

## Return a ready-to-use StandardMaterial3D from a preset dict.
## Pass `double_sided: true` for thin shells visible from inside.
static func make(preset: Dictionary, double_sided: bool = false, exposed: bool = true) -> StandardMaterial3D:
	var color: Color = preset.get("color", Color(0.5, 0.5, 0.5))
	var roughness := float(preset.get("roughness", 0.85))
	var metallic := float(preset.get("metallic", 0.0))
	var emission: Color = preset.get("emission", Color.BLACK)
	var emission_energy := float(preset.get("emission_energy", 0.0))
	var is_emissive := emission_energy > 0.0
	var actual_exposed := exposed and not is_emissive
	var key := "%s|%.4f|%.4f|%s|%.3f|%s|%s" % [
		color.to_html(true), roughness, metallic, emission.to_html(true),
		emission_energy, double_sided, actual_exposed,
	]
	if _material_cache.has(key):
		return _material_cache[key] as StandardMaterial3D
	var material := MeshBuilder.make_material(color, roughness, metallic, double_sided)
	if is_emissive:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	material.set_meta("palette_base_color", color)
	material.set_meta("palette_base_roughness", roughness)
	material.set_meta("palette_exposed", actual_exposed)
	_material_cache[key] = material
	_apply_wetness_to_material(material)
	return material


static func preset_for_tag(tag: String) -> Dictionary:
	return (MATERIAL_TAGS.get(tag.to_lower(), {}) as Dictionary).duplicate()


static func has_tag(tag: String) -> bool:
	return MATERIAL_TAGS.has(tag.to_lower())


static func make_tagged(tag: String, fallback: Dictionary = {}, double_sided: bool = false, exposed: bool = true) -> StandardMaterial3D:
	var preset := preset_for_tag(tag)
	if preset.is_empty():
		preset = fallback
	return make(preset, double_sided, exposed)


static func set_wetness(amount: float) -> void:
	var next := clampf(amount, 0.0, 1.0)
	if is_equal_approx(next, _wetness):
		return
	_wetness = next
	for value in _material_cache.values():
		_apply_wetness_to_material(value as StandardMaterial3D)


static func clear_cache() -> void:
	_material_cache.clear()


static func cached_material_count() -> int:
	return _material_cache.size()


static func _apply_wetness_to_material(material: StandardMaterial3D) -> void:
	if material == null or not bool(material.get_meta("palette_exposed", false)):
		return
	var base_color: Color = material.get_meta("palette_base_color", material.albedo_color)
	var base_roughness := float(material.get_meta("palette_base_roughness", material.roughness))
	material.albedo_color = base_color.darkened(_wetness * 0.18)
	material.roughness = lerpf(base_roughness, maxf(0.18, base_roughness * 0.48), _wetness)
