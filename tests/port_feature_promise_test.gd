extends Node

## LANE B — EVERY FACILITY THE PORT UI PRESENTS TO A PLAYER IS EITHER BUILT IN
## THE WORLD, OR NAMED IN A REGISTER WITH A CLAIM THAT IS CHECKED.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/port_feature_promise_test.tscn
##
## ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
##
## `port_expander.gd:170,172` appends **"Lighthouse"** and **"Fog Horn"** to a
## port's `features`, and `map_overlay.gd:441` prints them to the player in the
## home-port pick panel: `FACILITIES  Lighthouse, Fog Horn, Fish Landing`.
## **Nothing in the world builds either one.** A player picks a harbour because
## it has a lighthouse, sails there, and there is no lighthouse — and every
## check in the gate was green, because no check anywhere asserted that an
## advertised facility corresponds to something a player can find. That is
## REALITY §4b: a whole property with no check pointed at it.
##
## It is not lighthouse-specific and this file is deliberately not written that
## way. The property is:
##
##     for every port the pick panel presents a facility on,
##       the world's stamp of THAT port contains that facility
##       — or the facility is in UNBUILT_PROMISES with a CHECKED claim.
##
## ── THE TWO SIDES ARE DERIVED INDEPENDENTLY, AND THAT IS THE WHOLE POINT ────
##
## Six checks in this repo this month were one derivation testing itself —
## `port_apron_draw_test`'s header records the pad case, where the outline was
## read back out of the dictionary that produced it. The trap here is obvious
## and fatal: `PortData.has_lighthouse` sets the feature string AND would be the
## easy thing to assert the world against. That check passes on a world with no
## lighthouse in it.
##
## **ADVERTISED** is taken by DRIVING THE PRODUCTION UI. `ChartDataSnapshot`
## (`PortExpander.chart_summary` per port) → `MapOverlay.set_data_snapshot` →
## `enter_home_port_pick_mode(port_id)` → the `FACILITIES` line is read out of
## `pick_body.text`. No facility string is written down in this file: the
## vocabulary is whatever the panel prints, so a feature added to
## `port_expander.gd` tomorrow joins the population without anybody editing a
## list here — and is checked for delivery the same day.
##
## **DELIVERED** is taken from the NODE TREE the game stamps: `PortExpander.expand`
## → `PortPlot.configure` → `PortLayoutGraphVisualizer` and the rest of
## `_rebuild()`, then a walk of the resulting subtree. A facility is delivered at
## a port when that port's stamped tree holds a `Node3D` whose name matches the
## facility's and which draws at least one `MeshInstance3D`. It reads no flag, no
## `features` array and no layout-graph attribute. The two sides can and do
## disagree: **Fish Landing** was in the register below until 2026-08-17, because
## the panel printed ELIGIBILITY while the world built from the BERTH PLAN, and
## those are not the same question. That entry is struck off — the two producers
## now share one derivation (`PortExpander.summary_expansion`, which since the
## parallel-derivation collapse supplies the panel's WHOLE dossier and not just
## this flag) — and this file is what would catch the divergence coming back.
##
## Name matching is deliberately LOOSE (lowercase, alphanumerics only,
## substring): `"Fish Landing"` is delivered by `FishLandingPlant`. Loose is the
## safe direction for a promise checker — it under-reports broken promises, so
## everything it DOES report is real. What it cannot do is tell a facility from a
## same-named node that has nothing to do with it; the `MeshInstance3D`
## requirement is what stops a bare marker or a label from answering.
##
## ── WHY LANE B ──────────────────────────────────────────────────────────────
##
## Under `--script`, `harbour_authority_bridge.gd` and `harbour_master_npc.gd`
## name `WorldGateway` / `LocalPlayerView` as bare identifiers, the cascade takes
## `harbour_controller.gd`, `port_layout_graph_visualizer.gd` and `port_plot.gd`
## with it, and `HarbourController.activate()` plus `_spawn_harbour_staff()` both
## die with *"Nonexistent function 'new'"*. Measured 2026-08-17. A third of the
## port stamp never happens — and a verdict of "the world does not build it",
## read off a stamp that could not build anything, is an instrument artefact
## (REALITY §8, check the camera before you blame the subject). Booted as a
## scene the autoloads exist and the whole stamp runs. The two stamp floors below
## re-measure that on every run rather than trusting this paragraph — and the
## second of them exists because a mutation walked straight past the first.
##
## ── WHAT THIS DOES NOT COVER ────────────────────────────────────────────────
##
## Stated here rather than left for a reader to discover, because a check that
## quietly excludes what it cannot see is worse than one that names the gap.
##
## 1. **The delivery survey is a WITNESS SAMPLE, not a census.** Stamping a port
##    costs 0.2–1.0 s and the survey is 142 of them. Delivery is measured at a
##    DECLARED, deterministic set of witnesses — per facility AND per population,
##    the smallest and largest size that advertises it, plus the divergence
##    witness where one exists — so `BROKEN` below is a LOWER BOUND. A facility
##    broken only at ports outside the witness set is not seen. TEN ports are
##    stamped today and they are printed by id on every run.
## 2. **Geometry outside the port plot is not walked.** A lighthouse placed on a
##    headland by `world.gd` rather than inside `PortPlot` would read as
##    undelivered here. That is why the `builder_exists_unplaced` claim also
##    checks, in source, that nothing outside a showcase constructs the builder
##    class at all — the two together cover the world, not just the plot.
## 3. **Whether a delivered facility WORKS.** `FishLandingPlant` draws meshes;
##    whether a player can land fish at it is a different property.
## 4. **The `Export:` half of `features` is filtered out by the panel** and is
##    therefore outside this property. It is not re-listed here — the filter is
##    observed by comparing what the panel printed against what the port's
##    `features` held, and the strings the panel dropped are counted and printed.
## 5. **NO PORT ANYWHERE IN THIS PROJECT IS BIGGER THAN SIZE 4.** The placer
##    tops out at 4 over both world seeds, and population B — which ASKS for
##    0…8 — is clamped to 4 as well, because `chart_summary` caps `size` at
##    `PortTradeProfile.max_size_for_profile`. Population B widens the region
##    kinds and forces both facility flags on; it does not widen the size range.
##    So nothing here is evidence about a size-5-to-8 harbour, and
##    `OBSERVED_SIZES` reds the day one exists rather than leaving that to this
##    paragraph.
## 6. **A second presenter, or a second way into the pick panel.** Both are
##    declared sets that red when they gain a member (`FEATURE_FILES`,
##    `PICK_MODE_CALLERS`) — but a declared set only reports that something
##    moved; it does not tell you the new surface is safe.

