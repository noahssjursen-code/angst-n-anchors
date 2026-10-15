extends Node

const Repository = preload("res://scripts/port/state/custom_port_repository.gd")
const State = preload("res://scripts/port/state/custom_port_state.gd")
const Fixture = preload("res://tests/custom_port_data_test.gd")

var failures: Array[String] = []
var checks := 0
var directory := ""
var fixture: Node
var record: Dictionary
var catalog: Dictionary


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Repository tests require --shipyard-playtest isolation.")
		get_tree().quit(1)
		return
	directory = "user://custom-port-repository-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	fixture = Fixture.new()
	record = fixture.call("_fixture")
	catalog = fixture.call("_catalog")
	_test_save_load_and_recovery()
	_test_versions_and_identity()
	_test_atomic_failures()
	_test_raw_injection_and_bad_data()
	_test_computed_precision()
	_cleanup()
	fixture.free()
	for failure in failures: push_error(failure)
	print("CUSTOM PORT REPOSITORY %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_save_load_and_recovery() -> void:
	var path := directory.path_join("harbour.json")
	var state := _fresh()
	var first := Repository.save(path, state)
	_check(first.ok, "first snapshot is saved: " + str(first))
	if not first.ok: return
	var initial_bytes := FileAccess.get_file_as_bytes(path)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(document.file_format == Repository.FILE_FORMAT and document.snapshot.placements.size() == record.placements.size(), "save contains full port data in a versioned envelope")
	var loaded := Repository.load_state(path, record.world, catalog)
	_check(loaded.ok and not loaded.recovered_from_backup, "primary snapshot validates against catalogue and world: " + str(loaded.get("errors", [])))
	if not loaded.ok: return
	_check(_same(loaded.snapshot, state.to_dict()), "all data round-trips exactly")
	var command := _dock_command(state)
	_check(state.apply(command).ok, "test vessel docks before second save")
	_check(Repository.save(path, state).ok, "second revision atomically replaces existing file on this platform")
	_check(FileAccess.get_file_as_bytes(path + ".bak") == initial_bytes, "backup preserves exact previous known-good file")
	loaded = Repository.load_state(path, record.world, catalog)
	_check(loaded.ok and int(loaded.snapshot.revision) == 1, "latest revision loads")
	_check(loaded.state.apply(command).code == "already_applied", "saved command receipt prevents duplicate dock after reload")
	var stale := Repository.save(path, _fresh())
	_check(not stale.ok and stale.code == "stale_snapshot", "older in-memory state cannot overwrite newer saved revision")
	var fork := _fresh()
	var fork_command := _dock_command(fork)
	fork_command.payload.berth_id = fork.derived_berths()[1].id
	fork.apply(fork_command)
	_check(Repository.save(path, fork).code == "snapshot_revision_conflict", "divergent changes at the same revision cannot overwrite the first writer")
	_write(path, "{\"file_format\":\"angst-custom-port\",\"snapshot\":")
	var truncated := FileAccess.get_file_as_bytes(path)
	loaded = Repository.load_state(path, record.world, catalog)
	_check(loaded.ok and loaded.recovered_from_backup and int(loaded.snapshot.revision) == 0, "truncated primary explicitly recovers previous snapshot")
	_check(loaded.primary_error == "invalid_json" and not loaded.warnings.is_empty(), "recovery is reported rather than hidden")
	_check(FileAccess.get_file_as_bytes(path) == truncated, "read recovery preserves damaged file for inspection")
	_check(Repository.save(path, loaded.state).ok, "explicit save repairs the damaged primary")
	_check(FileAccess.get_file_as_bytes(path + ".bak") == initial_bytes, "damaged file never replaces the good backup")
	document = JSON.parse_string(FileAccess.get_file_as_string(path))
	document.snapshot.name = "Changed without checksum"
	_write(path, JSON.stringify(document))
	loaded = Repository.load_state(path, record.world, catalog)
	_check(loaded.ok and loaded.recovered_from_backup and loaded.primary_error == "checksum_mismatch", "checksum catches parseable but altered snapshot")


func _test_versions_and_identity() -> void:
	var path := directory.path_join("versions.json")
	var state := _fresh()
	_check(Repository.save(path, state).ok and Repository.save(path, state).ok, "version fixture has a valid backup")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	envelope.file_version = 99
	_write(path, JSON.stringify(envelope))
	var bytes := FileAccess.get_file_as_bytes(path)
	_check(Repository.load_state(path, record.world, catalog).code == "unsupported_file_version", "future file format cannot silently fall back to an older backup")
	_check(Repository.save(path, state).code == "existing_file_incompatible", "save cannot erase an unknown future format")
	_check(FileAccess.get_file_as_bytes(path) == bytes, "future format bytes remain untouched")
	var newer := record.duplicate(true)
	newer.schema_version = 99
	_write(path, JSON.stringify(newer))
	_check(Repository.load_state(path, record.world, catalog).code == "unsupported_schema_version", "future data schema is rejected explicitly")
	var wrong := record.duplicate(true)
	wrong.world.seed = 999
	_write(path, JSON.stringify(wrong))
	_check(Repository.load_state(path, record.world, catalog).code == "wrong_world", "valid port from another world never falls back to old local geometry")
	_check(Repository.save(path, state).code == "port_identity_conflict", "saving cannot overwrite another world's port")
	wrong = record.duplicate(true)
	wrong.id = "different-port"
	_write(path, JSON.stringify(wrong))
	_check(Repository.save(path, state).code == "port_identity_conflict", "saving cannot overwrite a different port identity")
	envelope.file_version = Repository.FILE_VERSION
	envelope.file_format = "unrelated-data"
	_write(path, JSON.stringify(envelope))
	_check(Repository.load_state(path, record.world, catalog).code == "wrong_file_format", "unrelated envelopes are not treated as port saves")


func _test_atomic_failures() -> void:
	var path := directory.path_join("atomic.json")
	var state := _fresh()
	_check(Repository.save(path, state).ok, "atomic fixture created")
	var original := FileAccess.get_file_as_bytes(path)
	# Force the backup replacement to fail without permission changes or external
	# files: an existing directory occupies the expected backup filename.
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path + ".bak"))
	state.apply(_dock_command(state))
	var failed := Repository.save(path, state)
	_check(not failed.ok and failed.code == "backup_failed", "backup failure aborts commit")
	_check(FileAccess.get_file_as_bytes(path) == original, "failed commit leaves original save byte-identical")
	var directory_access := DirAccess.open(directory)
	var abandoned := false
	for filename in directory_access.get_files():
		if filename.contains(".tmp-"): abandoned = true
	_check(not abandoned, "failed commit cleans only its own temporary files")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	_check(Repository.save(path, state).ok, "save succeeds when transient obstruction is removed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var recovered := Repository.load_state(path, record.world, catalog)
	_check(recovered.ok and recovered.recovered_from_backup and recovered.primary_error == "not_found", "missing primary can recover a retained valid backup")


func _test_raw_injection_and_bad_data() -> void:
	var path := directory.path_join("injected.json")
	var raw := record.duplicate(true)
	raw.origin_m = [-0.0, 0.125, 123.123456789]
	_write(path, JSON.stringify(raw, "\t", true, true))
	var loaded := Repository.load_state(path, record.world, catalog)
	_check(loaded.ok, "raw authored JSON snapshot can be injected without a save envelope: " + str(loaded.get("errors", [])))
	if not loaded.ok: return
	_check(Repository.save(path, loaded.state).ok, "raw injection is upgraded to checksummed envelope on save")
	_check(Repository.load_state(path, record.world, catalog).ok, "negative zero and high precision coordinates verify after reload")
	var before := FileAccess.get_file_as_bytes(path)
	var invalid_record := record.duplicate(true)
	invalid_record.placements[0].position_m[0] = 10000.0
	var invalid := State.from_dict(invalid_record, record.world, catalog)
	_check(Repository.save(path, invalid).code == "invalid_document", "invalid state cannot replace a good file")
	_check(FileAccess.get_file_as_bytes(path) == before, "rejected invalid save is non-mutating")
	var invalid_path := directory.path_join("invalid.json")
	_write(invalid_path, JSON.stringify(invalid_record))
	_check(Repository.load_state(invalid_path, record.world, catalog).code == "invalid_document", "raw injection still enforces full geometry and ownership validation")
	_write(invalid_path, "[]")
	_check(Repository.load_state(invalid_path, record.world, catalog).code == "invalid_document", "array is not accepted as a port record")
	_check(Repository.save("res://forbidden-port.json", _fresh()).code == "invalid_path", "repository cannot overwrite project assets")
	_check(Repository.save("relative.json", _fresh()).code == "invalid_path", "ambiguous relative save path is rejected")
	_check(Repository.load_state(directory.path_join("missing.json"), record.world, catalog).code == "not_found", "missing document reports a clear error")


func _test_computed_precision() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19737
	var value := record.duplicate(true)
	var custom_values: Array = []
	for index in 128: custom_values.append(rng.randf_range(-40000, 40000) * rng.randf())
	value.origin_m = [custom_values[0], 0, custom_values[1]]
	value.placements[0].attributes.support_depth_m = absf(float(custom_values[2])) / 100.0 + 1.0
	value.placements[0].attributes.custom_values = custom_values
	value.water_regions[0].depth_m = absf(float(custom_values[3])) / 100.0 + 12.0
	var state := State.from_dict(value, record.world, catalog)
	_check(state.validation_errors.is_empty(), "computed precision fixture validates")
	var expected := state.to_dict()
	var path := directory.path_join("computed-precision.json")
	for pass_index in 3:
		var saved := Repository.save(path, state)
		_check(saved.ok, "computed snapshot passes checksum verification on save %d: %s" % [pass_index, saved.get("code", "")])
		if not saved.ok: return
		var loaded := Repository.load_state(path, record.world, catalog)
		_check(loaded.ok and loaded.snapshot == expected, "repeated file reconstruction preserves exact canonical surveyed depths and custom numbers")
		if not loaded.ok: return
		state = loaded.state
		_check(Repository._checksum(state.to_dict()) == Repository._checksum(expected), "checksum remains stable after computed-number reload")


func _fresh() -> RefCounted:
	return State.from_dict(record, record.world, catalog)


func _dock_command(state: RefCounted) -> Dictionary:
	return {"command_id": "repository-dock", "expected_revision": int(state.to_dict().revision),
		"actor_company_id": "company-a", "kind": "dock", "payload": {"vessel_id": "ship-a", "berth_id": state.derived_berths()[0].id}}


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _same(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)


func _cleanup() -> void:
	# Delete only files this fixture created in its unique, non-recursive directory.
	var access := DirAccess.open(directory)
	if access == null: return
	for filename in access.get_files(): DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(filename)))
	for dirname in access.get_directories(): DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(dirname)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
