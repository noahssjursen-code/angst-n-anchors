extends SceneTree

## Lane A — EVERY SCENE THE PROJECT SHIPS IS EITHER REACHABLE FROM WHAT THE
## ENGINE STARTS, OR NAMED IN A REGISTER WITH A CLAIM THAT IS CHECKED.
##
## WHY THIS UNIT EXISTS. On 2026-08-17 a forward closure from `main_scene` plus
## the 19 autoloads reached **311 files containing the entire game** and not one
## `scenes/apps/` file. A player can buy a boat and sail it; they cannot build or
## change one. The gate was green throughout, and structurally so:
## `structure_studio`'s lane-C probe passes 225 checks *while its scene is
## unreachable* — every one of them is about what it does once running — and no
## gate unit anywhere asserted that anything could be opened at all. This is
## REALITY §3 (the layer trap) with the whole premise inside it, and the reason
## it survived is that reachability was never a property anybody pointed a check
## at (REALITY §4b).
##
## THE PROPERTY IS A SET EQUALITY, NOT A COUNT — §4f ranks that shape strongest
## because the population is what is conserved:
##
##     { files in the population that the closure does not reach }
##       ==  { keys of KNOWN_UNREACHABLE }
##
## A new unreachable scene fails. A registered one that becomes reachable fails
## until it is struck off. A registered one whose file is deleted fails. It can
## only shrink.
##
## THE REGISTER IS WHERE THE HONESTY LIVES, SO IT IS POLICED. `signal_reach_test`
## carries the same shape and its `layout_confirmed` entry was excused with *"the
## caller reads the layout back instead"* — **there is no caller**. A register
## entry is a check whose evidence is prose, and prose does not fail. So here
## every entry MUST declare a `claim` from a closed set, each claim kind has a
## verifier that runs a real check, and an unrecognised kind is a hard FAIL
## rather than a silent skip — the same rule `gate.sh` uses for an undeclarable
## `## gate-requires:` token. A reason that asserts somebody calls the thing is
## rejected outright: this register exists precisely because nobody does.
##
## THE CLOSURE. Seeds are the only two things the engine starts on its own:
## `application/run/main_scene` and every `autoload/*`. From each reachable file
## it follows every `res://…gd|tscn` literal AND every global `class_name` token,
## because `world.gd` reaches the shipwright through `PortPlot.new()` with no
## path anywhere — a walker that follows only paths misses most of the game.
## GDScript comments are STRIPPED: a mention in prose is not a call, and that is
## not a technicality here — `ShipyardBrickEditor` is named in two production
## files and both are comments, so a comment-blind walker calls a dead editor
## live. Both closures are computed and the difference is printed.
##
## WHAT DEFEATS IT, counted and printed rather than quietly excluded:
##
## 1. A LOAD BY `uid://`. The closure matches `res://` paths. Godot also
##    addresses resources by uid, and a `load("uid://b6qk…")` would be invisible
##    to it and would produce a FALSE "unreachable". Measured: **zero** uid
##    literals in `scripts/` — asserted below, not assumed, because the day one
##    appears this scan starts lying in the dangerous direction.
## 2. A PATH BUILT AT RUNTIME. `load("res://scenes/%s.tscn" % name)` is outside
##    any static walker. Counted below and printed with the sites.
## 3. AN AUTHORING SURFACE OUTSIDE THE POPULATION. The population is the app
##    cluster (`scenes/apps`, `scripts/apps`) plus every `.tscn` under
##    `res://scenes` outside the declared excluded roots. An editor written into
##    `scripts/ui/` is not seen. This is a real gap and it is printed on every
##    run rather than left to a reader of this comment.
## 4. `res://scenes/showcases` IS EXCLUDED AS A ROOT — 23 scenes. They are dev
##    surfaces by naming convention and none is reachable; folding them in would
##    put 23 lines in the register that say the same thing and would train
##    everyone to add a 24th. The exclusion is DECLARED, its members are counted
##    and printed, and a scene can only escape the population by being moved into
##    that directory, which is a visible move in a diff.
##
## What it cannot see at all, stated with the others: whether a reachable scene
## can be reached by a PLAYER (a scene loaded only behind a debug key is
## "reachable" here), and whether anything on the far side works. This unit
## answers "is there a path from the engine to this file", nothing more. The
## live half — pressing the buttons — is `tests/_entry_reach_probe.tscn`, which
## is a probe because driving a UI is not a property, it is an observation.

