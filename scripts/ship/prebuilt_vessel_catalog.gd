class_name PrebuiltVesselCatalog
extends RefCounted

## Source-controlled, ready-built vessel configurations authored by the
## ShipyardBrickEditor engine tool. Shipwright sells only certified presets;
## drafts remain loadable in the authoring app so incomplete ships stay editable.

const PREBUILT_DIR := "res://resources/data/vessels/prebuilt"
const FORMAT_VERSION := 2


static func catalog_entries(include_drafts: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(PREBUILT_DIR)
	if dir == null:
		return out
	var files := PackedStringArray()
	dir.list_dir_begin()
	var filename := dir.get_next()
	while not filename.is_empty():
		if not dir.current_is_dir() and filename.to_lower().ends_with(".json"):
			files.append(filename)
		filename = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for file in files:
		var entry := _load_entry("%s/%s" % [PREBUILT_DIR, file])
		if entry.is_empty():
			continue
		if not include_drafts and bool(entry.get("is_draft", false)):
			continue
		out.append(entry)
	return out


## Official yard stock — compliance-passed, non-draft presets only.
static func for_sale_entries() -> Array[Dictionary]:
	return catalog_entries(false)


static func _load_entry(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PrebuiltVesselCatalog: invalid JSON: %s" % path)
		return {}
	var preset := parsed as Dictionary
	if int(preset.get("format_version", 0)) != FORMAT_VERSION:
		push_warning("PrebuiltVesselCatalog: unsupported format: %s" % path)
		return {}
	var preset_id := str(preset.get("id", "")).strip_edges()
	var hull_id := str(preset.get("hull_id", "")).strip_edges()
	var registration_id := str(preset.get("registration_id", "")).strip_edges()
	var layout_raw: Variant = preset.get("brick_layout", null)
	if (
		preset_id.is_empty()
		or hull_id.is_empty()
		or registration_id.is_empty()
		or typeof(layout_raw) != TYPE_DICTIONARY
	):
		push_warning("PrebuiltVesselCatalog: incomplete preset: %s" % path)
		return {}
	if HullRegistry.resolve_network_hull_id(hull_id) != hull_id:
		push_warning("PrebuiltVesselCatalog: unknown hull '%s' in %s" % [hull_id, path])
		return {}
	var layout := layout_raw as Dictionary
	if str(layout.get("hull_id", hull_id)) != hull_id:
		push_warning("PrebuiltVesselCatalog: hull/layout mismatch: %s" % path)
		return {}
	var brick_layout := BrickLayout.from_dict(layout)
	var outfit := VesselCompliance.validate(
		brick_layout, hull_id, registration_id, HullRegistry.make_grid(hull_id)
	)
	var compliance_ok := bool(outfit.get("ok", false))
	var marked_draft := bool(preset.get("draft", false))
	var is_draft := marked_draft or not compliance_ok
	if is_draft:
		var errors: PackedStringArray = outfit.get("errors", PackedStringArray())
		push_warning(
			"PrebuiltVesselCatalog: draft preset %s — %s"
			% [path, " · ".join(errors) if not errors.is_empty() else "marked draft"]
		)

	var entry := HullRegistry.get_by_id(hull_id)
	var vessel_name := str(preset.get("name", entry.get("display", "Vessel"))).strip_edges()
	var hull_display := str(entry.get("display", "Hull"))
	entry["display"] = vessel_name
	entry["hull_display"] = hull_display
	entry["hull_id"] = hull_id
	entry["is_prebuilt"] = true
	entry["prebuilt_id"] = preset_id
	entry["prebuilt_name"] = vessel_name
	entry["prebuilt_layout"] = layout.duplicate(true)
	entry["registration_id"] = registration_id
	entry["registration_display"] = VesselRegistrationCatalog.display_name(registration_id)
	entry["prebuilt_path"] = path
	entry["compliance_ok"] = compliance_ok
	entry["is_draft"] = is_draft
	entry["compliance_errors"] = outfit.get("errors", PackedStringArray())
	## Catalog hulls have no .tscn — keep empty scene_path and spawn by hull_id.
	var scene_path := str(preset.get("scene_path", entry.get("scene_path", ""))).strip_edges()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		entry["scene_path"] = ""
	else:
		entry["scene_path"] = scene_path
	if preset.has("price_marks"):
		entry["price_marks"] = maxi(int(preset.get("price_marks", 0)), 0)
	entry["shaft_power_kw"] = maxf(
		float(preset.get(
			"shaft_power_kw",
			entry.get("default_shaft_power_kw", 1.0)
		)),
		1.0
	)
	return entry
