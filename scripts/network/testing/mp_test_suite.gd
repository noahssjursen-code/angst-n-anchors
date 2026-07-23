extends Node3D

## Automated multiplayer service-layer test suite. Spins up independent virtual
## clients — each hosting the REAL WorldGateway service stack — against the
## deployed server and certifies the networked building blocks: reliable state,
## transforms, lifecycle, hydration, races, and stress.
##
## All berth work happens at a fictional port id, so live gameplay berths are
## never touched, and all realtime entities live at a far corner of the world
## so no real player's area of interest ever sees them.
##
## Run headless:
##   godot --headless --path . res://scenes/showcases/mp_test_suite_showcase.tscn
## Add `-- --mp-server=local` after the scene path to target 127.0.0.1.

const VirtualClientScript = preload("res://scripts/network/testing/virtual_client.gd")
const RunnerScript = preload("res://scripts/network/testing/mp_test_runner.gd")

const DEFAULT_HTTP := "http://142.93.43.16:8080"
const DEFAULT_UDP_HOST := "142.93.43.16"
const LOCAL_HTTP := "http://127.0.0.1:8080"
const LOCAL_UDP_HOST := "127.0.0.1"
const UDP_PORT := 7777

const TEST_PORT := "mp-test-harness-port"
const BERTH_A := TEST_PORT + "/quay_alpha"
const BERTH_B := TEST_PORT + "/quay_bravo"
const BERTH_C := TEST_PORT + "/quay_charlie"
const DOOR_ID := "mp-test-harness/door-1"
const DOOR_BINDING_ID := "mp-test-harness/door-binding"
const DOOR_BURST_ID := "mp-test-harness/door-burst"
const TEST_ORIGIN := Vector3(37000.0, 0.0, 37000.0)
const PASSWORD := "mp-harness-password-1"

const UID_A1 := "mp-test-vessel-a1"
const UID_A2 := "mp-test-vessel-a2"
const UID_B1 := "mp-test-vessel-b1"

var _a: MpVirtualClient
var _b: MpVirtualClient
var _c: MpVirtualClient ## late joiner — account/session opened mid-suite
var _obs: MpVirtualClient
var _runner: MpTestRunner
var _bootstrap_ok := false
var _hud_label: RichTextLabel


func _ready() -> void:
	_build_hud()
	call_deferred("_run")


func _run() -> void:
	var http_base := DEFAULT_HTTP
	var udp_host := DEFAULT_UDP_HOST
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--mp-server=local":
			http_base = LOCAL_HTTP
			udp_host = LOCAL_UDP_HOST

	_runner = RunnerScript.new()
	_runner.name = "Runner"
	add_child(_runner)
	_runner.context = {
		"server": http_base,
		"started_at": Time.get_datetime_string_from_system(true),
		"godot": Engine.get_version_info().get("string", "?"),
		"client_commit": _git_commit(),
		"test_port": TEST_PORT,
	}
	_runner.forensics_provider = _collect_forensics
	_runner.scenario_finished.connect(_on_scenario_finished)

	_a = _make_client("alpha", http_base, udp_host)
	_b = _make_client("bravo", http_base, udp_host)
	_c = _make_client("charlie", http_base, udp_host)
	_obs = _make_client("observer", http_base, udp_host)

	_runner.add_scenario("session_bootstrap", _s_bootstrap)
	_runner.add_scenario("player_presence", _s_player_presence)
	_runner.add_scenario("berth_claim_first_candidate", _s_berth_claim)
	_runner.add_scenario("berth_contention_blocked", _s_berth_contention)
	_runner.add_scenario("berth_fallback_second_candidate", _s_berth_fallback)
	_runner.add_scenario("mooring_replication", _s_mooring)
	_runner.add_scenario("ship_transform_replication", _s_ship_replication)
	_runner.add_scenario("ship_tombstone_removal", _s_ship_tombstone)
	_runner.add_scenario("silent_drop_ghost_ttl", _s_ghost_ttl)
	_runner.add_scenario("vessel_replacement_atomic", _s_replacement)
	_runner.add_scenario("release_and_reclaim", _s_release_reclaim)
	_runner.add_scenario("interaction_broadcast_scoped", _s_interaction)
	_runner.add_scenario("state_binding_service", _s_state_binding)
	_runner.add_scenario("late_joiner_hydration", _s_late_joiner)
	_runner.add_scenario("reconnect_resume", _s_reconnect)
	_runner.add_scenario("simultaneous_berth_claim", _s_race_claim)
	_runner.add_scenario("double_submit_idempotency", _s_double_submit)
	_runner.add_scenario("logout_during_claim", _s_logout_race)
	_runner.add_scenario("simultaneous_ship_spawn", _s_race_spawn)
	_runner.add_scenario("entity_fleet_stress", _s_fleet_stress)
	_runner.add_scenario("command_burst_latency", _s_command_burst)
	_runner.add_scenario("logout_cleanup", _s_logout)

	await _runner.run_all()
	await _cleanup()
	var exit_code := _runner.finish()
	_hud_line("[b]done — see console / report file[/b]")
	if DisplayServer.get_name() == "headless":
		get_tree().quit(exit_code)


