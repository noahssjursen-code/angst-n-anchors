class_name VesselRegistrationCatalog
extends RefCounted

## Source-controlled legal code for declared vessel registrations.

const CATALOG_PATH := "res://resources/data/vessels/registrations/catalog.json"
const FORMAT_VERSION := 1

static var _cache: Dictionary = {}


static func reload() -> void:
	_cache.clear()


static func raw_catalog() -> Dictionary:
	if not _cache.is_empty():
		return _cache.duplicate(true)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("VesselRegistrationCatalog: invalid JSON")
		return {}
	var catalog := parsed as Dictionary
	var errors := validate_catalog(catalog)
	if not errors.is_empty():
		push_error("VesselRegistrationCatalog: " + " · ".join(errors))
		return {}
	_cache = catalog.duplicate(true)
	return _cache.duplicate(true)


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in registrations():
		out.append(str(entry.get("id", "")))
	return out


static func registrations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = raw_catalog().get("registrations", [])
	if raw is Array:
		for item in raw as Array:
			if item is Dictionary:
				out.append((item as Dictionary).duplicate(true))
	return out


static func has(registration_id: String) -> bool:
	return not get_registration(registration_id).is_empty()


static func get_registration(registration_id: String) -> Dictionary:
	var target := registration_id.strip_edges()
	for entry in registrations():
		if str(entry.get("id", "")) == target:
			return entry
	return {}


static func resolved_registration(registration_id: String) -> Dictionary:
	var errors := PackedStringArray()
	return _resolve(registration_id.strip_edges(), {}, errors)


static func display_name(registration_id: String) -> String:
	var entry := get_registration(registration_id)
	return str(entry.get("display", registration_id.capitalize()))


static func catalog_version() -> int:
	return int(raw_catalog().get("version", 0))


static func validate_catalog(catalog: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	## `tag_side` is `brick_side` addressed by TAG, and it is what the shipped
	## sidelight rules use: a brick id names one vocabulary's object, a tag names
	## the legal thing both vocabularies carry. `brick_count` / `brick_side` are
	## kept — a registration may legitimately demand one specific model — but a
	## rule that must be met by BOTH build paths has to be tag-addressed, which is
	## the property `vessel_registration_test` now holds every shipped rule to.
	var allowed_kinds := [
		"slot_count", "brick_count", "tag_count", "cargo_cells", "metric_range", "capacity",
		"capability", "equipment_rating_max", "brick_side", "tag_side",
		"white_above_sidelights",
	]
	if int(catalog.get("version", 0)) != FORMAT_VERSION:
		errors.append("Unsupported registration catalog version")
	var raw: Variant = catalog.get("registrations", null)
	if not raw is Array:
		errors.append("registrations must be an array")
		return errors
	var seen := {}
	for item in raw as Array:
		if not item is Dictionary:
			errors.append("Every registration must be an object")
			continue
		var entry := item as Dictionary
		var id := str(entry.get("id", "")).strip_edges()
		if id.is_empty():
			errors.append("Registration id is required")
		elif seen.has(id):
			errors.append("Duplicate registration id: " + id)
		else:
			seen[id] = true
		if not entry.get("rules", []) is Array:
			errors.append("%s rules must be an array" % id)
		else:
			for rule_raw in entry.get("rules", []) as Array:
				if not rule_raw is Dictionary:
					errors.append("%s contains a non-object rule" % id)
					continue
				var rule := rule_raw as Dictionary
				var rule_id := str(rule.get("id", "")).strip_edges()
				var kind := str(rule.get("kind", "")).strip_edges()
				if rule_id.is_empty():
					errors.append("%s contains a rule without id" % id)
				if not allowed_kinds.has(kind):
					errors.append("%s/%s has unknown rule kind %s" % [id, rule_id, kind])
	for item in raw as Array:
		if not item is Dictionary:
			continue
		var entry := item as Dictionary
		var parent := str(entry.get("inherits", "")).strip_edges()
		if not parent.is_empty() and not seen.has(parent):
			errors.append("%s inherits unknown registration %s" % [
				str(entry.get("id", "")), parent,
			])
		elif not parent.is_empty() and _inherits_from(parent, str(entry.get("id", "")), raw):
			errors.append("Registration inheritance cycle at %s" % str(entry.get("id", "")))
	return errors


static func save_catalog(catalog: Dictionary) -> Error:
	var errors := validate_catalog(catalog)
	if not errors.is_empty():
		push_error("VesselRegistrationCatalog: refusing invalid save: " + " · ".join(errors))
		return ERR_INVALID_DATA
	var absolute := ProjectSettings.globalize_path(CATALOG_PATH)
	var temp := absolute + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(catalog, "\t") + "\n")
	file.close()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(temp))
	if typeof(parsed) != TYPE_DICTIONARY:
		DirAccess.remove_absolute(temp)
		return ERR_PARSE_ERROR
	if FileAccess.file_exists(absolute):
		var remove_err := DirAccess.remove_absolute(absolute)
		if remove_err != OK:
			DirAccess.remove_absolute(temp)
			return remove_err
	var err := DirAccess.rename_absolute(temp, absolute)
	if err == OK:
		reload()
	return err


static func _resolve(
	registration_id: String,
	visiting: Dictionary,
	errors: PackedStringArray,
) -> Dictionary:
	if registration_id.is_empty() or visiting.has(registration_id):
		if visiting.has(registration_id):
			errors.append("Registration inheritance cycle at " + registration_id)
		return {}
	var own := get_registration(registration_id)
	if own.is_empty():
		return {}
	visiting[registration_id] = true
	var resolved := own.duplicate(true)
	var rules: Array = []
	var caps: Dictionary = {}
	var terminal_families: Array = []
	var parent := str(own.get("inherits", "")).strip_edges()
	if not parent.is_empty():
		var inherited := _resolve(parent, visiting, errors)
		rules.append_array(inherited.get("rules", []) as Array)
		caps.merge(inherited.get("budget_caps", {}) as Dictionary, true)
		terminal_families = (inherited.get("terminal_families", []) as Array).duplicate()
	rules.append_array(own.get("rules", []) as Array)
	caps.merge(own.get("budget_caps", {}) as Dictionary, true)
	if own.has("terminal_families"):
		terminal_families = (own.get("terminal_families", []) as Array).duplicate()
	resolved["rules"] = rules
	resolved["budget_caps"] = caps
	if not terminal_families.is_empty():
		resolved["terminal_families"] = terminal_families
	visiting.erase(registration_id)
	return resolved


static func _inherits_from(current: String, target: String, entries: Array) -> bool:
	var guard := {}
	var cursor := current
	while not cursor.is_empty() and not guard.has(cursor):
		if cursor == target:
			return true
		guard[cursor] = true
		var next := ""
		for raw in entries:
			if raw is Dictionary and str((raw as Dictionary).get("id", "")) == cursor:
				next = str((raw as Dictionary).get("inherits", ""))
				break
		cursor = next
	return false
