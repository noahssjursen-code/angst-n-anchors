class_name DialogueScript
extends RefCounted

## Dialogue data loading and action registration. Presentation was removed.

const RESERVED_ACTION_CLOSE := "close"

var _title:    String = ""
var _entry:    String = ""
var _screens:  Dictionary = {}   # id (String) → Dictionary (the screen)
var _actions:  Dictionary = {}   # name (String) → Callable
var _conditions: Dictionary = {} # name (String) → bool


# ── Loading ───────────────────────────────────────────────────────────────────

## Returns true on success, false on parse / IO error.
func load_from_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("DialogueScript: file not found: %s" % path)
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DialogueScript: could not open %s" % path)
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DialogueScript: %s is not a JSON object" % path)
		return false
	return _load_from_dict(parsed)


func _load_from_dict(data: Dictionary) -> bool:
	var document := DialogueDocument.normalize(data)
	_title = str(document.get("title", ""))
	_entry = str(document.get("entry", "main"))
	_screens = document.get("screens", {})
	if not (_screens is Dictionary) or _screens.is_empty():
		push_error("DialogueScript: 'screens' missing or empty")
		return false
	if not _screens.has(_entry):
		push_error("DialogueScript: entry screen '%s' not in screens" % _entry)
		return false
	return true


func get_title() -> String:
	return _title


func get_entry() -> String:
	return _entry


# ── NPC hooks ─────────────────────────────────────────────────────────────────

## Register a callback for any option that has `"action": "<name>"` in the JSON.
## Register before executing dialogue actions.
func register_action(name: String, callback: Callable) -> void:
	_actions[name] = callback


## Set the value of a condition flag for options that use `"enabled_if"`. NPCs
## update these when the interaction context changes.
func set_condition(name: String, value: bool) -> void:
	_conditions[name] = value