const TestReport := preload("res://tests/support/test_report.gd")

## ── POPULATION A: production placer, real worlds ────────────────────────────
## `ChartDataSnapshot.for_preview` is the exact call `MainMenu` makes through
## `ChartPreviewBootstrap` — world generation, coastal placement, 35 ports,
## `chart_summary` each. Declared as a literal (§4f shape 1): the stable thing
## is the SEED SET, not the port count it happens to yield.
const WORLD_SEEDS := [424242, 20260817]
const PORT_COUNT := 35

## ── POPULATION B: synthetic matrix ──────────────────────────────────────────
## Nine sizes × four region kinds × two flag variants — 72 definitions, and
## cheap: `chart_summary` over all of them is 5 ms against 6–10 SECONDS for one
## seed of population A. Yesterday's measurement of this defect was ONE seed,
## MAINLAND, sizes 0/4/8; this is the widening, and it is the only population
## that reaches `LEGACY_ISLAND` (which `chart_summary` prints as `coastal`) or
## that forces `has_lighthouse` / `has_fog_horn` on rather than leaving them to
## the site RNG.
##
## IT DOES NOT WIDEN THE SIZE RANGE, THOUGH IT ASKS TO — see `OBSERVED_SIZES`.
const SWEEP_SEED := 987654
const REGION_KINDS := [
	PortDefinition.RegionKind.LEGACY_ISLAND,
	PortDefinition.RegionKind.MAINLAND,
	PortDefinition.RegionKind.FJORD,
	PortDefinition.RegionKind.ARCHIPELAGO,
]

const SETTLE_FRAMES := 8

## MEASURED, NOT ASSUMED — and it is not what population B was written to prove.
## The sweep REQUESTS sizes 0…`PortSizing.MAX_SIZE` (8). The expander realizes
## none above 4: `chart_summary` clamps `size` to `PortTradeProfile
## .max_size_for_profile(trade)`, and a definition with no trade weight behind it
## caps at 4 — so does every port the coastal placer produces, over both world
## seeds. **There is no size-5-to-8 port anywhere in this project today, and this
## survey therefore says nothing about one.** Frozen as a declared set rather
## than written in a comment: the day the generator produces a bigger port this
## reds, and the witness rule below has to be widened before the verdict is
## worth anything. Same for the four region words `chart_summary` emits.
const OBSERVED_SIZES := [0, 1, 2, 3, 4]
const OBSERVED_REGIONS := ["archipelago", "coastal", "fjord", "mainland"]

## A stamp that built nothing would make every facility "undelivered" and this
## whole unit would report a catastrophe that is really a broken test. The
## smallest port stamped in lane B carries a few hundred nodes; the floors are
## set well under that and are asserted before any delivery verdict is trusted.
##
## THE SECOND FLOOR EXISTS BECAUSE MUTATION M6 GOT PAST THE FIRST — 2026-08-17.
## Disabling `visualizer.configure()` in `PortPlot._rebuild()` — the entire port
## STAMP, every quay, pad, crane and plant — left the plot at 938 nodes, because
## `_spawn_harbour_staff` builds three NPCs whose garment and body parts are
## hundreds of nodes on their own. The whole-plot floor passed on scenery that
## has nothing to do with facilities, and the unit reported the facilities
## missing for the one reason it promises not to. So the floor that matters is
## on the VISUALISER'S OWN SUBTREE, which is the thing whose absence this file
## would otherwise misread (REALITY §8: check the camera before the subject).
const STAMP_FLOOR_NODES := 100
const STAMP_FLOOR_VISUALISER_NODES := 100
const VISUALISER_NODE := "PortLayoutGraph"

## Every file outside `tests/` whose comment-stripped source names `features`.
## DECLARED, not discovered (§4f shape 1). The advertised side of this unit is
## derived by driving ONE presenter, `map_overlay.gd`. If a second surface
## starts printing `features` to a player, this list gains a member and this
## check goes red — which is the only way this file learns that its derivation
## has stopped covering the property.
const FEATURE_FILES := [
	"res://scripts/port/port_catalog.gd",
	"res://scripts/port/port_data.gd",
	"res://scripts/port/port_expander.gd",
	"res://scripts/port/port_plot.gd",
	"res://scripts/ui/map_overlay.gd",
	"res://scripts/world/world.gd",
]
const MAP_OVERLAY_PATH := "res://scripts/ui/map_overlay.gd"

## THE PICK PANEL IS FED BY ONE SNAPSHOT FACTORY, AND THAT IS LOAD-BEARING HERE.
## There are two. `ChartDataSnapshot.for_preview` fills `features` from
## `chart_summary`; `from_live_tree` fills it from `PortCatalog`, which is
## `expand_uncached`'s list — and THAT one also carries **"Terrain-traced Port
## Layout"**, a string no port stamp builds anything for. It reaches no player
## today for one reason only: the in-game chart uses the live-tree factory and
## `open_navigation()`, never pick mode, and `_refresh_pick_panel` returns early
## outside pick mode. Measured 2026-08-17 — `main_menu.gd:432` is the ONLY
## production call to `enter_home_port_pick_mode`.
##
## One such call in `game_menu.gd` would put that string in front of a player,
## and `FEATURE_FILES` above would not notice, because no new file would name
## `features`. So the panel's entry points are declared as well.
const PICK_MODE_CALLERS := [
	"res://scripts/ui/main_menu.gd",
]

