class_name NetworkClientStorageScope
extends RefCounted

## Separates device-local multiplayer state for side-by-side test clients.
##
## Production launches use the legacy unscoped paths. The local multiplayer
## launcher supplies --mp-client-slot=<name> after Godot's `--` separator.

const SLOT_ARGUMENT := "--mp-client-slot="
const SLOT_ENVIRONMENT := "ANGST_MP_CLIENT_SLOT"


static func scoped_path(default_path: String) -> String:
	var slot := current_slot()
	if slot.is_empty():
		return default_path
	var extension := default_path.get_extension()
	var base := default_path.trim_suffix("." + extension) if not extension.is_empty() else default_path
	return "%s_%s.%s" % [base, slot, extension] if not extension.is_empty() else "%s_%s" % [base, slot]


static func current_slot() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(SLOT_ARGUMENT):
			return _safe_slot(argument.trim_prefix(SLOT_ARGUMENT))
	var environment_slot := OS.get_environment(SLOT_ENVIRONMENT)
	return _safe_slot(environment_slot)


static func _safe_slot(raw: String) -> String:
	var result := ""
	const ALLOWED := "abcdefghijklmnopqrstuvwxyz0123456789_-"
	for character in raw.strip_edges().to_lower():
		if ALLOWED.contains(character):
			result += character
		elif character == " ":
			result += "-"
	return result.left(48)