func _make_client(client_label: String, http_base: String, udp_host: String) -> MpVirtualClient:
	var vc: MpVirtualClient = VirtualClientScript.new()
	vc.name = "VC_%s" % client_label
	vc.setup(client_label, http_base, udp_host, UDP_PORT)
	add_child(vc)
	return vc


func _ship_entity_id(vc: MpVirtualClient, local_uid: String) -> String:
	return "ship:" + ("%s|%s" % [vc.captain_id(), local_uid]).sha256_text().substr(0, 32)


## Matches berth events for a vessel whether the payload rides in the event
## body or in the attached projection state.
func _vessel_event(vessel: String) -> Callable:
	return func(event: Dictionary) -> bool:
		var body := event.get("body", {}) as Dictionary
		if str(body.get("vessel_id", "")) == vessel:
			return true
		var state := (event.get("projection", {}) as Dictionary).get("state", {}) as Dictionary
		return str(state.get("vessel_id", "")) == vessel


func _entity_event(entity_id: String) -> Callable:
	return func(event: Dictionary) -> bool:
		return str((event.get("body", {}) as Dictionary).get("entity_id", "")) == entity_id


func _release(vc: MpVirtualClient, uid: String, reason: String) -> Dictionary:
	return await vc.await_command(
		WorldContracts.COMMAND_VESSEL_BERTH_RELEASE,
		{"vessel_id": vc.vessel_id(uid), "reason": reason},
	)


func _claim(vc: MpVirtualClient, uid: String, candidates: Array, replace_uid := "") -> Dictionary:
	var replace_vessel := vc.vessel_id(replace_uid) if not replace_uid.is_empty() else ""
	return await vc.await_command(
		WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body(vc.vessel_id(uid), TEST_PORT, candidates, replace_vessel),
	)


func _assigned_berth(result: Dictionary) -> String:
	return str(((result.get("data", {}) as Dictionary).get("assignment", {}) as Dictionary).get("berth_id", ""))


# ── Scenarios: bootstrap and presence ────────────────────────────────────────

func _s_bootstrap() -> void:
	var clients: Array = [
		[_a, "mp-test-alpha@harness.local", "MP Test Alpha"],
		[_b, "mp-test-bravo@harness.local", "MP Test Bravo"],
		[_obs, "mp-test-observer@harness.local", "MP Test Observer"],
	]
	for entry in clients:
		var vc := entry[0] as MpVirtualClient
		var auth: Dictionary = await vc.login_or_register(str(entry[1]), PASSWORD)
		if not _runner.check(bool(auth.get("ok")), "%s account session" % vc.label, auth):
			return
		var cap: Dictionary = await vc.ensure_captain(str(entry[2]))
		if not _runner.check(bool(cap.get("ok")), "%s captain" % vc.label, cap):
			return
	for vessel_setup in [[_a, UID_A1, "Harness Alpha One"], [_a, UID_A2, "Harness Alpha Two"], [_b, UID_B1, "Harness Bravo One"]]:
		var vc := vessel_setup[0] as MpVirtualClient
		var res: Dictionary = await vc.ensure_vessel(str(vessel_setup[1]), str(vessel_setup[2]))
		if not _runner.check(bool(res.get("ok")), "%s vessel %s" % [vc.label, vessel_setup[1]], res):
			return
	for vc: MpVirtualClient in [_a, _b, _obs]:
		var opened: Dictionary = await vc.open_world_session()
		if not _runner.check(bool(opened.get("ok")), "%s authority session" % vc.label, opened):
			return
	# Interests before any action, so scoped events can never race scope
	# activation (backend replays stale-scope windows losslessly since the
	# interest-epoch fix, but confirmed-first stays the deterministic baseline).
	var interest_sets: Array = [
		[_a, ["port:%s" % TEST_PORT]],
		[_b, ["port:%s" % TEST_PORT, "entity:%s" % DOOR_ID]],
		[_obs, ["port:%s" % TEST_PORT]],
	]
	for entry in interest_sets:
		var vc := entry[0] as MpVirtualClient
		var res: Dictionary = await vc.ensure_interests(entry[1] as Array)
		if not _runner.check(bool(res.get("ok")), "%s interest scopes" % vc.label, res):
			return
	# A previous run (or crash) may have left berth projections assigned;
	# release everything owned by the harness so scenarios are deterministic.
	for release_setup in [[_a, UID_A1], [_a, UID_A2], [_b, UID_B1]]:
		var vc := release_setup[0] as MpVirtualClient
		var res: Dictionary = await _release(vc, str(release_setup[1]), "test_setup")
		_runner.note("pre-clean release %s/%s" % [vc.label, release_setup[1]], {"ok": res.get("ok"), "code": res.get("code", "")})
	var spawn_offsets := {"alpha": Vector3.ZERO, "bravo": Vector3(6, 0, 0), "observer": Vector3(3, 0, 6)}
	for vc: MpVirtualClient in [_a, _b, _obs]:
		var udp: Dictionary = vc.udp_start()
		if not _runner.check(bool(udp.get("ok")), "%s udp socket" % vc.label, udp):
			return
		vc.set_avatar(TEST_ORIGIN + (spawn_offsets[vc.label] as Vector3))
	_bootstrap_ok = true


func _guard() -> bool:
	if not _bootstrap_ok:
		_runner.check(false, "skipped — bootstrap failed")
	return _bootstrap_ok