## A claim kind with no verifier is a claim nobody checks. The set is closed and
## an entry naming something outside it is a hard FAIL, not a silent skip — the
## rule `entry_reach_test` uses, for the same reason.
## `advertised_before_realized` HAS NO ENTRY TODAY — the fish landing was struck
## off on 2026-08-17 — and it is kept rather than deleted because this file's rule
## is that an entry naming a kind outside this set is a hard FAIL. Deleting the
## kind and its verifier would leave the next facility of that shape with nowhere
## to be registered and no worked example of the four checks it owes.
const CLAIM_KINDS := [
	"builder_exists_unplaced",
	"advertised_before_realized",
]

## A reason may say what the promise IS and why it is broken. It may not claim
## the world delivers it — that contradicts the register's own membership, and
## it is the exact shape of the false sentence `signal_reach_test` accepted for
## `layout_confirmed` and that `entry_reach_test` carried for the lighthouse
## until today ("the port placer builds its own lighthouse geometry" — it sets a
## boolean).
const DELIVERY_ASSERTING_PHRASES := [
	"is built in the world",
	"the world builds",
	"the port builds",
	"the placer builds",
	"the stamp draws it",
	"the visualiser draws it",
	"a player can find it",
]

## ── THE REGISTER ────────────────────────────────────────────────────────────
##
## Facility string → `{reason, claim, arg}`. POLICED IN BOTH DIRECTIONS, as a
## set equality against what the witness survey measures:
##
##     { facilities a witness port advertises and does not deliver }
##       ==  { keys of UNBUILT_PROMISES }
##
## A newly-unbuilt facility fails. A registered one that becomes built fails
## until it is struck off. An entry whose facility stops being advertised at all
## fails. It can only shrink.
##
## **NOTHING HERE IS APPROVED, AND NOTHING HERE IS WIRED.** Every entry is a
## promise the game makes to a player and does not keep. Where the lighthouse
## and the fog horn go is an owner decision on record in STATE.md 2026-08-17;
## making this file green by building one is not this check's job and would
## destroy the only record of the gap.
const UNBUILT_PROMISES := {
	"Lighthouse": {
		"reason": "`port_expander.gd:170` appends this whenever the port's"
			+ " `has_lighthouse` is set, which `coastal_port_placer.gd:598`"
			+ " sets for the home port and every fifth site. The scene"
			+ " `scenes/systems/lighthouse_building.tscn` and the class"
			+ " `LighthouseBuilding` are FINISHED — a 26 m tapered tower with"
			+ " gallery ring, lantern drum and a rotating volumetric beam —"
			+ " and no port stamp instantiates either. The only lighthouse a"
			+ " player ever sees is a hand-built silhouette in the main-menu"
			+ " backdrop, which is a different class in a different scene.",
		"claim": "builder_exists_unplaced",
		"arg": "LighthouseBuilding",
	},
	"Fog Horn": {
		"reason": "`port_expander.gd:172` appends this whenever `has_fog_horn`"
			+ " is set, which `coastal_port_placer.gd:599` sets for the home"
			+ " port and every seventh site — the commonest promise in the"
			+ " panel. `FogHornBuilding` is a modelled station with a flared"
			+ " trumpet and a `FogHorn` that samples fog at five points with"
			+ " hysteresis, and it is constructed in NO file in the project,"
			+ " not even a showcase. `fog_horn_1.wav` is 2.3 MB shipped and"
			+ " nothing reaches the code that would play it.",
		"claim": "builder_exists_unplaced",
		"arg": "FogHornBuilding",
	},
	## ── STRUCK OFF 2026-08-17: "Fish Landing" ──────────────────────────────────
	##
	## The promise is kept. `chart_summary` no longer prints raw
	## `PortFishingService.is_eligible`; it reads the flag back from the realized
	## berth plan through `PortExpander.summary_expansion`, so the panel and the
	## world now have ONE derivation of the fact (REALITY §3b) and the set equality
	## below no longer names it. Deleting the entry rather than editing it is the
	## rule this register is written on: it can only shrink.
	##
	## WHAT WAS NOT DONE, AND IS THE OWNER'S: the 52 ports that lost the promise
	## lost it because they are size 0, where `PortTradeProfile._import_count(0)` is
	## 0 and the size ladder trims `fresh_groundfish` out of the trade slots before
	## the berth plan reads them. Whether a hamlet should get a fish landing anyway
	## is a world-building decision, and building 52 of them to make a panel honest
	## is the wrong direction. Measured consequence of the honest fix, six seeds and
	## 210 ports: 85 ports still land fish, never fewer than 11 in a world, so a
	## fishing captain still has a home port — but `port-home` itself is one of them
	## in only 3 of the 6 seeds measured.
}

## §4f shape 4, under the set equality. Most of this file's checks sit in a loop
## over the ADVERTISED VOCABULARY, which is discovered from the panel — a port
## generator that stopped advertising a facility would delete its checks rather
## than fail them, and the run would stay green with less coverage. The
## populations are declared and floored, which catches a collection that went
## EMPTY; this catches one that merely got SMALLER (§4f: a floor is not a
## budget). Re-freeze it in the SAME commit as the checks you add.
##
## Measured 2026-08-17 against `WORLD_SEEDS`, `SWEEP_SEED` and port generation
## version 46, and enumerated rather than copied off a run — a budget re-frozen to
## match a number nobody predicted is the guard writing the answer down for you:
##
##  11  advertised-side, coverage and derivation checks
##  10  witness-stamp floors — one per DISTINCT witness port stamped. Twelve
##      witnesses are chosen (three facilities × two populations × smallest and
##      largest), of which `sweep-4-0-on` answers for all three facilities and
##      `sweep-0-0-nat` for two, leaving ten stamps.
##   3  register well-formedness checks
##   8  claim verifications — 2 entries × 4
##   1  the set equality
##   1  this budget, counting itself
##  ── 34
##
## It was 35 with three register entries and nine stamps. Striking **Fish Landing**
## on 2026-08-17 removed its four claim checks; its witness set also lost the
## divergence witness it no longer has, and the two extremes it now contributes
## (`port-4`, `sweep-1-0-nat`) are ports no other facility nominates, so the stamp
## count rose by one. 35 − 4 + 1 = 32.
##
## 32 → 34 later the same day, and PREDICTED before the run rather than read off
## it: collapsing `chart_summary`'s parallel derivation made the panel publish the
## world's `features` verbatim, so `PortExpander.LAYOUT_FEATURE_NOTE` now arrives
## on the preview path and `map_overlay` filters it. That added exactly the two
## advertised-side checks that hold it from both ends — every surveyed port really
## carries the note, and the panel prints it to nobody. This budget caught the
## addition on the first run, which is the guard working in the direction nobody
## usually tests.
const EXPECTED_CHECKS := 34

