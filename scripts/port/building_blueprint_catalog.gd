class_name BuildingBlueprintCatalog
extends RefCounted

const BLUEPRINT_DIR := "res://resources/data/buildings/"


static func all() -> Array[BuildingLayout]:
	var layouts: Array[BuildingLayout] = []
	for blueprint_id in ids():
		var layout := by_id(blueprint_id)
		if layout != null:
			layouts.append(layout)
	return layouts


static func ids() -> Array[String]:
	var out: Array[String] = []
	for filename in DirAccess.get_files_at(BLUEPRINT_DIR):
		if filename.get_extension().to_lower() != "json":
			continue
		out.append(filename.get_basename())
	out.sort()
	return out


static func path_for(blueprint_id: String) -> String:
	return BLUEPRINT_DIR + blueprint_id + ".json"


static func by_id(blueprint_id: String) -> BuildingLayout:
	var trimmed := blueprint_id.strip_edges()
	if trimmed.is_empty():
		return null
	var direct := load_path(path_for(trimmed))
	if direct != null:
		return direct
	# Legacy: internal JSON id may differ from filename.
	for filename in DirAccess.get_files_at(BLUEPRINT_DIR):
		if filename.get_extension().to_lower() != "json":
			continue
		var layout := load_path(BLUEPRINT_DIR + filename)
		if layout != null and layout.blueprint_id == trimmed:
			return layout
	return null


static func load_path(path: String) -> BuildingLayout:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BuildingBlueprintCatalog: invalid JSON object at %s" % path)
		return null
	var layout := BuildingLayout.from_dict(parsed as Dictionary)
	# File name is the public ID — no typed identifiers.
	layout.blueprint_id = path.get_file().get_basename()
	var report := BuildingRules.validate(layout)
	if not bool(report.get("ok", false)):
		push_error(
			"BuildingBlueprintCatalog: invalid blueprint %s: %s"
			% [path, ", ".join(report.get("errors", PackedStringArray()))]
		)
		return null
	return layout


static func build(blueprint_id: String, collision_enabled: bool = true) -> Node3D:
	var layout := by_id(blueprint_id)
	return BuildingFitout.build(layout, collision_enabled) if layout != null else null


## First blueprint matching apron pad role + template size (exact), else role only.
static func find_for_pad(role_id: String, pad_template_id: String) -> BuildingLayout:
	var wanted_role := role_id.strip_edges()
	var wanted_pad := pad_template_id.strip_edges()
	if wanted_role.is_empty():
		return null
	var role_only: BuildingLayout = null
	for blueprint_id in ids():
		var layout := by_id(blueprint_id)
		if layout == null:
			continue
		if layout.role != wanted_role:
			continue
		if not wanted_pad.is_empty() and layout.pad_template_id == wanted_pad:
			return layout
		if role_only == null:
			role_only = layout
	return role_only