func _s_player_presence() -> void:
	if not _guard():
		return
	var a_seen: Dictionary = await _obs.await_snapshot_entity(_a.captain_id(), 15.0)
	_runner.check(not a_seen.is_empty(), "observer sees player alpha", a_seen)
	var b_seen: Dictionary = await _obs.await_snapshot_entity(_b.captain_id(), 15.0)
	_runner.check(not b_seen.is_empty(), "observer sees player bravo", b_seen)
	var cross: Dictionary = await _a.await_snapshot_entity(_b.captain_id(), 15.0)
	_runner.check(not cross.is_empty(), "alpha sees player bravo", cross)


# ── Scenarios: berth authority ───────────────────────────────────────────────

func _s_berth_claim() -> void:
	if not _guard():
		return
	var vessel := _a.vessel_id(UID_A1)
	var since_b := _b.mark()
	var since_obs := _obs.mark()
	var res: Dictionary = await _claim(_a, UID_A1, [BERTH_A, BERTH_B])
	if not _runner.check(bool(res.get("ok")), "alpha claim accepted", res):
		return
	_runner.check(_assigned_berth(res) == BERTH_A, "first free candidate assigned", res)
	var event_b: Dictionary = await _b.await_event(
		WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, _vessel_event(vessel), 8.0, since_b
	)
	_runner.check(not event_b.is_empty(), "bravo received berth.assigned via port scope", event_b)
	var event_obs: Dictionary = await _obs.await_event(
		WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, _vessel_event(vessel), 8.0, since_obs
	)
	_runner.check(not event_obs.is_empty(), "observer received berth.assigned via port scope", event_obs)


func _s_berth_contention() -> void:
	if not _guard():
		return
	var res: Dictionary = await _claim(_b, UID_B1, [BERTH_A])
	_runner.check(not bool(res.get("ok", false)), "bravo claim on occupied berth rejected", res)
	_runner.note("rejection code", {"code": res.get("code", ""), "message": res.get("message", "")})


func _s_berth_fallback() -> void:
	if not _guard():
		return
	var res: Dictionary = await _claim(_b, UID_B1, [BERTH_A, BERTH_B])
	if not _runner.check(bool(res.get("ok")), "bravo claim with fallback accepted", res):
		return
	_runner.check(_assigned_berth(res) == BERTH_B, "occupied candidate skipped, next assigned", res)


func _s_mooring() -> void:
	if not _guard():
		return
	var vessel := _a.vessel_id(UID_A1)
	var since := _b.mark()
	var res: Dictionary = await _a.await_command(
		WorldContracts.COMMAND_VESSEL_MOORING_SET,
		WorldContracts.vessel_mooring_body(vessel, TEST_PORT, BERTH_A, true, false),
	)
	if not _runner.check(bool(res.get("ok")), "stern line cast off accepted", res):
		return
	var changed: Dictionary = await _b.await_event(
		WorldContracts.EVENT_VESSEL_MOORING_CHANGED, _vessel_event(vessel), 8.0, since
	)
	_runner.check(not changed.is_empty(), "bravo received mooring.changed", changed)
	since = _b.mark()
	res = await _a.await_command(
		WorldContracts.COMMAND_VESSEL_MOORING_SET,
		WorldContracts.vessel_mooring_body(vessel, TEST_PORT, BERTH_A, false, false),
	)
	if not _runner.check(bool(res.get("ok")), "both lines off accepted", res):
		return
	var released: Dictionary = await _b.await_event(
		WorldContracts.EVENT_VESSEL_BERTH_RELEASED, _vessel_event(vessel), 8.0, since
	)
	_runner.check(not released.is_empty(), "casting off both lines released the berth", released)
	since = _b.mark()
	res = await _a.await_command(
		WorldContracts.COMMAND_VESSEL_MOORING_SET,
		WorldContracts.vessel_mooring_body(vessel, TEST_PORT, BERTH_A, true, true),
	)
	if not _runner.check(bool(res.get("ok")), "re-tying lines accepted", res):
		return
	var reassigned: Dictionary = await _b.await_event(
		WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, _vessel_event(vessel), 8.0, since
	)
	_runner.check(not reassigned.is_empty(), "re-tying reacquired the berth", reassigned)


# ── Scenarios: transform plane ───────────────────────────────────────────────

func _s_ship_replication() -> void:
	if not _guard():
		return
	var ship_id := _ship_entity_id(_a, "harness-ship-1")
	var meta := "vid=%s;lh=harness" % _a.vessel_id(UID_A1)
	_a.set_ship_entity(ship_id, "hull_90x24", TEST_ORIGIN + Vector3(0, 0, -30), meta)
	var seen: Dictionary = await _obs.await_snapshot_entity(ship_id, 15.0)
	if not _runner.check(not seen.is_empty(), "observer sees alpha's ship entity", seen):
		return
	_runner.check(str(seen.get("owner_id")) == _a.captain_id(), "ship owner is alpha's captain", seen)
	_runner.check(str(seen.get("type")) == "ship_hull_90x24", "ship type carries hull id", seen)
	_runner.check(str(seen.get("meta", "")).contains("vid="), "ship meta carries durable vessel id", seen)


