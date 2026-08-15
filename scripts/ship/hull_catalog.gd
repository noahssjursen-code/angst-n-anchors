class_name HullCatalog
extends RefCounted

## Reusable data-driven hull components for the shipyard editor.
## Edit resources/data/vessels/hulls/catalog.json — `loa_m` / `beam_m` / `depth_m`
## are REAL METRES. One world unit is one metre; `hull_150x32` is a 150 m ship.
##
## This line read *"dimensions are in-world metres (2× real)"*. That is the note
## CONVENTIONS.md §3a says was corrected on 2026-08-09 — the correction landed in
## the JSON's own `notes` field and in `HullRegistry`, and never here. Two
## readers were talked into a double-scale world by this sentence.
##
## `_normalize` still OVERWRITES the authored `display` with
## `ShipClass.format_display_dimensions(loa_m, beam_m)`, which multiplies by
## `ShipClass.DISPLAY_METRE_SCALE` = 0.5. Measured 2026-08-15: hull_150x32 is
## labelled "75.0 × 16.0 m" and hull_70x18 "35.0 × 9.0 m" in the player-facing
## catalog. So the DATA is single-scale and the LABEL is still half. Which of the
## two is wrong is an owner decision (see CONVENTIONS.md §3a) — do not silently
## "fix" either side.

const CATALOG_PATH := "res://resources/data/vessels/hulls/catalog.json"

static var _entries: Dictionary = {}
static var _ready := false


static func reload() -> void:
	_entries.clear()
	_ready = false
	ensure_loaded()


static func ensure_loaded() -> void:
	if _ready:
		return
	_ready = true
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("HullCatalog: cannot open %s" % CATALOG_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("HullCatalog: invalid catalog JSON")
		return
	var hulls = (parsed as Dictionary).get("hulls", [])
	if hulls is Array:
		for raw in hulls as Array:
			if raw is Dictionary:
				var entry := _normalize(raw as Dictionary)
				var id := str(entry.get("id", ""))
				if not id.is_empty():
					_entries[id] = entry


static func has_id(hull_id: String) -> bool:
	ensure_loaded()
	return _entries.has(hull_id.strip_edges())


static func get_by_id(hull_id: String) -> Dictionary:
	ensure_loaded()
	var id := hull_id.strip_edges()
	if _entries.has(id):
		return (_entries[id] as Dictionary).duplicate(true)
	return {}


static func all_ids() -> PackedStringArray:
	ensure_loaded()
	var result := PackedStringArray()
	for key in _entries.keys():
		result.append(str(key))
	result.sort()
	return result


static func catalog_entries() -> Array[Dictionary]:
	ensure_loaded()
	var result: Array[Dictionary] = []
	for id in all_ids():
		result.append(get_by_id(id))
	return result


static func _normalize(raw: Dictionary) -> Dictionary:
	var loa_m := float(raw.get("loa_m", 12.0))
	var beam_m := float(raw.get("beam_m", 6.0))
	var depth_m := float(raw.get("depth_m", 3.0))
	var draft_m := float(raw.get("draft_m", depth_m * 0.5))
	var shape := str(raw.get("shape", "pointed"))
	## Pointed = always 45° in plan (run = half beam). JSON bow_taper_m is ignored.
	var bow_taper_m := 0.0
	if shape == "pointed":
		bow_taper_m = beam_m * 0.5
	var displacement_t := float(raw.get("displacement_t", loa_m * beam_m * draft_m * 0.52))
	var entry := raw.duplicate(true)
	entry["id"] = str(raw.get("id", ""))
	entry["shape"] = shape
	entry["loa_m"] = loa_m
	entry["beam_m"] = beam_m
	entry["depth_m"] = depth_m
	entry["draft_m"] = draft_m
	entry["bow_taper_m"] = bow_taper_m
	entry["displacement_t"] = displacement_t
	var form_id := str(raw.get("form", HullFormProfile.DEFAULT_ID))
	entry["form"] = form_id
	var form_overrides: Dictionary = {}
	var raw_overrides = raw.get("form_overrides", {})
	if raw_overrides is Dictionary:
		form_overrides = raw_overrides as Dictionary
	entry["hull_form"] = HullFormProfile.resolve(form_id, form_overrides)
	var raw_livery = raw.get("livery", {})
	entry["livery"] = HullLivery.to_dict(
		raw_livery as Dictionary if raw_livery is Dictionary else {}
	)
	entry["scene_path"] = str(raw.get("scene_path", ""))
	entry["ship_class"] = _parse_ship_class(str(raw.get("ship_class", "coastal_trader")))
	## Keep source dimensions for physics/grid construction; normalize only the
	## player-facing catalog label.
	entry["display"] = ShipClass.format_display_dimensions(loa_m, beam_m)
	if shape == "catamaran":
		entry["display"] += " · catamaran"
	return entry


static func _parse_ship_class(name: String) -> int:
	match name.strip_edges().to_lower():
		"launch":
			return ShipClass.Type.LAUNCH
		"short_sea_coaster":
			return ShipClass.Type.SHORT_SEA_COASTER
		"handysize_feeder":
			return ShipClass.Type.HANDYSIZE_FEEDER
		"deep_sea_freighter":
			return ShipClass.Type.DEEP_SEA_FREIGHTER
		_:
			return ShipClass.Type.COASTAL_TRADER
