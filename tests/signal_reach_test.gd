extends SceneTree

## Lane A — EVERY `signal` DECLARED IN `scripts/` HAS A SUBSCRIBER SOMEWHERE THE
## GAME RUNS.
##
## `state_projection_reach_test` holds the same property for the members of
## `GameState`'s projections and it is the reason this file exists: while that
## check was being built, three more instances of the class were found sitting
## OUTSIDE its reach and left live — `BoatBody.fuel_depleted` and `fuel_changed`
## with zero subscribers, so running dry was silent. A check whose scope is one
## read model cannot see a signal on a `RigidBody3D`.
##
## THE ANSWER TO "CAN IT BE EXTENDED", MEASURED RATHER THAN ASSERTED: yes, and
## the extension is RED at 59 of 178 declarations. That is not three more
## instances of the class, it is 59 — **a third of every signal this project
## declares is emitted to nobody**. They are not fixed here; fixing them is 59
## separate design questions ("should a crane's slew angle drive a gauge?") and
## this wave had one of them. What IS done stops the number growing: the list
## below is FROZEN and POLICED IN BOTH DIRECTIONS, so a new unsubscribed signal
## fails the run, and one that acquires a subscriber fails until it is struck
## off. It is a debt register, not an approval — REALITY §2's warning about
## building a machine that agrees with you applies squarely, and the defence is
## that this list can only ever shrink.
##
## THE DISCIPLINE IS THE ONE THE PROJECTION CHECK ALREADY HAS:
##
## - A subscriber in `tests/` is NOT a subscriber (REALITY §3d). This scans
##   `scripts/` only and does not scan its own tree.
## - AN EMISSION IS NOT A SUBSCRIPTION. `harbour_controller.traffic_changed` is
##   emitted from five sites and connected from none; a scan that counted
##   `.emit(` would call it delivered. Only `connect` / `is_connected` / `await`
##   count.
## - Every accepted subscriber is PRINTED with the `file:line` and the shape it
##   matched, so the claim is auditable by eye and not only by exit code.
##
## WHAT DEFEATS IT — counted and printed rather than asserted over, because a
## check that quietly excludes what it cannot see is worse than one that names
## the gap:
##
## 1. A CONNECT WHOSE SIGNAL NAME IS NOT A LITERAL. Measured: **two lines in the
##    whole repository**, and they are the two halves of one helper —
##    `DebugDraw._connect_if`'s `obj.is_connected(signal_name, target)` and
##    `obj.connect(signal_name, target)` — whose own callers pass string literals
##    that this scan does read, and which `state_projection_reach_test` already
##    resolves against the class. There is no `callable_mp`-through-a-variable
##    and no signal name built at runtime anywhere in `scripts/`. The count is
##    printed on every run so it cannot become three unnoticed.
## 2. NAME COLLISION — the real limit, and it is a FALSE-GREEN direction. A scan
##    that matches on the signal's NAME lets a subscriber to one class answer for
##    another's identically-named signal. Measured: 27 names are declared more
##    than once, covering 61 of the declarations. **It was hiding four live
##    defects** — `BulkHoldComponent.fill_changed`, `ShipyardBrickEditor.closed`
##    and `CaptainService.captain_created`/`captain_deleted`, each answered for
##    by a subscriber on the OTHER class of the same name. So for a shared name
##    the receiver is resolved to its declared type and a mismatched site is
##    skipped; 22 receivers still cannot be typed and are accepted and PRINTED,
##    because a false green that is counted beats a false red nobody can explain.
## 3. A SUBSCRIBER INSIDE THE DECLARING FILE. Legitimate (a node wiring its own
##    signal) and also exactly what a dead wire looks like when a class talks
##    only to itself. Counted and printed separately rather than rejected.
## 4. `.tscn` EDITOR CONNECTIONS. Godot lets a scene file subscribe with no code
##    at all. This project has **zero** — asserted below, not assumed, because
##    the day one appears this scan starts producing false REDs.
##
## What it cannot see at all, stated with the others: whether a subscriber does
## anything useful with what it receives, and whether the signal is ever
## EMITTED. A declared-and-connected-and-never-emitted wire reads as green here.
##
## ── THE REGISTER'S REASONS ARE PROSE, AND TEN OF THEM WERE FALSE ────────────
## AUDITED 2026-08-17, entry by entry, by going and looking at the code each one
## names. Of the 59 entries, **23 assert nothing but a negative** ("nothing draws
## a crane gauge") — those restate the register's own membership and cannot be
## wrong on their own. **36 assert something CHECKABLE**: a named alternative
## consumer, a named function, a count, or an attribution to another class.
## **Eleven of those 36 did not hold.** `layout_confirmed`'s — *"the caller reads
## the layout back instead"* — was found first and there is no caller at all; ten
## more were found by checking the rest the same way, and every reason above now
## carries what is actually there. The corrections are marked in-line.
##
## Five of the eleven asserted a consumer or a driver THAT DOES NOT EXIST
## (`layout_confirmed`, the two `network_manager` realtime signals, the two
## mp-harness signals). Six misstated a mechanism or a count while the
## conclusion survived (the four `telemetry` entries, `traffic_changed`'s "five
## sites" which is six, `quay_equipment_job`'s reference to a `job_finished`
## this class does not declare).
##
## **WHAT IS NOT FIXED, AND IT IS THE STRUCTURAL HALF.** Nothing above CHECKS any
## of these sentences. A corrected reason rots exactly as fast as the one it
## replaced: `is_ready()` could be added to `NetworkManager` tomorrow and this
## file would neither notice nor care. `tests/entry_reach_test.gd` shows the
## shape that closes it — every register entry declares a typed `claim` from a
## closed set, each kind has a verifier that runs a real check, and an
## unrecognised kind is a hard FAIL rather than a silent skip. Retrofitting that
## here is 36 claims to type and verify across a dozen subsystems; it is real
## work and it is not a comment edit, which is why this paragraph names it
## instead of pretending it was done.

