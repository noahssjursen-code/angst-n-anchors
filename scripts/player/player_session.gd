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
signal data_loaded(data: PlayerData)
signal save_completed(success: bool)
signal vessels_synced()

var data: PlayerData = PlayerData.new()

## Test harnesses may opt a manually-created session into isolated persistence.
## The autoload remains read/write-disabled in every res://tests/ process.
var allow_test_persistent_io: bool = false
var _save_pending: bool = false
var _persistent_io_enabled: bool = true

# ── Autosave heartbeat (Phase 10 of the overnight refactor) ──────────────────
## Every AUTOSAVE_INTERVAL_S of real wall-clock time we force a flush, even
## if no event-driven save was requested. Insurance against crashes / power
## loss / OS-killing-the-process.
const AUTOSAVE_INTERVAL_S : float = 60.0
var _autosave_clock: float = 0.0
var _marks_sync_pending: bool = false
var _marks_sync_in_flight: bool = false


func _ready() -> void:
	_persistent_io_enabled = allow_test_persistent_io or not _is_test_script_process()
	if not _persistent_io_enabled:
		# Unit-test scripts must never read or overwrite the developer's live
		# player profile, even if a failed test process remains alive.
		data = PlayerData.new()
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
	data_loaded.emit(data)
	call_deferred("_connect_registry")


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

func earn_marks(amount: int) -> void:
	if amount <= 0:
		return
	data.marks              += amount
	data.total_marks_earned += amount
	marks_changed.emit(data.marks)
	_request_save()
	_request_marks_server_sync()


func spend_marks(amount: int) -> bool:
	if amount <= 0:
		return true
	if data.marks < amount:
		return false
	data.marks -= amount
	marks_changed.emit(data.marks)
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
		data.account_id = new_captain_id
	data.captain_id = new_captain_id
	var trimmed := display_name.strip_edges()
	if not trimmed.is_empty():
		data.display_name = trimmed
	data.marks = marks
	if appearance != null:
		data.appearance = appearance
	data_loaded.emit(data)
	_request_save()
	VesselSync.pull_captain_vessel(self)


func notify_vessels_synced() -> void:
	vessels_synced.emit()


func begin_new_captain(
	display_name: String,
	appearance: CharacterAppearance,
	home_port_id: String = "port-home",
	account_id: String = "",
	world_seed: int = 0,
) -> void:
	data = PlayerData.new()
	var id := account_id.strip_edges()
	data.account_id = id if not id.is_empty() else PlayerData.new_uuid()
	data.captain_id = ""
	data.marks = PlayerData.NEW_CAPTAIN_STARTING_MARKS
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
		data.world_context = {"seed": world_seed, "generation_version": 0, "layout_checksum": ""}
	# One hand-authored workboat on the registry so harbour deploy works immediately.
	var starter := VesselSpawn.default_owned_record()
	data.upsert_owned_vessel(starter)
	data.set_active_vessel(starter)
	data_loaded.emit(data)
	save_now()


## Singleplayer owns the local ledger. Drop the Postgres captain link so vessel
## sync can never replace owned_vessels with the server fleet mid-session.
func begin_offline_voyage() -> void:
	var config := get_node_or_null("/root/ServerConfig") as Node
	if config != null:
		config.set("is_multiplayer_mode", false)
	if data != null and not str(data.captain_id).is_empty():
		if str(data.account_id).is_empty():
			data.account_id = str(data.captain_id)
		data.captain_id = ""
		save_now()


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
	_ensure_local_identity()
	var safe := PlayerData.ledger_vessel_record(VesselSpawn.normalize_record(record))
	var uid := str(safe.get("uid", "")).strip_edges()
	var layout_raw: Variant = safe.get("brick_layout", null)
	if uid.is_empty() or typeof(layout_raw) != TYPE_DICTIONARY:
		push_error("PlayerSession: refused invalid configured vessel record")
		return false
	if not _persistent_io_enabled:
		data.upsert_owned_vessel(safe)
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
	if data == null:
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


static func _layout_has_configuration(layout: Dictionary) -> bool:
	var cells_raw: Variant = layout.get("cells", {})
	if typeof(cells_raw) == TYPE_DICTIONARY and not (cells_raw as Dictionary).is_empty():
		return true
	var zones_raw: Variant = layout.get("cargo_zones", [])
	return typeof(zones_raw) == TYPE_ARRAY and not (zones_raw as Array).is_empty()


static func _is_test_script_process() -> bool:
	var args := OS.get_cmdline_args()
	for i in range(args.size()):
		if str(args[i]).replace("\\", "/").begins_with("res://tests/"):
			return true
	return false


# ── Internal ──────────────────────────────────────────────────────────────────

func _connect_registry() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		push_error("PlayerSession: ContractRegistry autoload not found — check autoload order in Project Settings.")
		return
	if not registry.unit_delivered.is_connected(_on_unit_delivered):
		registry.unit_delivered.connect(_on_unit_delivered)
	if not registry.contract_completed.is_connected(_on_contract_completed):
		registry.contract_completed.connect(_on_contract_completed)


func _on_unit_delivered(_contract: Contract, reward: int) -> void:
	earn_marks(reward)


func _on_contract_completed(_contract: Contract) -> void:
	data.contracts_completed += 1
	_request_save()


func _request_marks_server_sync() -> void:
	if data.captain_id.is_empty():
		return
	var config := get_node_or_null("/root/ServerConfig") as Node
	if config == null or not bool(config.get("is_multiplayer_mode")):
		return
	_marks_sync_pending = true


func _sync_marks_to_server() -> void:
	if _marks_sync_in_flight or not _marks_sync_pending:
		return
	if data.captain_id.is_empty():
		_marks_sync_pending = false
		return
	var config := get_node_or_null("/root/ServerConfig") as Node
	if config == null or not bool(config.get("is_multiplayer_mode")):
		_marks_sync_pending = false
		return
	var http_url := "%s/v1/captains" % str(config.call("get_http_base_url"))
	var body := JSON.stringify({
		"id": data.captain_id,
		"marks": data.marks,
	})
	var req := HTTPRequest.new()
	add_child(req)
	_marks_sync_in_flight = true
	_marks_sync_pending = false
	req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		_marks_sync_in_flight = false
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			push_warning("PlayerSession: failed to sync marks to server (HTTP %d)" % response_code)
			_marks_sync_pending = true
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	req.request(http_url, headers, HTTPClient.METHOD_PUT, body)