var _t := TestReport.new("port_feature_promise_test")
var _world: Node3D
## Every surveyed port, in survey order.
## {pop, seed, id, size, region, definition, advertised, features, layout}
var _survey: Array[Dictionary] = []
var _vocabulary: Array[String] = []
var _placeholders: Dictionary = {}
var _unbacked: Array[String] = []
var _dropped_by_panel: Dictionary = {}
## facility -> {port_id -> bool}
var _delivered: Dictionary = {}
var _witnesses: Dictionary = {}
var _realized: Dictionary = {}
var _world_feature_cache: Dictionary = {}
var _stripped: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	_load_stripped_sources()
	await _collect_advertised()
	_check_advertised_side()
	await _collect_delivered()
	_check_register_is_well_formed()
	_check_every_claim()
	_check_set_equality()
	_t.check(
		"the unit ran the number of checks it was frozen at (%d, expected %d) —"
		% [_t.check_count() + 1, EXPECTED_CHECKS]
		+ " a fall means a check stopped being reached, not that it passed (§4f)",
		_t.check_count() + 1 == EXPECTED_CHECKS
	)
	_t.finish(get_tree())


# ── the advertised side: drive the production pick panel ──────────────────────

func _collect_advertised() -> void:
	var overlay := MapOverlay.new()
	add_child(overlay)
	await get_tree().process_frame

	## POPULATION A — the production path end to end, exactly as MainMenu runs
	## it through ChartPreviewBootstrap.
	for world_seed in WORLD_SEEDS:
		var snap := ChartDataSnapshot.for_preview(int(world_seed), PORT_COUNT)
		overlay.set_data_snapshot(snap)
		for id_raw in snap.port_ids():
			_record(overlay, snap, "A", int(world_seed), str(id_raw), snap.layout)

	## POPULATION B — the same producer and the same presenter, over a matrix
	## the placer cannot reach. Assembled here rather than generated, which is
	## what `port_apron_draw_test` does for the same reason: world generation is
	## six seconds a seed and none of it feeds `features`.
	var sweep := ChartDataSnapshot.new()
	sweep.world_seed = SWEEP_SEED
	sweep.preview = true
	## Population B has no WorldLayout, so its field state must be DECLARED rather
	## than inherited from whichever seed of population A ran last — see
	## `_bake_fields`.
	_bake_fields(null, SWEEP_SEED)
	for size in range(PortSizing.MAX_SIZE + 1):
		for region in REGION_KINDS:
			for forced in [false, true]:
				sweep.ports.append(PortExpander.chart_summary(
					_sweep_definition(size, int(region), forced), SWEEP_SEED))
	sweep._index_ports()
	overlay.set_data_snapshot(sweep)
	for id_raw in sweep.port_ids():
		_record(overlay, sweep, "B", SWEEP_SEED, str(id_raw), null)

	overlay.queue_free()
	await get_tree().process_frame

	var vocab: Dictionary = {}
	for row in _survey:
		for f in (row["advertised"] as Array):
			vocab[str(f)] = true
	for f in vocab:
		_vocabulary.append(str(f))
	_vocabulary.sort()

	var sizes: Dictionary = {}
	var regions: Dictionary = {}
	for row in _survey:
		sizes[int(row["size"])] = true
		regions[str(row["region"])] = true
	var sk: Array = sizes.keys()
	sk.sort()
	var rk: Array = regions.keys()
	rk.sort()
	print("[advertised] %d ports surveyed · seeds %s + sweep %d · sizes %s · regions %s"
		% [_survey.size(), str(WORLD_SEEDS), SWEEP_SEED, str(sk), str(rk)])
	print("[advertised] the panel's FACILITIES vocabulary (%d): %s"
		% [_vocabulary.size(), str(_vocabulary)])
	print("[advertised] printed with no feature behind it (panel placeholders): %s"
		% str(_placeholders))
	print("[advertised] feature strings the panel DROPPED (%d distinct): %s"
		% [_dropped_by_panel.size(), str(_dropped_by_panel.keys())])


func _sweep_definition(size: int, region: int, forced: bool) -> PortDefinition:
	var definition := PortDefinition.new()
	definition.port_id = "sweep-%d-%d-%s" % [size, region, "on" if forced else "nat"]
	definition.display_name = "SWEEP %d/%d" % [size, region]
	definition.size = size
	definition.region_kind = region as PortDefinition.RegionKind
	definition.site_seed = SWEEP_SEED ^ (size * 7919) ^ (region * 104729) ^ (1 if forced else 0)
	definition.has_lighthouse = forced
	definition.has_fog_horn = forced
	definition.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	return definition


