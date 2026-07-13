class_name LocalCaptainStore
extends RefCounted

## Multi-slot local captain persistence.
##
## Layout:
##   user://save/index.json
##   user://save/captains/{account_id}/player.json
##   user://save/captains/{account_id}/vessels/{uid}.json
##
## Legacy single-slot `user://save/player.json` migrates into one captain folder
## on first access.

const ROOT_DIR := "user://save"
const INDEX_PATH := ROOT_DIR + "/index.json"
const CAPTAINS_DIR := ROOT_DIR + "/captains"

static var active_id: String = ""
static var root_override: String = ""


static func root_dir() -> String:
	return root_override if not root_override.is_empty() else ROOT_DIR


static func index_path() -> String:
	return root_dir() + "/index.json"


static func captains_dir() -> String:
	return root_dir() + "/captains"


static func captain_dir(captain_id: String) -> String:
	return captains_dir().path_join(_safe_id(captain_id))


static func ensure_migrated() -> void:
	DirAccess.make_dir_recursive_absolute(captains_dir())
	if FileAccess.file_exists(index_path()):
		return
	_migrate_legacy_slot()
	if not FileAccess.file_exists(index_path()):
		_write_index([])


static func list_captains() -> Array[Dictionary]:
	ensure_migrated()
	var entries: Array[Dictionary] = []
	var dropped_orphans := false
	for raw in _read_index():
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry := _normalize_index_entry(raw as Dictionary)
		if entry.is_empty():
			continue
		# Older title-screen autosaves could add an index row without ever
		# creating a captain directory. Such rows are not real save slots.
		if not DirAccess.dir_exists_absolute(captain_dir(str(entry["id"]))):
			dropped_orphans = true
			continue
		entries.append(entry)
	if dropped_orphans:
		_write_index(entries)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("last_played_unix", 0)) > int(b.get("last_played_unix", 0))
	)
	return entries


static func has_any() -> bool:
	return not list_captains().is_empty()


static func activate(captain_id: String) -> bool:
	ensure_migrated()
	var id := _safe_id(captain_id)
	if id.is_empty():
		return false
	var path := captain_dir(id)
	if not DirAccess.dir_exists_absolute(path):
		return false
	active_id = id
	PlayerSaveStore.storage_root_override = path
	return true


static func clear_active() -> void:
	active_id = ""
	PlayerSaveStore.storage_root_override = ""


static func has_active() -> bool:
	return not active_id.is_empty() and not PlayerSaveStore.storage_root_override.is_empty()


static func create_slot(captain_id: String, summary: Dictionary = {}) -> bool:
	ensure_migrated()
	var id := _safe_id(captain_id)
	if id.is_empty():
		return false
	var path := captain_dir(id)
	var err := DirAccess.make_dir_recursive_absolute(path.path_join("vessels"))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("LocalCaptainStore: could not create captain slot %s" % id)
		return false
	active_id = id
	PlayerSaveStore.storage_root_override = path
	_upsert_index_entry(_merge_summary(id, summary))
	return true


static func delete_captain(captain_id: String) -> bool:
	ensure_migrated()
	var id := _safe_id(captain_id)
	if id.is_empty():
		return false
	var path := captain_dir(id)
	var ok := true
	if DirAccess.dir_exists_absolute(path):
		ok = PlayerSaveStore._remove_tree(path) and ok
	var entries: Array = []
	for raw in _read_index():
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry := raw as Dictionary
		if str(entry.get("id", "")) == id:
			continue
		entries.append(entry)
	_write_index(entries)
	if active_id == id:
		clear_active()
	return ok


static func load_player(captain_id: String) -> PlayerData:
	if not activate(captain_id):
		return PlayerData.new()
	return PlayerSaveStore.load_player()


static func touch_index_from_player(player: PlayerData) -> void:
	if player == null:
		return
	var id := str(player.account_id).strip_edges()
	if id.is_empty():
		id = str(player.captain_id).strip_edges()
	if id.is_empty():
		return
	var ctx: Dictionary = player.world_context if typeof(player.world_context) == TYPE_DICTIONARY else {}
	_upsert_index_entry({
		"id": id,
		"display_name": player.display_name,
		"home_port_id": player.home_port_id,
		"world_seed": int(ctx.get("seed", 0)),
		"last_played_unix": int(Time.get_unix_time_from_system()),
		"marks": player.marks,
	})


