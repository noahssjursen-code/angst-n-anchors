extends SceneTree

## Lane A — THE COMPUTED-AND-UNSEEN CHECK, generalised off the one in
## `ship_hud_readout_test`.
##
## Nine instances of the same defect were surveyed in this project on
## 2026-08-16 — a value computed on a schedule, published into a field or a
## dictionary, and read by nothing the game runs (REALITY §3d). Every one of
## them was found by a human grepping, which is the reason there were nine.
## `ship_hud_readout_test._survey_snapshot_keys` holds ONE producer, the helm
## instrument snapshot. This holds the other three seams of the same shape:
##
## 1. GAMESTATE'S PROJECTIONS. `GameState` is described in its own header as
##    "central read model — systems write here on change; UI and tools read from
##    here". Every field and every signal on the sub-states it holds is therefore
##    a promise that something reads it. `PlayerState.current_port_id` was never
##    written and never read by any file in the repository;
##    `ShipState.hull_health` / `fuel` and their two signals were never assigned
##    after construction and never read; `ContractState.active` was rewritten by
##    `FreightService` on every contract change and read by nobody. All four are
##    deleted as of 2026-08-16 and this check is what says so if a fifth lands.
##
## 2. SIGNAL NAMES CONNECTED AS STRINGS. `debug_draw` connected
##    `ContractState.active_changed`, a signal that class never declared.
##    `Object.connect` would have errored — but the call goes through
##    `DebugDraw._connect_if`, which guards on `has_signal` and drops a wrong
##    name in silence. A wire to a name that does not exist reads exactly like
##    coverage.
##
## 3. THE OTHER DIRECTION, WHERE IT IS DECIDABLE. `capabilities` is a metric
##    namespace addressed BY DATA: a registration rule in
##    `resources/data/vessels/registrations/catalog.json` names a metric by
##    string and `VesselCompliance._evaluate_rule` looks it up with
##    `int(capabilities.get(metric, 0))`. A key with no rule naming it is
##    inventory, not a defect — but a RULE naming a key nothing publishes reads
##    0 forever and fails (or passes) silently, and nothing checked that.
##    `vessel_registration_test._answerable` returns "measured off geometry" for
##    exactly these two rule kinds without looking.
##
## WHAT THIS CANNOT SEE, stated up front because the method is a source scan:
##
## - Whether a reader reads the RIGHT VALUE, or a stale one. Same blindness the
##   HUD survey states about `_capture_instruments`.
## - A reader that reaches the member some way this scan does not model:
##   `obj.get("field")` with a computed name, `_state.get(field_name)`, a
##   `Callable` built from a string. Those read as unreached — a false RED,
##   which is the safe direction, and the excuse list is where one goes.
## - THE OPPOSITE, AND IT IS THE REAL LIMIT: a member whose name collides with
##   another object's member on a line that also mentions the projection —
##   `.data`, `.active` — can read as reached when the reader is a different
##   object's. The scan therefore PRINTS the file and line it accepted for every
##   member, so the claim is auditable by eye rather than only by exit code. It
##   was audited that way when this test landed: eleven members, eleven readers,
##   each one the reader named in the report.
## - Anything outside `scripts/`. A reader in `tests/` is NOT a reader
##   (REALITY §3d — if the only callers are test rigs, it is not delivered), and
##   this test does not scan its own tree.

const TestReport := preload("res://tests/support/test_report.gd")

const GAME_STATE_PATH := "res://scripts/state/game_state.gd"
const SCRIPT_ROOT := "res://scripts"
const REGISTRATIONS_PATH := "res://resources/data/vessels/registrations/catalog.json"
const PLAN_OUTFIT_PATH := "res://scripts/ship/plan_outfit.gd"
const VESSEL_OUTFIT_PATH := "res://scripts/ship/vessel_outfit.gd"

## Members of a GameState projection that nothing reads, each with the reason it
## is not simply a defect to delete. POLICED IN BOTH DIRECTIONS, the way
## `ship_hud_readout_test.KNOWN_UNCONSUMED` is: a member named here that
## acquires a reader fails the run, and so does one that has been deleted. An
## excuse that outlives its defect is a claim that has rotted (REALITY §4b).
##
## EMPTY. It is empty because the four members that would have been in it were
## deleted instead of excused, and an empty list is the only state of this
## dictionary that needs no argument.
const KNOWN_UNREACHED := {}

