class_name CustomPortRepository
extends RefCounted
## Complete port documents, not scene dumps. No player/company save side effects.
## Writes use a same-directory temporary file and replace by rename; the previous
## validated snapshot is retained as .bak. A corrupt primary is never overwritten
## merely by loading it, and unknown newer formats are never silently downgraded.

const State = preload("res://scripts/port/state/custom_port_state.gd")
const FILE_FORMAT := "angst-custom-port"
const FILE_VERSION := 1
const MAX_FILE_BYTES := 67108864


static func save(path: String, state: RefCounted) -> Dictionary:
	var resolved := _path(path)
	if resolved.is_empty(): return _failure("invalid_path", path, ["Choose an absolute path or user:// port file."])
	if state == null or not state.has_method("to_dict") or not state.has_method("validate"):
		return _failure("invalid_state", path, ["A validated CustomPortState is required."])
	var validation: Array = state.call("validate")
	if not validation.is_empty(): return _failure("invalid_document", path, validation)
	var snapshot: Dictionary = state.call("to_dict")
	# State and persistence share one full-precision wire representation, including
	# negative zero and computed doubles that Godot parses one ULP differently.
	var normalized: Dictionary = State._canonical(snapshot)
	var envelope := {"file_format": FILE_FORMAT, "file_version": FILE_VERSION,
		"snapshot": normalized, "snapshot_sha256": _checksum(normalized)}
	var text := JSON.stringify(envelope, "\t", true, true) + "\n"
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _failure("file_too_large", path, ["Port document exceeds 64 MiB."])
	var directory_error := DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if directory_error != OK: return _failure("directory_failed", path, [error_string(directory_error)])
	var temporary := _temporary(resolved)
	var write := _write(temporary, text.to_utf8_buffer())
	if not write.ok: return _failure("write_failed", path, write.errors)
	var decoded := _read_document(temporary)
	if not decoded.ok:
		_remove_temporary(temporary)
		return _failure("write_verification_failed", path, decoded.errors)
	var catalog: Dictionary = state.get("_catalog")
	var reconstructed = State.from_dict(decoded.snapshot, snapshot.get("world", {}), catalog)
	if not reconstructed.validation_errors.is_empty():
		_remove_temporary(temporary)
		return _failure("roundtrip_validation_failed", path, reconstructed.validation_errors)
	var backup := resolved + ".bak"
	var prior: Dictionary = {"ok": false}
	if FileAccess.file_exists(resolved):
		prior = _load_candidate(resolved, {}, catalog)
		if not prior.ok and prior.code in ["unsupported_file_version", "unsupported_schema_version", "wrong_file_format"]:
			_remove_temporary(temporary)
			return _failure("existing_file_incompatible", path, prior.errors)
	# Recovery is still an existing document. A missing/damaged primary must not
	# let stale callers discard its newer cargo or receipts, or claim its path for
	# another port. This comparison never rewrites the recovery file itself.
	var baseline: Dictionary = prior
	if not baseline.ok and FileAccess.file_exists(backup):
		baseline = _load_candidate(backup, {}, catalog)
		if not baseline.ok and baseline.code in ["unsupported_file_version", "unsupported_schema_version", "wrong_file_format"]:
			_remove_temporary(temporary)
			return _failure("existing_file_incompatible", path, baseline.errors)
	if baseline.ok:
		if str(baseline.snapshot.id) != str(snapshot.id) or _checksum(baseline.snapshot.world) != _checksum(snapshot.world):
			_remove_temporary(temporary)
			return _failure("port_identity_conflict", path, ["This file belongs to a different port or world."])
		if int(baseline.snapshot.revision) > int(snapshot.revision):
			_remove_temporary(temporary)
			return _failure("stale_snapshot", path, ["A newer port revision is already saved."])
		if int(baseline.snapshot.revision) == int(snapshot.revision) and _checksum(baseline.snapshot) != _checksum(snapshot):
			_remove_temporary(temporary)
			return _failure("snapshot_revision_conflict", path, ["Different changes already occupy this saved revision."])
	# A damaged current file must not replace a known-good recovery file.
	if prior.ok:
		var backup_temporary := _temporary(backup)
		var backup_write := _write(backup_temporary, FileAccess.get_file_as_bytes(resolved))
		if not backup_write.ok:
			_remove_temporary(temporary)
			return _failure("backup_failed", path, backup_write.errors)
		var backup_error := DirAccess.rename_absolute(backup_temporary, backup)
		if backup_error != OK:
			_remove_temporary(backup_temporary)
			_remove_temporary(temporary)
			return _failure("backup_failed", path, [error_string(backup_error)])
	var commit_error := DirAccess.rename_absolute(temporary, resolved)
	if commit_error != OK:
		_remove_temporary(temporary)
		return _failure("commit_failed", path, [error_string(commit_error)])
	return {"ok": true, "code": "saved", "path": resolved, "revision": int(snapshot.get("revision", 0)),
		"bytes_written": text.to_utf8_buffer().size(), "backup_path": backup if FileAccess.file_exists(backup) else "", "errors": []}


