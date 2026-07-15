class_name PortModuleCatalog
extends RefCounted

## Loads data-only socketed port module templates.

const CATALOG_PATH := "res://resources/data/ports/modules/catalog.json"
const FORMAT_VERSION := 1

static var _definitions: Dictionary = {}
static var _scaled: Dictionary = {}
static var _loaded := false


static func clear_cache() -> void:
	_definitions.clear()
	_scaled.clear()
	_loaded = false


static func definition(module_id: String) -> PortModuleDefinition:
	_ensure_loaded()
	return _definitions.get(module_id) as PortModuleDefinition


## Size-aware clone. Use this for placement, overlap, and visualization.
static func definition_for_size(module_id: String, size: int) -> PortModuleDefinition:
	var n := PortSizing.normalized_size(size)
	var cache_key := "%s@%d" % [module_id, n]
	if _scaled.has(cache_key):
		return _scaled[cache_key] as PortModuleDefinition
	var base := definition(module_id)
	if base == null:
		return null
	var scaled := base.scaled_for_size(n)
	_scaled[cache_key] = scaled
	return scaled


static func module_ids() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for key in _definitions.keys():
		out.append(str(key))
	out.sort()
	return out


static func candidates_for_output(output_type: String) -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for module_id in module_ids():
		var item := definition(module_id)
		if item != null and not item.input_for(output_type).is_empty():
			out.append(module_id)
	return out


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_definitions.clear()
	_scaled.clear()
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("PortModuleCatalog: missing %s" % CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("PortModuleCatalog: invalid JSON at %s" % CATALOG_PATH)
		return
	var payload := parsed as Dictionary
	if int(payload.get("format_version", -1)) != FORMAT_VERSION:
		push_error("PortModuleCatalog: unsupported format version")
		return
	for raw in payload.get("modules", []) as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var item := PortModuleDefinition.from_dict(raw as Dictionary)
		if not item.is_valid():
			push_error("PortModuleCatalog: invalid module '%s'" % item.id)
			continue
		if _definitions.has(item.id):
			push_error("PortModuleCatalog: duplicate module '%s'" % item.id)
			continue
		_definitions[item.id] = item