var _t := TestReport.new("state_projection_reach_test")
var _sources: Dictionary = {}


func _initialize() -> void:
	_load_sources()
	var projections := _discover_projections()
	_check_projection_members(projections)
	_check_connect_names_resolve(projections)
	_check_rule_metrics_are_published()
	_t.finish(self)


# ── the corpus ────────────────────────────────────────────────────────────────

## Every production script, read once. `tests/` is deliberately absent.
func _load_sources() -> void:
	for path in _gd_files(SCRIPT_ROOT):
		_sources[path] = FileAccess.get_file_as_string(path)
	_t.check(
		"the production corpus loaded (%d scripts under %s)" % [_sources.size(), SCRIPT_ROOT],
		_sources.size() > 100
	)


func _gd_files(root: String) -> PackedStringArray:
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
				out.append_array(_gd_files(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


# ── 1. every member of every GameState projection has a reader ────────────────

## `{ field_name: {"class": "ShipState", "path": "res://…/ship_state.gd"} }`,
## derived from `GameState`'s own declarations rather than restated here: add a
## sub-state to the read model and it is surveyed without editing this file
## (REALITY §4a — a list you restate is a list that goes stale).
func _discover_projections() -> Dictionary:
	var text := str(_sources.get(GAME_STATE_PATH, ""))
	var out := {}
	if text.is_empty():
		_t.fail("could not read %s" % GAME_STATE_PATH)
		return out
	var regex := RegEx.new()
	regex.compile("(?m)^var\\s+(\\w+)\\s*:\\s*(\\w+)\\s*=\\s*(\\w+)\\.new\\(\\)")
	for m in regex.search_all(text):
		if m.get_string(2) != m.get_string(3):
			continue
		var path := _path_of_class(m.get_string(2))
		if path.is_empty():
			_t.fail("GameState holds a %s and no script declares that class_name" % m.get_string(2))
			continue
		out[m.get_string(1)] = {"class": m.get_string(2), "path": path}
	_t.check(
		"GameState's read model was discovered from its own declarations (%d projections: %s)"
		% [out.size(), ", ".join(PackedStringArray(out.keys()))],
		out.size() >= 3
	)
	return out


func _path_of_class(class_id: String) -> String:
	for path in _sources:
		if str(_sources[path]).begins_with("class_name %s\n" % class_id):
			return str(path)
	return ""


func _check_projection_members(projections: Dictionary) -> void:
	var surveyed := 0
	var unreached := PackedStringArray()
	for field in projections:
		var info := projections[field] as Dictionary
		var path := str(info["path"])
		var class_id := str(info["class"])
		var members := _members_of(path)
		_t.check(
			"%s declares members to survey (%d)" % [class_id, members.size()],
			members.size() > 0
		)
		for member in members:
			surveyed += 1
			var name := str(member["name"])
			var found := _find_reader(name, str(member["kind"]), path, field, class_id)
			var key := "%s.%s" % [class_id, name]
			if found.is_empty():
				unreached.append(key)
				if KNOWN_UNREACHED.has(key):
					print("  KNOWN UNREACHED  %s — %s" % [key, KNOWN_UNREACHED[key]])
					continue
				_t.check(
					"%s %s '%s' reaches a reader in scripts/ (nothing reads it — REALITY §3d)"
					% [class_id, member["kind"], name],
					false
				)
				continue
			print("  %-34s read by %s" % [key, found])
	_t.check(
		"every projection member either reaches a reader or is named in KNOWN_UNREACHED"
		+ " (%d surveyed, %d unreached)" % [surveyed, unreached.size()],
		unreached.size() == KNOWN_UNREACHED.size()
	)
	## Both halves of the self-policing, so an excuse cannot outlive its defect.
	for key in KNOWN_UNREACHED:
		_t.check(
			"KNOWN_UNREACHED '%s' is still unread (strike it off if it now has a reader)" % key,
			unreached.has(key)
		)


## The code half of a line — everything before an unquoted `#`.
##
## THIS FUNCTION IS A MUTATION THAT PASSED. The first version of `_find_reader`
## skipped whole comment lines and nothing else, so a TRAILING comment counted
## as a reader: `var registry := …  # someday: gs.world.probe_commented` made an
## unread field report `read by scripts/ui/debug_draw.gd:638` and the run stayed
## green. A check that accepts a note about intent as evidence of a reader is
## precisely the failure this test exists to catch, one level up (REALITY §4,
## standing order 8). Quotes are tracked because a `#` inside a string is not a
## comment, and this project writes colours as `"#rrggbb"`.
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


## `[{"name", "kind"}]` for the `var`s and `signal`s a state class declares at
## column 0. Setters, comments and locals are indented and do not match.
func _members_of(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var text := str(_sources.get(path, ""))
	var regex := RegEx.new()
	regex.compile("(?m)^(var|signal)\\s+(\\w+)")
	for m in regex.search_all(text):
		out.append({"name": m.get_string(2), "kind": "field" if m.get_string(1) == "var" else "signal"})
	return out


## The file:line of the first line outside `declaring_path` that READS `name`
## through this projection, or "" if there is none.
##
## A read is `.name` not immediately followed by `=`, or the name in quotes (the
## `connect("name", …)` / `get("name")` idiom). An ASSIGNMENT IS NOT A READ, and
## that distinction is the whole check: `GameState._refresh_weather` writes
## `world.weather_label` six ways, `PortProximity` writes `nearest_port_id`, and
## `FreightService` wrote `contract.active` on every change — a scan that counted
## those would have called all three delivered.
##
## The line must also name the projection (the GameState field, or the class),
## which is what keeps `.data` on a `PlayerSession` from answering for
## `ShipState.data`.
func _find_reader(
	name: String, kind: String, declaring_path: String, field: String, class_id: String
) -> String:
	var write := RegEx.new()
	write.compile("\\.%s\\s*=[^=]" % name)
	var read := RegEx.new()
	read.compile("\\.%s\\b" % name)
	var quoted := RegEx.new()
	quoted.compile("\"%s\"" % name)
	for path in _sources:
		if path == declaring_path:
			continue
		var text := str(_sources[path])
		if not text.contains(name):
			continue
		var lines := text.split("\n")
		for i in range(lines.size()):
			var line := _code_of(str(lines[i]))
			if line.strip_edges().is_empty():
				continue
			if not (line.to_lower().contains(field) or line.contains(class_id)):
				continue
			var is_read := quoted.search(line) != null
			if not is_read and read.search(line) != null and write.search(line) == null:
				is_read = true
			if kind == "signal" and not (line.contains("connect") or quoted.search(line) != null):
				is_read = false
			if is_read:
				return "%s:%d" % [str(path).trim_prefix("res://"), i + 1]
	return ""


# ── 2. no wire names a signal that does not exist ─────────────────────────────

## `DebugDraw._connect_if(obj, "sig", cb)` drops a name the object does not
## carry, on purpose, so the panel survives a missing autoload. The cost is that
## a WRONG name is indistinguishable from a working wire, and one sat there
## being wrong: `_connect_if(gs.contract, "active_changed", …)`.
##
## Only the sites whose receiver is statically resolvable are asserted — that is
## every `_connect_if(<var>.<field>, …)` where `<field>` is a GameState
## projection. The other string connects in the tree (`weather.connect(
## "state_changed")` in `world_renderer`, `rain_field`, `weather_hud`;
## `client.connect("packet_received")` in `network_manager`) name a receiver
## this scan cannot resolve from source, and they are counted and printed rather
## than asserted, so the gap is visible instead of implied.
func _check_connect_names_resolve(projections: Dictionary) -> void:
	var regex := RegEx.new()
	regex.compile("_connect_if\\(\\s*\\w+\\.(\\w+)\\s*,\\s*\"([^\"]+)\"")
	var sites := 0
	for path in _sources:
		for m in regex.search_all(str(_sources[path])):
			var field := m.get_string(1)
			var signal_name := m.get_string(2)
			if not projections.has(field):
				continue
			sites += 1
			var info := projections[field] as Dictionary
			var script: Script = load(str(info["path"]))
			var instance: Object = script.new()
			_t.check(
				"%s connects %s.%s and %s declares that signal"
				% [str(path).get_file(), field, signal_name, info["class"]],
				instance.has_signal(signal_name)
			)
	## Without this the check above is vacuous the moment the pattern drifts.
	_t.check(
		"the _connect_if scan found the panel's wires (%d resolvable sites)" % sites,
		sites >= 6
	)
	var loose := RegEx.new()
	loose.compile("(?<!_connect_if\\()\\bconnect\\(\\s*\"([^\"]+)\"")
	var unresolved := PackedStringArray()
	for path in _sources:
		for m in loose.search_all(str(_sources[path])):
			unresolved.append("%s:\"%s\"" % [str(path).get_file(), m.get_string(1)])
	print("  string connects this scan cannot resolve: %s" % ", ".join(unresolved))


# ── 3. every rule metric names a capability something publishes ───────────────

func _check_rule_metrics_are_published() -> void:
	var plan_keys := _dict_literal_keys(PLAN_OUTFIT_PATH, "var capabilities := {")
	var brick_keys := _dict_literal_keys(VESSEL_OUTFIT_PATH, "var caps := {")
	## Negatives against an empty universe pass for free (REALITY §4).
	_t.check("PlanOutfit publishes capabilities (%d keys)" % plan_keys.size(), plan_keys.size() >= 10)
	_t.check("VesselOutfit publishes capabilities (%d keys)" % brick_keys.size(), brick_keys.size() >= 10)

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRATIONS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_t.fail("could not read %s" % REGISTRATIONS_PATH)
		return
	var named := PackedStringArray()
	var rules_seen := 0
	for raw in ((parsed as Dictionary).get("registrations", []) as Array):
		var registration := raw as Dictionary
		for rule_raw in (registration.get("rules", []) as Array):
			var rule := rule_raw as Dictionary
			var kind := str(rule.get("kind", ""))
			var metric := ""
			if kind == "metric_range":
				metric = str(rule.get("metric", ""))
			elif kind == "capability":
				metric = str(rule.get("capability", ""))
			if metric.is_empty():
				continue
			rules_seen += 1
			if not named.has(metric):
				named.append(metric)
			_t.check(
				"%s/%s reads capability '%s' and PlanOutfit publishes it"
				% [registration.get("id", "?"), kind, metric],
				plan_keys.has(metric)
			)
			_t.check(
				"%s/%s reads capability '%s' and VesselOutfit publishes it"
				% [registration.get("id", "?"), kind, metric],
				brick_keys.has(metric)
			)
	_t.check(
		"the registration catalogue was walked (%d capability-addressed rules, %d metrics)"
		% [rules_seen, named.size()],
		rules_seen >= 3
	)
	## Inventory, NOT a failure. A capability no rule names is a metric that is
	## computed and unread — `max_stack_y` is one, and its value was 5.5 m wrong
	## on `demo_workboat` for exactly that reason — but the namespace is
	## addressed by data, so the day a rule names one it is consumed with no code
	## change. Printed so the count is visible and cannot grow unnoticed.
	var unaddressed := PackedStringArray()
	for key in plan_keys:
		if not named.has(key):
			unaddressed.append(key)
	print("  capabilities no registration rule names (%d): %s"
		% [unaddressed.size(), ", ".join(unaddressed)])


## Keys of the dictionary literal opened by `marker`, up to its closing `\n\t}`.
## Comment lines are stripped first so prose inside the literal cannot be read
## as a key.
func _dict_literal_keys(path: String, marker: String) -> PackedStringArray:
	var out := PackedStringArray()
	var text := str(_sources.get(path, ""))
	if text.is_empty():
		_t.fail("could not read %s" % path)
		return out
	var start := text.find(marker)
	if start < 0:
		_t.fail("%s no longer contains `%s` — the publisher moved" % [path, marker])
		return out
	var close := text.find("\n\t}", start)
	if close < 0:
		_t.fail("%s: could not find the end of `%s`" % [path, marker])
		return out
	var body := PackedStringArray()
	for line in text.substr(start, close - start).split("\n"):
		if not str(line).strip_edges().begins_with("#"):
			body.append(str(line))
	var regex := RegEx.new()
	regex.compile("\"([a-z_]+)\"\\s*:")
	for m in regex.search_all("\n".join(body)):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out
