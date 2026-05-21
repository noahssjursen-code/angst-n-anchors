class_name JsonUtil
extends RefCounted

## Shared JSON file loader. Three classes had near-identical _load_json
## implementations (ShipBuilder, MeshTransformer, ModelAssembler) plus a
## handful of inline JSON.parse blocks scattered across NPCs. Centralised
## so the parse-error handling and "is file present" check live in one place.

## Load a JSON file and return its root Dictionary. Returns an empty Dictionary
## on any failure (missing file, parse error, root not a Dictionary), with
## a descriptive push_error so the caller can fail fast and the user can
## debug from the console.
static func load(path: String) -> Dictionary:
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
	return data as Dictionary
