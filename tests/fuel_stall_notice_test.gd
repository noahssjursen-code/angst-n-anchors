extends SceneTree

## Lane A — RUNNING DRY, and the fact that until 2026-08-16 it happened in
## silence.
##
## `BoatBody.fuel_depleted` was emitted when the tank crossed to empty and had
## ZERO subscribers anywhere in the repository. `PropulsionComponent` `return`s
## at `fuel_pct <= 0.0`, so the boat stopped answering the throttle and nothing
## said why (REALITY §3d — a value with no consumer is not delivered).
##
## Everything here runs through the PRODUCTION wire and nothing is hand-wired:
## the vessel is added to the live tree, `GameState`'s own `node_added` sweep
## finds its `BoatController`, and `_wire_boat` is reached the way it is reached
## in a game (REALITY §3 — assert against the path that can break, not the
## artefact in the middle). The autoload instances are real: `--script` registers
## no compile-time GLOBALS, but the autoload NODES exist and resolve by path
## (CONVENTIONS §2), which is why this is lane A and not lane B.
##
## The last hop, `LocalPlayerView.ship_notice_requested` → `ShipHud.show_toast`
## → `BrandToast`, is held by `ship_hud_readout_test` in lane B, where a viewport
## lives.
##
## THE STALL IS ASSERTED TOO, in the same file, because "the engine stops" and
## "the player is told" are two claims and a test for one is not a test for the
## other. The stall half found its own defect: the dry branch used to leave
## `delivered_thrust_n` at the last value it computed, so a stalled engine
## reported 12345.0 N indefinitely.
##
## WHAT THIS CANNOT SEE:
##
## - Whether the toast is legible, or on screen. That is `ship_hud_readout_test`.
## - Whether the ShipHud is VISIBLE when the notice fires. It is owned by
##   `BoatController` and hidden off the helm, so a boat that runs dry under
##   autopilot with the captain on deck emits this notice into a hidden panel.
##   Named in the report; not fixed here, because the answer is a design choice.
## - Anything about NPC BEHAVIOUR when it runs dry. `AutonomousVesselCaptain`
##   drives the same `PropulsionComponent` and burns the same fuel and has no
##   fuel awareness at all; what IS asserted here is that an NPC hull is wired
##   like the player's and stays SILENT, which is the false positive the first
##   version of this fix had.
## - `VesselAutopilot`. It contains no reference to fuel and disengages only on
##   arrival or a 650 m route error, so a dry boat stays "ENGAGED" with a
##   distance-to-run that never falls. Read, not run.
## - Whether the tank is the right size, or whether the burn rate makes running
##   dry a thing that happens in an hour or in a week.

const TestReport := preload("res://tests/support/test_report.gd")

var _t := TestReport.new("fuel_stall_notice_test")

var _notices: Array[Dictionary] = []
var _relayed: Array[Dictionary] = []


func _on_notice(message: String, duration_seconds: float) -> void:
	_notices.append({"message": message, "duration": duration_seconds})


func _on_relayed(message: String, duration_seconds: float) -> void:
	_relayed.append({"message": message, "duration": duration_seconds})


func _initialize() -> void:
	await process_frame
	await _check_the_wire_and_the_notice()
	_check_the_stall()
	_t.finish(self)


# ── 1 · the boat runs dry and the helmsman is told ────────────────────────────

