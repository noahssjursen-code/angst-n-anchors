extends Node

## Autoload — register as "PlayerSession".
## Single source of truth for the active player's state.
##
## DB-readiness: all game code calls PlayerSession — never PlayerData directly.
## Local saves go through PlayerSaveStore; swap load/save there for a server
## fetch when accounts arrive. Nothing else in the game needs to change.

## Fictional ledger currency — abstract enough to fit any era or tone.
const CURRENCY_SYMBOL := PlayerData.CURRENCY_SYMBOL
const CURRENCY_NAME   := PlayerData.CURRENCY_NAME


static func format_money(amount: int) -> String:
	return PlayerData.format_money(amount)

signal marks_changed(new_balance: int)
signal company_changed(summary: Dictionary)
signal data_loaded(data: PlayerData)
signal save_completed(success: bool)
signal vessels_synced()
signal remote_load_completed(captain_id: String, success: bool, message: String)
signal remote_save_conflict(captain_id: String, current_revision: int)

enum PersistenceMode { NONE, LOCAL, REMOTE }

var data: PlayerData = PlayerData.new()
var company_service := CompanyService.new()

## Test harnesses may opt a manually-created session into isolated persistence.
## The autoload remains read/write-disabled in every res://tests/ process.
var allow_test_persistent_io: bool = false
var _save_pending: bool = false
var _persistent_io_enabled: bool = true
var persistence_mode: PersistenceMode = PersistenceMode.NONE
var _remote_save_client := RemotePlayerSaveClient.new()
var _remote_profile: Dictionary = {}
var _remote_captain_ready := false

# ── Autosave heartbeat (Phase 10 of the overnight refactor) ──────────────────
## Every AUTOSAVE_INTERVAL_S of real wall-clock time we force a flush, even
## if no event-driven save was requested. Insurance against crashes / power
## loss / OS-killing-the-process.
const AUTOSAVE_INTERVAL_S : float = 60.0
var _autosave_clock: float = 0.0
var _marks_sync_pending: bool = false
var _marks_sync_in_flight: bool = false


func _ready() -> void:
	_remote_save_client.loaded.connect(_on_remote_document_loaded)
	_remote_save_client.saved.connect(_on_remote_document_saved)
	_remote_save_client.save_conflict.connect(_on_remote_document_conflict)
	_remote_save_client.request_failed.connect(_on_remote_document_failed)
	_remote_save_client.authentication_required.connect(_on_remote_authentication_required)
	_persistent_io_enabled = allow_test_persistent_io or not _is_test_script_process()
	if not _persistent_io_enabled:
		# Unit-test scripts must never read or overwrite the developer's live
		# player profile, even if a failed test process remains alive.
		data = PlayerData.new()
		company_service.bind(data)
		set_process(false)
		data_loaded.emit(data)
		return
	if OS.get_cmdline_args().has("--wipe-player-data"):
		if not PlayerSaveStore.wipe_all_local_data():
			push_error("PlayerSession: --wipe-player-data failed")
	LocalCaptainStore.ensure_migrated()
	# Title screen owns which captain is active; boot with a clean empty ledger.
	LocalCaptainStore.clear_active()
	data = PlayerData.new()
	company_service.bind(data)
	data_loaded.emit(data)
	call_deferred("_connect_economy")


func _process(delta: float) -> void:
	_autosave_clock += delta
	if _autosave_clock >= AUTOSAVE_INTERVAL_S:
		_autosave_clock = 0.0
		save_now()
	if _marks_sync_pending and not _marks_sync_in_flight:
		_sync_marks_to_server()


func _exit_tree() -> void:
	if _persistent_io_enabled:
		_flush_save()


func _notification(what: int) -> void:
	if not _persistent_io_enabled:
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED:
			_flush_save()


# ── Economy API ───────────────────────────────────────────────────────────────