## One port, taken through the production presenter and read back out of the
## label a player reads.
##
## Splitting what the panel printed into BACKED and UNBACKED is how the panel's
## own filter gets observed instead of re-listed. A port whose whole `features`
## list is filtered away prints one placeholder string and nothing else — that
## shape is identified structurally (nothing printed is a feature, and exactly
## one thing was printed), never by naming the placeholder.
func _record(
		overlay: MapOverlay,
		snap: ChartDataSnapshot,
		pop: String,
		world_seed: int,
		port_id: String,
		layout: WorldLayout,
) -> void:
	overlay.enter_home_port_pick_mode(port_id)
	var printed: Array[String] = []
	for bit in _facilities_line(overlay.pick_body.text).split(", "):
		var s := str(bit).strip_edges()
		if not s.is_empty():
			printed.append(s)
	var info := snap.port_info(port_id)
	var features: Array = info.get("features", []) as Array
	var advertised: Array[String] = []
	var loose: Array[String] = []
	for s in printed:
		if features.has(s):
			advertised.append(s)
		else:
			loose.append(s)
	if advertised.is_empty() and loose.size() == 1:
		_placeholders[loose[0]] = int(_placeholders.get(loose[0], 0)) + 1
	else:
		for s in loose:
			_unbacked.append("%s:%s" % [port_id, s])
	for f in features:
		if not advertised.has(str(f)):
			_dropped_by_panel[str(f)] = int(_dropped_by_panel.get(str(f), 0)) + 1
	_survey.append({
		"pop": pop,
		"seed": world_seed,
		"id": port_id,
		"size": int(info.get("size", -1)),
		"region": str(info.get("region", "?")),
		"definition": PortDefinition.from_dict(info.get("port_definition", {}) as Dictionary),
		"advertised": advertised,
		"features": features,
		"layout": layout,
	})


static func _facilities_line(text: String) -> String:
	for line in text.split("\n"):
		if str(line).begins_with("FACILITIES  "):
			return str(line).substr("FACILITIES  ".length())
	return ""


func _check_advertised_side() -> void:
	var floor_ports := WORLD_SEEDS.size() * PORT_COUNT \
			+ (PortSizing.MAX_SIZE + 1) * REGION_KINDS.size() * 2
	_t.check(
		"the panel was driven over the whole declared population (%d ports, %d"
		% [_survey.size(), floor_ports]
		+ " declared) — a shrunken survey deletes checks below rather than"
		+ " failing them",
		_survey.size() == floor_ports
	)
	_t.check(
		"the advertised vocabulary is not empty (%d: %s) — a panel that printed"
		% [_vocabulary.size(), str(_vocabulary)]
		+ " nothing would make this whole unit pass by asking nothing",
		_vocabulary.size() >= 2
	)
	_t.check(
		"every string the panel printed is a feature that port really has, or"
		+ " the panel's lone empty-list placeholder (%d unbacked: %s) — an"
			% [_unbacked.size(), str(_unbacked)]
		+ " unbacked string is a promise with no producer at all",
		_unbacked.is_empty()
	)
	_t.check(
		"the panel prints exactly one placeholder for a port with no presentable"
		+ " feature (%d distinct: %s) — a second one would be a facility name"
			% [_placeholders.size(), str(_placeholders.keys())]
		+ " this survey is mis-reading as boilerplate",
		_placeholders.size() == 1
	)
	_t.check(
		"the panel really does drop part of `features` (%d distinct dropped: %s)"
		% [_dropped_by_panel.size(), str(_dropped_by_panel.keys())]
		+ " — the filter is OBSERVED here, not re-listed, so a change to it"
		+ " moves this population instead of going unnoticed",
		_dropped_by_panel.size() >= 1
	)
	## ── the generation note, both ways — 2026-08-17 ───────────────────────────
	##
	## `PortExpander.LAYOUT_FEATURE_NOTE` is a note about how the harbour was
	## generated and no port stamp builds anything for it. Until today it was in the
	## WORLD's list only, and reached no player because pick mode is menu-only and
	## the menu used the other producer. `chart_summary` stopped re-deriving its own
	## feature list and now publishes the world's verbatim, so the note arrives on
	## the preview path too and `map_overlay` filters it beside `Export:`.
	##
	## Asserted from BOTH sides, because either one alone is vacuous: that every
	## surveyed port really carries the note (otherwise the filter check below has
	## nothing to filter and would pass on an empty population — REALITY §4), and
	## that no port's panel printed it.
	var carrying := 0
	var printing: Array[String] = []
	for row in _survey:
		if (row["features"] as Array).has(PortExpander.LAYOUT_FEATURE_NOTE):
			carrying += 1
		if (row["advertised"] as Array).has(PortExpander.LAYOUT_FEATURE_NOTE):
			printing.append(str(row["id"]))
	_t.equal(
		"every surveyed port's `features` carries the generation note — the panel"
		+ " publishes the world's list verbatim, so a port without it means the"
		+ " producer changed and the filter check below is asking nothing",
		carrying,
		_survey.size(),
	)
	_t.check(
		"and the panel prints it to nobody (%d ports would: %s) — it is a note"
			% [printing.size(), str(printing)]
		+ " about generation, not a facility, and it is advertised at every port"
		+ " while being built at none",
		printing.is_empty(),
	)
	var sizes: Dictionary = {}
	var regions: Dictionary = {}
	for row in _survey:
		sizes[int(row["size"])] = true
		regions[str(row["region"])] = true
	var sk: Array = sizes.keys()
	sk.sort()
	var rk: Array = regions.keys()
	rk.sort()
	_t.check(
		"the survey realized exactly the declared port sizes (%s, declared %s) —"
		% [str(sk), str(OBSERVED_SIZES)]
		+ " the sweep ASKS for 0…%d and the expander clamps every one above 4,"
			% PortSizing.MAX_SIZE
		+ " so nothing here is evidence about a bigger port; when one appears,"
		+ " widen the witness rule before believing this file",
		sk == OBSERVED_SIZES
	)
	_t.check(
		"the survey realized exactly the declared region kinds (%s, declared %s)"
		% [str(rk), str(OBSERVED_REGIONS)]
		+ " — the placer never emits `coastal`, and population B exists to reach"
		+ " it",
		rk == OBSERVED_REGIONS
	)
	## The derivation guard. This unit reads ONE presenter; if a second appears,
	## the advertised set silently stops covering the property.
	var namers: Array[String] = []
	for path in _stripped:
		if str(_stripped[path]).contains("features"):
			namers.append(str(path))
	namers.sort()
	var declared: Array[String] = []
	for p in FEATURE_FILES:
		declared.append(str(p))
	declared.sort()
	_t.check(
		"the set of production files naming `features` is the declared one (%d"
		% namers.size()
		+ " found: %s / %d declared) — a new member may be a second surface"
			% [str(namers), declared.size()]
		+ " presenting facilities, and this unit drives only map_overlay",
		namers == declared
	)
	var pickers: Array[String] = []
	for path in _stripped:
		if str(path) == MAP_OVERLAY_PATH:
			continue
		if str(_stripped[path]).contains("enter_home_port_pick_mode"):
			pickers.append(str(path))
	pickers.sort()
	var declared_pickers: Array[String] = []
	for p in PICK_MODE_CALLERS:
		declared_pickers.append(str(p))
	declared_pickers.sort()
	_t.check(
		"the pick panel has exactly the declared entry points (%d found: %s /"
		% [pickers.size(), str(pickers)]
		+ " declared %s) — a second one may feed it the LIVE-TREE feature list,"
			% str(declared_pickers)
		+ " which carries `Terrain-traced Port Layout` and no port stamp builds"
		+ " anything for that; nothing else here would see it",
		pickers == declared_pickers
	)