static func _migrate_legacy_slot() -> void:
	var legacy_player := root_dir().path_join("player.json")
	var legacy_backup := root_dir().path_join("player.json.bak")
	var legacy_vessels := root_dir().path_join("vessels")
	if not FileAccess.file_exists(legacy_player) and not FileAccess.file_exists(legacy_backup):
		return
	# Temporarily point PlayerSaveStore at the legacy root to read the old file.
	var previous := PlayerSaveStore.storage_root_override
	PlayerSaveStore.storage_root_override = root_dir()
	var player := PlayerSaveStore.load_player()
	PlayerSaveStore.storage_root_override = previous
	if player == null:
		player = PlayerData.new()
	if str(player.account_id).strip_edges().is_empty():
		player.account_id = PlayerData.new_uuid()
	var id := str(player.account_id).strip_edges()
	var dest := captain_dir(id)
	DirAccess.make_dir_recursive_absolute(dest.path_join("vessels"))
	_move_if_exists(legacy_player, dest.path_join("player.json"))
	_move_if_exists(legacy_backup, dest.path_join("player.json.bak"))
	_move_if_exists(root_dir().path_join("player.json.tmp"), dest.path_join("player.json.tmp"))
	_migrate_legacy_vessels(id, dest.path_join("vessels"), legacy_vessels)
	var ctx: Dictionary = player.world_context if typeof(player.world_context) == TYPE_DICTIONARY else {}
	_write_index([{
		"id": id,
		"display_name": player.display_name if not player.display_name.is_empty() else "Captain",
		"home_port_id": player.home_port_id,
		"world_seed": int(ctx.get("seed", 42)),
		"last_played_unix": int(Time.get_unix_time_from_system()),
		"marks": player.marks,
	}])
	push_warning("LocalCaptainStore: migrated legacy player.json into captains/%s" % id)


static func _migrate_legacy_vessels(owner_id: String, dest_vessels: String, src_vessels: String) -> void:
	var dir := DirAccess.open(src_vessels)
	if dir == null:
		return
	dir.list_dir_begin()
	var filename := dir.get_next()
	while not filename.is_empty():
		if not dir.current_is_dir() and filename.ends_with(".json"):
			var path := src_vessels.path_join(filename)
			var envelope := _read_json_dict(path)
			if str(envelope.get("owner_id", "")) == owner_id:
				DirAccess.rename_absolute(path, dest_vessels.path_join(filename))
		filename = dir.get_next()
	dir.list_dir_end()


static func _read_index() -> Array:
	var raw := _read_json_dict(index_path())
	var captains_raw: Variant = raw.get("captains", [])
	return captains_raw as Array if typeof(captains_raw) == TYPE_ARRAY else []


static func _write_index(entries: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(root_dir())
	var payload := {
		"version": 1,
		"captains": entries,
	}
	var file := FileAccess.open(index_path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


static func _upsert_index_entry(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	if id.is_empty():
		return
	var entries: Array = []
	var replaced := false
	for raw in _read_index():
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var existing := raw as Dictionary
		if str(existing.get("id", "")) == id:
			entries.append(_merge_summary(id, entry, existing))
			replaced = true
		else:
			entries.append(existing)
	if not replaced:
		entries.append(_merge_summary(id, entry))
	_write_index(entries)


static func _merge_summary(id: String, summary: Dictionary, base: Dictionary = {}) -> Dictionary:
	return {
		"id": id,
		"display_name": str(summary.get("display_name", base.get("display_name", "Captain"))),
		"home_port_id": str(summary.get("home_port_id", base.get("home_port_id", "port-home"))),
		"world_seed": int(summary.get("world_seed", base.get("world_seed", 0))),
		"last_played_unix": int(summary.get("last_played_unix", base.get("last_played_unix", 0))),
		"marks": int(summary.get("marks", base.get("marks", 0))),
	}


static func _normalize_index_entry(raw: Dictionary) -> Dictionary:
	var id := str(raw.get("id", "")).strip_edges()
	if id.is_empty():
		return {}
	return _merge_summary(id, raw)


static func _safe_id(captain_id: String) -> String:
	var out := ""
	var uid := captain_id.strip_edges()
	for i in range(uid.length()):
		var code := uid.unicode_at(i)
		var valid := (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or code == 45
			or code == 95
		)
		if valid:
			out += uid[i]
	return out


static func _move_if_exists(src: String, dest: String) -> void:
	if FileAccess.file_exists(src):
		DirAccess.rename_absolute(src, dest)


static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}