func _s_ship_tombstone() -> void:
	if not _guard():
		return
	var ship_id := _ship_entity_id(_a, "harness-ship-1")
	var start := _obs.mark()
	_a.tombstone_entity(ship_id)
	var gone: Dictionary = await _obs.await_entity_absent(ship_id, 2500, 15.0, start)
	if not _runner.check(bool(gone.get("ok")), "tombstoned ship left observer snapshots", gone):
		return
	var lingered := float(gone.get("lingered_s", 99.0))
	_runner.note("tombstone removal latency", {"seconds": lingered})
	_runner.check(lingered <= 3.5, "tombstone removal under 3.5s", gone)


func _s_ghost_ttl() -> void:
	if not _guard():
		return
	var ship_id := _ship_entity_id(_a, "harness-ship-2")
	_a.set_ship_entity(ship_id, "hull_90x24", TEST_ORIGIN + Vector3(10, 0, -30), "vid=%s" % _a.vessel_id(UID_A2))
	var seen: Dictionary = await _obs.await_snapshot_entity(ship_id, 15.0)
	if not _runner.check(not seen.is_empty(), "observer sees second ship", seen):
		return
	var start := _obs.mark()
	_a.drop_entity_silently(ship_id)
	var gone: Dictionary = await _obs.await_entity_absent(ship_id, 3000, 40.0, start)
	_runner.check(bool(gone.get("ok")), "silently dropped ship eventually pruned", gone)
	_runner.note("ghost replica lifetime without tombstone", {"seconds": gone.get("lingered_s")})


func _s_replacement() -> void:
	if not _guard():
		return
	var old_vessel := _a.vessel_id(UID_A1)
	var new_vessel := _a.vessel_id(UID_A2)
	var since := _obs.mark()
	var res: Dictionary = await _claim(_a, UID_A2, [BERTH_A, BERTH_C], UID_A1)
	if not _runner.check(bool(res.get("ok")), "replacement claim accepted", res):
		return
	_runner.check(_assigned_berth(res) == BERTH_A, "replacement atomically reused the released berth", res)
	var released: Dictionary = await _obs.await_event(
		WorldContracts.EVENT_VESSEL_BERTH_RELEASED, _vessel_event(old_vessel), 8.0, since
	)
	_runner.check(not released.is_empty(), "old vessel release event emitted", released)
	var assigned: Dictionary = await _obs.await_event(
		WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, _vessel_event(new_vessel), 8.0, since
	)
	if not _runner.check(not assigned.is_empty(), "new vessel assignment event emitted", assigned):
		return
	_runner.check(
		int(released.get("cursor", 0)) < int(assigned.get("cursor", 0)),
		"release ordered before assignment",
		{"released_cursor": released.get("cursor"), "assigned_cursor": assigned.get("cursor")}
	)


func _s_release_reclaim() -> void:
	if not _guard():
		return
	var bravo_vessel := _b.vessel_id(UID_B1)
	var since := _obs.mark()
	var res: Dictionary = await _release(_b, UID_B1, "test_release")
	if not _runner.check(bool(res.get("ok")), "bravo release accepted", res):
		return
	var released: Dictionary = await _obs.await_event(
		WorldContracts.EVENT_VESSEL_BERTH_RELEASED, _vessel_event(bravo_vessel), 8.0, since
	)
	_runner.check(not released.is_empty(), "release event reached observer", released)
	res = await _claim(_a, UID_A1, [BERTH_B])
	if not _runner.check(bool(res.get("ok")), "released berth reclaimable by other captain", res):
		return
	_runner.check(_assigned_berth(res) == BERTH_B, "reclaim landed on freed berth", res)


# ── Scenarios: reliable state services ───────────────────────────────────────

func _s_interaction() -> void:
	if not _guard():
		return
	var since_b := _b.mark()
	var since_obs := _obs.mark()
	var res: Dictionary = await _a.await_command(
		WorldContracts.COMMAND_INTERACTION_SET,
		{"entity_id": DOOR_ID, "kind": "door", "action": "open", "state": {"open": true}},
	)
	if not _runner.check(bool(res.get("ok")), "door open accepted", res):
		return
	var event_b: Dictionary = await _b.await_event(
		WorldContracts.EVENT_INTERACTION_CHANGED, _entity_event(DOOR_ID), 8.0, since_b
	)
	if not _runner.check(not event_b.is_empty(), "subscribed client received door event", event_b):
		return
	var first_revision := int((event_b.get("projection", {}) as Dictionary).get("revision", -1))
	await get_tree().create_timer(3.0).timeout
	_runner.check(
		_obs.events_of_type(WorldContracts.EVENT_INTERACTION_CHANGED, since_obs, _entity_event(DOOR_ID)).is_empty(),
		"unsubscribed client did not receive door event"
	)
	since_b = _b.mark()
	res = await _a.await_command(
		WorldContracts.COMMAND_INTERACTION_SET,
		{"entity_id": DOOR_ID, "kind": "door", "action": "close", "state": {"open": false}},
	)
	if not _runner.check(bool(res.get("ok")), "door close accepted", res):
		return
	var second: Dictionary = await _b.await_event(
		WorldContracts.EVENT_INTERACTION_CHANGED, _entity_event(DOOR_ID), 8.0, since_b
	)
	if not _runner.check(not second.is_empty(), "second door event received", second):
		return
	var second_revision := int((second.get("projection", {}) as Dictionary).get("revision", -1))
	_runner.check(
		second_revision > first_revision, "interaction revision advanced",
		{"first": first_revision, "second": second_revision}
	)


