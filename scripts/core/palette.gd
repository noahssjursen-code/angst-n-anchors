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

# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

## Return a ready-to-use StandardMaterial3D from a preset dict.
## Pass `double_sided: true` for thin shells visible from inside.
static func make(preset: Dictionary, double_sided: bool = false) -> StandardMaterial3D:
	return MeshBuilder.make_material(
		preset.get("color",    Color(0.5, 0.5, 0.5)),
		preset.get("roughness", 0.85),
		preset.get("metallic",  0.0),
		double_sided
	)
