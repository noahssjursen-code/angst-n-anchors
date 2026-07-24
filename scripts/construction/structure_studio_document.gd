class_name StructureStudioDocument
extends RefCounted

## Pure document helpers for Structure Studio persistence paths / naming.
## Kept free of Node dependencies for headless tests.


const STRUCTURES_DIR := "res://resources/data/structures"


static func sanitize_name(plan_name: String) -> String:
	return plan_name.strip_edges().to_snake_case()


static func path_for_name(plan_name: String) -> String:
	var trimmed := sanitize_name(plan_name)
	if trimmed.is_empty():
		return ""
	return "%s/%s.json" % [STRUCTURES_DIR, trimmed]


static func list_plan_paths(dir_path := STRUCTURES_DIR) -> PackedStringArray:
	var names: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return PackedStringArray()
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		if file_name == "item_catalog.json":
			continue
		names.append(file_name)
	names.sort()
	var out := PackedStringArray()
	for file_name in names:
		out.append("%s/%s" % [dir_path, file_name])
	return out


static func is_demo_path(path: String) -> bool:
	return path.get_file().begins_with("demo_")
