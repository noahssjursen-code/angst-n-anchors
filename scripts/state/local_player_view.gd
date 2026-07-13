extends Node

## Per-client view of the player and their world. Single source of truth
## that UIs (WalkingHud, ShipHud, DebugDraw, dialog screens, future
## minimap) consult to ask "what is *my* player doing?".
##
## Today it just delegates to the global autoloads (PlayerSession,
## GameState, ContractRegistry) since the game is single-player. When
## multiplayer lands, this autoload becomes a per-client object that
## the network layer populates with the local player's projection of
## the world — and every UI that already routes through here keeps
## working without further changes.
##
## Why bother now: pulling UIs off direct `/root/PlayerSession` lookups
## stops new UI code from baking in single-player assumptions. The lift
## later is incremental — migrate one HUD at a time.

signal marks_changed(balance: int)
signal helm_changed(boat: Node)            # null when not helming
signal contracts_changed(contracts: Array)


# ── Current view state ───────────────────────────────────────────────────────
var _session:  Node = null
var _registry: Node = null
var _state:    Node = null
var _helmed:   Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_session  = get_node_or_null("/root/PlayerSession")
	_registry = get_node_or_null("/root/ContractRegistry")
	_state    = get_node_or_null("/root/GameState")

	if _session != null:
		if _session.has_signal("marks_changed") and not _session.marks_changed.is_connected(_emit_marks):
			_session.marks_changed.connect(_emit_marks)

	if _registry != null:
		if _registry.has_signal("contract_accepted") and not _registry.contract_accepted.is_connected(_on_contracts_changed_two):
			_registry.contract_accepted.connect(_on_contracts_changed_two)
		if _registry.has_signal("contract_completed") and not _registry.contract_completed.is_connected(_on_contracts_changed_one):
			_registry.contract_completed.connect(_on_contracts_changed_one)

	# Watch for boat controllers to learn when the player boards / leaves.
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "BoatController", true, false):
		_wire_controller(n as BoatController)


# ── Public read API ──────────────────────────────────────────────────────────
##
## **Convention**: UI code (HUDs, menus, debug overlays) should *only* read
## per-player state through this view. NPCs and gameplay-mutating systems
## (VesselSpawn, PortDock, etc.) may continue to consult the autoloads
## directly — they're the world-authority side, not a per-client view.
##
## In multiplayer this autoload becomes a per-client object the network
## layer populates with the local player's projection of the world. Every
## UI that already reads from here will keep working with no further
## changes; gameplay-mutating code stays on the (per-server) authority.

func get_marks() -> int:
	if _session == null:
		return 0
	return int(_session.get_marks())


func get_display_name() -> String:
	if _session == null:
		return ""
	return str(_session.data.display_name)


func is_helming() -> bool:
	return _helmed != null and is_instance_valid(_helmed)


## The RigidBody3D the player is currently helming, or null when on foot.
func get_helmed_boat() -> Node:
	if _helmed == null or not is_instance_valid(_helmed):
		return null
	return _helmed


## The player's commissioned ship if one is spawned (regardless of whether
## they're currently helming it). Returns null if no ship is in the world.
##
## Routes through PlayerVessel today — single-player logic; in MP this
## becomes "the local player's authoritative ship reference from the
## server projection".
func get_active_ship() -> Node:
	return PlayerVessel.find_active_ship(get_tree())


func has_active_ship() -> bool:
	return get_active_ship() != null


func get_active_contracts() -> Array:
	if _registry == null:
		return []
	return _registry.get_accepted_contracts()


## Display-port lookup. UI code wanting "what's the human-readable name
## of port X" should ask the view rather than reaching into ContractRegistry.
func get_port_display_name(port_id: String) -> String:
	if _registry == null or port_id.is_empty():
		return ""
	return str(_registry.get_port_display_name(port_id))


func get_port_position(port_id: String) -> Vector3:
	if _registry == null or port_id.is_empty():
		return Vector3(INF, INF, INF)
	return _registry.get_port_position(port_id)


# ── Wiring ───────────────────────────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if node is BoatController:
		_wire_controller(node as BoatController)


