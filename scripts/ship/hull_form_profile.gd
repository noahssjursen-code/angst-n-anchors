class_name HullFormProfile
extends RefCounted

## Normalized low-poly hull-form presets. Width values are half-beam fractions;
## longitudinal values are fractions of LOA. HullStations turns these presets
## into the single station lattice consumed by visuals, collision, and physics.
##
## `shoulder_width` is the RUBBING STRAKE and is deliberately greater than 1.0 — the
## strake stands proud of the deck edge, so the topside flares out up to it and tumbles
## home above it. Two normals, one line. Held at 0.96–1.0 it sat INBOARD of the deck
## edge, where flare below and flare above give the same normal and no line is drawn:
## measured on hull_15x5 at 0.96 and again at 0.88, two renders, no visible difference.
## `shoulder_freeboard_fraction` places it low enough in the freeboard that the sheer
## curve can lift it at the ends without hitting `HullStations.STRAKE_MIN_CLEAR_FRACTION`.

const DEFAULT_ID := "fine_entry"

const PRESETS: Dictionary = {
	"full_bodied": {
		"bottom_width": 0.58,
		"chine_width": 0.78,
		"waterline_width": 0.88,
		"shoulder_width": 1.02,
		"chine_draft_fraction": 0.34,
		"shoulder_freeboard_fraction": 0.44,
		"underwater_bow_fraction": 0.20,
		"stern_taper_fraction": 0.08,
		"stern_underwater_width": 0.74,
		"bow_keel_rise": 0.18,
		"stern_keel_rise": 0.05,
	},
	"rounded_full": {
		"bottom_width": 0.48,
		"chine_width": 0.76,
		"waterline_width": 0.91,
		"shoulder_width": 1.02,
		"chine_draft_fraction": 0.38,
		"shoulder_freeboard_fraction": 0.44,
		"underwater_bow_fraction": 0.22,
		"stern_taper_fraction": 0.09,
		"stern_underwater_width": 0.72,
		"bow_keel_rise": 0.22,
		"stern_keel_rise": 0.07,
	},
	"high_volume": {
		"bottom_width": 0.50,
		"chine_width": 0.78,
		"waterline_width": 0.90,
		"shoulder_width": 1.02,
		"chine_draft_fraction": 0.38,
		"shoulder_freeboard_fraction": 0.44,
		"underwater_bow_fraction": 0.23,
		"stern_taper_fraction": 0.10,
		"stern_underwater_width": 0.70,
		"bow_keel_rise": 0.24,
		"stern_keel_rise": 0.08,
	},
	"fine_entry": {
		"bottom_width": 0.18,
		"chine_width": 0.60,
		"waterline_width": 0.82,
		"shoulder_width": 1.03,
		"chine_draft_fraction": 0.42,
		"shoulder_freeboard_fraction": 0.36,
		"underwater_bow_fraction": 0.27,
		"stern_taper_fraction": 0.10,
		"stern_underwater_width": 0.66,
		"bow_keel_rise": 0.32,
		"stern_keel_rise": 0.10,
	},
	## Small open working boat — the ~15 m Norwegian sjark hull_15x5 is sized on.
	##
	## It exists because `hull_15x5` and `hull_28x10` were both `fine_entry`, and a
	## preset is a normalised SHAPE: two hulls that share one produce the same drawing
	## at two sizes, which is exactly what the fleet was called out for. Every value
	## below differs from `fine_entry` in the direction a boat gets when it is small and
	## works close inshore: a deeper forefoot cut-up and a harder-raked stem, a sharper
	## bottom, a heavier rubbing band, and a narrow transom.
	"workboat_small": {
		"bottom_width": 0.12,
		"chine_width": 0.52,
		"waterline_width": 0.78,
		"shoulder_width": 1.07,
		"chine_draft_fraction": 0.50,
		"shoulder_freeboard_fraction": 0.30,
		"underwater_bow_fraction": 0.30,
		"stern_taper_fraction": 0.14,
		"stern_underwater_width": 0.54,
		"bow_keel_rise": 0.40,
		"stern_keel_rise": 0.14,
	},
	"catamaran_demihull": {
		"bottom_width": 0.58,
		"chine_width": 0.88,
		"waterline_width": 0.98,
		"shoulder_width": 1.02,
		"chine_draft_fraction": 0.40,
		"shoulder_freeboard_fraction": 0.40,
		"underwater_bow_fraction": 0.28,
		"stern_taper_fraction": 0.10,
		"stern_underwater_width": 0.62,
		"bow_keel_rise": 0.30,
		"stern_keel_rise": 0.10,
	},
}

const LEGACY_ALIASES := {
	"container": "full_bodied",
	"tanker": "rounded_full",
	"lng": "high_volume",
	"trawler": "fine_entry",
}


static func resolve(profile_id: String, overrides: Dictionary = {}) -> Dictionary:
	var id := profile_id.strip_edges().to_lower()
	id = str(LEGACY_ALIASES.get(id, id))
	if not PRESETS.has(id):
		id = DEFAULT_ID
	var result := (PRESETS[id] as Dictionary).duplicate(true)
	for key in overrides.keys():
		result[key] = overrides[key]
	result["id"] = id
	return result


static func known_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for key in PRESETS.keys():
		result.append(str(key))
	result.sort()
	return result
