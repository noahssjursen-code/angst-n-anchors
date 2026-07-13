class_name VesselArchive
extends RefCounted

## Durable, append/update-only safety copies for configured vessels.
## player.json remains the session snapshot; these per-UUID files ensure a
## fleet merge or partial profile reset cannot erase a deck configuration.

const ARCHIVE_DIR := "user://save/vessels"
const FORMAT_VERSION := 1


static func save_record(owner_id: String, record: Dictionary) -> bool:
	var owner := owner_id.strip_edges()
	var safe := PlayerData.ledger_vessel_record(VesselSpawn.normalize_record(record))
	var uid := str(safe.get("uid", "")).strip_edges()
	if owner.is_empty() or uid.is_empty():
		push_error("VesselArchive: owner UUID and vessel UUID are required")
		return false
	var archive_dir := _archive_dir()
	var err := DirAccess.make_dir_recursive_absolute(archive_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("VesselArchive: could not create archive directory (err %d)" % err)
		return false
	var path := "%s/%s.json" % [archive_dir, _safe_filename(uid)]
	var temp_path := path + ".tmp"
	var envelope := {
		"version": FORMAT_VERSION,
		"owner_id": owner,
		"vessel": safe,
		"saved_at_unix": Time.get_unix_time_from_system(),
	}
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("VesselArchive: could not write %s" % temp_path)
		return false
	file.store_string(JSON.stringify(envelope, "\t"))
	file.flush()
	file.close()
	if _load_envelope(temp_path).is_empty():
		DirAccess.remove_absolute(temp_path)
		push_error("VesselArchive: temporary archive failed validation uid=%s" % uid)
		return false
	if FileAccess.file_exists(path):
		err = DirAccess.remove_absolute(path)
		if err != OK:
			DirAccess.remove_absolute(temp_path)
			return false
	err = DirAccess.rename_absolute(temp_path, path)
	return err == OK


static func load_records(owner_id: String) -> Array:
	var owner := owner_id.strip_edges()
	var out: Array = []
	if owner.is_empty():
		return out
	var archive_dir := _archive_dir()
	var dir := DirAccess.open(archive_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var filename := dir.get_next()
	while not filename.is_empty():
		if not dir.current_is_dir() and filename.ends_with(".json"):
			var envelope := _load_envelope("%s/%s" % [archive_dir, filename])
			if str(envelope.get("owner_id", "")) == owner:
				var vessel_raw: Variant = envelope.get("vessel", {})
				if typeof(vessel_raw) == TYPE_DICTIONARY:
					var vessel := PlayerData.ledger_vessel_record(
						VesselSpawn.normalize_record(vessel_raw as Dictionary)
					)
					if not vessel.is_empty():
						out.append(vessel)
		filename = dir.get_next()
	dir.list_dir_end()
	return out


static func _load_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var envelope := parsed as Dictionary
	if int(envelope.get("version", 0)) != FORMAT_VERSION:
		return {}
	if str(envelope.get("owner_id", "")).is_empty():
		return {}
	if typeof(envelope.get("vessel", null)) != TYPE_DICTIONARY:
		return {}
	return envelope


static func _safe_filename(uid: String) -> String:
	var out := ""
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
	return out if not out.is_empty() else PlayerData.new_uuid()


static func archive_path_for_uid(uid: String) -> String:
	return "%s/%s.json" % [_archive_dir(), _safe_filename(uid)]


static func _archive_dir() -> String:
	return PlayerSaveStore._save_dir() + "/vessels"
