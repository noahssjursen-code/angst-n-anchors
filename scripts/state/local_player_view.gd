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
##   • ship runtime state (world position, yaw, throttle stage)
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

	# Ship runtime state.
	var ship := get_active_ship() as Node3D
	if ship != null:
		var stage_idx := 1
		var ctrl := ship.get_node_or_null("BoatController") as BoatController
		if ctrl != null and ctrl.has_method("get_throttle_stage_idx"):
			stage_idx = ctrl.get_throttle_stage_idx()
		var fuel_fraction := 1.0
		var boat_body := ship as BoatBody
		if boat_body != null and boat_body.has_method("get_fuel_fraction"):
			fuel_fraction = boat_body.get_fuel_fraction()
		data.ship_runtime_state = {
			"world_pos":          ship.global_position,
			"yaw":                ship.rotation.y,
			"throttle_stage_idx": stage_idx,
			"fuel_fraction":      fuel_fraction,
			"aboard":             true,
			"helming":            is_helming(),
		}
	else:
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
		push_warning("LocalPlayerView: saved ship/contracts belong to a different generated world; coordinate state was not restored")

	# Contracts.
	if world_matches and not data.accepted_contracts.is_empty() and _registry != null and _registry.has_method("restore_accepted"):
		_registry.restore_accepted(data.accepted_contracts)
		contracts_changed.emit(get_active_contracts())

	# Ship pose — defer one frame so spawn-side code has settled.
	if world_matches and not data.ship_runtime_state.is_empty():
		call_deferred("_restore_ship_pose", data.ship_runtime_state.duplicate())


func _current_world_context() -> Dictionary:
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("get_world_context"):
		return world.call("get_world_context") as Dictionary
	return {}


## Apply saved fuel / throttle to the active ship after a berth spawn.
## Does **not** restore world position or yaw — `PortDock.dock_at_berth()` owns that.
func apply_runtime_state_to_active_ship() -> void:
	if _session == null:
		return
	var data: PlayerData = _session.data
	if data == null or data.ship_runtime_state.is_empty():
		_snapshot_active_ship_runtime()
		return
	_apply_ship_runtime_state(data.ship_runtime_state.duplicate(), false)
	_snapshot_active_ship_runtime()


func _restore_ship_pose(state: Dictionary) -> void:
	## Mid-ocean / mid-voyage resume: spawn the active vessel if missing, then
	## put the captain back on deck at the saved pose.
	var ship := get_active_ship() as BoatBody
	if ship == null:
		ship = _spawn_saved_active_vessel(state)
	if ship == null:
		return
	_apply_ship_runtime_state(state, true)
	if bool(state.get("aboard", true)):
		_place_player_on_ship_deck(ship)
		if bool(state.get("helming", false)):
			call_deferred("_resume_helm", ship)


func _spawn_saved_active_vessel(state: Dictionary) -> BoatBody:
	if _session == null or _session.data == null:
		return null
	var record: Dictionary = _session.data.active_vessel
	if record.is_empty():
		return null
	var world := get_tree().get_first_node_in_group("world") as Node
	if world == null:
		return null
	PlayerVessel.replace_before_spawn(get_tree())
	var boat := VesselSpawn.instantiate_from_record(record)
	if boat == null:
		return null
	boat.name = "PlayerShip"
	world.add_child(boat)
	PlayerVessel.mark_player_ship(boat)
	var pos_raw: Variant = state.get("world_pos", null)
	if typeof(pos_raw) == TYPE_VECTOR3:
		boat.global_position = pos_raw
	boat.rotation.y = float(state.get("yaw", 0.0))
	if boat.has_method("place_at_waterline"):
		boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	VesselSpawn.apply_identity(boat, record)
	return boat


func _place_player_on_ship_deck(ship: BoatBody) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or ship == null:
		return
	var deck_y := 1.4
	if ship.hull_stations != null and ship.hull_stations.deck_y > 0.0:
		deck_y = ship.hull_stations.deck_y + 0.25
	elif ship.depth_m > 0.0:
		deck_y = ship.depth_m * 0.85
	# Slightly aft of amidships so the player is clearly on deck.
	var local := Vector3(0.0, deck_y, maxf(ship.length_m * 0.08, 1.2))
	player.global_position = ship.to_global(local)
	player.rotation.y = ship.rotation.y


func _resume_helm(ship: BoatBody) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var ctrl := ship.get_node_or_null("BoatController") as BoatController
	if ctrl != null and ctrl.has_method("activate"):
		ctrl.activate()


func _apply_ship_runtime_state(state: Dictionary, restore_transform: bool) -> void:
	var ship := get_active_ship() as Node3D
	if ship == null:
		return
	if restore_transform:
		var pos_raw: Variant = state.get("world_pos", null)
		if typeof(pos_raw) == TYPE_VECTOR3:
			ship.global_position = pos_raw
		ship.rotation.y = float(state.get("yaw", 0.0))
		var boat_body := ship as BoatBody
		if boat_body != null and boat_body.has_method("place_at_waterline"):
			boat_body.place_at_waterline(WaveSurface.WATER_LEVEL)
	# Restore fuel level if persisted (defaults to 1.0 = full tank for
	# pre-v2 saves and freshly-commissioned ships).
	if state.has("fuel_fraction"):
		var boat := ship as BoatBody
		if boat != null:
			boat.fuel_l = boat.fuel_capacity_l * float(state["fuel_fraction"])
	if state.has("throttle_stage_idx"):
		var ctrl := ship.get_node_or_null("BoatController") as BoatController
		if ctrl != null and ctrl.has_method("set_throttle_stage_idx"):
			ctrl.set_throttle_stage_idx(int(state["throttle_stage_idx"]))


func _snapshot_active_ship_runtime() -> void:
	if _session == null:
		return
	var data: PlayerData = _session.data
	if data == null:
		return
	var ship := get_active_ship() as Node3D
	if ship == null:
		data.ship_runtime_state = {}
		return
	var stage_idx := 1
	var ctrl := ship.get_node_or_null("BoatController") as BoatController
	if ctrl != null and ctrl.has_method("get_throttle_stage_idx"):
		stage_idx = ctrl.get_throttle_stage_idx()
	var fuel_fraction := 1.0
	var boat_body := ship as BoatBody
	if boat_body != null and boat_body.has_method("get_fuel_fraction"):
		fuel_fraction = boat_body.get_fuel_fraction()
	data.ship_runtime_state = {
		"world_pos":          ship.global_position,
		"yaw":                ship.rotation.y,
		"throttle_stage_idx": stage_idx,
		"fuel_fraction":      fuel_fraction,
		"aboard":             true,
		"helming":            is_helming(),
	}