const TestReport := preload("res://tests/support/test_report.gd")

const SCRIPT_ROOT := "res://scripts"
const SCENE_ROOT := "res://scenes"

## `<file>:<signal>` → why it is not simply a defect to delete today.
##
## POLICED IN BOTH DIRECTIONS, the way `state_projection_reach_test`'s and
## `ship_hud_readout_test`'s excuse lists are: an entry that acquires a
## subscriber fails the run, and so does one whose declaration has been deleted.
## An excuse that outlives its defect is a claim that has rotted (REALITY §4b).
##
## THESE ARE NOT APPROVED. Every one is a live instance of REALITY §3d — a value
## computed for a consumer that does not exist. The reasons below say what the
## thing IS, so the next reader can judge it, and deliberately do not say "this
## is fine".
const KNOWN_UNSUBSCRIBED := {
	# ── crane telemetry: 15 signals, one subsystem, no gauge anywhere ──────────
	"bulk_crane.gd:bucket_fill_changed": "crane pose/telemetry — nothing draws a crane gauge",
	"bulk_crane.gd:material_dropped": "crane pose/telemetry — nothing draws a crane gauge",
	"bulk_crane.gd:model_loaded": "crane pose/telemetry — nothing draws a crane gauge",
	"bulk_crane.gd:slew_changed": "crane pose/telemetry — nothing draws a crane gauge",
	"bulk_crane.gd:boom_changed": "crane pose/telemetry — nothing draws a crane gauge",
	"bulk_crane.gd:hoist_changed": "crane pose/telemetry — nothing draws a crane gauge",
	"bulk_crane.gd:bucket_changed": "crane pose/telemetry — nothing draws a crane gauge",
	"provision_crane.gd:model_loaded": "crane pose/telemetry — nothing draws a crane gauge",
	"provision_crane.gd:slew_changed": "crane pose/telemetry — nothing draws a crane gauge",
	"provision_crane.gd:trolley_changed": "crane pose/telemetry — nothing draws a crane gauge",
	"provision_crane.gd:hoist_changed": "crane pose/telemetry — nothing draws a crane gauge",
	"bulk_crane_auto_operator.gd:job_started": "auto-operator progress — no operator panel reads it",
	"bulk_crane_auto_operator.gd:cycle_completed": "auto-operator progress — no operator panel reads it",
	"bulk_crane_auto_operator.gd:phase_changed": "auto-operator progress — no operator panel reads it",
	"provision_crane_auto_operator.gd:job_started": "auto-operator progress — no operator panel reads it",
	"provision_crane_auto_operator.gd:cycle_completed": "auto-operator progress — no operator panel reads it",
	"provision_crane_auto_operator.gd:phase_changed": "auto-operator progress — no operator panel reads it",
	"quay_equipment_job.gd:job_started": "quay job lifecycle — CORRECTED 2026-08-17: this class declares job_started/job_completed/job_stopped and has no job_finished at all (that name is bulk_crane_auto_operator's). harbour_authority_bridge subscribes job_completed and job_stopped; this one is not",
	# ── port / world state nobody watches ─────────────────────────────────────
	"bulk_material_drop.gd:landed": "cargo drop outcome — the drop is resolved inline by its caller",
	"bulk_material_drop.gd:spilled": "cargo drop outcome — the drop is resolved inline by its caller",
	"shore_rsw_tank_bank.gd:inventory_changed": "shore tank level — the landing pump polls the bank instead",
	"harbour_controller.gd:traffic_changed": "emitted from SIX sites (counted 2026-08-17; the reason here said five); the chart harbour board reads HarbourController through PortPlot when it opens",
	"world_traffic_service.gd:fleet_changed": "traffic fleet churn — the map overlay polls the service",
	"world_traffic_service.gd:presentation_changed": "traffic presentation churn — same, polled",
	# ── ship systems ──────────────────────────────────────────────────────────
	"ship_lighting.gd:preset_changed": "the preset NAME reaches the HUD through the instrument snapshot instead",
	"cargo_slot_pad.gd:cargo_changed": "deck slot occupancy — the pad is queried, never watched",
	"cargo_slot_pad.gd:container_landed": "deck slot occupancy — the pad is queried, never watched",
	"bulk_hold_component.gd:fill_changed": "bulk hold level — FOUND BY ATTRIBUTION: the one fill_changed subscriber is on a CatchHoldComponent",
	"container_node.gd:grabbed": "container pick/place — the crane calls notify_grabbed and knows already",
	"container_node.gd:released": "container pick/place — the crane calls notify_released and knows already",
	"hull_ladder_board.gd:disembarked": "ladder use — boarding is handled by the interactable, not by this",
	"bridge_watch_alarm.gd:alarm_started": "the alarm reaches WalkingHud through get_autopilot_snapshot(), polled",
	"bridge_watch_alarm.gd:alarm_acknowledged": "the alarm reaches WalkingHud through get_autopilot_snapshot(), polled",
	"boat_body.gd:mass_properties_changed": "mass/COM churn — buoyancy reads the body directly each tick",
	"vessel_autopilot.gd:engaged": "engagement reaches the HUD through the instrument snapshot instead",
	"vessel_autopilot.gd:navigation_updated": "per-tick progress — the HUD reads remaining_distance_m from the snapshot",
	"autonomous_vessel_captain.gd:phase_changed": "NPC voyage phase — nothing observes an NPC captain",
	"autonomous_vessel_captain.gd:voyage_completed": "NPC voyage outcome — nothing observes an NPC captain",
	"autonomous_vessel_captain.gd:voyage_failed": "NPC voyage outcome — nothing observes an NPC captain",
	# ── UI panels whose owner wires the button, not the signal ────────────────
	"map_overlay.gd:port_selected": "chart selection — the overlay acts on the click itself",
	"harbour_board_panel.gd:berth_chosen": "harbour board selection — the panel acts on the click itself",
	"shipyard_brick_editor.gd:layout_confirmed": "editor result — AUDITED 2026-08-17, THE OLD REASON HERE WAS FALSE: it said \"the caller reads the layout back instead\" and there is no caller. The editor is unreachable from the shipped game (entry_reach_test)",
	"shipyard_brick_editor.gd:closed": "editor lifecycle — FOUND BY ATTRIBUTION: the one `closed` subscriber is on a ShipwrightCatalogPanel",
	"player_camera.gd:mode_changed": "camera mode — no HUD element shows it",
	# ── services and platform ─────────────────────────────────────────────────
	"game_settings.gd:settings_changed": "settings are re-read on open; nothing live-updates",
	"world_clock.gd:day_changed": "calendar events — no system has a per-day hook yet",
	"world_clock.gd:hour_changed": "calendar events — no system has a per-hour hook yet",
	"player_session.gd:save_completed": "save outcome — every caller awaits save_now() instead",
	"captain_service.gd:captain_created": "roster churn — FOUND BY ATTRIBUTION: the subscribers are on RemoteCaptainClient's identically-named pair",
	"captain_service.gd:captain_deleted": "roster churn — FOUND BY ATTRIBUTION: the subscribers are on RemoteCaptainClient's identically-named pair",
	"telemetry.gd:metric_published": "CORRECTED 2026-08-17: the F3 panel has no timer — debug_draw.gd:48 connects Telemetry.sampled, a DIFFERENT signal on this same class, and repaints on that",
	"telemetry.gd:event_recorded": "CORRECTED 2026-08-17: the F3 panel repaints on Telemetry.sampled (debug_draw.gd:48), not on a timer",
	"telemetry.gd:flags_changed": "CORRECTED 2026-08-17: the F3 panel repaints on Telemetry.sampled (debug_draw.gd:48), not on a timer",
	"telemetry.gd:peaks_reset": "CORRECTED 2026-08-17: the F3 panel repaints on Telemetry.sampled (debug_draw.gd:48), not on a timer",
	"network_client.gd:connection_status_changed": "connection state — NetworkManager polls the client",
	"network_manager.gd:realtime_session_started": "realtime session outcome — CORRECTED 2026-08-17: NetworkManager has no is_ready(); main_menu learns the outcome from WorldGateway.session_ready/authority_error, which it CONNECTS to",
	"network_manager.gd:realtime_session_failed": "realtime session outcome — CORRECTED 2026-08-17: NetworkManager has no is_ready(); main_menu learns the outcome from WorldGateway.session_ready/authority_error, which it CONNECTS to",
	# ── the multiplayer test harness, which is production code by location ────
	"virtual_client.gd:event_recorded": "mp_test harness plumbing — CORRECTED 2026-08-17: NOTHING under tests/ names it. Its only drivers are mp_test_suite.gd and mp_stress_viewer.gd, siblings under scripts/network/testing/, reachable only from a showcase scene the game never loads",
	"mp_test_runner.gd:scenario_started": "mp_test harness plumbing — CORRECTED 2026-08-17: NOTHING under tests/ names it; see virtual_client.gd:event_recorded above",
}