const TestReport := preload("res://tests/support/test_report.gd")

const SCENE_ROOT := "res://scenes"
const SCRIPT_ROOT := "res://scripts"
const APP_SCENE_ROOT := "res://scenes/apps"
const APP_SCRIPT_ROOT := "res://scripts/apps"

## Declared, not discovered: see "WHAT DEFEATS IT" 4.
const EXCLUDED_ROOTS := ["res://scenes/showcases"]

## The closure must reach these or it is broken, and every "NOT REACHABLE"
## verdict below would be an artefact of a dead walker rather than a fact about
## the game. Two `.tscn`s, the world script, an NPC the world spawns by class
## name only, and the two construction layers recent waves have been building.
const WALKER_CONTROLS := [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/world.tscn",
	"res://scripts/world/world.gd",
	"res://scripts/npc/shipwright_npc.gd",
	"res://scripts/ship/deck_fitout.gd",
	"res://scripts/construction/structure_baker.gd",
	"res://scripts/construction/piece_kit.gd",
]

## The lane-C declaration `gate.sh` scans for, ASSEMBLED AT RUNTIME AND NOT
## WRITTEN OUT. Spelling it in full here makes this file a malformed lane-C app:
## the gate collects every `.gd` in the tree containing that token — the
## `implements` half of its search skips `tests/`, the `declares` half does not
## — and reports `FAIL(selfck)` against a lane-A unit that merely talks about
## the mechanism. Measured, 2026-08-17, by writing it out and watching the gate
## go red with this unit ALSO passing in lane A.
const SELFCHECK_PREFIX := "## gate-" + "selfcheck:"

## A claim kind with no verifier is a claim nobody checks. The set is closed and
## an entry naming something outside it is a hard FAIL.
const CLAIM_KINDS := [
	"gate_selfcheck",
	"hosts_script",
	"scene_tree_script",
	"no_code_referrer",
]

## A reason may say what the thing IS. It may not assert that something reaches
## it — that is the sentence `signal_reach_test` accepted and that was false, and
## in THIS register it would contradict the register's own membership.
const CALLER_ASSERTING_PHRASES := [
	"the caller",
	"its caller",
	"callers",
	"reads it back",
	"reads the layout back",
	"is called from",
	"is opened from",
	"is launched from the game",
	"polls it",
	"subscriber",
]

