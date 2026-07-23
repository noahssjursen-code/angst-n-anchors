extends SceneTree

const TEST_ROOT := "user://automated_tests/remote_persistence"


func _init() -> void:
	RemoteAccountCredentialStore.store_path_override = TEST_ROOT + "/account_sessions.json"
	RemoteSaveOutbox.store_path_override = TEST_ROOT + "/save_outbox.json"
	RemoteAccountCredentialStore.clear_test_storage()
	RemoteSaveOutbox.clear_test_storage()

	_test_account_server_scoping_and_recovery()
	_test_save_outbox_scoping_and_recovery()

	RemoteAccountCredentialStore.clear_test_storage()
	RemoteSaveOutbox.clear_test_storage()
	RemoteAccountCredentialStore.store_path_override = ""
	RemoteSaveOutbox.store_path_override = ""
	print("Remote persistence store test: all checks passed")
	quit()


func _test_account_server_scoping_and_recovery() -> void:
	var server_a := "https://alpha.example.test/"
	var server_b := "https://beta.example.test"
	assert(RemoteAccountCredentialStore.set_session(server_a, "token-alpha", {
		"id": "account-alpha",
		"email": "alpha@example.test",
	}))
	assert(RemoteAccountCredentialStore.set_session(server_b, "token-beta", {
		"id": "account-beta",
		"email": "beta@example.test",
	}))
	assert(RemoteAccountCredentialStore.token_for(server_a) == "token-alpha")
	assert(RemoteAccountCredentialStore.token_for(server_b) == "token-beta")
	assert(str(RemoteAccountCredentialStore.account_for(server_a).get("id", "")) == "account-alpha")

	var text := _read(RemoteAccountCredentialStore.store_path_override)
	assert(not text.contains("password"), "credential cache must never contain passwords")
	# Another local process may replace the shared disk file. The authenticated
	# process must keep its own session until it explicitly signs out.
	_write(RemoteAccountCredentialStore.store_path_override, JSON.stringify({
		"https://alpha.example.test": {
			"access_token": "token-from-other-process",
			"account": {"id": "other-account"},
		},
	}))
	assert(RemoteAccountCredentialStore.token_for(server_a) == "token-alpha")

	RemoteAccountCredentialStore.clear_runtime_cache_for_test()
	_write(RemoteAccountCredentialStore.store_path_override, "not valid json")
	# The backup was rotated before the beta write and still contains alpha.
	assert(RemoteAccountCredentialStore.token_for(server_a) == "token-alpha")

	# A valid empty primary is authoritative; it must not resurrect the backup.
	RemoteAccountCredentialStore.clear_runtime_cache_for_test()
	_write(RemoteAccountCredentialStore.store_path_override, "{}")
	assert(RemoteAccountCredentialStore.token_for(server_a).is_empty())


func _test_save_outbox_scoping_and_recovery() -> void:
	var state_a := {"display_name": "Maren", "tutorial_seen": {"helm": true}}
	var state_b := {"display_name": "Elias", "company": {"name": "North Star"}}
	assert(RemoteSaveOutbox.save_entry("https://alpha.example.test", "account-a", "captain-a", {
		"base_revision": 4,
		"format_version": 5,
		"latest_state": state_a,
		"sent_state": {},
	}))
	assert(RemoteSaveOutbox.save_entry("https://beta.example.test", "account-b", "captain-b", {
		"base_revision": 8,
		"format_version": 5,
		"latest_state": state_b,
		"sent_state": state_b,
	}))
	var loaded_a := RemoteSaveOutbox.load_entry("https://alpha.example.test/", "account-a", "captain-a")
	assert(int(loaded_a.get("base_revision", -1)) == 4)
	assert(loaded_a.get("latest_state", {}) == state_a)
	assert(RemoteSaveOutbox.load_entry("https://beta.example.test", "account-a", "captain-a").is_empty())

	_write(RemoteSaveOutbox.store_path_override, "[")
	var recovered := RemoteSaveOutbox.load_entry("https://alpha.example.test", "account-a", "captain-a")
	assert(recovered.get("latest_state", {}) == state_a)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null)
	return file.get_as_text()


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(content)
	file.flush()