func _s_state_binding() -> void:
	if not _guard():
		return
	var scoped: Dictionary = await _b.ensure_interests(["entity:%s" % DOOR_BINDING_ID])
	if not _runner.check(bool(scoped.get("ok")), "bravo scoped to binding door", scoped):
		return
	var actor_binding: WorldStateBinding = _a.make_state_binding(DOOR_BINDING_ID, "door")
	var viewer_binding: WorldStateBinding = _b.make_state_binding(DOOR_BINDING_ID, "door")
	var emissions: Array = []
	viewer_binding.authoritative_state_changed.connect(
		func(state: Dictionary, action: String, _event: Dictionary) -> void:
			emissions.append({"state": state, "action": action})
	)
	await get_tree().create_timer(1.0).timeout ## let both bindings hydrate
	var baseline := emissions.size()
	var rid := actor_binding.request("open", {"open": true})
	var res: Dictionary = await _a.await_command_result(rid)
	if not _runner.check(bool(res.get("ok")), "binding open request accepted", res):
		return
	var deadline := Time.get_ticks_msec() + 8000
	while emissions.size() <= baseline and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not _runner.check(emissions.size() > baseline, "viewer binding emitted authoritative state", emissions):
		return
	var last := emissions[emissions.size() - 1] as Dictionary
	_runner.check(bool((last.get("state", {}) as Dictionary).get("open", false)), "viewer state is open", last)
	rid = actor_binding.request("close", {"open": false})
	res = await _a.await_command_result(rid)
	if not _runner.check(bool(res.get("ok")), "binding close request accepted (optimistic revision)", res):
		return
	deadline = Time.get_ticks_msec() + 8000
	while emissions.size() < baseline + 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_runner.check(emissions.size() >= baseline + 2, "viewer binding emitted close", {"count": emissions.size()})
	_runner.check(viewer_binding.revision() > 0, "binding tracked stream revision", {"revision": viewer_binding.revision()})
	## Hydration idempotence: repeated projection queries must not re-emit.
	var settled := emissions.size()
	for i in 3:
		_b.gateway.query_projections("interaction", DOOR_BINDING_ID)
		await get_tree().create_timer(0.5).timeout
	_runner.check(
		emissions.size() == settled, "repeated hydration produced zero re-emissions",
		{"before": settled, "after": emissions.size()}
	)
	actor_binding.queue_free()
	viewer_binding.queue_free()


func _s_late_joiner() -> void:
	if not _guard():
		return
	var auth: Dictionary = await _c.login_or_register("mp-test-charlie@harness.local", PASSWORD)
	if not _runner.check(bool(auth.get("ok")), "charlie account session", auth):
		return
	var cap: Dictionary = await _c.ensure_captain("MP Test Charlie")
	if not _runner.check(bool(cap.get("ok")), "charlie captain", cap):
		return
	var opened: Dictionary = await _c.open_world_session()
	if not _runner.check(bool(opened.get("ok")), "charlie authority session", opened):
		return
	var scoped: Dictionary = await _c.ensure_interests(["port:%s" % TEST_PORT, "entity:%s" % DOOR_BINDING_ID])
	if not _runner.check(bool(scoped.get("ok")), "charlie interest scopes", scoped):
		return
	## Everything below happened BEFORE charlie existed — hydration must fully
	## reconstruct it from projections alone.
	var a1_assigned := func(p: Dictionary) -> bool:
		var state := (p.get("state", {}) as Dictionary)
		return str(state.get("berth_id", "")) == BERTH_B and str(state.get("status", "")) == "assigned"
	var a2_assigned := func(p: Dictionary) -> bool:
		var state := (p.get("state", {}) as Dictionary)
		return str(state.get("berth_id", "")) == BERTH_A and str(state.get("status", "")) == "assigned"
	var door_closed := func(p: Dictionary) -> bool:
		var envelope := (p.get("state", {}) as Dictionary)
		return not bool((envelope.get("state", {}) as Dictionary).get("open", true))
	var a1_projection: Dictionary = await _c.await_projection("vessel_berth", _a.vessel_id(UID_A1), a1_assigned, 10.0)
	_runner.check(not a1_projection.is_empty(), "late joiner hydrated a1 berth occupancy", a1_projection)
	var a2_projection: Dictionary = await _c.await_projection("vessel_berth", _a.vessel_id(UID_A2), a2_assigned, 10.0)
	_runner.check(not a2_projection.is_empty(), "late joiner hydrated a2 berth occupancy", a2_projection)
	var door_projection: Dictionary = await _c.await_projection("interaction", DOOR_BINDING_ID, door_closed, 10.0)
	_runner.check(not door_projection.is_empty(), "late joiner hydrated door closed state", door_projection)
	_c.close_session()