# ── the delivered side: walk the node tree the game stamps ────────────────────

func _collect_delivered() -> void:
	## The witness set, DECLARED as a rule rather than as port ids: per facility
	## AND PER POPULATION, the smallest and the largest size that advertises it,
	## plus the one port where the world's own realized feature list drops it.
	## Per population matters — without it every witness came from the generated
	## worlds and the synthetic matrix was surveyed but never stamped, which is
	## §3's layer trap one level along: a population that contributes to the
	## question and to none of the answers. Deterministic given the seeds, and
	## printed by id on every run.
	for facility in _vocabulary:
		var rows: Array[Dictionary] = []
		for row in _survey:
			if (row["advertised"] as Array).has(facility):
				rows.append(row)
		if rows.is_empty():
			continue
		var divergent: Dictionary = {}
		var advertised_n := 0
		var realized_n := 0
		var extremes: Dictionary = {}
		for row in rows:
			var pop := str(row["pop"])
			if not extremes.has(pop):
				extremes[pop] = {"small": row, "large": row}
			var pair: Dictionary = extremes[pop]
			if int(row["size"]) < int((pair["small"] as Dictionary)["size"]):
				pair["small"] = row
			if int(row["size"]) > int((pair["large"] as Dictionary)["size"]):
				pair["large"] = row
			advertised_n += 1
			if _world_features(row).has(facility):
				realized_n += 1
			elif divergent.is_empty():
				divergent = row
		var chosen: Array[Dictionary] = []
		var pops: Array = extremes.keys()
		pops.sort()
		for pop in pops:
			for which in ["small", "large"]:
				var row: Dictionary = (extremes[pop] as Dictionary)[which] as Dictionary
				if not _has_id(chosen, str(row["id"])):
					chosen.append(row)
		if not divergent.is_empty() and not _has_id(chosen, str(divergent["id"])):
			chosen.append(divergent)
		_realized[facility] = {
			"advertised": advertised_n,
			"realized": realized_n,
			"divergent_id": str(divergent.get("id", "")),
		}
		_witnesses[facility] = chosen
		print("[witness] %-14s advertised at %d ports, in the world's own feature"
			% [facility, advertised_n]
			+ " list at %d · witnesses %s" % [realized_n, _ids(chosen)])

	## Stamp each distinct witness once and census what the port really built.
	var stamped: Dictionary = {}
	for facility in _vocabulary:
		for row in (_witnesses.get(facility, []) as Array):
			var pid := str((row as Dictionary)["id"])
			if not stamped.has(pid):
				stamped[pid] = await _stamp_and_census(row as Dictionary)
			if not _delivered.has(facility):
				_delivered[facility] = {}
			(_delivered[facility] as Dictionary)[pid] = _matches(stamped[pid], facility)


## The production composition root, not a hand-picked subsystem: `PortPlot` is
## what `world.gd` adds for the home port and what `ProximityLoader` streams in
## for every other one.
func _stamp_and_census(row: Dictionary) -> Dictionary:
	_bake_fields(row["layout"] as WorldLayout, int(row["seed"]))
	PortDataCache.clear()
	var data := PortExpander.expand(
		row["definition"] as PortDefinition,
		int(row["seed"]),
		row["layout"] as WorldLayout,
	)
	var plot := PortPlot.new()
	_world.add_child(plot)
	plot.configure(data)
	for _f in range(SETTLE_FRAMES):
		await get_tree().process_frame
	var census := {"nodes": 0, "meshy": {}}
	_census(plot, census)
	## Counted separately and floored separately: the facilities live under the
	## visualiser, and only the visualiser's own size can say the stamp ran.
	var vis_census := {"nodes": 0, "meshy": {}}
	var vis := plot.get_node_or_null(NodePath(VISUALISER_NODE))
	if vis != null:
		_census(vis, vis_census)
	_t.check(
		"%s (pop %s, size %d, %s) stamped a real port tree: %d nodes, %d under"
		% [row["id"], row["pop"], int(row["size"]), row["region"],
			int(census["nodes"]), int(vis_census["nodes"])]
		+ " the visualiser, %d of them named and drawing — a stamp that built"
			% (vis_census["meshy"] as Dictionary).size()
		+ " nothing would report every facility undelivered and be believed",
		int(census["nodes"]) >= STAMP_FLOOR_NODES
			and int(vis_census["nodes"]) >= STAMP_FLOOR_VISUALISER_NODES
	)
	plot.queue_free()
	await get_tree().process_frame
	return census