## THE REGISTER. `res://` path → `{reason, claim, arg}`.
##
## POLICED IN BOTH DIRECTIONS. An entry that becomes reachable fails until it is
## struck off; an entry whose file is deleted fails; a file that is unreachable
## and not here fails. **NOTHING HERE IS APPROVED.** Eleven of these seventeen
## are the defect STATE.md records on 2026-08-17 — the entire authoring half of
## this project, sitting behind a door that does not exist. Six more are scenes
## with no referrer anywhere in the repository, found by this unit on the day it
## was written. The reasons say what each one is so the next reader can judge it,
## and deliberately do not say "this is fine".
const KNOWN_UNREACHABLE := {
	# ── the app cluster: every authoring surface this project has ─────────────
	"res://scenes/apps/structure_studio.tscn": {
		"reason": "Structure Studio's scene. The current authoring tool, booted"
			+ " by typing its path; the gate boots it in lane C. WHERE A PLAYER'S"
			+ " DOOR TO IT GOES IS AN OPEN OWNER DECISION (STATE 2026-08-17).",
		"claim": "gate_selfcheck",
		"arg": "res://scenes/apps/structure_studio.tscn",
	},
	"res://scripts/apps/structure_studio.gd": {
		"reason": "Structure Studio's script — 225 lane-C self-checks, all of them"
			+ " about what it does once running, none about getting to it.",
		"claim": "gate_selfcheck",
		"arg": "res://scenes/apps/structure_studio.tscn",
	},
	"res://scenes/apps/shipyard_brick_editor.tscn": {
		"reason": "scene wrapper around the brick editor script; it adds a"
			+ " CanvasLayer and standalone_tool and nothing else.",
		"claim": "hosts_script",
		"arg": "res://scripts/apps/shipyard_brick_editor.gd",
	},
	"res://scripts/apps/shipyard_brick_editor.gd": {
		"reason": "the brick vessel editor. Described in earlier notes as retired"
			+ " in favour of Structure Studio; the shipwright sells certified"
			+ " prebuilts a human authored with THIS tool. Named twice in"
			+ " production source and both mentions are comments.",
		"claim": "no_code_referrer",
		"arg": "",
	},
	"res://scenes/apps/vessel_registration_audit.tscn": {
		"reason": "scene wrapper around the registration audit script.",
		"claim": "hosts_script",
		"arg": "res://scripts/apps/vessel_registration_audit.gd",
	},
	"res://scripts/apps/vessel_registration_audit.gd": {
		"reason": "a developer audit over the vessel registration data. Not a"
			+ " player surface; it has no scene entry and no flag.",
		"claim": "no_code_referrer",
		"arg": "",
	},
	"res://scripts/apps/building_brick_editor.gd": {
		"reason": "the land-building brick editor, 71 KB, WITH NO SCENE AT ALL —"
			+ " there is no .tscn that hosts it, so nothing can boot it by any"
			+ " means, including a command line.",
		"claim": "no_code_referrer",
		"arg": "",
	},
	# ── offline asset generators: SceneTree scripts, so not surfaces at all ───
	# `extends SceneTree` cannot be attached to a node (gate.sh calls that
	# pairing STALE and refuses to run it), so these are `--script`-only by
	# construction and could not be given a door if somebody wanted to.
	"res://scripts/apps/character_body_author.gd": {
		"reason": "offline generator: writes the articulated body JSON that"
			+ " production loads. Not a UI.",
		"claim": "scene_tree_script",
		"arg": "",
	},
	"res://scripts/apps/character_wardrobe_author.gd": {
		"reason": "offline generator: writes the block wardrobe JSON. Not a UI.",
		"claim": "scene_tree_script",
		"arg": "",
	},
	"res://scripts/apps/character_fitted_wardrobe_author.gd": {
		"reason": "offline generator: writes the fitted wardrobe JSON. Not a UI.",
		"claim": "scene_tree_script",
		"arg": "",
	},
	"res://scripts/apps/icelander_sweater_author.gd": {
		"reason": "offline generator: writes the sweater proof JSON. Not a UI.",
		"claim": "scene_tree_script",
		"arg": "",
	},
	# ── scenes with no referrer ANYWHERE in the repository ───────────────────
	# Found by this unit, 2026-08-17. Not authoring surfaces and not showcases:
	# these are game scenes and one of them is the loading screen. Zero
	# referrers means zero, including tests and docs — measured, and the claim
	# below re-measures it on every run.
	"res://scenes/systems/fuel_station.tscn": {
		"reason": "a fuel station scene. Refuelling in the shipped game is a"
			+ " harbour-master menu action, not this object.",
		"claim": "no_code_referrer",
		"arg": "",
	},
	"res://scenes/systems/lighthouse_building.tscn": {
		"reason": "a lighthouse scene. The port placer builds its own lighthouse"
			+ " geometry; nothing loads this file.",
		"claim": "no_code_referrer",
		"arg": "",
	},
	"res://scenes/systems/fog_horn_building.tscn": {
		"reason": "a fog horn scene. Same shape as the lighthouse.",
		"claim": "no_code_referrer",
		"arg": "",
	},
	"res://scenes/shared/npc_base.tscn": {
		"reason": "an NPC base scene. The three port NPCs are constructed in code"
			+ " by `PortPlot`, from class names, never from this file.",
		"claim": "no_code_referrer",
		"arg": "",
	},
	"res://scenes/shared/trommel.tscn": {
		"reason": "a trommel (screening drum) scene from an earlier direction.",
		"claim": "no_code_referrer",
		"arg": "",
	},
	"res://scenes/ui/loading_screen.tscn": {
		"reason": "A LOADING SCREEN NOTHING SHOWS. The world loads with no cover"
			+ " because no code names this file.",
		"claim": "no_code_referrer",
		"arg": "",
	},
}

## §4f shape 4, the catch-all under the set equality: the population is
## DISCOVERED, so a root that stops listing takes its per-member checks with it
## and the set equality would be comparing two empty sets. Re-freeze this in the
## SAME commit as any check you add — never afterwards to match a number.
const EXPECTED_CHECKS := 48