func _s_reconnect() -> void:
	if not _guard():
		return
	var reopened: Dictionary = await _b.reopen_session()
	if not _runner.check(bool(reopened.get("ok")), "bravo reconnected with fresh session", reopened):
		return
	var scoped: Dictionary = await _b.ensure_interests(
		["port:%s" % TEST_PORT, "entity:%s" % DOOR_ID, "entity:%s" % DOOR_BINDING_ID]
	)
	if not _runner.check(bool(scoped.get("ok")), "bravo scopes confirmed after reconnect", scoped):
		return
	var a2_at_berth_a := func(p: Dictionary) -> bool:
		return str(((p.get("state", {}) as Dictionary)).get("berth_id", "")) == BERTH_A
	var hydrated: Dictionary = await _b.await_projection("vessel_berth", _a.vessel_id(UID_A2), a2_at_berth_a, 10.0)
	_runner.check(not hydrated.is_empty(), "state rehydrated after reconnect", hydrated)
	var since := _b.mark()
	var res: Dictionary = await _a.await_command(
		WorldContracts.COMMAND_INTERACTION_SET,
		{"entity_id": DOOR_BINDING_ID, "kind": "door", "action": "open", "state": {"open": true}},
	)
	if not _runner.check(bool(res.get("ok")), "post-reconnect action accepted", res):
		return
	var event: Dictionary = await _b.await_event(
		WorldContracts.EVENT_INTERACTION_CHANGED, _entity_event(DOOR_BINDING_ID), 8.0, since
	)
	_runner.check(not event.is_empty(), "events flow on the new session", event)
	await _a.await_command(
		WorldContracts.COMMAND_INTERACTION_SET,
		{"entity_id": DOOR_BINDING_ID, "kind": "door", "action": "close", "state": {"open": false}},
	)


# ── Scenarios: races ─────────────────────────────────────────────────────────

func _s_race_claim() -> void:
	if not _guard():
		return
	await _release(_a, UID_A1, "race_setup")
	await _release(_b, UID_B1, "race_setup")
	for round_index in 4:
		var body_a := WorldContracts.vessel_berth_claim_body(_a.vessel_id(UID_A1), TEST_PORT, [BERTH_C])
		var body_b := WorldContracts.vessel_berth_claim_body(_b.vessel_id(UID_B1), TEST_PORT, [BERTH_C])
		var rid_a: String
		var rid_b: String
		if round_index % 2 == 0:
			rid_a = _a.send_world_command(WorldContracts.COMMAND_VESSEL_BERTH_CLAIM, body_a)
			rid_b = _b.send_world_command(WorldContracts.COMMAND_VESSEL_BERTH_CLAIM, body_b)
		else:
			rid_b = _b.send_world_command(WorldContracts.COMMAND_VESSEL_BERTH_CLAIM, body_b)
			rid_a = _a.send_world_command(WorldContracts.COMMAND_VESSEL_BERTH_CLAIM, body_a)
		var res_a: Dictionary = await _a.await_command_result(rid_a)
		var res_b: Dictionary = await _b.await_command_result(rid_b)
		var a_won := bool(res_a.get("ok", false))
		var b_won := bool(res_b.get("ok", false))
		_runner.check(
			a_won != b_won, "round %d: exactly one simultaneous claim won" % round_index,
			{"alpha_ok": a_won, "bravo_ok": b_won, "alpha_code": res_a.get("code", ""), "bravo_code": res_b.get("code", "")}
		)
		if a_won:
			await _release(_a, UID_A1, "race_round_reset")
		elif b_won:
			await _release(_b, UID_B1, "race_round_reset")


func _s_double_submit() -> void:
	if not _guard():
		return
	var fixed_rid := "mp-test:double-submit:%d" % Time.get_ticks_usec()
	var body := WorldContracts.vessel_berth_claim_body(_a.vessel_id(UID_A1), TEST_PORT, [BERTH_C])
	var since := _obs.mark()
	var first: Dictionary = await _a.await_command(
		WorldContracts.COMMAND_VESSEL_BERTH_CLAIM, body, 8.0, fixed_rid
	)
	if not _runner.check(bool(first.get("ok")), "first submit accepted", first):
		return
	_a.command_results.erase(fixed_rid)
	var second: Dictionary = await _a.await_command(
		WorldContracts.COMMAND_VESSEL_BERTH_CLAIM, body, 8.0, fixed_rid
	)
	_runner.check(bool(second.get("ok")), "replayed request id accepted", second)
	_runner.check(
		_assigned_berth(second) == _assigned_berth(first),
		"replay returned the cached assignment", {"first": _assigned_berth(first), "second": _assigned_berth(second)}
	)
	await get_tree().create_timer(2.0).timeout
	var assigned_events := _obs.events_of_type(
		WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, since, _vessel_event(_a.vessel_id(UID_A1))
	)
	_runner.check(assigned_events.size() == 1, "exactly one assignment event despite double submit", {"count": assigned_events.size()})
	await _release(_a, UID_A1, "double_submit_reset")


func _s_logout_race() -> void:
	if not _guard():
		return
	var rid := _b.send_world_command(
		WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body(_b.vessel_id(UID_B1), TEST_PORT, [BERTH_C]),
	)
	await _b.send_logout(1)
	var res: Dictionary = await _b.await_command_result(rid, 6.0)
	_runner.note("claim racing logout", {"ok": res.get("ok"), "code": res.get("code", "")})
	var reopened: Dictionary = await _b.reopen_session()
	if not _runner.check(bool(reopened.get("ok")), "bravo recovered a session after logout race", reopened):
		return
	await _b.ensure_interests(["port:%s" % TEST_PORT, "entity:%s" % DOOR_ID])
	var projection: Dictionary = await _b.await_projection("vessel_berth", _b.vessel_id(UID_B1), Callable(), 6.0)
	var status := str(((projection.get("state", {}) as Dictionary)).get("status", "released"))
	_runner.note("post-race berth state", {"status": status})
	if status == "assigned":
		var released: Dictionary = await _release(_b, UID_B1, "logout_race_cleanup")
		_runner.check(bool(released.get("ok")), "raced claim releasable — no stuck berth", released)
	var reclaim: Dictionary = await _claim(_a, UID_A1, [BERTH_C])
	_runner.check(bool(reclaim.get("ok")), "berth usable after logout race", reclaim)
	await _release(_a, UID_A1, "logout_race_reset")


