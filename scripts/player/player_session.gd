extends Node

## Autoload — register as "PlayerSession".
## Single source of truth for the active player's state.
##
## DB-readiness: all game code calls PlayerSession — never PlayerData directly.
## Local saves go through PlayerSaveStore; swap load/save there for a server
## fetch when accounts arrive. Nothing else in the game needs to change.

## Fictional ledger currency — abstract enough to fit any era or tone.
const CURRENCY_SYMBOL := "ℳ"
const CURRENCY_NAME   := "Marks"


static func format_money(amount: int) -> String:
	return "%s %d" % [CURRENCY_SYMBOL, amount]

signal marks_changed(new_balance: int)
signal data_loaded(data: PlayerData)
signal save_completed(success: bool)

var data: PlayerData = PlayerData.new()

var _save_pending: bool = false


func _ready() -> void:
	_load_from_disk()
	call_deferred("_connect_registry")


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


func spend_marks(amount: int) -> bool:
	if amount <= 0:
		return true
	if data.marks < amount:
		return false
	data.marks -= amount
	marks_changed.emit(data.marks)
	_request_save()
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


func add_distance_sailed(delta_m: float) -> void:
	if delta_m <= 0.0:
		return
	data.distance_sailed_m += delta_m
	_request_save()


func has_local_save() -> bool:
	return PlayerSaveStore.has_save()


func save_now() -> bool:
	return _flush_save()


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