var _t := TestReport.new("entry_reach_test")
var _strict: Dictionary = {}
var _loose: Dictionary = {}
var _class_paths: Dictionary = {}
var _corpus: Dictionary = {} ## res:// path -> comment-stripped source


func _initialize() -> void:
	_load_class_index()
	_load_corpus()
	_strict = _closure(true)
	_loose = _closure(false)
	_report_closure()
	_check_walker_is_alive()
	_check_what_defeats_the_scan()
	var population := _population()
	_check_register_is_well_formed()
	_check_set_equality(population)
	_check_every_claim()
	_t.check(
		"the unit ran the number of checks it was frozen at (%d, expected %d) —"
		% [_t.check_count() + 1, EXPECTED_CHECKS]
		+ " a fall means a check stopped being reached, not that it passed (§4f)",
		_t.check_count() + 1 == EXPECTED_CHECKS
	)
	_t.finish(self)


# ── the corpus and the class index ────────────────────────────────────────────

func _load_class_index() -> void:
	for entry in ProjectSettings.get_global_class_list():
		var n := str(entry.get("class", ""))
		var p := str(entry.get("path", ""))
		if not n.is_empty() and p.begins_with("res://"):
			_class_paths[n] = p
	_t.check(
		"the global class_name index loaded (%d classes) — without it the walker"
		% _class_paths.size()
		+ " cannot follow `PortPlot.new()` and misses most of the game",
		_class_paths.size() >= 200
	)


func _load_corpus() -> void:
	for path in _files(SCRIPT_ROOT, ".gd"):
		_corpus[path] = _strip_comments(FileAccess.get_file_as_string(path))
	for path in _files(SCENE_ROOT, ".tscn"):
		_corpus[path] = FileAccess.get_file_as_string(path)
	for path in _files("res://tests", ".gd"):
		_corpus[path] = _strip_comments(FileAccess.get_file_as_string(path))
	for path in _files("res://tests", ".tscn"):
		_corpus[path] = FileAccess.get_file_as_string(path)
	for path in _files("res://tools", ".sh"):
		_corpus[path] = FileAccess.get_file_as_string(path)
	_corpus["res://project.godot"] = FileAccess.get_file_as_string("res://project.godot")
	_t.check(
		"the referrer corpus loaded (%d files across scripts/, scenes/, tests/,"
		% _corpus.size()
		+ " tools/ and project.godot) — an empty corpus makes every"
		+ " `no_code_referrer` claim vacuously true",
		_corpus.size() > 300
	)