func _s_race_spawn() -> void:
	if not _guard():
		return
	var ship_a := _ship_entity_id(_a, "race-ship-a")
	var ship_b := _ship_entity_id(_b, "race-ship-b")
	_a.set_ship_entity(ship_a, "hull_90x24", TEST_ORIGIN + Vector3(-20, 0, -40), "vid=%s" % _a.vessel_id(UID_A1))
	_b.set_ship_entity(ship_b, "hull_90x24", TEST_ORIGIN + Vector3(20, 0, -40), "vid=%s" % _b.vessel_id(UID_B1))
	var seen_a: Dictionary = await _obs.await_snapshot_entity(ship_a, 15.0)
	var seen_b: Dictionary = await _obs.await_snapshot_entity(ship_b, 15.0)
	_runner.check(not seen_a.is_empty() and not seen_b.is_empty(), "both simultaneous ships visible", {"a": not seen_a.is_empty(), "b": not seen_b.is_empty()})
	_runner.check(str(seen_a.get("owner_id")) == _a.captain_id(), "alpha ship ownership intact", seen_a)
	_runner.check(str(seen_b.get("owner_id")) == _b.captain_id(), "bravo ship ownership intact", seen_b)
	_a.tombstone_entity(ship_a)
	_b.tombstone_entity(ship_b)
	var gone_a: Dictionary = await _obs.await_entity_absent(ship_a, 2500, 15.0)
	var gone_b: Dictionary = await _obs.await_entity_absent(ship_b, 2500, 15.0)
	_runner.check(bool(gone_a.get("ok")) and bool(gone_b.get("ok")), "both raced ships tombstoned cleanly")


# ── Scenarios: stress ────────────────────────────────────────────────────────

func _s_fleet_stress() -> void:
	if not _guard():
		return
	const FLEET := 24
	var ids: Array[String] = []
	for i in FLEET:
		var entity_id := "ship:fleet-%02d-%s" % [i, _a.captain_id().substr(0, 8)]
		ids.append(entity_id)
		var offset := Vector3(float(i % 6) * 30.0 - 75.0, 0.0, -60.0 - floorf(float(i) / 6.0) * 30.0)
		_a.set_ship_entity(entity_id, "hull_90x24", TEST_ORIGIN + offset, "fleet=1")
	var start := Time.get_ticks_msec()
	var deadline := start + 25000
	var visible := 0
	while Time.get_ticks_msec() < deadline:
		visible = 0
		for entity_id in ids:
			if _obs.has_seen_entity(entity_id):
				visible += 1
		if visible == FLEET:
			break
		await get_tree().process_frame
	var acquisition_s := float(Time.get_ticks_msec() - start) / 1000.0
	_runner.check(visible == FLEET, "full fleet of %d visible to observer" % FLEET, {"visible": visible})
	_runner.note("fleet acquisition time", {"seconds": acquisition_s, "entities": FLEET})
	for entity_id in ids:
		_a.tombstone_entity(entity_id)
	start = Time.get_ticks_msec()
	deadline = start + 25000
	var gone := 0
	while Time.get_ticks_msec() < deadline:
		gone = 0
		var now := Time.get_ticks_msec()
		for entity_id in ids:
			var last_seen := _obs.entity_last_seen_ms(entity_id)
			if last_seen < 0 or now - last_seen >= 2500:
				gone += 1
		if gone == FLEET:
			break
		await get_tree().process_frame
	_runner.check(gone == FLEET, "full fleet tombstoned from observer", {"gone": gone})
	_runner.note("fleet teardown time", {"seconds": float(Time.get_ticks_msec() - start) / 1000.0})


