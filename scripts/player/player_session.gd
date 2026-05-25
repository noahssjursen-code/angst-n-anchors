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

var _save_pending: bool = false

# ── Autosave heartbeat (Phase 10 of the overnight refactor) ──────────────────
## Every AUTOSAVE_INTERVAL_S of real wall-clock time we force a flush, even
## if no event-driven save was requested. Insurance against crashes / power
## loss / OS-killing-the-process.
const AUTOSAVE_INTERVAL_S : float = 60.0
var _autosave_clock: float = 0.0
var _marks_sync_pending: bool = false
var _marks_sync_in_flight: bool = false


func _ready() -> void:
	_load_from_disk()
	call_deferred("_connect_registry")


func _process(delta: float) -> void:
	_autosave_clock += delta
	if _autosave_clock >= AUTOSAVE_INTERVAL_S:
		_autosave_clock = 0.0
		save_now()
	if _marks_sync_pending and not _marks_sync_in_flight:
		_sync_marks_to_server()


func _exit_tree() -> void:
	_flush_save()


func _notification(what: int) -> void:
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
	data.captain_id = captain_id.strip_edges()
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


func begin_new_captain(display_name: String, appearance: CharacterAppearance) -> void:
	data = PlayerData.new()
	data.captain_id = ""
	data.marks = PlayerData.NEW_CAPTAIN_STARTING_MARKS
	data.total_marks_earned = 0
	data.owned_vessels = []
	data.active_vessel = {}
	data.ship_runtime_state = {}
	var trimmed := display_name.strip_edges()
	data.display_name = trimmed if not trimmed.is_empty() else "Captain"
	data.appearance = appearance if appearance != null else CharacterAppearance.default_appearance()
	data_loaded.emit(data)
	save_now()


func add_distance_sailed(delta_m: float) -> void:
	if delta_m <= 0.0:
		return
	data.distance_sailed_m += delta_m
	_request_save()


func has_local_save() -> bool:
	return PlayerSaveStore.has_save()


func save_now() -> bool:
	# Let LocalPlayerView capture in-world state (contracts, ship pose,
	# world clock) into PlayerData before we serialise. If LocalPlayerView
	# is the caller, it skips this leg to avoid infinite recursion.
	_snapshot_world_state()
	return _flush_save()


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
	if _save_pending:
		return
	_save_pending = true
	call_deferred("_flush_save")


func _flush_save() -> bool:
	_save_pending = false
	var ok := PlayerSaveStore.save_player(data)
	save_completed.emit(ok)
	return ok


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
	var auth := get_node_or_null("/root/AuthSession")
	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	if auth != null:
		headers = auth.auth_headers()
	req.request(http_url, headers, HTTPClient.METHOD_PUT, body)