## Every node that draws: itself a `MeshInstance3D`, or an ancestor of one. A
## facility a player can find has geometry; a bare marker or a `Label3D` does
## not answer for one.
func _census(node: Node, out: Dictionary) -> bool:
	out["nodes"] = int(out["nodes"]) + 1
	var draws := node is MeshInstance3D
	for child in node.get_children():
		if _census(child, out):
			draws = true
	if draws and node is Node3D:
		(out["meshy"] as Dictionary)[_norm(str(node.name))] = true
	return draws


func _matches(census: Dictionary, facility: String) -> bool:
	var needle := _norm(facility)
	if needle.is_empty():
		return false
	for key in (census["meshy"] as Dictionary):
		if str(key).contains(needle):
			return true
	return false


## The feature list the WORLD builds a port from — `expand_uncached`, whose
## `has_fish_landing` is overwritten from the realized berth plan. Kept apart
## from the advertised side on purpose: this is the producer no player sees, and
## where it disagrees with `chart_summary` the disagreement is the finding, not
## something to average (REALITY §4a).
func _world_features(row: Dictionary) -> Array:
	var key := "%s/%s" % [row["seed"], row["id"]]
	if _world_feature_cache.has(key):
		return _world_feature_cache[key] as Array
	_bake_fields(row["layout"] as WorldLayout, int(row["seed"]))
	PortDataCache.clear()
	var built: Array = PortExpander.expand_uncached(
		row["definition"] as PortDefinition,
		int(row["seed"]),
		row["layout"] as WorldLayout,
	).features
	_world_feature_cache[key] = built
	return built


# ── the register polices itself ───────────────────────────────────────────────

func _check_register_is_well_formed() -> void:
	var bad_kind: Array[String] = []
	var no_reason: Array[String] = []
	var asserts_delivery: Array[String] = []
	for key in UNBUILT_PROMISES:
		var entry: Dictionary = UNBUILT_PROMISES[key]
		if not CLAIM_KINDS.has(str(entry.get("claim", ""))):
			bad_kind.append(str(key))
		var reason := str(entry.get("reason", ""))
		if reason.strip_edges().length() < 40:
			no_reason.append(str(key))
		var low := reason.to_lower()
		for phrase in DELIVERY_ASSERTING_PHRASES:
			if low.contains(str(phrase)) and not asserts_delivery.has(str(key)):
				asserts_delivery.append(str(key))
	_t.check(
		"every register entry declares a claim kind this file can verify (%d"
		% bad_kind.size()
		+ " cannot: %s) — a kind with no verifier is an excuse with no check"
			% str(bad_kind),
		bad_kind.is_empty()
	)
	_t.check(
		"every register entry carries a reason with something in it (%d do not:"
		% no_reason.size()
		+ " %s)" % str(no_reason),
		no_reason.is_empty()
	)
	_t.check(
		"no register reason claims the world delivers the thing (%d do: %s) —"
		% [asserts_delivery.size(), str(asserts_delivery)]
		+ " that is the sentence entry_reach_test carried for the lighthouse"
		+ " until today, and it was false",
		asserts_delivery.is_empty()
	)


func _check_every_claim() -> void:
	var keys: Array[String] = []
	for key in UNBUILT_PROMISES:
		keys.append(str(key))
	keys.sort()
	for key in keys:
		var entry: Dictionary = UNBUILT_PROMISES[key]
		match str(entry.get("claim", "")):
			"builder_exists_unplaced":
				_verify_builder_exists_unplaced(key, str(entry.get("arg", "")))
			"advertised_before_realized":
				_verify_advertised_before_realized(key, str(entry.get("arg", "")))
			_:
				## Already failed above; this is the second half of that rule —
				## an unrecognised kind must cost the same four checks it would
				## have run, or it becomes a way to make checks vanish.
				for i in range(4):
					_t.fail("register entry %s declares an unverifiable claim (%d/4)"
						% [key, i + 1])


## "The geometry is written and nothing in the shipped world places it." Four
## checks, none of them prose: the class exists, it really draws, no production
## file constructs it, and no port stamped in this run contains it.
func _verify_builder_exists_unplaced(facility: String, builder: String) -> void:
	var script_path := ""
	for entry in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == builder:
			script_path = str(entry.get("path", ""))
	if not _t.check(
		"%s: `%s` is a real global class (%s) — an entry naming a class that"
		% [facility, builder, script_path]
		+ " does not exist would excuse the gap with a fiction",
		not script_path.is_empty() and FileAccess.file_exists(script_path)
	):
		_t.fail("%s: `%s` missing, so its geometry cannot be measured" % [facility, builder])
		_t.fail("%s: `%s` missing, so its referrers cannot be measured" % [facility, builder])
		_t.fail("%s: `%s` missing, so its absence from the stamp proves nothing"
			% [facility, builder])
		return

	## FINISHED, not merely named: build one and count what it draws. This is
	## what makes "unfinished-and-unplugged" a measurement rather than a story,
	## and it is the half that says the fix is a placement and not a model.
	var meshes := 0
	var built := (load(script_path) as GDScript).new() as Node
	if built != null:
		_world.add_child(built)
		meshes = _mesh_count(built)
		built.queue_free()
	_t.check(
		"%s: `%s` draws real geometry when constructed (%d MeshInstance3D) — so"
		% [facility, builder, meshes]
		+ " what is missing is a PLACEMENT, not a model",
		meshes >= 1
	)

	## Nothing in the shipped world path builds it. A showcase does not count,
	## and "is a showcase" is decided by the file's own name rather than by a
	## list somebody would have to keep true.
	var non_showcase: Array[String] = []
	for path in _stripped:
		if str(path) == script_path:
			continue
		if not str(_stripped[path]).contains(builder):
			continue
		if str(path).get_file().contains("showcase"):
			continue
		non_showcase.append(str(path))
	non_showcase.sort()
	_t.check(
		"%s: nothing outside a showcase constructs `%s` (%d do: %s) — this half"
		% [facility, builder, non_showcase.size(), str(non_showcase)]
		+ " covers the whole world, not only the port plot",
		non_showcase.is_empty()
	)

	## Conserved the other way: the day a port stamps one, this reds, and the
	## fix is to strike the entry off — never to unwire the lighthouse.
	var delivering: Array[String] = []
	for pid in (_delivered.get(facility, {}) as Dictionary):
		if bool((_delivered[facility] as Dictionary)[pid]):
			delivering.append(str(pid))
	_t.check(
		"%s: no witness port's stamped tree contains it (%d do: %s) — when one"
		% [facility, delivering.size(), str(delivering)]
		+ " does, DELETE this register entry",
		delivering.is_empty()
	)


