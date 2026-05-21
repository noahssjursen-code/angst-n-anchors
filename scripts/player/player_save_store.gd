class_name PlayerSaveStore
extends RefCounted

## Local persistence for the active player account.
## Game code goes through PlayerSession; this class only handles JSON I/O.
## A future online backend can replace load/save here without touching callers.

## v1 → v2 adds: accepted_contracts, ship_runtime_state, world_clock_hours.
## PlayerData.from_dict tolerates missing keys, so v1 saves auto-upgrade
## on first load + save (in-flight contract counts will be left as-is for
## the migration tick, but any subsequent save snapshots properly).
const SAVE_VERSION: int = 2
const SAVE_DIR: String = "user://save"
const SAVE_PATH: String = SAVE_DIR + "/player.json"


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func load_envelope() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("PlayerSaveStore: could not read %s (err %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PlayerSaveStore: invalid save format at %s" % SAVE_PATH)
		return {}
	return _normalize_envelope(parsed as Dictionary)


static func load_player() -> PlayerData:
	var envelope := load_envelope()
	var player_raw: Variant = envelope.get("player", {})
	if typeof(player_raw) != TYPE_DICTIONARY:
		return PlayerData.new()
	return PlayerData.from_dict(player_raw as Dictionary)


static func save_player(player: PlayerData) -> bool:
	if player == null:
		return false
	var envelope := {
		"version": SAVE_VERSION,
		"player": player.to_dict(),
		"saved_at_unix": Time.get_unix_time_from_system(),
	}
	return _write_envelope(envelope)


static func delete_save() -> bool:
	if not has_save():
		return true
	var err := DirAccess.remove_absolute(SAVE_PATH)
	return err == OK


static func _normalize_envelope(raw: Dictionary) -> Dictionary:
	# v1 envelope: { version, player, saved_at_unix }
	if raw.has("player") and typeof(raw["player"]) == TYPE_DICTIONARY:
		return raw
	# Legacy / hand-edited: flat player fields at root.
	if raw.has("marks") or raw.has("display_name"):
		return {"version": SAVE_VERSION, "player": raw}
	return {}


static func _write_envelope(envelope: Dictionary) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("PlayerSaveStore: could not create %s (err %d)" % [SAVE_DIR, err])
		return false
	var json := JSON.stringify(envelope, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("PlayerSaveStore: could not write %s (err %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(json)
	file.close()
	return true
