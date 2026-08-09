extends SceneTree

const TEST_ROOT := "user://automated_tests/remote_persistence"
const TestReport := preload("res://tests/support/test_report.gd")


func _init() -> void:
	var t := TestReport.new("remote_persistence_store_test")
	RemoteAccountCredentialStore.store_path_override = TEST_ROOT + "/account_sessions.json"
	RemoteSaveOutbox.store_path_override = TEST_ROOT + "/save_outbox.json"
	RemoteAccountCredentialStore.clear_test_storage()
	RemoteSaveOutbox.clear_test_storage()

	_test_account_server_scoping_and_recovery(t)
	_test_save_outbox_scoping_and_recovery(t)

	RemoteAccountCredentialStore.clear_test_storage()
	RemoteSaveOutbox.clear_test_storage()
	RemoteAccountCredentialStore.store_path_override = ""
	RemoteSaveOutbox.store_path_override = ""
	t.finish(self)


func _test_account_server_scoping_and_recovery(t: TestReport) -> void:
	var server_a := "https://alpha.example.test/"
	var server_b := "https://beta.example.test"
	t.check("the alpha session is stored", RemoteAccountCredentialStore.set_session(server_a, "token-alpha", {
		"id": "account-alpha",
		"email": "alpha@example.test",
	}))
	t.check("the beta session is stored", RemoteAccountCredentialStore.set_session(server_b, "token-beta", {
		"id": "account-beta",
		"email": "beta@example.test",
	}))
	t.check("the alpha token is scoped to alpha", RemoteAccountCredentialStore.token_for(server_a) == "token-alpha")
	t.check("the beta token is scoped to beta", RemoteAccountCredentialStore.token_for(server_b) == "token-beta")
	t.check(
		"the alpha account record round-trips",
		str(RemoteAccountCredentialStore.account_for(server_a).get("id", "")) == "account-alpha",
	)

	var text := _read(t, RemoteAccountCredentialStore.store_path_override)
	t.check("credential cache must never contain passwords", not text.contains("password"))
	# Another local process may replace the shared disk file. The authenticated
	# process must keep its own session until it explicitly signs out.
	_write(t, RemoteAccountCredentialStore.store_path_override, JSON.stringify({
		"https://alpha.example.test": {
			"access_token": "token-from-other-process",
			"account": {"id": "other-account"},
		},
	}))
	t.check(
		"an outside rewrite cannot displace the live session",
		RemoteAccountCredentialStore.token_for(server_a) == "token-alpha",
	)

	RemoteAccountCredentialStore.clear_runtime_cache_for_test()
	_write(t, RemoteAccountCredentialStore.store_path_override, "not valid json")
	# The backup was rotated before the beta write and still contains alpha.
	t.check(
		"a corrupt primary recovers alpha from the backup",
		RemoteAccountCredentialStore.token_for(server_a) == "token-alpha",
	)

	# A valid empty primary is authoritative; it must not resurrect the backup.
	RemoteAccountCredentialStore.clear_runtime_cache_for_test()
	_write(t, RemoteAccountCredentialStore.store_path_override, "{}")
	t.check(
		"a valid empty primary is authoritative",
		RemoteAccountCredentialStore.token_for(server_a).is_empty(),
	)


func _test_save_outbox_scoping_and_recovery(t: TestReport) -> void:
	var state_a := {"display_name": "Maren", "tutorial_seen": {"helm": true}}
	var state_b := {"display_name": "Elias", "company": {"name": "North Star"}}
	t.check("the alpha outbox entry is saved", RemoteSaveOutbox.save_entry(
		"https://alpha.example.test", "account-a", "captain-a", {
			"base_revision": 4,
			"format_version": 5,
			"latest_state": state_a,
			"sent_state": {},
		}
	))
	t.check("the beta outbox entry is saved", RemoteSaveOutbox.save_entry(
		"https://beta.example.test", "account-b", "captain-b", {
			"base_revision": 8,
			"format_version": 5,
			"latest_state": state_b,
			"sent_state": state_b,
		}
	))
	var loaded_a := RemoteSaveOutbox.load_entry("https://alpha.example.test/", "account-a", "captain-a")
	t.check("the alpha base revision round-trips", int(loaded_a.get("base_revision", -1)) == 4)
	t.check("the alpha state round-trips", loaded_a.get("latest_state", {}) == state_a)
	t.check(
		"an entry is not visible from another server",
		RemoteSaveOutbox.load_entry("https://beta.example.test", "account-a", "captain-a").is_empty(),
	)

	_write(t, RemoteSaveOutbox.store_path_override, "[")
	var recovered := RemoteSaveOutbox.load_entry("https://alpha.example.test", "account-a", "captain-a")
	t.check("a truncated outbox recovers alpha from the backup", recovered.get("latest_state", {}) == state_a)


func _read(t: TestReport, path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not t.check("%s opens for reading" % path, file != null):
		return ""
	return file.get_as_text()


func _write(t: TestReport, path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not t.check("%s opens for writing" % path, file != null):
		return
	file.store_string(content)
	file.flush()
