class_name HullFormProfile
extends RefCounted

## Normalized low-poly hull-form presets. Width values are half-beam fractions;
## longitudinal values are fractions of LOA. HullStations turns these presets
## into the single station lattice consumed by visuals, collision, and physics.

const DEFAULT_ID := "workboat"

const PRESETS: Dictionary = {
	"container": {
		"bottom_width": 0.58,
		"chine_width": 0.78,
		"waterline_width": 0.88,
		"shoulder_width": 0.98,
		"chine_draft_fraction": 0.34,
		"shoulder_freeboard_fraction": 0.58,
		"underwater_bow_fraction": 0.20,
		"stern_taper_fraction": 0.08,
		"stern_underwater_width": 0.74,
		"bow_keel_rise": 0.18,
		"stern_keel_rise": 0.05,
	},
	"tanker": {
		"bottom_width": 0.48,
		"chine_width": 0.76,
		"waterline_width": 0.91,
		"shoulder_width": 0.99,
		"chine_draft_fraction": 0.38,
		"shoulder_freeboard_fraction": 0.54,
		"underwater_bow_fraction": 0.22,
		"stern_taper_fraction": 0.09,
		"stern_underwater_width": 0.72,
		"bow_keel_rise": 0.22,
		"stern_keel_rise": 0.07,
	},
	"lng": {
		"bottom_width": 0.50,
		"chine_width": 0.78,
		"waterline_width": 0.90,
		"shoulder_width": 0.99,
		"chine_draft_fraction": 0.38,
		"shoulder_freeboard_fraction": 0.50,
		"underwater_bow_fraction": 0.23,
		"stern_taper_fraction": 0.10,
		"stern_underwater_width": 0.70,
		"bow_keel_rise": 0.24,
		"stern_keel_rise": 0.08,
	},
	"workboat": {
		"bottom_width": 0.50,
		"chine_width": 0.74,
		"waterline_width": 0.87,
		"shoulder_width": 0.98,
		"chine_draft_fraction": 0.36,
		"shoulder_freeboard_fraction": 0.60,
		"underwater_bow_fraction": 0.24,
		"stern_taper_fraction": 0.07,
		"stern_underwater_width": 0.78,
		"bow_keel_rise": 0.24,
		"stern_keel_rise": 0.04,
	},
	"trawler": {
		"bottom_width": 0.18,
		"chine_width": 0.60,
		"waterline_width": 0.82,
		"shoulder_width": 0.96,
		"chine_draft_fraction": 0.42,
		"shoulder_freeboard_fraction": 0.62,
		"underwater_bow_fraction": 0.27,
		"stern_taper_fraction": 0.10,
		"stern_underwater_width": 0.66,
		"bow_keel_rise": 0.32,
		"stern_keel_rise": 0.10,
	},
	"catamaran_demihull": {
		"bottom_width": 0.58,
		"chine_width": 0.88,
		"waterline_width": 0.98,
		"shoulder_width": 1.0,
		"chine_draft_fraction": 0.40,
		"shoulder_freeboard_fraction": 0.62,
		"underwater_bow_fraction": 0.28,
		"stern_taper_fraction": 0.10,
		"stern_underwater_width": 0.62,
		"bow_keel_rise": 0.30,
		"stern_keel_rise": 0.10,
	},
}


static func resolve(profile_id: String, overrides: Dictionary = {}) -> Dictionary:
	var id := profile_id.strip_edges().to_lower()
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
