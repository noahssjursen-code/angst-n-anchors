extends Node

## Autoload — register as "PlayerSession".
## Single source of truth for the active player's state.
##
## DB-readiness: all game code calls PlayerSession — never PlayerData directly.
## When accounts arrive, replace _load_data() with a server fetch and call it
## after login. Nothing else in the game needs to change.

const CURRENCY_SYMBOL := "ℳ"
const CURRENCY_NAME   := "Marks"

signal marks_changed(new_balance: int)
signal data_loaded(data: PlayerData)

var data: PlayerData = PlayerData.new()


func _ready() -> void:
	call_deferred("_connect_registry")


# ── Economy API ───────────────────────────────────────────────────────────────

func earn_marks(amount: int) -> void:
	if amount <= 0:
		return
	data.marks             += amount
	data.total_marks_earned += amount
	marks_changed.emit(data.marks)


func spend_marks(amount: int) -> bool:
	if amount <= 0 or data.marks < amount:
		return false
	data.marks -= amount
	marks_changed.emit(data.marks)
	return true


func get_marks() -> int:
	return data.marks


# ── Future DB hook ────────────────────────────────────────────────────────────

## Swap this for a server fetch when accounts are introduced.
## Call it with the raw JSON/dict from the auth response.
func _load_data(raw: Dictionary = {}) -> void:
	data = PlayerData.from_dict(raw) if not raw.is_empty() else PlayerData.new()
	data_loaded.emit(data)


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
