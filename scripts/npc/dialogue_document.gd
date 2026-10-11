class_name DialogueDocument
extends RefCounted

## Versioned dialogue document. DialogueScript still plays a tree.
## This record is the saved shape for harbour talk, tablet messages, and NPC lines.

const SCHEMA_VERSION := 1


static func normalize(raw: Dictionary) -> Dictionary:
	var document := raw.duplicate(true)
	document["schema_version"] = SCHEMA_VERSION
	document["id"] = str(document.get("id", ""))
	document["title"] = str(document.get("title", ""))
	document["speaker_role"] = str(document.get("speaker_role", ""))
	document["entry"] = str(document.get("entry", "main"))
	var screens_raw: Variant = document.get("screens", {})
	var screens := {}
	if typeof(screens_raw) == TYPE_DICTIONARY:
		for screen_id in (screens_raw as Dictionary).keys():
			var screen_raw: Variant = (screens_raw as Dictionary)[screen_id]
			if typeof(screen_raw) != TYPE_DICTIONARY:
				continue
			var screen := (screen_raw as Dictionary).duplicate(true)
			screen["quote"] = str(screen.get("quote", ""))
			var options: Array = []
			var options_raw: Variant = screen.get("options", [])
			if typeof(options_raw) == TYPE_ARRAY:
				for option_raw in options_raw as Array:
					if typeof(option_raw) != TYPE_DICTIONARY:
						continue
					var option := (option_raw as Dictionary).duplicate(true)
					option["label"] = str(option.get("label", ""))
					if option.has("goto"):
						option["goto"] = str(option.get("goto", ""))
					if option.has("action"):
						option["action"] = str(option.get("action", ""))
					options.append(option)
			screen["options"] = options
			screens[str(screen_id)] = screen
	document["screens"] = screens
	return document


static func valid(document: Dictionary) -> bool:
	if str(document.get("title", "")).is_empty():
		return false
	var screens: Variant = document.get("screens", {})
	if typeof(screens) != TYPE_DICTIONARY or (screens as Dictionary).is_empty():
		return false
	return (screens as Dictionary).has(str(document.get("entry", "")))
