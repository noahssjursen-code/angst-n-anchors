class_name WorldConfig
extends RefCounted

## Server/session world identity: size + archetype + seed handoff.
## Geography stays procedural Norway-inspired — never a real DEM.

const ARCHETYPE_PATH := "res://resources/data/world/norway_coast.json"
const PRESETS_PATH := "res://resources/data/world/world_size_presets.json"
const REFERENCE_SIZE_M := 40000.0
const MIN_SIZE_M := 10000.0
const MAX_SIZE_M := 120000.0
const MIN_RASTER := 129
const MAX_RASTER := 513

## Preset ids → world_size_m (loaded from JSON, with fallbacks).
const FALLBACK_PRESETS := {
	"small": 15000.0,
	"standard": 40000.0,
	"large": 100000.0,
}


static func validate_size_m(size_m: float) -> float:
	return clampf(size_m, MIN_SIZE_M, MAX_SIZE_M)


static func preset_size_m(preset_id: String) -> float:
	var presets := load_presets()
	var id := preset_id.strip_edges().to_lower()
	if presets.has(id):
		return validate_size_m(float(presets[id]))
	return validate_size_m(float(FALLBACK_PRESETS.get(id, REFERENCE_SIZE_M)))


static func load_presets() -> Dictionary:
	var out := FALLBACK_PRESETS.duplicate()
	if not FileAccess.file_exists(PRESETS_PATH):
		return out
	var file := FileAccess.open(PRESETS_PATH, FileAccess.READ)
	if file == null:
		return out
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var root := parsed as Dictionary
	for key in root.keys():
		out[str(key).to_lower()] = float(root[key])
	return out


static func recommend_raster_resolution(world_size_m: float) -> int:
	## ~156 m/cell at 40 km / 257. Cap for boot cost on huge maps.
	var size := validate_size_m(world_size_m)
	var target_cell := 156.25
	var res := int(round(size / target_cell)) + 1
	if res % 2 == 0:
		res += 1
	return clampi(res, MIN_RASTER, MAX_RASTER)


static func scale_factor(world_size_m: float) -> float:
	return validate_size_m(world_size_m) / REFERENCE_SIZE_M


## Load archetype JSON and apply world_size_m (+ optional raster override).
static func resolve(
		world_size_m: float = REFERENCE_SIZE_M,
		archetype_path: String = ARCHETYPE_PATH,
		raster_resolution: int = -1,
) -> Dictionary:
	var size := validate_size_m(world_size_m)
	var file := FileAccess.open(archetype_path, FileAccess.READ)
	## Both of these were bare `assert()`s, and both are load-bearing: the very
	## next line calls `file.get_as_text()` on a null FileAccess, and the line
	## after that calls `.duplicate(true)` on a null Dictionary cast. `assert` is
	## compiled out of release builds, so in a shipped game a missing or
	## malformed archetype was a null dereference during world boot with no
	## diagnostic at all — the one place the message inside the assert was
	## needed most is the one place it did not exist.
	##
	## The fallback is an empty archetype rather than an early return: every
	## reader below (`_scale_metres_in_place`, and the generator downstream)
	## already treats a missing section as "use my defaults", so an empty
	## dictionary still yields a generatable world of the requested size instead
	## of a crash — and the pushed error names the path that failed.
	var config := {}
	if file == null:
		push_error(
			"WorldConfig: cannot open archetype %s (%s) — falling back to an empty archetype" % [
				archetype_path, error_string(FileAccess.get_open_error()),
			]
		)
	else:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			config = (parsed as Dictionary).duplicate(true)
		else:
			push_error(
				"WorldConfig: archetype %s must be a JSON object, parsed as %s — falling back to an empty archetype" % [
					archetype_path, type_string(typeof(parsed)),
				]
			)
	config["world_size_m"] = size
	config["archetype_path"] = archetype_path
	var scale := scale_factor(size)
	_scale_metres_in_place(config, scale, size)
	var res := raster_resolution
	if res < MIN_RASTER:
		res = int(config.get("raster_resolution", recommend_raster_resolution(size)))
		## If archetype still has a fixed 257 for 40km, retarget for other sizes.
		if not is_equal_approx(size, REFERENCE_SIZE_M):
			res = recommend_raster_resolution(size)
	if res % 2 == 0:
		res += 1
	config["raster_resolution"] = clampi(res, MIN_RASTER, MAX_RASTER)
	return config


static func _scale_metres_in_place(config: Dictionary, scale: float, size_m: float) -> void:
	if is_equal_approx(scale, 1.0):
		return
	var half := size_m * 0.5
	var mainland: Dictionary = config.get("mainland", {}) as Dictionary
	if not mainland.is_empty():
		mainland["coast_x_m"] = float(mainland.get("coast_x_m", 6500.0)) * scale
		mainland["coast_amplitude_m"] = float(mainland.get("coast_amplitude_m", 2100.0)) * scale
		config["mainland"] = mainland
	var fjords: Dictionary = config.get("fjords", {}) as Dictionary
	if not fjords.is_empty():
		for key in [
			"trunk_width_min_m", "trunk_width_max_m",
			"branch_width_min_m", "branch_width_max_m",
			"inland_reach_min_m", "inland_reach_max_m",
			"root_spacing_m",
		]:
			if fjords.has(key):
				fjords[key] = float(fjords[key]) * scale
		config["fjords"] = fjords
	var arch: Dictionary = config.get("archipelago", {}) as Dictionary
	if not arch.is_empty():
		for key in ["belt_x_min_m", "belt_x_max_m", "radius_min_m", "radius_max_m"]:
			if arch.has(key):
				arch[key] = float(arch[key]) * scale
		## Keep archipelago inside map after scale.
		arch["belt_x_min_m"] = maxf(float(arch.get("belt_x_min_m", -half)), -half * 0.95)
		arch["belt_x_max_m"] = minf(float(arch.get("belt_x_max_m", half * 0.1)), half * 0.15)
		config["archipelago"] = arch
	var classification: Dictionary = config.get("classification", {}) as Dictionary
	if not classification.is_empty():
		if classification.has("fjord_influence_m"):
			classification["fjord_influence_m"] = float(classification["fjord_influence_m"]) * scale
		if classification.has("open_water_x_m"):
			classification["open_water_x_m"] = float(classification["open_water_x_m"]) * scale
		config["classification"] = classification