func _s_command_burst() -> void:
	if not _guard():
		return
	const BURST := 20
	var scoped: Dictionary = await _b.ensure_interests(["entity:%s" % DOOR_BURST_ID])
	if not _runner.check(bool(scoped.get("ok")), "bravo scoped to burst door", scoped):
		return
	## Projections are scope-filtered even for their author (events are not), so
	## the acting client needs the entity scope to hydrate the prior revision —
	## the game's WorldStateBinding does this automatically via _retain_scope.
	var actor_scoped: Dictionary = await _a.ensure_interests(["entity:%s" % DOOR_BURST_ID])
	if not _runner.check(bool(actor_scoped.get("ok")), "alpha scoped to burst door", actor_scoped):
		return
	var initial_projection: Dictionary = await _a.await_projection("interaction", DOOR_BURST_ID, Callable(), 4.0)
	var initial_revision := int(initial_projection.get("revision", 0))
	var since := _b.mark()
	var send_times: Dictionary = {}
	var rids: Array[String] = []
	for i in BURST:
		var rid := _a.send_world_command(
			WorldContracts.COMMAND_INTERACTION_SET,
			{"entity_id": DOOR_BURST_ID, "kind": "door", "action": "toggle", "state": {"n": i}},
		)
		send_times[rid] = Time.get_ticks_msec()
		rids.append(rid)
	var latencies: Array[float] = []
	var all_ok := true
	for rid in rids:
		var res: Dictionary = await _a.await_command_result(rid, 15.0)
		if not bool(res.get("ok", false)):
			all_ok = false
		latencies.append(float(Time.get_ticks_msec() - int(send_times[rid])) / 1000.0)
	_runner.check(all_ok, "all %d burst commands accepted" % BURST)
	latencies.sort()
	_runner.note("burst command latency", {
		"p50_s": latencies[BURST / 2], "p95_s": latencies[int(float(BURST) * 0.95)], "max_s": latencies[BURST - 1],
	})
	var deadline := Time.get_ticks_msec() + 15000
	var received := 0
	while Time.get_ticks_msec() < deadline:
		received = _b.events_of_type(WorldContracts.EVENT_INTERACTION_CHANGED, since, _entity_event(DOOR_BURST_ID)).size()
		if received >= BURST:
			break
		await get_tree().process_frame
	_runner.check(received >= BURST, "all burst events delivered to subscriber", {"received": received})
	var revision_caught_up := func(p: Dictionary) -> bool:
		return int(p.get("revision", 0)) >= initial_revision + BURST
	var final_projection: Dictionary = await _a.await_projection("interaction", DOOR_BURST_ID, revision_caught_up, 8.0)
	_runner.check(
		int(final_projection.get("revision", 0)) == initial_revision + BURST,
		"stream revision advanced exactly by burst size",
		{"initial": initial_revision, "final": final_projection.get("revision", 0)}
	)


# ── Scenarios: lifecycle end ─────────────────────────────────────────────────

func _s_logout() -> void:
	if not _guard():
		return
	var start := _obs.mark()
	await _b.send_logout()
	var gone: Dictionary = await _obs.await_entity_absent(_b.captain_id(), 2500, 15.0, start)
	if _runner.check(bool(gone.get("ok")), "bravo player left observer snapshots after logout", gone):
		_runner.note("logout removal latency", {"seconds": gone.get("lingered_s")})
	var envelope := WorldContracts.command(
		"mp-test:post-logout:%d" % Time.get_ticks_usec(),
		WorldContracts.COMMAND_VESSEL_BERTH_RELEASE,
		{"vessel_id": _b.vessel_id(UID_B1), "reason": "after_logout"},
	)
	var res: Dictionary = await _b._http(HTTPClient.METHOD_POST, "/v2/commands", envelope, "bearer")
	_runner.check(int(res.get("status", 0)) == 401, "udp logout revoked the authority session", res)


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _cleanup() -> void:
	if _a != null and _a.is_session_ready():
		for uid in [UID_A1, UID_A2]:
			await _release(_a, uid, "test_teardown")
		await _a.send_logout()
	if _obs != null:
		await _obs.send_logout()
	for vc in [_a, _b, _c, _obs]:
		if vc != null:
			vc.close_session()


func _collect_forensics() -> Dictionary:
	var out := {}
	for vc in [_a, _b, _c, _obs]:
		if vc == null:
			continue
		var events: Array = []
		var tail: Array[Dictionary] = vc.recorded_events.slice(maxi(0, vc.recorded_events.size() - 8))
		for event in tail:
			events.append(event)
		var snapshot_summary := {}
		for entity_id in vc.snapshot_entities.keys():
			var info := vc.snapshot_entities[entity_id] as Dictionary
			snapshot_summary[entity_id] = {
				"type": (info.get("entity", {}) as Dictionary).get("type", ""),
				"ms_since_seen": Time.get_ticks_msec() - int(info.get("last_seen_ms", 0)),
			}
		out[vc.label] = {
			"captain_id": vc.captain_id(),
			"session_failed": vc.session_failed_code,
			"recent_events": events,
			"recent_commands": vc.command_results.values().slice(maxi(0, vc.command_results.size() - 6)),
			"snapshot_entities": snapshot_summary,
		}
	return out


func _git_commit() -> String:
	var output: Array = []
	var code := OS.execute(
		"git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short", "HEAD"], output
	)
	if code == 0 and output.size() > 0:
		return str(output[0]).strip_edges()
	return "unknown"


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.07, 0.09, 0.92)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	_hud_label = RichTextLabel.new()
	_hud_label.bbcode_enabled = true
	_hud_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_label.offset_left = 24.0
	_hud_label.offset_top = 16.0
	_hud_label.offset_right = -24.0
	_hud_label.offset_bottom = -16.0
	layer.add_child(_hud_label)
	_hud_line("[b]MP service-layer test suite[/b] — running against real server…")


func _on_scenario_finished(scenario_name: String, status: String) -> void:
	var color := "green" if status == "PASS" else ("orange" if status == "EXPECTED_FAIL" else "red")
	_hud_line("[color=%s]%s[/color]  %s" % [color, status, scenario_name])


func _hud_line(text: String) -> void:
	if _hud_label != null:
		_hud_label.append_text(text + "\n")