func earn_marks(
	amount: int,
	category: String = "gameplay_income",
	description: String = "Gameplay income",
	related_entity_id: String = "",
) -> void:
	if amount <= 0:
		return
	_ensure_company_authority()
	var result := company_service.post_transaction({
		"request_id": PlayerData.new_uuid(),
		"amount_marks": amount,
		"category": category,
		"description": description,
		"related_entity_id": related_entity_id,
		"count_as_earned": true,
	})
	if not bool(result.get("ok", false)):
		push_warning("PlayerSession: income transaction rejected: %s" % str(result.get("code", "unknown")))
		return
	marks_changed.emit(data.marks)
	company_changed.emit(company_service.company_summary())
	_request_save()
	_request_marks_server_sync()


func spend_marks(
	amount: int,
	category: String = "gameplay_expense",
	description: String = "Gameplay expense",
	related_entity_id: String = "",
) -> bool:
	if amount <= 0:
		return true
	_ensure_company_authority()
	var result := company_service.post_transaction({
		"request_id": PlayerData.new_uuid(),
		"amount_marks": -amount,
		"category": category,
		"description": description,
		"related_entity_id": related_entity_id,
	})
	if not bool(result.get("ok", false)):
		return false
	marks_changed.emit(data.marks)
	company_changed.emit(company_service.company_summary())
	_request_save()
	_request_marks_server_sync()
	return true


func get_marks() -> int:
	return data.marks


func set_display_name(name: String) -> void:
	var trimmed := name.strip_edges()
	if trimmed.is_empty():
		return
	data.display_name = trimmed
	data_loaded.emit(data)
	_request_save()


func set_appearance(appearance: CharacterAppearance) -> void:
	if appearance == null:
		return
	data.appearance = appearance
	data_loaded.emit(data)
	_request_save()


func set_captain_profile(captain_id: String, display_name: String, marks: int, appearance: CharacterAppearance) -> void:
	var new_captain_id := captain_id.strip_edges()
	if new_captain_id.is_empty():
		push_error("PlayerSession: multiplayer captain profile requires a UUID")
		return
	# Identity is UUID-based, never display-name-based. Selecting or creating a
	# different UUID starts from a clean cache before that captain's server pull.
	if data == null or str(data.captain_id) != new_captain_id:
		data = PlayerData.new()
		data.account_id = _remote_account_id()
	data.captain_id = new_captain_id
	var trimmed := display_name.strip_edges()
	if not trimmed.is_empty():
		data.display_name = trimmed
	data.marks = marks
	if appearance != null:
		data.appearance = appearance
	company_service.bind(data)
	data_loaded.emit(data)
	_request_save()
	VesselSync.pull_captain_vessel(self)


func notify_vessels_synced() -> void:
	vessels_synced.emit()


## Drop all per-captain runtime state when the active roster entry is deleted.
## Autoload consumers (including FreightService) reset from data_loaded.
func clear_active_captain() -> void:
	persistence_mode = PersistenceMode.NONE
	_remote_profile.clear()
	_remote_captain_ready = false
	_remote_save_client.setup(self, "", "")
	LocalCaptainStore.clear_active()
	data = PlayerData.new()
	company_service.bind(data)
	data_loaded.emit(data)


func begin_new_captain(
	display_name: String,
	appearance: CharacterAppearance,
	home_port_id: String = "port-home",
	account_id: String = "",
	world_seed: int = 0,
	company_name: String = "",
	brand_color: Color = Color("2f7f83"),
	starter_vessel: String = "fishing",
	captain_id: String = "",
) -> void:
	if persistence_mode != PersistenceMode.REMOTE:
		persistence_mode = PersistenceMode.LOCAL
	data = PlayerData.new()
	var id := account_id.strip_edges()
	data.account_id = id if not id.is_empty() else PlayerData.new_uuid()
	data.captain_id = captain_id.strip_edges()
	data.marks = 0
	data.total_marks_earned = 0
	data.owned_vessels = []
	data.active_vessel = {}
	data.ship_runtime_state = {}
	var trimmed := display_name.strip_edges()
	data.display_name = trimmed if not trimmed.is_empty() else "Captain"
	data.appearance = appearance if appearance != null else CharacterAppearance.default_appearance()
	var home := home_port_id.strip_edges()
	data.home_port_id = home if not home.is_empty() else "port-home"
	if world_seed > 0:
		var settings := get_node_or_null("/root/GameSettings")
		var size_m := 40000.0
		var preset := "standard"
		if settings != null:
			size_m = float(settings.get("map_world_size_m"))
			preset = str(settings.get("map_world_preset"))
		data.world_context = {
			"seed": world_seed,
			"world_size_m": size_m,
			"world_preset": preset,
			"generation_version": 0,
			"weather_generation_version": 3,
			"layout_checksum": "",
		}
	company_service.bind(data)
	var resolved_company_name := company_name.strip_edges()
	if resolved_company_name.is_empty():
		resolved_company_name = "%s Maritime" % data.display_name
	var create_result := company_service.create_company({
		"request_id": "onboarding:%s" % data.account_id,
		"company_name": resolved_company_name,
		"brand_color": brand_color.to_html(false),
		"starter_vessel": starter_vessel,
	})
	if not bool(create_result.get("ok", false)):
		push_error("PlayerSession: company onboarding failed: %s" % str(create_result.get("message", "unknown")))
	data_loaded.emit(data)
	company_changed.emit(company_service.company_summary())
	save_now()