func _wire_controller(bc: BoatController) -> void:
	if bc == null:
		return
	if not bc.helm_activated.is_connected(_on_helm_on.bind(bc)):
		bc.helm_activated.connect(_on_helm_on.bind(bc))
	if not bc.helm_deactivated.is_connected(_on_helm_off):
		bc.helm_deactivated.connect(_on_helm_off)


func _on_helm_on(bc: BoatController) -> void:
	_helmed = bc.get_parent()
	helm_changed.emit(_helmed)


func _on_helm_off() -> void:
	_helmed = null
	helm_changed.emit(null)


func _emit_marks(balance: int) -> void:
	marks_changed.emit(balance)


func _on_contracts_changed_one(_a: Variant = null) -> void:
	contracts_changed.emit(get_active_contracts())


func _on_contracts_changed_two(_a: Variant = null, _b: Variant = null) -> void:
	contracts_changed.emit(get_active_contracts())


# ── Persistence (Phase 4 of the overnight refactor) ──────────────────────────
##
## Capture the per-player runtime state into the PlayerSession's PlayerData
## so the player's progress survives quit / crash / sleep.
##
## Captured here:
##   • accepted contracts (taken / delivered counts)
##   • world clock hours (so day/night picks up where it left off)
##
## Marks, lifetime stats, appearance, active_vessel record are saved by
## their own write paths (PlayerSession setters) — this just supplements.
##
## Called by PlayerSession from inside save_now() — split from the write
## itself so we don't recurse if a saver wants to call snapshot directly.
func _snapshot_into_player_data() -> void:
	if _session == null:
		return
	var data: PlayerData = _session.data
	if data == null:
		return

	# Accepted contracts.
	if _registry != null and _registry.has_method("snapshot_accepted"):
		data.accepted_contracts = _registry.snapshot_accepted()
	else:
		data.accepted_contracts = []

	# Resume-in-vessel persistence was removed. Old runtime snapshots are
	# discarded so loading always starts the captain on foot at their home port.
	data.ship_runtime_state = {}

	# World clock — game-hours since the world epoch.
	var clock := get_node_or_null("/root/WorldClock")
	if clock != null and clock.has_method("get_game_hours_elapsed"):
		data.world_clock_hours = float(clock.call("get_game_hours_elapsed"))
	# Only overwrite when a live world (or hydrated session context) exists.
	# Title-screen captain creation has no World node yet; wiping here used to
	# clear the rolled seed and cause a different map on first sail.
	var live_context := _current_world_context()
	if not live_context.is_empty() and int(live_context.get("seed", 0)) > 0:
		data.world_context = live_context


## Convenience: snapshot + write. Used by the abandon-ship flow and any
## explicit "save right now" callers. PlayerSession's save_now() already
## snapshots internally so calling it directly works too.
func save_player_state() -> void:
	if _session != null and _session.has_method("save_now"):
		_session.save_now()


## Restore the per-player snapshot. Called by World after the home port
## spawns. Contract restore is best-effort — any contract IDs that no
## longer exist are ignored. Ship pose restore only fires if the active
## vessel was successfully respawned by the existing flow.
func restore_player_state() -> void:
	if _session == null:
		return
	var data: PlayerData = _session.data
	if data == null:
		return

	# World clock.
	if data.world_clock_hours >= 0.0:
		var clock := get_node_or_null("/root/WorldClock")
		if clock != null and clock.has_method("set_game_hours_elapsed"):
			clock.call("set_game_hours_elapsed", data.world_clock_hours)

	var world_matches := WorldGenerationContext.matches(data.world_context, _current_world_context())
	if not world_matches:
		push_warning("LocalPlayerView: saved contracts belong to a different generated world and were not restored")

	# Contracts.
	if world_matches and not data.accepted_contracts.is_empty() and _registry != null and _registry.has_method("restore_accepted"):
		_registry.restore_accepted(data.accepted_contracts)
		contracts_changed.emit(get_active_contracts())

func _current_world_context() -> Dictionary:
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("get_world_context"):
		return world.call("get_world_context") as Dictionary
	return {}
