class_name PlayerSaveStore
extends RefCounted

## Local persistence for the active player account.
## Game code goes through PlayerSession; this class only handles JSON I/O.
## A future online backend can replace load/save here without touching callers.

## v1 → v2 adds: accepted_contracts, ship_runtime_state, world_clock_hours.
## v3 associates coordinate-bearing state with a deterministic world context.
## PlayerData.from_dict tolerates missing keys, so v1 saves auto-upgrade
## on first load + save (in-flight contract counts will be left as-is for
## the migration tick, but any subsequent save snapshots properly).
const SAVE_VERSION: int = 3
const SAVE_DIR: String = "user://save"
const SAVE_PATH: String = SAVE_DIR + "/player.json"
const SAVE_TEMP_PATH: String = SAVE_DIR + "/player.json.tmp"
const SAVE_BACKUP_PATH: String = SAVE_DIR + "/player.json.bak"
static var storage_root_override: String = ""


static func has_save() -> bool:
	return FileAccess.file_exists(_save_path()) or FileAccess.file_exists(_backup_path())


static func load_envelope() -> Dictionary:
	var envelope := _load_envelope_from_path(_save_path())
	if not envelope.is_empty():
		return envelope
	# A power loss or forced process kill must not erase the last valid ledger.
	envelope = _load_envelope_from_path(_backup_path())
	if not envelope.is_empty():
		push_warning("PlayerSaveStore: recovered player ledger from backup")
	return envelope


static func _load_envelope_from_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("PlayerSaveStore: could not read %s (err %d)" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PlayerSaveStore: invalid save format at %s" % path)
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
	var ok := true
	for path in [_save_path(), _temp_path(), _backup_path()]:
		if FileAccess.file_exists(path):
			ok = DirAccess.remove_absolute(path) == OK and ok
	return ok


static func wipe_all_local_data() -> bool:
	LocalCaptainStore.clear_active()
	var root: String = SAVE_DIR
	if not LocalCaptainStore.root_override.is_empty():
		root = LocalCaptainStore.root_dir()
	if not DirAccess.dir_exists_absolute(root):
		return true
	return _remove_tree(root)


static func _normalize_envelope(raw: Dictionary) -> Dictionary:
	# v1 envelope: { version, player, saved_at_unix }
	if raw.has("player") and typeof(raw["player"]) == TYPE_DICTIONARY:
		return raw
	# Legacy / hand-edited: flat player fields at root.
	if raw.has("marks") or raw.has("display_name"):
		return {"version": SAVE_VERSION, "player": raw}
	return {}


static func _write_envelope(envelope: Dictionary) -> bool:
	var save_dir := _save_dir()
	var save_path := _save_path()
	var temp_path := _temp_path()
	var backup_path := _backup_path()
	var err := DirAccess.make_dir_recursive_absolute(save_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("PlayerSaveStore: could not create %s (err %d)" % [save_dir, err])
		return false
	var json := JSON.stringify(envelope, "\t")
	# Write and validate a complete temporary file before touching player.json.
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("PlayerSaveStore: could not write %s (err %d)" % [temp_path, FileAccess.get_open_error()])
		return false
	file.store_string(json)
	file.flush()
	file.close()
	if _load_envelope_from_path(temp_path).is_empty():
		push_warning("PlayerSaveStore: refused to replace player.json with an invalid temporary save")
		DirAccess.remove_absolute(temp_path)
		return false

	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(save_path):
		err = DirAccess.rename_absolute(save_path, backup_path)
		if err != OK:
			push_warning("PlayerSaveStore: could not rotate player.json to backup (err %d)" % err)
			DirAccess.remove_absolute(temp_path)
			return false
	err = DirAccess.rename_absolute(temp_path, save_path)
	if err != OK:
		push_warning("PlayerSaveStore: could not install new player.json (err %d)" % err)
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, save_path)
		return false
	return true


static func _save_dir() -> String:
	return storage_root_override if not storage_root_override.is_empty() else SAVE_DIR


static func _save_path() -> String:
	return _save_dir() + "/player.json"


static func _temp_path() -> String:
	return _save_dir() + "/player.json.tmp"


static func _backup_path() -> String:
	return _save_dir() + "/player.json.bak"


static func _remove_tree(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var child := path.path_join(entry)
		var err := OK
		if dir.current_is_dir():
			if not _remove_tree(child):
				dir.list_dir_end()
				return false
		else:
			err = DirAccess.remove_absolute(child)
			if err != OK:
				dir.list_dir_end()
				return false
		entry = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path) == OK