## Everything before an unquoted `#`. A mention in prose is not a call, and the
## two production files that name `ShipyardBrickEditor` name it in comments.
static func _strip_comments(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var idx := line.find("#")
		while idx >= 0:
			var head := line.substr(0, idx)
			if head.count("\"") % 2 == 0 and head.count("'") % 2 == 0:
				line = head
				break
			idx = line.find("#", idx + 1)
		out.append(line)
	return "\n".join(out)


func _files(root: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
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
	out.sort()
	return out


# ── the closure ───────────────────────────────────────────────────────────────

## Forward from what the engine starts. `strict` strips GDScript comments.
func _closure(strict: bool) -> Dictionary:
	var seen := {}
	var order: Array[String] = []
	var seeds: Array[String] = [str(ProjectSettings.get_setting("application/run/main_scene", ""))]
	for key in ProjectSettings.get_property_list():
		var name := str(key.get("name", ""))
		if not name.begins_with("autoload/"):
			continue
		var value := str(ProjectSettings.get_setting(name, "")).lstrip("*")
		if value.begins_with("res://"):
			seeds.append(value)
	for s in seeds:
		if s.begins_with("res://") and not seen.has(s):
			seen[s] = true
			order.append(s)
	var path_re := RegEx.new()
	path_re.compile("res://[A-Za-z0-9_./\\-]+\\.(gd|tscn)")
	var ident_re := RegEx.new()
	ident_re.compile("[A-Za-z_][A-Za-z0-9_]*")
	var cursor := 0
	while cursor < order.size():
		var path := order[cursor]
		cursor += 1
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		if strict and path.ends_with(".gd"):
			text = _strip_comments(text)
		for m in path_re.search_all(text):
			var found := m.get_string()
			if not seen.has(found):
				seen[found] = true
				order.append(found)
		var here := {}
		for m in ident_re.search_all(text):
			var token := m.get_string()
			if here.has(token) or not _class_paths.has(token):
				continue
			here[token] = true
			var cp := str(_class_paths[token])
			if not seen.has(cp):
				seen[cp] = true
				order.append(cp)
	return seen


func _report_closure() -> void:
	var scenes := 0
	for p in _strict:
		if str(p).ends_with(".tscn"):
			scenes += 1
	print("[closure] strict: %d files (%d scenes) · loose: %d files"
		% [_strict.size(), scenes, _loose.size()])
	var prose_only: Array[String] = []
	for p in _loose:
		if not _strict.has(p):
			prose_only.append(str(p))
	prose_only.sort()
	print("[closure] reached ONLY through prose (%d): %s" % [prose_only.size(), str(prose_only)])
	_t.check(
		"the seeds produced a closure that is most of the project (%d files) —"
		% _strict.size()
		+ " a collapsed walker would make every register entry trivially true",
		_strict.size() >= 250
	)


func _check_walker_is_alive() -> void:
	for must in WALKER_CONTROLS:
		_t.check(
			"the closure reaches %s, which the game demonstrably runs"
			% str(must).trim_prefix("res://"),
			_strict.has(must)
		)


func _check_what_defeats_the_scan() -> void:
	## A `uid://` load is invisible to a path walker and would produce a FALSE
	## unreachable — the one direction this unit must not fail in silently.
	var uid_sites: Array[String] = []
	var runtime_paths: Array[String] = []
	var uid_re := RegEx.new()
	uid_re.compile("uid://")
	var built_re := RegEx.new()
	built_re.compile("\"res://[^\"]*%[sdf]")
	for path in _corpus:
		if not str(path).begins_with(SCRIPT_ROOT):
			continue
		var text := str(_corpus[path])
		if uid_re.search(text) != null:
			uid_sites.append(str(path))
		if built_re.search(text) != null:
			runtime_paths.append(str(path))
	print("[defeats] res:// paths built at runtime in scripts/ (%d): %s"
		% [runtime_paths.size(), str(runtime_paths)])
	print("[defeats] population excludes the declared roots %s and every"
		% str(EXCLUDED_ROOTS)
		+ " authoring surface written outside scenes/apps or scripts/apps")
	_t.check(
		"no script loads a resource by `uid://` (%d sites: %s) — one would be"
		% [uid_sites.size(), str(uid_sites)]
		+ " invisible to this walker and would read as UNREACHABLE",
		uid_sites.is_empty()
	)


# ── the population ────────────────────────────────────────────────────────────

## Every `.tscn` the project ships outside the declared excluded roots, plus
## every `.gd` in the app cluster. Discovered, so a new app scene joins it the
## day it lands and does not need to be added anywhere.
func _population() -> Array[String]:
	var out: Array[String] = []
	var excluded := 0
	for p in _files(SCENE_ROOT, ".tscn"):
		var skip := false
		for root in EXCLUDED_ROOTS:
			if p.begins_with(str(root) + "/"):
				skip = true
		if skip:
			excluded += 1
			continue
		out.append(p)
	for p in _files(APP_SCRIPT_ROOT, ".gd"):
		out.append(p)
	out.sort()
	print("[population] %d files (%d scenes excluded by the declared roots %s)"
		% [out.size(), excluded, str(EXCLUDED_ROOTS)])
	_t.check(
		"the population is a real listing (%d files, %d of them in the app cluster)"
		% [out.size(), _files(APP_SCENE_ROOT, ".tscn").size() + _files(APP_SCRIPT_ROOT, ".gd").size()]
		+ " — a root that stopped listing would make the set equality below"
		+ " compare two empty sets",
		out.size() >= 15
	)
	return out


# ── the register polices itself ───────────────────────────────────────────────

func _check_register_is_well_formed() -> void:
	var bad_kind: Array[String] = []
	var no_reason: Array[String] = []
	var asserts_a_caller: Array[String] = []
	for key in KNOWN_UNREACHABLE:
		var entry: Dictionary = KNOWN_UNREACHABLE[key]
		if not CLAIM_KINDS.has(str(entry.get("claim", ""))):
			bad_kind.append(str(key))
		var reason := str(entry.get("reason", ""))
		if reason.strip_edges().length() < 20:
			no_reason.append(str(key))
		var low := reason.to_lower()
		for phrase in CALLER_ASSERTING_PHRASES:
			if low.contains(str(phrase)) and not asserts_a_caller.has(str(key)):
				asserts_a_caller.append(str(key))
	_t.check(
		"every register entry declares a claim kind this file can verify"
		+ " (%d cannot: %s) — a kind with no verifier is an excuse with no check"
		% [bad_kind.size(), str(bad_kind)],
		bad_kind.is_empty()
	)
	_t.check(
		"every register entry carries a reason (%d do not: %s)"
		% [no_reason.size(), str(no_reason)],
		no_reason.is_empty()
	)
	_t.check(
		"no register reason asserts that something reaches the file (%d do: %s)"
		% [asserts_a_caller.size(), str(asserts_a_caller)]
		+ " — this is the sentence signal_reach_test accepted for"
		+ " `layout_confirmed`, and it was false",
		asserts_a_caller.is_empty()
	)


func _check_set_equality(population: Array[String]) -> void:
	var unreachable: Array[String] = []
	for p in population:
		if not _strict.has(p):
			unreachable.append(p)
	var unregistered: Array[String] = []
	for p in unreachable:
		if not KNOWN_UNREACHABLE.has(p):
			unregistered.append(p)
	var struck_off: Array[String] = []
	var vanished: Array[String] = []
	var outside: Array[String] = []
	for key in KNOWN_UNREACHABLE:
		var k := str(key)
		if not FileAccess.file_exists(k):
			vanished.append(k)
			continue
		if not population.has(k):
			outside.append(k)
			continue
		if _strict.has(k):
			struck_off.append(k)
	print("[reach] population %d · reachable %d · unreachable %d · register %d"
		% [population.size(), population.size() - unreachable.size(), unreachable.size(),
			KNOWN_UNREACHABLE.size()])
	for p in unreachable:
		print("  NOT REACHABLE  %s" % p.trim_prefix("res://"))

	_t.check(
		"every unreachable file in the population is named in KNOWN_UNREACHABLE"
		+ " (%d are not: %s) — a new one is a FINDING, not a register line"
		% [unregistered.size(), str(unregistered)],
		unregistered.is_empty()
	)
	_t.check(
		"no register entry has become reachable (%d have: %s) — strike it off"
		% [struck_off.size(), str(struck_off)]
		+ " the day the door is built, so the register can only shrink",
		struck_off.is_empty()
	)
	_t.check(
		"every register entry still names a file that exists (%d do not: %s)"
		% [vanished.size(), str(vanished)]
		+ " — an excuse that outlives its subject is a claim that has rotted",
		vanished.is_empty()
	)
	_t.check(
		"every register entry is inside the population this unit walks (%d are"
		% outside.size()
		+ " not: %s) — an entry outside it is never re-checked" % str(outside),
		outside.is_empty()
	)
	## The conserved statement, said once as a set equality rather than implied
	## by the four checks above.
	_t.check(
		"the unreachable set and the register are the same set (%d vs %d)"
		% [unreachable.size(), KNOWN_UNREACHABLE.size()],
		unreachable.size() == KNOWN_UNREACHABLE.size()
	)


# ── every claim is verified, none is taken on prose ───────────────────────────

func _check_every_claim() -> void:
	var keys: Array[String] = []
	for key in KNOWN_UNREACHABLE:
		keys.append(str(key))
	keys.sort()
	for key in keys:
		var entry: Dictionary = KNOWN_UNREACHABLE[key]
		match str(entry.get("claim", "")):
			"gate_selfcheck":
				_verify_gate_selfcheck(key, str(entry.get("arg", "")))
			"hosts_script":
				_verify_hosts_script(key, str(entry.get("arg", "")))
			"scene_tree_script":
				_verify_scene_tree_script(key)
			"no_code_referrer":
				_verify_no_code_referrer(key)
			_:
				## Unrecognised kinds already failed `_check_register_is_well_formed`;
				## this is the second half of that rule — no silent skip.
				_t.fail("register entry %s declares an unverifiable claim" % key)


## "The gate boots it from a command line." Checkable, and it is the only
## legitimate-looking excuse in this register, so it gets the most checking:
## the lane-C self-check marker must exist, must name this scene, and its
## flag must actually appear in the script that parses the command line.
func _verify_gate_selfcheck(key: String, scene: String) -> void:
	var script_path := key if key.ends_with(".gd") else _script_of_scene(key)
	var text := FileAccess.get_file_as_string(script_path)
	var marker := ""
	for line in text.split("\n"):
		if str(line).begins_with(SELFCHECK_PREFIX):
			marker = str(line)
			break
	if not _t.check(
		"%s: its script %s declares a lane-C self-check marker, so the gate"
		% [key.get_file(), script_path.get_file()]
		+ " boots it every run",
		not marker.is_empty()
	):
		_t.fail("%s: no marker, so its scene and flag cannot be checked" % key.get_file())
		_t.fail("%s: no marker, so its flag is not parsed by anything" % key.get_file())
		return
	_t.check(
		"%s: the marker names this very scene (%s)" % [key.get_file(), scene],
		marker.contains(scene)
	)
	var flag := ""
	var idx := marker.find(" -- ")
	if idx >= 0:
		for token in marker.substr(idx + 4).strip_edges().split(" "):
			if str(token).begins_with("--"):
				flag = str(token)
				break
	_t.check(
		"%s: the marker's flag `%s` is a literal in the script, so the app really"
		% [key.get_file(), flag]
		+ " parses the command line the gate types",
		not flag.is_empty() and _strip_comments(text).contains("\"%s\"" % flag)
	)


## A scene whose only content is a host for a registered script inherits that
## script's justification — and only if the wrapping is real and the script is
## itself in the register, so the chain cannot end in nothing.
func _verify_hosts_script(key: String, script: String) -> void:
	var text := FileAccess.get_file_as_string(key)
	_t.check(
		"%s: really is a wrapper — its ext_resource names %s"
		% [key.get_file(), script.trim_prefix("res://")],
		text.contains("path=\"%s\"" % script)
	)
	_t.check(
		"%s: the script it wraps is itself registered, so the excuse chains to"
		% key.get_file()
		+ " a checked claim rather than to nothing",
		KNOWN_UNREACHABLE.has(script)
	)


## `extends SceneTree` cannot be assigned to a Node — `gate.sh` calls that
## pairing STALE and refuses to run it — so such a file is `--script`-only by
## construction and is not a surface anybody could open, now or later.
func _verify_scene_tree_script(key: String) -> void:
	var code := _strip_comments(FileAccess.get_file_as_string(key))
	var is_scene_tree := false
	for line in code.split("\n"):
		if str(line).strip_edges() == "extends SceneTree":
			is_scene_tree = true
			break
	_t.check(
		"%s: is `extends SceneTree`, so it cannot be attached to a node in any"
		% key.get_file()
		+ " scene and is a command-line script by construction",
		is_scene_tree
	)
	var hosts: Array[String] = []
	for path in _corpus:
		if str(path).ends_with(".tscn") and str(_corpus[path]).contains(key):
			hosts.append(str(path))
	_t.check(
		"%s: no .tscn anywhere tries to host it (%d do: %s)"
		% [key.get_file(), hosts.size(), str(hosts)],
		hosts.is_empty()
	)


## REALITY §3's rule, written as a check: "grep for its entry point outside
## tests/; if the only callers are test rigs, it does not exist yet." This is
## NOT implied by the closure — a file with a live code referrer that is itself
## unreachable passes the closure test and fails this one.
func _verify_no_code_referrer(key: String) -> void:
	var tokens: Array[String] = [key]
	for name in _class_paths:
		if str(_class_paths[name]) == key:
			tokens.append(str(name))
	var referrers: Array[String] = []
	for path in _corpus:
		var p := str(path)
		if p == key:
			continue
		if p.begins_with(APP_SCRIPT_ROOT + "/") or p.begins_with(APP_SCENE_ROOT + "/"):
			continue
		if p.begins_with("res://tests/"):
			continue
		var text := str(_corpus[path])
		for token in tokens:
			if text.contains(str(token)) and not referrers.has(p):
				referrers.append(p)
	_t.check(
		"%s: nothing outside the app cluster and tests/ names it in code (%d do:"
		% [key.get_file(), referrers.size()]
		+ " %s) — searched %s" % [str(referrers), str(tokens)],
		referrers.is_empty()
	)


func _script_of_scene(scene: String) -> String:
	var text := FileAccess.get_file_as_string(scene)
	var re := RegEx.new()
	re.compile("path=\"(res://[^\"]+\\.gd)\"")
	var m := re.search(text)
	return m.get_string(1) if m != null else ""