func get_company_summary() -> Dictionary:
	_ensure_company_authority()
	return company_service.company_summary()


func store_company_inventory(command: Dictionary) -> Dictionary:
	_ensure_company_authority()
	var result := company_service.store_inventory(command)
	_company_mutation_completed(result)
	return result


func reserve_company_inventory(command: Dictionary) -> Dictionary:
	_ensure_company_authority()
	var result := company_service.reserve_inventory(command)
	_company_mutation_completed(result)
	return result


func withdraw_company_inventory(command: Dictionary) -> Dictionary:
	_ensure_company_authority()
	var result := company_service.withdraw_inventory(command)
	_company_mutation_completed(result)
	return result


func _company_mutation_completed(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	company_changed.emit(company_service.company_summary())
	_request_save()


func _ensure_company_authority() -> void:
	if company_service == null:
		company_service = CompanyService.new()
	company_service.bind(data)


## Singleplayer owns the local ledger. Drop the Postgres captain link so vessel
## sync can never replace owned_vessels with the server fleet mid-session.
func begin_offline_voyage() -> void:
	persistence_mode = PersistenceMode.LOCAL
	var config := get_node_or_null("/root/ServerConfig") as Node
	if config != null:
		config.set("is_multiplayer_mode", false)
	if data != null and not str(data.captain_id).is_empty():
		if str(data.account_id).is_empty():
			data.account_id = str(data.captain_id)
		data.captain_id = ""
		save_now()


## Multiplayer durability belongs to the selected server. Local captain slots
## and vessel archives must never become an accidental second authority.
func begin_remote_voyage(captain_id: String = "", new_document: bool = false) -> void:
	persistence_mode = PersistenceMode.REMOTE
	_save_pending = false
	_remote_captain_ready = new_document and not captain_id.strip_edges().is_empty()
	LocalCaptainStore.clear_active()
	var config := get_node_or_null("/root/ServerConfig") as Node
	if config != null:
		config.set("is_multiplayer_mode", true)
	var base_url := ServerConfig.get_http_base_url()
	_remote_save_client.setup(self, base_url, captain_id, new_document)


## Load an account-owned captain document before entering shared waters. The
## roster row is deliberately kept separate: it is the canonical server view
## for identity and balance, while the document stores richer player progress.
func load_remote_captain(profile: Dictionary) -> bool:
	var captain_id := str(profile.get("id", "")).strip_edges()
	if captain_id.is_empty() or _remote_account_id().is_empty():
		return false
	_remote_profile = profile.duplicate(true)
	begin_remote_voyage(captain_id, false)
	_remote_save_client.load_document()
	return true


func is_remote_captain_ready(captain_id: String = "") -> bool:
	if persistence_mode != PersistenceMode.REMOTE or not _remote_captain_ready:
		return false
	var expected := captain_id.strip_edges()
	return expected.is_empty() or (data != null and str(data.captain_id) == expected)


func is_remote_voyage() -> bool:
	return persistence_mode == PersistenceMode.REMOTE


func add_distance_sailed(delta_m: float) -> void:
	if delta_m <= 0.0:
		return
	data.distance_sailed_m += delta_m
	_request_save()


func has_local_save() -> bool:
	return LocalCaptainStore.has_any() or PlayerSaveStore.has_save()


func save_now() -> bool:
	if not _persistent_io_enabled:
		return true
	if persistence_mode == PersistenceMode.REMOTE:
		_snapshot_world_state()
		return _queue_remote_save()
	# The title screen starts with an empty PlayerData. Never manufacture an
	# identity or save slot until the player creates/loads a local captain.
	if not LocalCaptainStore.has_active():
		return true
	# Let LocalPlayerView capture in-world state (contracts, ship pose,
	# world clock) into PlayerData before we serialise. If LocalPlayerView
	# is the caller, it skips this leg to avoid infinite recursion.
	_snapshot_world_state()
	return _flush_save()


## The only write path for a configured vessel. It updates the generic ledger,
## writes the complete player JSON atomically, then reads it back before success.
## Hull-specific code must never own persistence.
func persist_vessel_configuration(record: Dictionary, make_active: bool = false) -> bool:
	if data == null or record.is_empty():
		return false
	if persistence_mode != PersistenceMode.REMOTE:
		_ensure_local_identity()
	var safe := PlayerData.ledger_vessel_record(VesselSpawn.normalize_record(record))
	var uid := str(safe.get("uid", "")).strip_edges()
	var layout_raw: Variant = safe.get("brick_layout", null)
	if uid.is_empty() or typeof(layout_raw) != TYPE_DICTIONARY:
		push_error("PlayerSession: refused invalid configured vessel record")
		return false
	var hull_id := str(safe.get("hull_id", ""))
	var registration_id := str(safe.get("registration_id", ""))
	var compliance := VesselCompliance.validate(
		BrickLayout.from_dict(layout_raw as Dictionary),
		hull_id,
		registration_id,
		HullRegistry.make_grid(hull_id),
	)
	if not bool(compliance.get("ok", false)):
		var findings: PackedStringArray = compliance.get("errors", PackedStringArray())
		push_error(
			"PlayerSession: refused uncertified vessel uid=%s — %s"
			% [uid, " · ".join(findings)]
		)
		return false
	if not _persistent_io_enabled:
		data.upsert_owned_vessel(safe)
		return true
	if persistence_mode == PersistenceMode.REMOTE:
		data.upsert_owned_vessel(safe)
		if make_active:
			data.set_active_vessel(safe)
		if str(safe.get("server_vessel_id", "")).is_empty():
			VesselSync.ensure_vessel_registered(self, safe)
		else:
			VesselSync.push_brick_layout(self, safe)
		return true
	if not VesselArchive.save_record(_vessel_owner_id(), safe):
		push_error("PlayerSession: failed per-vessel archive uid=%s" % uid)
		return false
	data.upsert_owned_vessel(safe)
	if make_active:
		data.set_active_vessel(safe)
	if not save_now():
		push_error("PlayerSession: failed to write configured vessel uid=%s" % uid)
		return false

	var disk_data := PlayerSaveStore.load_player()
	var disk_record := disk_data.find_owned_vessel(uid)
	if disk_record.is_empty():
		push_error("PlayerSession: configured vessel missing after disk readback uid=%s" % uid)
		return false
	var expected_layout := VesselSpawn.brick_layout_of(safe)
	var disk_layout := VesselSpawn.brick_layout_of(disk_record)
	if not PlayerData.json_equivalent(disk_layout, expected_layout):
		push_error("PlayerSession: configured vessel layout failed disk readback uid=%s" % uid)
		return false
	if make_active and str(disk_data.active_vessel.get("uid", "")) != uid:
		push_error("PlayerSession: active configured vessel failed disk readback uid=%s" % uid)
		return false
	return true


## Pull world-state snapshots into PlayerData before each save flush.
## Called from save_now() and the autosave heartbeat (Phase 10).
func _snapshot_world_state() -> void:
	var view := get_node_or_null("/root/LocalPlayerView")
	if view == null or _snapshot_in_progress:
		return
	_snapshot_in_progress = true
	if view.has_method("_snapshot_into_player_data"):
		view._snapshot_into_player_data()
	_snapshot_in_progress = false


# Re-entrancy guard so LocalPlayerView -> save_now() -> _snapshot doesn't loop.
var _snapshot_in_progress: bool = false


# ── Persistence ───────────────────────────────────────────────────────────────

func _load_from_disk() -> void:
	var envelope := PlayerSaveStore.load_envelope()
	var player_raw: Variant = envelope.get("player", {})
	if typeof(player_raw) == TYPE_DICTIONARY:
		_load_data(player_raw as Dictionary)
	else:
		_load_data({})


## Hydrate session from a dictionary (local save, dev tools, or future auth).
func _load_data(raw: Dictionary = {}) -> void:
	data = PlayerData.from_dict(raw) if not raw.is_empty() else PlayerData.new()
	company_service.bind(data)
	if persistence_mode != PersistenceMode.REMOTE:
		_ensure_local_identity()
		_restore_vessel_archives()
	data_loaded.emit(data)
	if not data.captain_id.is_empty():
		call_deferred("_maybe_backfill_vessels")


func _maybe_backfill_vessels() -> void:
	var config := get_node_or_null("/root/ServerConfig") as Node
	if config == null or not bool(config.get("is_multiplayer_mode")):
		return
	if data.captain_id.is_empty():
		return
	VesselSync.pull_captain_vessel(self)


func _request_save() -> void:
	if not _persistent_io_enabled:
		return
	if _save_pending:
		return
	_save_pending = true
	call_deferred("_flush_save")


func _flush_save() -> bool:
	if not _persistent_io_enabled:
		return true
	_save_pending = false
	if persistence_mode == PersistenceMode.REMOTE:
		return _queue_remote_save()
	if not LocalCaptainStore.has_active():
		save_completed.emit(true)
		return true
	_ensure_local_identity()
	_restore_vessel_archives()
	var owner_id := _vessel_owner_id()
	for entry_raw in data.owned_vessels:
		if typeof(entry_raw) == TYPE_DICTIONARY:
			if not VesselArchive.save_record(owner_id, entry_raw as Dictionary):
				push_error("PlayerSession: refused player save because vessel archive failed")
				save_completed.emit(false)
				return false
	var ok := PlayerSaveStore.save_player(data)
	if ok:
		LocalCaptainStore.touch_index_from_player(data)
	save_completed.emit(ok)
	return ok


func _ensure_local_identity() -> void:
	if data == null:
		return
	if str(data.captain_id).is_empty() and str(data.account_id).is_empty():
		data.account_id = PlayerData.new_uuid()


func _vessel_owner_id() -> String:
	if data == null:
		return ""
	var captain_id := str(data.captain_id).strip_edges()
	return captain_id if not captain_id.is_empty() else str(data.account_id).strip_edges()


func _restore_vessel_archives() -> void:
	if data == null or persistence_mode == PersistenceMode.REMOTE:
		return
	for archived_raw in VesselArchive.load_records(_vessel_owner_id()):
		if typeof(archived_raw) != TYPE_DICTIONARY:
			continue
		var archived := archived_raw as Dictionary
		var uid := str(archived.get("uid", ""))
		var current := data.find_owned_vessel(uid)
		if current.is_empty():
			data.upsert_owned_vessel(archived)
			continue
		var merged := PlayerData.merge_vessel_record(archived, current)
		# An empty/stale current row may not erase a configured archive.
		if _layout_has_configuration(VesselSpawn.brick_layout_of(archived)) \
				and not _layout_has_configuration(VesselSpawn.brick_layout_of(current)):
			merged["brick_layout"] = VesselSpawn.brick_layout_of(archived)
		data.upsert_owned_vessel(merged)


func _queue_remote_save() -> bool:
	if data == null or not _remote_captain_ready or not _remote_save_client.is_ready():
		return false
	var queued := _remote_save_client.queue_save(_remote_document_state(), PlayerSaveStore.SAVE_VERSION)
	if not queued:
		save_completed.emit(false)
	return queued


func _on_remote_document_loaded(state: Dictionary, _format_version: int, _found: bool) -> void:
	if persistence_mode != PersistenceMode.REMOTE:
		return
	data = PlayerData.from_dict(state) if not state.is_empty() else PlayerData.new()
	# Normalize the document before overlaying server projections. CompanyService
	# mirrors its account balance back to PlayerData.marks during bind, so the
	# authoritative roster balance must be applied last.
	company_service.bind(data)
	_apply_remote_profile()
	_remote_captain_ready = true
	data_loaded.emit(data)
	remote_load_completed.emit(str(data.captain_id), true, "")
	VesselSync.pull_captain_vessel(self)


func _apply_remote_profile() -> void:
	var captain_id := str(_remote_profile.get("id", "")).strip_edges()
	data.account_id = _remote_account_id()
	data.captain_id = captain_id
	var display_name := str(_remote_profile.get("display_name", "Captain")).strip_edges()
	data.display_name = display_name if not display_name.is_empty() else "Captain"
	data.marks = int(_remote_profile.get("marks", data.marks))
	var company_account_raw: Variant = data.company.get("account", {})
	var company_account := (
		(company_account_raw as Dictionary).duplicate(true)
		if company_account_raw is Dictionary
		else {}
	)
	company_account["balance_marks"] = data.marks
	data.company["account"] = company_account
	data.appearance = RemoteCaptainClient.new().parse_appearance(
		_remote_profile.get("appearance_json", _remote_profile.get("appearance", {}))
	)
	var home_port_id := str(_remote_profile.get("home_port_id", "")).strip_edges()
	if not home_port_id.is_empty():
		data.home_port_id = home_port_id
	# These records have dedicated authoritative server projections. A stale
	# captain document may never resurrect a deleted vessel or change its layout.
	data.owned_vessels = []
	data.active_vessel = {}


## Only progress which does not yet have its own server projection belongs in
## the captain document. Vessel ownership/layout and runtime ship state are
## persisted through the vessel service; duplicating them here lets an old
## document resurrect deleted ships after a reconnect.
func _remote_document_state() -> Dictionary:
	var state := data.to_dict()
	state.erase("owned_vessels")
	state.erase("active_vessel")
	state.erase("ship_runtime_state")
	return state


func _remote_account_id() -> String:
	var account := RemoteAccountCredentialStore.account_for(ServerConfig.get_http_base_url())
	return str(account.get("id", "")).strip_edges()


func _on_remote_document_saved(_revision: int) -> void:
	save_completed.emit(true)


func _on_remote_document_conflict(current_revision: int) -> void:
	_remote_captain_ready = false
	remote_save_conflict.emit(str(data.captain_id), current_revision)
	save_completed.emit(false)


func _on_remote_document_failed(message: String) -> void:
	if not _remote_captain_ready:
		remote_load_completed.emit(str(_remote_profile.get("id", "")), false, message)
	else:
		push_warning("PlayerSession: multiplayer save failed: %s" % message)
		save_completed.emit(false)


func _on_remote_authentication_required() -> void:
	_remote_captain_ready = false
	remote_load_completed.emit(str(_remote_profile.get("id", "")), false, "Your server login expired.")


static func _layout_has_configuration(layout: Dictionary) -> bool:
	var cells_raw: Variant = layout.get("cells", {})
	if typeof(cells_raw) == TYPE_DICTIONARY and not (cells_raw as Dictionary).is_empty():
		return true
	var holds_raw: Variant = layout.get("bulk_holds", [])
	if typeof(holds_raw) == TYPE_ARRAY and not (holds_raw as Array).is_empty():
		return true
	var pads_raw: Variant = layout.get("container_pads", [])
	return typeof(pads_raw) == TYPE_ARRAY and not (pads_raw as Array).is_empty()


static func _is_test_script_process() -> bool:
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		if str(args[i]).replace("\\", "/").begins_with("res://tests/"):
			return true
	return false


# ── Internal ──────────────────────────────────────────────────────────────────

func _connect_economy() -> void:
	# Contract trade is purged; marks come from other systems until trade returns.
	pass


func _request_marks_server_sync() -> void:
	## Multiplayer balance is never uploaded from a client. Economy commands
	## will change the server projection; the client only presents that result.
	_marks_sync_pending = false


func _sync_marks_to_server() -> void:
	_marks_sync_pending = false
	_marks_sync_in_flight = false