func _check_the_wire_and_the_notice() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	var view := root.get_node_or_null("/root/LocalPlayerView")
	if not _t.check("the GameState autoload node is up", gs != null):
		return
	if not _t.check("the LocalPlayerView autoload node is up", view != null):
		return
	var ship_state := gs.get("ship") as ShipState
	if not _t.check("GameState holds a ShipState projection", ship_state != null):
		return
	_t.check(
		"ShipState.notice_requested reaches LocalPlayerView, so a notice has"
		+ " somewhere to go at all",
		ship_state.notice_requested.is_connected(view._emit_ship_notice)
	)

	var boat: BoatBody = await _spawn_wired_vessel(gs)
	PlayerVessel.mark_player_ship(boat)

	_t.check(
		"adding a vessel to the tree subscribes GameState to its fuel_depleted"
		+ " (it had NO subscriber anywhere in the repository before 2026-08-16"
		+ " — REALITY §3d)",
		boat.fuel_depleted.get_connections().size() > 0
	)

	ship_state.notice_requested.connect(_on_notice)
	view.ship_notice_requested.connect(_on_relayed)

	## Burning most of the tank must say nothing. Without this the count check
	## below passes on a wire that fires on every write (REALITY §4).
	boat.consume_fuel(60.0)
	boat.consume_fuel(30.0)
	_t.equal("burning 90 of 100 L raises no notice", _notices.size(), 0)
	_t.check("and the tank is genuinely low, not untouched", boat.get_fuel_fraction() < 0.11)

	boat.consume_fuel(10.0)
	_t.equal("crossing to empty raises exactly one notice", _notices.size(), 1)
	_t.equal("and it is relayed to LocalPlayerView", _relayed.size(), 1)
	if _notices.is_empty():
		boat.queue_free()
		return

	var first := _notices[0]
	_t.check("the notice carries a message", not str(first["message"]).strip_edges().is_empty())
	_t.check(
		"the message names fuel, so the helmsman knows which failure this is"
		+ " (the wording is the owner's — got: %s)" % first["message"],
		str(first["message"]).to_lower().contains("fuel")
	)
	_t.check(
		"the message says the engine stopped, not merely that a tank is empty",
		str(first["message"]).to_lower().contains("engine")
	)
	_t.check(
		"it is shown long enough to read (%.1f s)" % float(first["duration"]),
		float(first["duration"]) > 0.0
	)
	_t.check(
		"the relayed copy is the same message and the same duration",
		not _relayed.is_empty()
			and str(_relayed[0]["message"]) == str(first["message"])
			and is_equal_approx(float(_relayed[0]["duration"]), float(first["duration"]))
	)

	## An event, not a level. Burning against an empty tank must not repeat it —
	## the alternative is a toast sixty times a second.
	boat.consume_fuel(5.0)
	boat.consume_fuel(5.0)
	_t.equal("burning against a dry tank does not repeat the notice", _notices.size(), 1)

	## …and it is not a one-shot latch either: refuel, run dry again, be told
	## again. A `connect(…, CONNECT_ONE_SHOT)` would pass every check above.
	boat.add_fuel(100.0)
	_t.equal("refuelling raises no notice of its own", _notices.size(), 1)
	boat.consume_fuel(100.0)
	_t.equal("the SECOND time she runs dry the helmsman is told again", _notices.size(), 2)
	_t.equal("and that one is relayed too", _relayed.size(), 2)

	## EVERY vessel in the world carries a `BoatController` and burns the same
	## fuel — `CatalogHullVessel` adds one to NPC traffic unconditionally. A wire
	## that notified on any hull would toast the helm for a coaster three miles
	## away, and every check above would still have passed.
	var npc: BoatBody = await _spawn_wired_vessel(gs)
	_t.check(
		"an NPC hull is wired too, so this is a real negative and not an absent"
		+ " subscriber",
		npc.fuel_depleted.get_connections().size() > 0
	)
	npc.consume_fuel(100.0)
	_t.equal("a vessel that is not the player's runs dry in silence", _notices.size(), 2)
	PlayerVessel.unmark_player_ship(boat)
	boat.add_fuel(100.0)
	boat.consume_fuel(100.0)
	_t.equal(
		"and the player's own hull goes quiet the moment it stops being hers",
		_notices.size(), 2
	)

	ship_state.notice_requested.disconnect(_on_notice)
	view.ship_notice_requested.disconnect(_on_relayed)
	npc.queue_free()
	boat.queue_free()


## A hull with a `BoatController`, added to the live tree and given the frame
## `GameState._wire_boat`'s `call_deferred` needs to land.
func _spawn_wired_vessel(_gs: Node) -> BoatBody:
	var boat := BoatBody.new()
	boat.fuel_capacity_l = 100.0
	boat.fuel_l = 100.0
	var controller := BoatController.new()
	controller.name = "BoatController"
	boat.add_child(controller)
	## Into the live tree — `GameState._on_node_added` is what finds it.
	root.add_child(boat)
	await process_frame
	return boat


# ── 2 · the stall the notice is about ─────────────────────────────────────────

func _check_the_stall() -> void:
	var boat := BoatBody.new()
	root.add_child(boat)
	boat.fuel_capacity_l = 100.0
	boat.fuel_l = 100.0

	var prop := PropulsionComponent.new()
	prop.name = "PropulsionComponent"
	boat.add_child(prop)
	prop.fuel_burn_l_per_sec_full = 1.0
	_t.check("the propulsion component resolved its hull", prop._body != null)

	prop.throttle = -1.0
	var before := boat.fuel_l
	prop._physics_process(0.1)
	_t.check(
		"with fuel aboard, full ahead delivers thrust (%.0f N)" % prop.delivered_thrust_n,
		prop.delivered_thrust_n > 0.0
	)
	_t.check(
		"and burns fuel (%.4f L in 0.1 s)" % (before - boat.fuel_l),
		boat.fuel_l < before
	)

	boat.consume_fuel(boat.fuel_l)
	_t.equal("the tank is empty", boat.get_fuel_fraction(), 0.0)

	prop.delivered_thrust_n = 12345.0
	prop.throttle = -1.0
	prop._physics_process(0.1)
	_t.equal(
		"a dry tank at full ahead delivers no thrust — the stall itself",
		prop.delivered_thrust_n, 0.0
	)
	_t.equal("and burns nothing it does not have", boat.fuel_l, 0.0)

	## The throttle COMMAND is untouched by the stall, on purpose — the helm still
	## reads FULL AHEAD and the rudder still answers. Stated so the next reader
	## does not take the zero above as "the helm was reset".
	_t.equal("the helm command is not silently reset by the stall", prop.throttle, -1.0)

	boat.queue_free()