## "It is real, it is built somewhere, and it is promised at more ports than it
## is built at." Four checks. The entry survives until the two producers agree.
func _verify_advertised_before_realized(facility: String, flag: String) -> void:
	var stats: Dictionary = _realized.get(facility, {}) as Dictionary
	var advertised := int(stats.get("advertised", 0))
	var realized := int(stats.get("realized", 0))
	var divergent_id := str(stats.get("divergent_id", ""))

	var delivering: Array[String] = []
	var empty_handed: Array[String] = []
	for pid in (_delivered.get(facility, {}) as Dictionary):
		if bool((_delivered[facility] as Dictionary)[pid]):
			delivering.append(str(pid))
		else:
			empty_handed.append(str(pid))
	delivering.sort()
	empty_handed.sort()
	_t.check(
		"%s: at least one witness port really builds it (%d do: %s) — this entry"
		% [facility, delivering.size(), str(delivering)]
		+ " is about COVERAGE, and a facility that vanished entirely would"
		+ " belong under a different claim",
		not delivering.is_empty()
	)
	_t.check(
		"%s: the world's own feature list drops it at ports the panel promises"
		% facility
		+ " it at (%d advertised, %d realized, first divergence `%s`) — when"
			% [advertised, realized, divergent_id]
		+ " those two numbers meet, DELETE this register entry",
		realized < advertised and realized > 0
	)
	_t.check(
		"%s: `PortData` really carries the `%s` flag this reason is written on,"
		% [facility, flag]
		+ " so the mechanism it names is the one in the code",
		flag in PortData.new()
	)
	## The geometric half. A flag disagreement is a data fact; this is the one
	## that says a player standing on that quay finds nothing there.
	_t.check(
		"%s: the divergence witness `%s` stamps no such facility (%d witness"
		% [facility, divergent_id, empty_handed.size()]
		+ " ports built nothing for it: %s) — the gap is in the WORLD, not only"
			% str(empty_handed)
		+ " between two producers",
		not divergent_id.is_empty() and empty_handed.has(divergent_id)
	)


func _check_set_equality() -> void:
	var broken: Array[String] = []
	for facility in _vocabulary:
		var per_port: Dictionary = _delivered.get(facility, {}) as Dictionary
		for pid in per_port:
			if not bool(per_port[pid]) and not broken.has(facility):
				broken.append(facility)
	broken.sort()
	var registered: Array[String] = []
	for key in UNBUILT_PROMISES:
		registered.append(str(key))
	registered.sort()
	print("[promise] BROKEN at a witness port: %s" % str(broken))
	print("[promise] REGISTERED:               %s" % str(registered))
	_t.check(
		"the set of facilities a witness port advertises and does not build"
		+ " equals the register (%s vs %s) — a new one is a FINDING, not a"
			% [str(broken), str(registered)]
		+ " register line, and a registered one that becomes built must be"
		+ " struck off",
		broken == registered
	)


# ── helpers ───────────────────────────────────────────────────────────────────

## PORT EXPANSION HAS A HIDDEN GLOBAL INPUT, AND UNTIL 2026-08-17 THIS FILE'S TWO
## SIDES WERE COMPUTED UNDER DIFFERENT VALUES OF IT.
##
## `PortFishingService.is_eligible` samples `FishingField`, whose `open_water` term
## calls `LandField.distance_to_land` — and `LandField` is a static baked from ONE
## WorldLayout. This unit surveys two seeds plus a layout-free matrix in a single
## process: `ChartDataSnapshot.for_preview` baked the field for each seed as it
## went, and then every `expand_uncached` in `_world_features` ran afterwards
## against whichever seed happened to be last. So the ADVERTISED column came from
## one world's land and the DELIVERED column from another's.
##
## It was not a small effect and it is why this was worth chasing: measured over
## six seeds and 210 ports (`tests/_fish_landing_realization_probe.gd`), the same
## ports advertise a fish landing 137 times with their own land field baked, 139
## with an empty one and **80** with another world's. Before this call existed,
## this file reported 424242 / `port-home` as a divergence witness — a port that
## advertises AND builds a fish landing when its own world's land is baked.
##
## Both columns now bake the row's own fields first, so a disagreement between them
## is a disagreement between the two PRODUCERS and not between two worlds.
func _bake_fields(layout: WorldLayout, world_seed: int) -> void:
	FishingField.initialize(world_seed)
	if layout != null:
		LandField.initialize(layout)
	else:
		## Population B has no layout. An EMPTY field is the declared state for it —
		## `distance_to_land` reads `inf`, so `allows_trawling` permits everything —
		## rather than leaving it holding population A's last world.
		LandField.initialize([])


func _load_stripped_sources() -> void:
	for path in _all_scripts("res://scripts"):
		_stripped[path] = _strip_comments(FileAccess.get_file_as_string(path))


func _mesh_count(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _mesh_count(child)
	return n


static func _norm(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


static func _has_id(rows: Array, port_id: String) -> bool:
	for row in rows:
		if str((row as Dictionary)["id"]) == port_id:
			return true
	return false


static func _ids(rows: Array) -> String:
	var out: Array[String] = []
	for row in rows:
		out.append(str((row as Dictionary)["id"]))
	return str(out)


## Everything before an unquoted `#`. A facility named in a comment is not a
## presenter and a builder named in a comment is not a placement — the same rule
## `entry_reach_test` needed for `ShipyardBrickEditor`.
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


func _all_scripts(root: String) -> Array[String]:
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
				out.append_array(_all_scripts(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