static func load_state(path: String, expected_world: Dictionary = {}, catalog: Dictionary = {}) -> Dictionary:
	var resolved := _path(path)
	if resolved.is_empty(): return _failure("invalid_path", path, ["Choose an absolute path or user:// port file."])
	var primary := _load_candidate(resolved, expected_world, catalog)
	if primary.ok:
		primary.path = resolved
		primary.loaded_path = resolved
		primary.recovered_from_backup = false
		primary.warnings = []
		return primary
	if primary.code in ["unsupported_file_version", "unsupported_schema_version", "wrong_world", "wrong_file_format"]:
		return primary
	var backup_path := resolved + ".bak"
	if FileAccess.file_exists(backup_path):
		var backup := _load_candidate(backup_path, expected_world, catalog)
		if backup.ok:
			backup.path = resolved
			backup.loaded_path = backup_path
			backup.recovered_from_backup = true
			backup.warnings = ["Primary port file could not be loaded (%s); recovered the previous valid snapshot." % primary.code]
			backup.primary_error = primary.code
			return backup
	return primary


static func _load_candidate(path: String, expected_world: Dictionary, catalog: Dictionary) -> Dictionary:
	var decoded := _read_document(path)
	if not decoded.ok: return decoded
	var snapshot: Dictionary = decoded.snapshot
	if not expected_world.is_empty() and (not snapshot.get("world") is Dictionary or _checksum(snapshot.world) != _checksum(expected_world)):
		return _failure("wrong_world", path, ["Port coordinates belong to a different world."])
	var state = State.from_dict(snapshot, expected_world, catalog)
	if not state.validation_errors.is_empty(): return _failure("invalid_document", path, state.validation_errors)
	return {"ok": true, "code": "loaded", "state": state, "snapshot": state.to_dict(), "path": path, "errors": []}


static func _read_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return _failure("not_found", path, ["Port file does not exist."])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _failure("read_failed", path, [error_string(FileAccess.get_open_error())])
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return _failure("file_too_large", path, ["Port document exceeds 64 MiB."])
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF: return _failure("read_failed", path, [error_string(read_error)])
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		return _failure("invalid_json", path, ["Line %d: %s" % [parser.get_error_line(), parser.get_error_message()]])
	if not parser.data is Dictionary: return _failure("invalid_document", path, ["Port file must contain a JSON object."])
	var document: Dictionary = parser.data
	var snapshot: Dictionary
	if document.has("file_format") or document.has("file_version"):
		if str(document.get("file_format", "")) != FILE_FORMAT:
			return _failure("wrong_file_format", path, ["This file is not a custom port save."])
		if not _version(document.get("file_version"), FILE_VERSION):
			return _failure("unsupported_file_version", path, ["Unsupported port file version; original file was preserved."])
		if not document.get("snapshot") is Dictionary:
			return _failure("invalid_document", path, ["Port snapshot is missing."])
		snapshot = document.snapshot
		if str(document.get("snapshot_sha256", "")) != _checksum(snapshot):
			return _failure("checksum_mismatch", path, ["Port snapshot checksum does not match its contents."])
	else:
		# Authored raw documents are useful for fixture injection and database
		# exports; the same version and state validation still apply.
		snapshot = document
	if not _version(snapshot.get("schema_version"), State.FORMAT_VERSION):
		return _failure("unsupported_schema_version", path, ["Unsupported port schema; original file was preserved."])
	return {"ok": true, "code": "decoded", "snapshot": snapshot, "errors": []}


static func _write(path: String, bytes: PackedByteArray) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"ok": false, "errors": [error_string(FileAccess.get_open_error())]}
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		_remove_temporary(path)
		return {"ok": false, "errors": [error_string(error)]}
	return {"ok": true, "errors": []}


static func _checksum(snapshot: Dictionary) -> String:
	var normalized: Variant = State._canonical(snapshot)
	return JSON.stringify(normalized, "", true, true).sha256_text()


static func _version(value: Variant, expected: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(expected)


static func _path(path: String) -> String:
	if path.strip_edges().is_empty() or path.begins_with("res://"): return ""
	if path.begins_with("user://"): return ProjectSettings.globalize_path(path).simplify_path()
	return path.simplify_path() if path.is_absolute_path() else ""


static func _temporary(path: String) -> String:
	return path + ".tmp-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]


static func _remove_temporary(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)


static func _failure(code: String, path: String, errors: Array) -> Dictionary:
	return {"ok": false, "code": code, "path": path, "errors": errors, "snapshot": {}}
