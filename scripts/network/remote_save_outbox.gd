class_name RemoteSaveOutbox
extends RefCounted

## Durable write-ahead storage for multiplayer captain documents.
##
## HTTP cannot be awaited while the process is closing. Every desired remote
## save is therefore written here before it is sent. On the next login the
## client compares the server revision and the exact last-sent state before it
## replays anything, so another device's progress is never overwritten.

const DEFAULT_STORE_PATH := "user://network/remote_save_outbox.json"
const STORE_VERSION := 1

static var store_path_override := ""


static func load_entry(base_url: String, account_id: String, captain_id: String) -> Dictionary:
	var entries := _entries()
	var raw: Variant = entries.get(_key(base_url, account_id, captain_id), {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


static func save_entry(base_url: String, account_id: String, captain_id: String, entry: Dictionary) -> bool:
	if account_id.strip_edges().is_empty() or captain_id.strip_edges().is_empty() or entry.is_empty():
		return false
	var document := _load_document()
	var entries_raw: Variant = document.get("entries", {})
	var entries := (entries_raw as Dictionary).duplicate(true) if entries_raw is Dictionary else {}
	var safe := entry.duplicate(true)
	safe["base_url"] = _server_key(base_url)
	safe["account_id"] = account_id.strip_edges()
	safe["captain_id"] = captain_id.strip_edges()
	safe["updated_at_unix"] = int(Time.get_unix_time_from_system())
	entries[_key(base_url, account_id, captain_id)] = safe
	document["version"] = STORE_VERSION
	document["entries"] = entries
	return _save_document(document)


static func remove_entry(base_url: String, account_id: String, captain_id: String) -> bool:
	var document := _load_document()
	var entries_raw: Variant = document.get("entries", {})
	var entries := (entries_raw as Dictionary).duplicate(true) if entries_raw is Dictionary else {}
	entries.erase(_key(base_url, account_id, captain_id))
	document["version"] = STORE_VERSION
	document["entries"] = entries
	return _save_document(document)


static func clear_test_storage() -> void:
	for path in [_store_path(), _temp_path(), _backup_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _entries() -> Dictionary:
	var raw: Variant = _load_document().get("entries", {})
	return raw as Dictionary if raw is Dictionary else {}


static func _load_document() -> Dictionary:
	var loaded: Variant = _load_path(_store_path())
	if loaded is Dictionary:
		return loaded as Dictionary
	var backup: Variant = _load_path(_backup_path())
	return backup as Dictionary if backup is Dictionary else {"version": STORE_VERSION, "entries": {}}


static func _load_path(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	var parsed: Variant = parser.data
	return parsed if parsed is Dictionary else null


static func _save_document(document: Dictionary) -> bool:
	var directory := ProjectSettings.globalize_path(_store_path().get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var temp := FileAccess.open(_temp_path(), FileAccess.WRITE)
	if temp == null:
		return false
	temp.store_string(JSON.stringify(document))
	temp.flush()
	temp = null
	var absolute_store := ProjectSettings.globalize_path(_store_path())
	var absolute_temp := ProjectSettings.globalize_path(_temp_path())
	var absolute_backup := ProjectSettings.globalize_path(_backup_path())
	if FileAccess.file_exists(_store_path()):
		if FileAccess.file_exists(_backup_path()):
			DirAccess.remove_absolute(absolute_backup)
		if DirAccess.rename_absolute(absolute_store, absolute_backup) != OK:
			DirAccess.remove_absolute(absolute_temp)
			return false
	if DirAccess.rename_absolute(absolute_temp, absolute_store) != OK:
		if FileAccess.file_exists(_backup_path()):
			DirAccess.rename_absolute(absolute_backup, absolute_store)
		return false
	return true


static func _key(base_url: String, account_id: String, captain_id: String) -> String:
	return "%s|%s|%s" % [_server_key(base_url), account_id.strip_edges(), captain_id.strip_edges()]


static func _server_key(base_url: String) -> String:
	return base_url.strip_edges().trim_suffix("/").to_lower()


static func _store_path() -> String:
	return store_path_override if not store_path_override.is_empty() else NetworkClientStorageScope.scoped_path(DEFAULT_STORE_PATH)


static func _temp_path() -> String:
	return _store_path() + ".tmp"


static func _backup_path() -> String:
	return _store_path() + ".bak"