var _t := TestReport.new("signal_reach_test")
var _sources: Dictionary = {}


func _initialize() -> void:
	_load_sources()
	var declarations := _declarations()
	_check_no_scene_connections()
	_check_every_signal_has_a_subscriber(declarations)
	_report_what_defeats_the_scan(declarations)
	_t.finish(self)


# ── the corpus ────────────────────────────────────────────────────────────────

func _load_sources() -> void:
	for path in _files(SCRIPT_ROOT, ".gd"):
		_sources[path] = FileAccess.get_file_as_string(path)
	_t.check(
		"the production corpus loaded (%d scripts under %s)" % [_sources.size(), SCRIPT_ROOT],
		_sources.size() > 100
	)


func _files(root: String, suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		_t.fail("cannot open %s" % root)
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [root, entry]
		if dir.current_is_dir():
			if not entry.begins_with("."):
				out.append_array(_files(full, suffix))
		elif entry.ends_with(suffix):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


## The code half of a line — everything before an unquoted `#`. Lifted from
## `state_projection_reach_test`, which learned it the hard way: its first
## version accepted a TRAILING COMMENT as evidence of a reader.
func _code_of(line: String) -> String:
	var in_single := false
	var in_double := false
	for i in range(line.length()):
		var ch := line[i]
		if ch == "\"" and not in_single:
			in_double = not in_double
		elif ch == "'" and not in_double:
			in_single = not in_single
		elif ch == "#" and not in_single and not in_double:
			return line.substr(0, i)
	return line


## Comment-stripped LOGICAL lines: `[{"text", "line"}]`, where a call split
## across several physical lines is joined into one. Without this a
## `connect(\n\t"name",\n\tcallable)` — which `proximity_loader` really does
## write — is invisible to a per-line scan.
##
## IT CHANGES NO VERDICT TODAY, and that is stated rather than left as an
## implication: disabling the joining entirely still gives 178 declared / 119
## subscribed / 59 not, because the one multi-line connect in the project names
## `PortPlot.rebuild_completed`, which `world.gd:418` also `await`s. So this is
## insurance against the next such site, and it is currently UNEXERCISED —
## a mutation that passes is a blind check, not a safe one (REALITY, standing
## order 8), and this one is blind because the case does not arise yet.
func _logical_lines(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var buffer := ""
	var start := 0
	var depth := 0
	var raw := text.split("\n")
	for i in range(raw.size()):
		var line := _code_of(str(raw[i]))
		if buffer.is_empty():
			start = i + 1
			buffer = line
		else:
			buffer += " " + line.strip_edges()
		## Brackets INSIDE a string literal are not brackets. Without this a
		## `print("  PASS  (")` never balances and the joiner swallows the rest
		## of the file into one logical line, where every `connect` in it would
		## answer for every signal named in it.
		var in_single := false
		var in_double := false
		for ch in line:
			if ch == "\"" and not in_single:
				in_double = not in_double
			elif ch == "'" and not in_double:
				in_single = not in_single
			elif in_single or in_double:
				continue
			elif ch == "(" or ch == "[" or ch == "{":
				depth += 1
			elif ch == ")" or ch == "]" or ch == "}":
				depth = maxi(depth - 1, 0)
		if depth == 0:
			if not buffer.strip_edges().is_empty():
				out.append({"text": buffer, "line": start})
			buffer = ""
	if not buffer.strip_edges().is_empty():
		out.append({"text": buffer, "line": start})
	return out


# ── declarations ──────────────────────────────────────────────────────────────

## `[{"name", "path", "line"}]` for every `signal` declared at column 0.
func _declarations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var regex := RegEx.new()
	regex.compile("^signal\\s+(\\w+)")
	for path in _sources:
		var raw := str(_sources[path]).split("\n")
		for i in range(raw.size()):
			var m := regex.search(_code_of(str(raw[i])))
			if m != null:
				out.append({"name": m.get_string(1), "path": str(path), "line": i + 1})
	_t.check(
		"the scan found the project's signal declarations (%d)" % out.size(),
		out.size() >= 150
	)
	## `KNOWN_UNSUBSCRIBED` is keyed `<basename>:<signal>`, which is an address
	## only while basenames are unique. Two `state.gd`s in different folders
	## would silently MERGE two signals into one register entry — an excuse
	## covering a defect it was never written for, which is the one failure mode
	## a debt register must not have. Held here rather than assumed.
	var seen := {}
	var collisions := PackedStringArray()
	for path in _sources:
		var file := str(path).get_file()
		if seen.has(file):
			collisions.append("%s and %s" % [seen[file], path])
		seen[file] = path
	_t.check(
		"script basenames are unique, so `<file>:<signal>` addresses one"
		+ " declaration (%d collisions: %s)" % [collisions.size(), ", ".join(collisions)],
		collisions.is_empty()
	)
	return out


# ── 1 · every declared signal has a subscriber ────────────────────────────────

func _check_every_signal_has_a_subscriber(declarations: Array[Dictionary]) -> void:
	var duplicated := {}
	for decl in declarations:
		var n := str(decl["name"])
		duplicated[n] = int(duplicated.get(n, 0)) + 1

	var unsubscribed := PackedStringArray()
	var subscribed := 0
	var self_only := PackedStringArray()
	var ambiguous := PackedStringArray()
	for decl in declarations:
		var name := str(decl["name"])
		var path := str(decl["path"])
		var key := "%s:%s" % [path.get_file(), name]
		var found := _find_subscriber(
			name, path, int(decl["line"]), int(duplicated.get(name, 1)) > 1
		)
		if bool(found.get("ambiguous", false)):
			ambiguous.append(key)
		if found.is_empty():
			unsubscribed.append(key)
			if KNOWN_UNSUBSCRIBED.has(key):
				continue
			_t.check(
				"%s emits '%s' to somebody (nothing subscribes — REALITY §3d)" % [path.get_file(), name],
				false
			)
			continue
		subscribed += 1
		if str(found["path"]) == path:
			self_only.append(key)
		print("  %-52s %-8s %s:%d"
			% [key, found["shape"], str(found["path"]).trim_prefix("res://"), int(found["line"])])

	_t.check(
		"every declared signal either has a subscriber in scripts/ or is named in"
		+ " KNOWN_UNSUBSCRIBED (%d declared, %d subscribed, %d not)"
		% [declarations.size(), subscribed, unsubscribed.size()],
		unsubscribed.size() == KNOWN_UNSUBSCRIBED.size()
	)
	## The other half of the self-policing, so the register cannot rot into a
	## stale caveat: strike an entry off the day it acquires a subscriber, and
	## delete it the day the signal goes.
	for key in KNOWN_UNSUBSCRIBED:
		_t.check(
			"KNOWN_UNSUBSCRIBED '%s' is still declared and still unsubscribed"
			% key,
			unsubscribed.has(key)
		)
	print("  subscribed only from inside their own declaring file (%d): %s"
		% [self_only.size(), ", ".join(self_only)])
	## A subscription accepted for a DUPLICATED name whose receiver could not be
	## typed. It may belong to the other class of that name. Printed with the
	## count so the gap is visible instead of implied.
	print("  accepted on a shared name without an attributable receiver (%d): %s"
		% [ambiguous.size(), ", ".join(ambiguous)])


## `{"path", "line", "shape"}` for the first subscription to `name`, or `{}`.
##
## THREE SHAPES COUNT AND EMISSION IS NOT ONE OF THEM:
##
## - `direct` — `<expr>.<name>.connect(…)` / `.is_connected(…)`, the dominant
##   idiom here (105 of them).
## - `string` — the name in quotes on a logical line that also says `connect`.
##   This covers `obj.connect("name", cb)`, `obj.is_connected("name", cb)` and
##   `DebugDraw._connect_if(obj, "name", cb)`, whose whole point is that it
##   drops a name the object does not carry IN SILENCE.
## - `await` — `await obj.name`. A coroutine resuming on a signal is a consumer
##   as surely as a callback is; `world.gd:418` is the only one, and without
##   this shape `PortPlot.rebuild_completed` reads as dead.
##
## WHEN THE NAME IS SHARED BY TWO CLASSES the match is ATTRIBUTED, because
## matching on the name alone is a false-GREEN and it was producing two of them:
## the only `fill_changed` subscriber in the project is
## `catch_hold_showcase.gd:23` on a `CatchHoldComponent`, and it was answering
## for `BulkHoldComponent.fill_changed`, which has none; the only `closed`
## subscriber is `shipwright_npc.gd:71` on a `ShipwrightCatalogPanel`, and it was
## answering for `ShipyardBrickEditor.closed`, which has none. So for a shared
## name the receiver token before `.<name>.connect` is resolved to its declared
## type in the SUBSCRIBING file, and a site whose receiver is a different class
## is skipped. A receiver that cannot be typed is ACCEPTED and flagged
## `ambiguous` — a false green that is counted and printed beats a false red
## nobody can explain.
func _find_subscriber(
	name: String, declaring_path: String, declaring_line: int, shared_name: bool
) -> Dictionary:
	var direct := RegEx.new()
	direct.compile("(\\w+)?\\s*\\.?\\s*\\b%s\\s*\\.\\s*(connect|is_connected)\\s*\\(" % name)
	var quoted := RegEx.new()
	quoted.compile("\"%s\"" % name)
	var awaited := RegEx.new()
	awaited.compile("\\bawait\\b[^\\n]*\\b%s\\b" % name)
	var declaring_class := _class_name_of(declaring_path)
	var fallback := {}
	for path in _sources:
		var text := str(_sources[path])
		if not text.contains(name):
			continue
		for logical in _logical_lines(text):
			var line := str(logical["text"])
			var lineno := int(logical["line"])
			if path == declaring_path and lineno == declaring_line:
				continue
			var shape := ""
			var ambiguous := false
			var m := direct.search(line)
			if m != null:
				shape = "direct"
				if shared_name:
					var receiver := m.get_string(1)
					if receiver.is_empty():
						## A bare `name.connect(…)` is a self-connection, and it
						## only answers for the class that declares it.
						if path != declaring_path:
							continue
					else:
						var receiver_class := _declared_type_of(receiver, text)
						if receiver_class.is_empty() or declaring_class.is_empty():
							ambiguous = true
						elif receiver_class != declaring_class:
							continue
			elif quoted.search(line) != null and line.contains("connect"):
				shape = "string"
				ambiguous = shared_name
			elif awaited.search(line) != null:
				shape = "await"
				ambiguous = shared_name
			if shape.is_empty():
				continue
			var hit := {"path": path, "line": lineno, "shape": shape, "ambiguous": ambiguous}
			if not ambiguous:
				return hit
			## An unattributable hit is kept only as a fallback: if a site that
			## DOES resolve to this class exists anywhere, it is the better
			## answer and the scan should not report a gap it does not have.
			if fallback.is_empty():
				fallback = hit
	return fallback


## The `class_name` a script declares, or "" — autoloads and plain scripts have
## none, which is itself a reason a receiver cannot be attributed.
func _class_name_of(path: String) -> String:
	var m := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(str(_sources.get(path, "")))
	return m.get_string(1) if m != null else ""


## The declared type of `identifier` in `text`: `var x: T`, `@onready var x: T`,
## `var x := T.new()`. Returns "" when the declaration is untyped or absent.
func _declared_type_of(identifier: String, text: String) -> String:
	var typed := RegEx.create_from_string(
		"(?m)^\\s*(?:@onready\\s+)?var\\s+%s\\s*:\\s*(\\w+)" % identifier
	).search(text)
	if typed != null:
		return typed.get_string(1)
	var inferred := RegEx.create_from_string(
		"(?m)^\\s*(?:@onready\\s+)?var\\s+%s\\s*:=\\s*(\\w+)\\s*\\.\\s*new\\s*\\(" % identifier
	).search(text)
	if inferred != null:
		return inferred.get_string(1)
	var cast := RegEx.create_from_string(
		"(?m)^\\s*(?:@onready\\s+)?var\\s+%s\\s*:=.*\\bas\\s+(\\w+)\\s*$" % identifier
	).search(text)
	return cast.get_string(1) if cast != null else ""


# ── 2 · nothing subscribes from a scene file ──────────────────────────────────

## Godot can wire a signal in a `.tscn` with no code at all, and this scan reads
## code. Today there are none — asserted rather than assumed, because the day one
## appears every check above starts producing false REDs and the cause would be
## invisible.
func _check_no_scene_connections() -> void:
	var scenes := _files(SCENE_ROOT, ".tscn")
	var found := PackedStringArray()
	for path in scenes:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if str(line).begins_with("[connection "):
				found.append("%s: %s" % [str(path).get_file(), str(line)])
	_t.check("the scene corpus loaded (%d .tscn under %s)" % [scenes.size(), SCENE_ROOT], scenes.size() > 5)
	_t.check(
		"no scene file subscribes to a signal, so a code scan sees the whole"
		+ " wiring surface (%d editor connections)" % found.size(),
		found.is_empty()
	)
	for entry in found:
		print("  SCENE CONNECTION (invisible to this scan): %s" % entry)


# ── 3 · what defeats the scan, printed rather than asserted over ──────────────

func _report_what_defeats_the_scan(declarations: Array[Dictionary]) -> void:
	## (a) A CONNECT WHOSE SIGNAL NAME THIS SCAN CANNOT READ.
	##
	## `Signal.connect(callable, flags)` and `Object.connect(name, callable,
	## flags)` are the same seven characters, and only the second one names a
	## signal in argument ONE. Four things tell them apart, and all four were
	## needed — the first cut alone flagged sixteen sites, fourteen of which were
	## an ordinary `Signal.connect(a_local_callable)`:
	##
	## - `Object.connect` takes AT LEAST TWO arguments; a one-argument call is
	##   always `Signal.connect`.
	## - a second argument of `CONNECT_*` is a Signal-connect flag, so argument
	##   one was the callable.
	## - a string literal in argument one is a name this scan reads.
	## - a bare identifier in argument one is a callable exactly when the file
	##   declares `func <it>(`.
	##
	## What survives all four is a signal name this scan cannot resolve, and it
	## is printed rather than assumed away.
	var opaque := PackedStringArray()
	for path in _sources:
		var text := str(_sources[path])
		var declares_func := RegEx.new()
		for logical in _logical_lines(text):
			var line := str(logical["text"])
			var from := 0
			while true:
				var at := _find_connect_call(line, from)
				if at < 0:
					break
				from = at + 1
				var args := _arguments(line, at)
				if args.size() < 2:
					continue
				if str(args[1]).begins_with("CONNECT_"):
					continue
				var arg := str(args[0])
				if arg.is_empty() or arg.begins_with("\""):
					continue
				if RegEx.create_from_string("^[A-Za-z_]\\w*$").search(arg) == null:
					continue
				declares_func.compile("(?m)^func\\s+%s\\s*\\(" % arg)
				if declares_func.search(text) != null:
					continue
				opaque.append("%s:%d %s"
					% [str(path).get_file(), int(logical["line"]), line.strip_edges()])
	_t.check(
		"connect sites whose signal name this scan cannot resolve are counted, not"
		+ " assumed away (%d — both halves of DebugDraw._connect_if, whose own"
		% opaque.size()
		+ " callers pass literals this scan does read)",
		opaque.size() <= 2
	)
	for entry in opaque:
		print("  OPAQUE CONNECT: %s" % entry)

	## (b) name collision — the false-green direction, stated with its size.
	var by_name := {}
	for decl in declarations:
		var name := str(decl["name"])
		var files: PackedStringArray = by_name.get(name, PackedStringArray())
		files.append(str(decl["path"]).get_file())
		by_name[name] = files
	var shared := 0
	var shared_declarations := 0
	for name in by_name:
		var files := by_name[name] as PackedStringArray
		if files.size() > 1:
			shared += 1
			shared_declarations += files.size()
			print("  NAME SHARED BY %d DECLARATIONS: %-24s %s" % [files.size(), name, ", ".join(files)])
	_t.check(
		"%d names are declared by more than one class, covering %d of %d"
		% [shared, shared_declarations, declarations.size()]
		+ " declarations — every subscription to one of them is attributed by"
		+ " receiver type where the receiver can be typed, and the ones that"
		+ " cannot be are printed above with a count",
		shared > 0 and shared_declarations < declarations.size()
	)


## Index of the `(` of the next `.connect(` / `.is_connected(` at or after `from`.
func _find_connect_call(line: String, from: int) -> int:
	var best := -1
	for token in [".connect(", ".is_connected("]:
		var at := line.find(token, from)
		if at >= 0 and (best < 0 or at < best):
			best = at + token.length() - 1
	return best


## The top-level arguments of the call whose `(` is at `open_paren`, trimmed.
func _arguments(line: String, open_paren: int) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := 0
	var start := open_paren + 1
	for i in range(open_paren, line.length()):
		var ch := line[i]
		if ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
			if depth == 0:
				var tail := line.substr(start, i - start).strip_edges()
				if not tail.is_empty():
					out.append(tail)
				return out
		elif ch == "," and depth == 1:
			out.append(line.substr(start, i - start).strip_edges())
			start = i + 1
	return out
