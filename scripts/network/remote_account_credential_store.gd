class_name RemoteAccountCredentialStore
extends RefCounted

## Device-local multiplayer account session cache.
##
## Passwords never enter this store. The server issues a revocable opaque token
## after login; it is scoped by server URL so test, local, and production
## accounts cannot be confused. This is a client convenience cache, never an
## authority for captain ownership.

const DEFAULT_STORE_PATH := "user://network/account_sessions.json"

static var store_path_override := ""
static var _runtime_entries: Dictionary = {}
static var _runtime_path := ""
static var _runtime_loaded := false


static func token_for(base_url: String) -> String:
	return str(_entry_for(base_url).get("access_token", ""))


static func account_for(base_url: String) -> Dictionary:
	var raw: Variant = _entry_for(base_url).get("account", {})
	return (raw as Dictionary).duplicate(true) if raw is Dictionary else {}


static func has_session(base_url: String) -> bool:
	return not token_for(base_url).is_empty()


static func set_session(base_url: String, token: String, account: Dictionary) -> bool:
	var normalized_token := token.strip_edges()
	var account_id := str(account.get("id", "")).strip_edges()
	if normalized_token.is_empty() or account_id.is_empty():
		return false
	var entries := _load()
	entries[_server_key(base_url)] = {
		"access_token": normalized_token,
		"account": account.duplicate(true),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
	}
	return _save(entries)


static func update_account(base_url: String, account: Dictionary) -> bool:
	var entries := _load()
	var key := _server_key(base_url)
	var entry := entries.get(key, {}) as Dictionary
	if str(entry.get("access_token", "")).is_empty():
		return false
	entry["account"] = account.duplicate(true)
	entries[key] = entry
	return _save(entries)


static func clear_session(base_url: String) -> void:
	var entries := _load()
	entries.erase(_server_key(base_url))
	_save(entries)


static func _entry_for(base_url: String) -> Dictionary:
	var raw: Variant = _load().get(_server_key(base_url), {})
	return raw as Dictionary if raw is Dictionary else {}


static func _server_key(base_url: String) -> String:
	return base_url.strip_edges().trim_suffix("/").to_lower()


static func _load() -> Dictionary:
	var path := _store_path()
	if _runtime_loaded and _runtime_path == path:
		return _runtime_entries.duplicate(true)
	var loaded: Variant = _load_path(path)
	if loaded is Dictionary:
		_set_runtime_entries(path, loaded as Dictionary)
		return _runtime_entries.duplicate(true)
	var backup: Variant = _load_path(_backup_path())
	var entries := backup as Dictionary if backup is Dictionary else {}
	_set_runtime_entries(path, entries)
	return _runtime_entries.duplicate(true)


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


static func _save(entries: Dictionary) -> bool:
	var directory := ProjectSettings.globalize_path(_store_path().get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var temp := FileAccess.open(_temp_path(), FileAccess.WRITE)
	if temp == null:
		return false
	temp.store_string(JSON.stringify(entries))
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
	_set_runtime_entries(_store_path(), entries)
	return true


static func clear_test_storage() -> void:
	for path in [_store_path(), _temp_path(), _backup_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	clear_runtime_cache_for_test()


static func clear_runtime_cache_for_test() -> void:
	_runtime_entries = {}
	_runtime_path = ""
	_runtime_loaded = false


static func _store_path() -> String:
	return store_path_override if not store_path_override.is_empty() else NetworkClientStorageScope.scoped_path(DEFAULT_STORE_PATH)


static func _set_runtime_entries(path: String, entries: Dictionary) -> void:
	_runtime_path = path
	_runtime_entries = entries.duplicate(true)
	_runtime_loaded = true


static func _temp_path() -> String:
	return _store_path() + ".tmp"


static func _backup_path() -> String:
	return _store_path() + ".bak"
