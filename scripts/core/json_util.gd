@tool
class_name JsonUtil
extends RefCounted

## Shared JSON file loader. MeshTransformer, ModelAssembler, and various NPCs
## use this instead of duplicating FileAccess + JSON.parse. Centralised so the
## parse-error handling and "is file present" check live in one place.
##
## Parsed Dictionaries are cached by path and returned by reference — treat them
## as read-only. Callers that need to mutate must `duplicate(true)` first.

static var _cache: Dictionary = {}


## Load a JSON file and return its root Dictionary. Returns an empty Dictionary
## on any failure (missing file, parse error, root not a Dictionary), with
## a descriptive push_error so the caller can fail fast and the user can
## debug from the console.
static func load(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	if _cache.has(path):
		return _cache[path] as Dictionary

	if not FileAccess.file_exists(path):
		push_error("JsonUtil: file not found: " + path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("JsonUtil: could not open: " + path)
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		push_error("JsonUtil: parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("JsonUtil: root is not a Dictionary in " + path)
		return {}

	var dict := data as Dictionary
	_cache[path] = dict
	return dict


## Drop one path (or the whole cache) so the next load re-reads from disk.
static func clear_cache(path: String = "") -> void:
	if path.is_empty():
		_cache.clear()
	else:
		_cache.erase(path)
