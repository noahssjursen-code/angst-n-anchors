extends Node

## LANE B — WHAT THE LIVE CHART ACTUALLY DRAWS FOR A PORT NOBODY HAS SAILED TO.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/chart_live_harbour_test.tscn
##
## LANE B FOR A MEASURED REASON, like `port_feature_promise_test`. `ChartHarbourPlan`
## names `HarbourRegistry` bare, which reaches `harbour_authority_bridge.gd`'s bare
## `WorldGateway`, so under `--script` the file dies with `Identifier not found` and
## the failure cascades to this one (CONVENTIONS §2). A lane-A draft of this unit's
## probe printed exactly that and then loaded nothing. Do not move it.
##
## ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
##
## The marine chart draws a harbour silhouette for every port on screen. There are
## two ways it gets the `PortData` to draw from (`ChartHarbourPlan.resolve_port_data`):
##
##   STAMPED   — the port has a `PortPlot` in the tree, so the chart draws the
##               world's own expansion. Only the home port is stamped at boot;
##               everything else waits on `ProximityLoader` at 4.8 km.
##   UNSTAMPED — the chart rebuilds a `PortDefinition` out of a `PortCatalog`
##               record and expands it itself.
##
## **The unstamped path is reachable by a keypress, which is why this file treats it
## as player-facing.** `game_menu.gd:133` binds the `open_map` action (physical key
## M) and `:164` calls `MapOverlay.open_navigation()`, which builds its snapshot with
## `ChartDataSnapshot.from_live_tree` — the `PortCatalog` factory. So every port
## further out than `world.gd`'s 4.8 km `LOAD_RADIUS` is drawn from a rebuild: 34 of
## 35 at boot, and any port the player has not sailed to since.
##
## `PortCatalog.register_port` takes seventeen parameters and `world.gd:_setup_ports`
## used to supply fourteen of them — `region`, `max_ship_class_name` and
## `commodity_exports` all kept their defaults — and it publishes no `PortDefinition`
## at all, so the rebuilt definition is missing most of the placed site. That was
## reported as a `site_max_size` defect, and measured 2026-08-17 over six seeds x 35
## ports (`tests/_chart_live_ceiling_probe.gd`) it is not one — see the properties
## below. The ceiling changes nothing anyone sees; the REGION WORD changes the
## harbour.
##
## **`world.gd` now passes the region word (fifteen arguments), and P3 below is
## struck.** Two of the three defaults are still defaulted and are registered
## instead of fixed — see P4. The measurement that chose that split is
## `tests/_region_default_probe.gd`, six seeds x 35 ports, whole structures:
##
##   | registration | drawn + PortData-read keys | those plus features, population, the two facility booleans and the four showcase attributes |
##   |---|---|---|
##   | 14 args, as shipped before | **73 of 210 differ** | **139 of 210** |
##   | + `region` (the fix) | **0 of 210** | 87 of 210 |
##   | + `region` + `max_ship_class_name` + `commodity_exports` | **0 of 210** | 87 of 210 |
##   | + the whole placed `port_definition` | **0 of 210** | **0 of 210** |
##
## Two things in that table decided the mechanism. The region word alone closes
## every path a player can see, and the two further parameters close nothing extra
## because `resolve_port_data` never reads either. The `port_definition` variant is
## the only one that also closes the 87 — and every one of those 87 is a field of a
## `PortData` that is **discarded**: `resolve_port_data`'s single production caller
## is `ChartHarbourPlan.for_port`, which keeps the plan and drops the data, so the
## rebuild's `features`, `population`, `has_lighthouse` and `has_fog_horn` reach no
## reader. (They diverge because `expand_uncached` evaluates
## `definition.has_lighthouse or rng.randf() < 0.3`, which short-circuits, so a
## definition missing those booleans consumes the shared `rng` at a different offset
## and every later draw off it shifts.) Buying that with an eighteenth parameter
## would also leave the record's own `region` key at `"coastal"` while the silhouette
## beside it was a fjord's — one panel disagreeing with itself, REALITY §4a.
##
## ⚠ THE 133 ON RECORD IS A DIFFERENT KEY SET, NOT A DIFFERENT WORLD. STATE.md's
## entry reads "the live chart draws the wrong harbour at 133 of 210 ports" beside a
## path table this unit reproduces exactly. The count came from
## `_chart_live_ceiling_probe._diff`, which walks the UNION of both digests' keys and
## so also counted `data_features` and the four showcase attributes; add the four
## RNG-stream fields it did not carry and the same measurement gives 139. **The
## number for the harbour a player is shown is 73 of 210.** Neither probe was wrong;
## the sentence that quoted one of them was, because it named a key set it did not
## state. Say which keys, always.
##
## ── WHAT THIS UNIT CANNOT SEE, STATED RATHER THAN GLOSSED ───────────────────
##
## It builds the catalog record by REPLICATING `world.gd:_setup_ports`' argument
## list (below), because `_setup_ports` cannot be called from here — it wants a
## `World` node mid-`_rebuild`, a `ProximityLoader`, and it builds a `PortPlot`.
## So **nothing in the gate proves that `world.gd`'s own line passes the region
## word**; this unit proves that a record carrying it draws the right harbour and a
## record without it does not. That gap is REALITY §3's layer trap.
##
## It was closed by hand, outside the gate, rather than left as a caveat.
## `tests/_world_boot_region_probe.gd` boots the real `World`, lets the real
## `_rebuild` run the real `_setup_ports`, and reads `PortCatalog` back against an
## independently computed placer run: **20 of 20 records carry the placed word, 0
## carry "coastal"** (2026-08-17). With the argument removed again it reports 19 of 20
## "coastal" — and the twentieth is `port-home`, which is right only because
## `port_plot.gd` stamps it and re-registers with the full seventeen. It is a probe
## and not a gate unit because a real boot spawns a player and streams terrain;
## **re-run it by hand whenever this argument list is edited.**
##
## MEASURED, AND THE MUTATION THAT PROVES THE GAP IS REAL: removing the region
## argument from `world.gd` leaves THIS UNIT GREEN AT 119 CHECKS. The probe above is
## the only thing in the repository that sees it. Do not read this unit's green as
## evidence about `world.gd`'s call site.
##
## (The probe's own first run was wrong, and it is worth knowing why: `World._ready`
## overwrites `world_seed` from `GameSettings`, so setting the seed on the node booted
## a DIFFERENT WORLD and six records "disagreed with the placer" for that reason
## alone. An instrument error that looks exactly like the defect — REALITY §8.)
##
## ── WHAT IS ASSERTED, AND WHY IT IS NOT A CALL SIGNATURE ─────────────────────
##
## P1  The silhouette the live chart draws for a harbour is INDIFFERENT to the site
##     ceiling. Driven through the real `resolve_port_data` on the branch that
##     still reads a ceiling at all — the one a `port_definition` record takes —
##     varying that record's `site_max_size` between `PortSizing.MAX_SIZE` and the
##     placed geography ceiling and NOTHING else. Whole structures, point by point
##     (REALITY §4e; a conclusion was reversed this week by a `.size()` comparison).
##     This is the counterfactual that makes the deletion safe: if the catalog HAD
##     carried a ceiling, the harbour would have been drawn the same. The day that
##     stops being true, this reds and the deletion has to be revisited.
##
## P2  The deleted read is really gone and has no producer: `chart_summary` does not
##     republish `site_max_size` (REALITY §3d — it had one reader in the project and
##     that reader could never see it), a `PortCatalog` record does not carry one,
##     and writing one into a record by hand is INERT — no field of the resulting
##     harbour moves, not even the showcase-only attributes. Re-adding the read
##     reds that check, which is how the deletion stays deleted.
##
##     ⚠ THE FIRST VERSION OF P1 WAS THIS INERTNESS CHECK, AND IT WAS VACUOUS.
##     It injected the ceiling into the catalog record and asserted the drawn
##     harbour did not move — which after the deletion is true because the value is
##     read by nobody, so the check compared one expansion against itself and could
##     not fail. It was caught by its own floor (the injection was required to move
##     the layout graph's ceiling, and post-deletion it moved it at 0 of 20 ports),
##     which is the only reason it is not still sitting here green. The floor is the
##     check; keep it.
##
## P3  STRUCK 2026-08-17, AND WHAT REPLACES IT IS THE PROPERTY, NOT A SMALLER
##     NUMBER. It used to register, by name, the eight ports of twenty whose
##     unstamped silhouette was a different harbour from their stamp. `world.gd`
##     now passes the region word, so the property is that there is no such port:
##     the harbour the live chart draws for a port nobody has sailed to is the
##     harbour the world's own `PortPlot` would draw — every polygon point, every
##     station meta dictionary, the bounds rect and both camera helpers — at all
##     twenty.
##
##     **The eight ids are kept, as a COUNTERFACTUAL rather than a register.**
##     Forcing the record's region back to `"coastal"` — the word `register_port`
##     defaults to and the placer never assigns — must still produce exactly those
##     eight. That is what stops the property above from going vacuous: if the region
##     word stopped reaching the harbour for any reason, the counterfactual would
##     agree with the stamp too and this unit would red on it, instead of reporting a
##     green it had not earned. A property with no counterfactual beside it is
##     REALITY §4's check that cannot fail.
##
## P4  REGISTERED, NOT FIXED, and deliberately not fixed in this wave:
##     `max_ship_class_name` and `commodity_exports` are still defaulted on the
##     record `world.gd` writes. Neither is read by `resolve_port_data`, so neither
##     moves the silhouette this wave owes a frame for — and both are read
##     elsewhere, which is exactly why they are not being corrected in the same
##     breath as a silhouette fix:
##
##       `max_ship_class_name` — wrong at 20 of 20 here and 210 of 210 over six
##         seeds. The record says `"Vessel"`; the expander assigns Short Sea Coaster
##         (51), Coastal Trader (127) or Handysize Feeder (32). Read by
##         `chart_layer_renderer.gd`'s port card, which draws `MAX CLASS VESSEL` on
##         the very screen this wave photographs, and by `map_overlay.gd`'s pick
##         panel.
##       `commodity_exports` — the record collapses to `[commodity_export]`, the
##         primary alone. 74 of 210 ports have two or three export slots. Read by
##         `FreightOfferGenerator.generate`, so at those ports every secondary export
##         generates no freight offer at all. That is a change to the jobs a player
##         is given rather than to a readout, and it is an owner's call, not a
##         side effect of this one.
##
## ── THE FLOORS, AND WHY EACH ONE IS HERE ────────────────────────────────────
##
## Every floor below was earned by a specific failure, not added for symmetry:
##
##   * **The cache.** `PortDataCache` keys on `site_max_size`, so a warm cache
##     hands an injected run the other run's `PortData` and `expand_uncached` never
##     executes — the comparison becomes one object against itself and passes
##     asking nothing. That is the exact trap that let a mutation pass twice
##     against `chart_rewrite_integration_test` on 2026-08-17. The cache is cleared
##     before every draw and the forced misses are COUNTED.
##   * **The injection.** If injecting the ceiling moved nothing at all, P1 would
##     be comparing two identical inputs. It must be shown to move the layout
##     graph's own `site_max_size` at some port.
##   * **The geometry.** Two empty plans are identical. Every port must have
##     produced a foundation outline and at least one berth structure.
##   * **The population.** Declared as literals (§4f shape 1) and checked against
##     what the placer returned, plus a frozen `EXPECTED_CHECKS` (§4f shape 4),
##     because the per-port loop is what every check here lives inside.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const TestReport := preload("res://tests/support/test_report.gd")

## DECLARED population. Not discovered: the placer is asked for exactly this many
## ports at exactly this seed and told off if it returns another number, so no
## check below can quietly stop existing (§4f). 20 keeps the unit near a minute on
## llvmpipe; the six-seed 210-port base lives in `_chart_live_ceiling_probe.gd`.
const SEED := 90210
const PORT_COUNT := 20

## Frozen with the checks it counts, in the same edit as the checks (§4f shape 4).
## 20 ports x 5 per-port checks + 19 fixed. Was 96 (4 + 16) before the region fix
## added the property and the counterfactual and split the two remaining defaults
## out into their own register; re-frozen in that same edit, never after it.
const EXPECTED_CHECKS := 119

## The keys of a harbour digest that a player sees drawn on the chart, plus the three
## `data_*` fields the drawn plan is built out of. Declared so a digest field added
## later has to be classified rather than silently escaping both groups.
##
## BE PRECISE ABOUT WHICH IS WHICH, because the group name overstates it. The fifteen
## polygon/bounds/camera keys are drawn. The three `data_*` keys are NOT read by any
## UI at all — `resolve_port_data`'s only production caller keeps the plan and drops
## the `PortData` — so they are inputs and symptoms, not things a player reads. They
## stay in the group because a berth count that moved is how you find out the plan was
## built from the wrong site; they must not be quoted as "a player sees this".
##
## It does not matter to the verdict here: every one of the 73 divergent ports over six
## seeds differed on `quay_meta`, which IS drawn — it picks each pad's fill tint
## through `CommodityCatalog.terminal_family_color` and its printed label. So the
## divergence was visible at every port that had one, not merely present.
const PLAYER_FACING_KEYS: Array[String] = [
	"land_poly", "foundation_poly", "shore_poly", "dock_face_poly",
	"quay_polys", "quay_meta", "asphalt_polys", "asphalt_meta",
	"quay_poly_count", "asphalt_poly_count",
	"bounds", "centre_world", "suggested_span_m", "world_origin", "rotation_y",
	"data_size", "data_berth_count", "data_max_ship_class",
]

## THE COUNTERFACTUAL SET — was the registered divergence until 2026-08-17, and the
## history is worth keeping because of what it caught.
##
## As a register the check read `stamp_divergent > 0`. Flipping the live chart's
## region fallback from `LEGACY_ISLAND` to `MAINLAND` took the divergence from **8 of
## 20 ports to 2** and the unit **passed**: a register that asserts only "still
## broken" cannot see itself getting better, and the same hole is on record for
## `chart_rewrite_integration_test`'s register (STATE.md 2026-08-17 — "the register
## asserts disagreement, so a different wrong number still passes it"). Naming the
## members fixed it, and naming them is what makes the list re-usable now that the
## defect is closed: the same eight ids are the ports whose harbour the region word
## actually moves, so forcing `"coastal"` back onto the record must reproduce exactly
## this set. A count could only say a number moved.
##
## HONESTY ABOUT HOW THIS LIST WAS OBTAINED. The COUNT was predicted — 8 of 20,
## measured twice by the `> 0` version of this check before the set existed. The
## MEMBERSHIP was not: the first guess at the eight ids was wrong in six of eight
## (they were copied off a ceiling mutation's failure list, which is a different
## question), the check reded and named them, and the measured set is written here.
## A recorded run, not a prediction.
##
## MAINLAND is not a fix, incidentally, and must not be adopted as one: it agrees
## with the stamp more often at this seed because most sites here are fjord, which is
## REALITY §1's proxy trap — a number tuned on the population it was measured on.
## What agrees with the stamp everywhere is the word the placer actually assigned,
## and the reason MAINLAND scored well is worth writing down because it is not
## obvious: `PortTradeProfile._theme_weight` gives MAINLAND and LEGACY_ISLAND the
## SAME weights, so the theme does not move at all between them. What moves is
## `PortFishingService.is_eligible`, which returns true for LEGACY_ISLAND (and
## ARCHIPELAGO) **without sampling water**, so every `"coastal"` port was granted a
## fish landing it had not earned — which is the quay pad the frames for this fix show
## disappearing.
const COASTAL_FALLBACK_PORTS: Array[String] = [
	"port-home", "port-3", "port-5", "port-10", "port-11", "port-15", "port-17", "port-18",
]

## P4's second register, as a named set (§4f shape 1). The ports whose
## `commodity_exports` the record collapses to the primary export alone, so
## `FreightOfferGenerator` never offers their other cargoes.
##
## MEASURED, AND THE GUESS BEFORE IT WAS WRONG — recorded because the same thing
## happened to `COASTAL_FALLBACK_PORTS` above and the pattern is the point. The count
## was predictable from the six-seed probe (68 ports with two export slots and 6 with
## three, so 74 of 210 = 35%, and 6 of 20 here is 30%). The MEMBERSHIP was not: the
## eleven ids written here first were wrong in seven, and missed two the measurement
## found (`port-12`, `port-18`). The check reded, named the real set, and this is it.
## A count would have passed the wrong list without comment.
const EXPORTS_COLLAPSED_PORTS: Array[String] = [
	"port-home", "port-3", "port-11", "port-12", "port-17", "port-18",
]

## Published into `layout_graph.initial_attributes` and read, in this whole
## project, only by `port_showcase.gd` — the F6 gallery, which no route from the
## shipped game reaches. These are the ONLY things the site ceiling moves.
const SHOWCASE_ONLY_KEYS: Array[String] = [
	"graph_site_max_size", "basin_max_size", "basin_site_max_size", "berth_notes",
]


class StubWorld:
	extends Node
	var layout: WorldLayout
	var seed_value := 0

	func get_world_layout() -> WorldLayout:
		return layout

	func get_shipping_lane_network():
		return null

	func get_world_traffic_service():
		return null

	func get_world_context() -> Dictionary:
		return {
			"seed": seed_value,
			"generation_version": 0,
			"layout_checksum": str(layout.layout_checksum) if layout != null else "",
			"world_size_m": layout.world_size_m if layout != null else 40000.0,
			"world_preset": "standard",
		}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("chart_live_harbour_test")
	_check_all(t)
	t.finish(get_tree())


func _check_all(t: TestReport) -> void:
	var catalog := get_node_or_null("/root/PortCatalog")
	if not t.check("the PortCatalog autoload is present — this unit measures it", catalog != null):
		return

	var layout: WorldLayout = GENERATOR.generate(SEED)
	if not t.check("the world layout generated", layout != null):
		return
	var defs: Array = PLACER.place_ports(
		layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
	if not t.equal(
		"the placer returned the DECLARED population — every check below lives"
		+ " inside a loop over it, so a shrunken population is a vanished check",
		defs.size(), PORT_COUNT,
	):
		return

	## The world, exactly as `world.gd:_setup_ports` does it: expand the placed
	## definition, then hand `register_port` the fifteen scalars it passes.
	## REPLICATED, not called — see the header. If `world.gd`'s argument list is
	## edited, this one has to be edited with it and nothing here will notice.
	catalog.call("clear")
	PortDataCache.clear()
	LandField.initialize(layout)
	FishingField.initialize(SEED)
	WeatherField.world_seed = SEED
	WeatherFrontField.initialize(SEED)

	var records: Array = []
	for raw in defs:
		var placed := raw as PortDefinition
		var source := placed.to_dict()
		var world_def := PortDefinition.from_dict(source)
		var world_data := PortExpander.expand(world_def, SEED, layout)
		var world_chart := world_data.to_chart_dict()
		catalog.call(
			"register_port",
			world_data.port_id, world_data.display_name, world_data.world_position,
			Vector3(INF, INF, INF),
			world_data.commodity_export, world_data.commodity_imports,
			world_data.island_width,
			world_data.plot_depth,
			world_data.layout_seed,
			world_data.population, world_data.features, world_data.rotation_y,
			world_data.berth_count, world_data.size,
			str(world_chart.get("region", "")),
		)
		records.append({
			"source": source,
			"resolved_ceiling": world_def.site_max_size,
			"data": world_data,
			"real_class": str(world_chart.get("max_ship_class_name", "")),
			"real_exports": (world_data.trade_profile.export_slots.duplicate()
				if world_data.trade_profile != null else []),
		})

	## ── P2, the premise ──────────────────────────────────────────────────────
	var summary_definition := PortDefinition.from_dict((records[0]["source"]) as Dictionary)
	var summary: Dictionary = PortExpander.chart_summary(summary_definition, SEED, layout)
	t.check(
		"`chart_summary` publishes a full dossier (%d keys) — asserting a key is"
			% summary.size()
		+ " absent from an empty dictionary would assert nothing",
		summary.size() >= 15,
	)
	t.check(
		"`chart_summary` does NOT publish `site_max_size` — deleted 2026-08-17 as a"
		+ " REALITY §3d value: its one reader in the project"
		+ " (`ChartHarbourPlan.resolve_port_data`) only reads it on the branch taken"
		+ " when the record carries no `port_definition`, and this record always"
		+ " carries one",
		not summary.has("site_max_size"),
	)
	var first_info: Dictionary = catalog.call("get_port_info", str(summary.get("id", "")))
	t.check(
		"a `PortCatalog` record carries no `site_max_size` either — `register_port`"
		+ " has no such parameter, so the live chart's rebuilt definition keeps"
		+ " `PortDefinition`'s own default ceiling. This is the premise the"
		+ " indifference below is measured under; if the catalog starts carrying"
		+ " one, re-ask the question",
		not first_info.has("site_max_size"),
	)
	t.check(
		"and no `port_definition`, which is why the live chart takes the rebuilding"
		+ " branch at all — deliberately still true after the region fix: the"
		+ " eighteenth parameter was weighed and rejected (see the header table), so"
		+ " the rebuilding branch is still the one 34 of 35 ports are drawn from",
		not first_info.has("port_definition"),
	)
	## ── THE PREMISE OF THE FIX, on the record `register_port` actually built ──
	##
	## Not "world.gd passes a region word" — this unit cannot see that (header) —
	## but the two halves it CAN see: the word on the record is the word the placed
	## definition carries, and it is never the `"coastal"` `register_port` defaults
	## to. If `register_port` ever starts flattening it again, this reds before any
	## harbour comparison does, and says so in one line instead of twenty.
	var region_word_wrong: Array[String] = []
	var placed_region_words: Dictionary = {}
	for rec_premise_raw in records:
		var rec_premise: Dictionary = rec_premise_raw
		var pid_premise := str((rec_premise["source"] as Dictionary).get("port_id", ""))
		var want := _region_word(
			int((rec_premise["source"] as Dictionary).get("region_kind", 0)))
		placed_region_words[want] = int(placed_region_words.get(want, 0)) + 1
		var got := str((catalog.call("get_port_info", pid_premise) as Dictionary).get("region", ""))
		if got != want or got == "coastal":
			region_word_wrong.append("%s:%s!=%s" % [pid_premise, got, want])
	t.equal(
		"every record carries the region word its placed definition carries, and not"
		+ " one of them is the \"coastal\" `register_port` defaults to. The placer"
		+ " assigned %s here — it has no \"coastal\" branch at all, over 210 ports it"
			% str(placed_region_words)
		+ " assigns fjord 170 / archipelago 34 / mainland 6, so \"coastal\" was never"
		+ " a region any port had. It was a null wearing a value's clothes",
		region_word_wrong, [] as Array[String],
	)

	## ── the live chart snapshot, taken from the live tree ────────────────────
	var stub := StubWorld.new()
	stub.name = "ProbeWorld"
	stub.layout = layout
	stub.seed_value = SEED
	stub.add_to_group("world")
	get_tree().root.add_child(stub)
	var snapshot := ChartDataSnapshot.from_live_tree(get_tree())
	t.equal(
		"`from_live_tree` filled the snapshot from `PortCatalog`",
		snapshot.ports.size(), PORT_COUNT,
	)

	var forced_misses := 0
	var ceiling_moved_the_graph := 0
	var geometry_present := 0
	var ceiling_changed_something_drawn: Array[String] = []
	var stamp_divergent: Array[String] = []
	var coastal_divergent: Array[String] = []
	var definition_closes := 0
	var region_words: Dictionary = {}
	## P4's two registers, accumulated off the same records.
	var class_wrong: Array[String] = []
	var exports_collapsed: Array[String] = []

	for index in range(records.size()):
		var rec: Dictionary = records[index]
		var pid := str((rec["source"] as Dictionary).get("port_id", ""))
		var region_word := _region_word(
			int((rec["source"] as Dictionary).get("region_kind", 0)))
		region_words[region_word] = int(region_words.get(region_word, 0)) + 1

		## ── P4, measured on the record, before any injection touches it ───────
		var live_info: Dictionary = catalog.call("get_port_info", pid)
		if str(live_info.get("max_ship_class_name", "")) != str(rec["real_class"]):
			class_wrong.append(pid)
		if JSON.stringify(_strings(live_info.get("commodity_exports", []) as Array)) \
				!= JSON.stringify(_strings(rec["real_exports"] as Array)):
			exports_collapsed.append(pid)

		var placed_ceiling := int((rec["source"] as Dictionary).get("site_max_size", -1))
		var raised := ((rec["source"] as Dictionary) as Dictionary).duplicate(true)
		raised["site_max_size"] = PortSizing.MAX_SIZE

		## A — the catalog exactly as the world registered it. No ceiling, no
		##     definition: the branch 34 of 35 ports are drawn from.
		var a := _draw_live(pid, snapshot, {}, catalog)
		## A2 — identical, except a `site_max_size` is written into the record. The
		##      read that would have consumed it is DELETED, so this must be inert.
		var a2 := _draw_live(pid, snapshot,
			{"site_max_size": int(rec["resolved_ceiling"])}, catalog)
		## G / H — the `port_definition` branch, which DOES read a ceiling. One
		##         field varied: the ceiling. This is the counterfactual.
		var g := _draw_live(pid, snapshot, {"port_definition": raised}, catalog)
		var h := _draw_live(pid, snapshot, {"port_definition": rec["source"]}, catalog)
		## F — THE COUNTERFACTUAL: the record with its region forced back to the
		##     `"coastal"` `register_port` defaults to, everything else as the world
		##     registered it. This is the harbour the chart drew before the fix.
		var f := _draw_live(pid, snapshot, {"region": "coastal"}, catalog)
		## C — the STAMPED harbour: the world's own PortData, no rebuilding.
		var c := _digest(
			ChartHarbourPlan.from_port_data(rec["data"] as PortData),
			rec["data"] as PortData,
		)
		forced_misses += int(a["forced_misses"]) + int(a2["forced_misses"]) \
				+ int(g["forced_misses"]) + int(h["forced_misses"]) \
				+ int(f["forced_misses"])

		if not t.check(
			"port %s resolved a harbour on all five live-tree variants" % pid,
			bool(a.get("resolved", false)) and bool(a2.get("resolved", false))
				and bool(g.get("resolved", false)) and bool(h.get("resolved", false))
				and bool(f.get("resolved", false)),
		):
			continue
		if (a["foundation_poly"] as Array).size() >= 3 \
				and int(a["quay_poly_count"]) + int(a["asphalt_poly_count"]) > 0:
			geometry_present += 1
		if str(g["graph_site_max_size"]) != str(h["graph_site_max_size"]):
			ceiling_moved_the_graph += 1

		## ── P2, the deletion: the catalog's ceiling is INERT ─────────────────
		t.check(
			"port %s: writing `site_max_size` into its `PortCatalog` record moves" % pid
			+ " no field of the harbour at all, showcase attributes included — the"
			+ " read that consumed it is deleted (%s)"
				% str(_diff(a, a2, PLAYER_FACING_KEYS + SHOWCASE_ONLY_KEYS).keys()),
			_diff(a, a2, PLAYER_FACING_KEYS + SHOWCASE_ONLY_KEYS).is_empty(),
		)

		## ── P1, THE PROPERTY ────────────────────────────────────────────────
		var drawn_gh := _diff(g, h, PLAYER_FACING_KEYS)
		if not drawn_gh.is_empty():
			ceiling_changed_something_drawn.append("%s:%s" % [pid, str(drawn_gh.keys())])
		t.check(
			"port %s draws the SAME harbour whether its definition carries the" % pid
			+ " ceiling %d or the placed %d — %s"
				% [PortSizing.MAX_SIZE, placed_ceiling, str(drawn_gh.keys())],
			drawn_gh.is_empty(),
		)

		## ── P3, THE PROPERTY, and the counterfactual beside it ──────────────
		var drawn_ac := _diff(a, c, PLAYER_FACING_KEYS)
		if not drawn_ac.is_empty():
			stamp_divergent.append(pid)
		if not _diff(f, c, PLAYER_FACING_KEYS).is_empty():
			coastal_divergent.append(pid)
		if _diff(h, c, PLAYER_FACING_KEYS).is_empty():
			definition_closes += 1
		t.check(
			"port %s: the harbour the LIVE CHART draws for it — rebuilt from its" % pid
			+ " `PortCatalog` record, the branch 34 of 35 ports are drawn from — is"
			+ " the harbour the world's own stamp builds, on every drawn path: %s"
				% str(drawn_ac.keys()),
			drawn_ac.is_empty(),
		)
		t.check(
			"port %s: handing the live chart the placed `port_definition` instead" % pid
			+ " reproduces the STAMPED harbour too — the alternative mechanism,"
			+ " measured rather than assumed, so the choice between them stays a"
			+ " measurement and not a memory",
			_diff(h, c, PLAYER_FACING_KEYS).is_empty(),
		)

	get_tree().root.remove_child(stub)
	stub.free()

	## ── the floors, evaluated ────────────────────────────────────────────────
	t.equal(
		"every one of the %d live draws really entered `expand_uncached` rather" % (PORT_COUNT * 5)
		+ " than hitting `PortDataCache` — the cache keys on `site_max_size`, so a"
		+ " hit hands the varied run the other run's PortData and every comparison"
		+ " above becomes one object against itself. This is the trap that let a"
		+ " mutation pass twice on 2026-08-17",
		forced_misses, PORT_COUNT * 5,
	)
	t.check(
		"and varying the DEFINITION's ceiling really did reach the expander (%d of"
			% ceiling_moved_the_graph
		+ " %d ports moved `layout_graph.initial_attributes[\"site_max_size\"]`) —"
			% PORT_COUNT
		+ " otherwise P1 is agreement between two identical inputs, which is exactly"
		+ " how its first version passed vacuously",
		ceiling_moved_the_graph > 0,
	)
	t.check(
		"THE PROPERTY: the site ceiling changes nothing a player sees on the live"
		+ " chart, at all %d ports (%s). What it moves is %s, whose only reader in"
			% [PORT_COUNT, str(ceiling_changed_something_drawn), str(SHOWCASE_ONLY_KEYS)]
		+ " this project is `port_showcase.gd`, an F6 gallery with no route from the"
		+ " shipped game",
		ceiling_changed_something_drawn.is_empty(),
	)
	t.check(
		"and the harbours compared were not empty outlines — %d of %d carried a"
			% [geometry_present, PORT_COUNT]
		+ " foundation and a berth structure",
		geometry_present == PORT_COUNT,
	)

	## ── P3, THE PROPERTY (the register is STRUCK) ────────────────────────────
	##
	## What used to sit here was `stamp_divergent == DIVERGENT_PORTS`, eight named
	## ports of twenty. `world.gd` passes the region word now, so the set is empty
	## and the entry is struck: a stale register sends the next reader after a defect
	## that is gone, which is the only thing worse than not registering one.
	t.equal(
		"THE PROPERTY: no port draws a different harbour on the live chart from the"
		+ " one its stamp builds. Twenty of twenty, whole structures — every polygon"
		+ " point, every station meta dictionary, the bounds rect and both camera"
		+ " helpers. Was a register of eight named ports until `world.gd` passed the"
		+ " region word; over six seeds the same measurement went 73 of 210 to 0 of"
		+ " 210 (`tests/_region_default_probe.gd`)",
		stamp_divergent, [] as Array[String],
	)
	t.equal(
		"THE COUNTERFACTUAL, so the property above cannot pass vacuously: forcing the"
		+ " region back to the \"coastal\" `register_port` defaults to reproduces the"
		+ " defect at exactly the eight ports it was registered at. The placer"
		+ " assigned %s here and has no \"coastal\" branch, so this is not a"
			% str(region_words)
		+ " tolerance — it is the input the fix removed. If the region word ever"
		+ " stops reaching the harbour, THIS check reds, not the property",
		coastal_divergent, COASTAL_FALLBACK_PORTS,
	)
	t.equal(
		"and the whole placed definition closes it at every port too — the"
		+ " alternative mechanism, kept measured. It was rejected because it closes"
		+ " nothing extra that any reader sees (`resolve_port_data`'s only production"
		+ " caller keeps the plan and drops the PortData) while duplicating the region"
		+ " on the record and leaving the port card's own `region` key wrong",
		definition_closes, PORT_COUNT,
	)

	## ── P4, the two defaults that are REGISTERED and NOT FIXED ───────────────
	##
	## Same rule as the entry just struck: these must still be wrong, by name, or be
	## struck off. Correcting either changes something a player reads that this
	## wave's frame does not show — a port card row and the freight offers — so they
	## are an owner's call and not a silhouette fix's side effect.
	t.equal(
		"REGISTERED, BY NAME: exactly these ports carry the wrong"
		+ " `max_ship_class_name` on their `PortCatalog` record — `world.gd` still"
		+ " leaves that parameter defaulted, so the record says \"Vessel\" and"
		+ " `chart_layer_renderer`'s port card draws MAX CLASS VESSEL for every port"
		+ " in the game. `resolve_port_data` never reads it, so it moves no"
		+ " silhouette. 210 of 210 over six seeds",
		class_wrong, _all_port_ids(records),
	)
	t.equal(
		"REGISTERED, BY NAME: exactly these ports have their `commodity_exports`"
		+ " collapsed to the primary export alone on the record, because `world.gd`"
		+ " leaves that parameter defaulted too and `register_port` falls back to"
		+ " `[commodity_export]`. `FreightOfferGenerator.generate` reads this list, so"
		+ " every secondary export at these ports offers no freight at all — 6 of 20"
		+ " here, 74 of 210 over six seeds. Strike this when the owner has decided"
		+ " about the offers",
		exports_collapsed, EXPORTS_COLLAPSED_PORTS,
	)

	t.equal(
		"this unit ran its frozen number of checks — a PASS with fewer checks than"
		+ " yesterday has stopped looking, not passed (REALITY §4f)",
		t.check_count() + 1, EXPECTED_CHECKS,
	)


## Drive the real `ChartHarbourPlan.resolve_port_data` against the live catalog.
## Keys named in `inject` are written into the port's catalog entry and the others
## are removed, so exactly the intended inputs vary.
func _draw_live(
		port_id: String,
		snapshot: ChartDataSnapshot,
		inject: Dictionary,
		catalog: Node,
) -> Dictionary:
	var ports: Dictionary = catalog.get("_ports")
	var entry := ports[port_id] as Dictionary
	for key in ["site_max_size", "port_definition"]:
		if inject.has(key):
			entry[key] = inject[key]
		else:
			entry.erase(key)
	## `region` is OVERWRITTEN ONLY WHEN INJECTED, and that changed with the fix.
	## This line used to read `entry["region"] = str(inject.get("region", "coastal"))`,
	## which forced every un-injected draw back onto the broken input — correct while
	## the defect was being registered, and a check that could never see the fix
	## afterwards. Variant A must be the record as `register_port` built it.
	if inject.has("region"):
		entry["region"] = str(inject["region"])
	## Cleared so this draw MUST enter `expand_uncached`. Counted here rather than
	## by the caller: a delta measured around a call that clears the cache itself is
	## meaningless, which is how the first version of the miss floor read 4 of 20.
	PortDataCache.clear()
	ChartHarbourPlan.clear_cache()
	var data := ChartHarbourPlan.resolve_port_data(port_id, get_tree(), snapshot)
	if data == null:
		return {"resolved": false, "forced_misses": PortDataCache._cache.size()}
	var out := _digest(ChartHarbourPlan.from_port_data(data), data)
	out["forced_misses"] = 1 if PortDataCache._cache.size() > 0 else 0
	return out


## Whole structure — every polygon point, every meta dict, the bounds rect, the
## camera helpers, and the layout-graph attributes the ceiling is published into.
## Never a `.size()` and never a sum.
func _digest(plan: ChartHarbourPlan, data: PortData) -> Dictionary:
	var attrs: Dictionary = {}
	if data.layout_graph != null:
		attrs = data.layout_graph.initial_attributes
	var berth_plan := attrs.get("berth_plan", {}) as Dictionary
	var basin := berth_plan.get("basin", {}) as Dictionary
	return {
		"resolved": true,
		"data_size": int(data.size),
		"data_berth_count": int(data.berth_count),
		"data_max_ship_class": int(data.max_ship_class),
		"graph_site_max_size": int(attrs.get("site_max_size", -1)),
		"basin_max_size": int(attrs.get("basin_max_size", -1)),
		"basin_site_max_size": int(basin.get("site_max_size", -1)),
		"berth_notes": str(berth_plan.get("notes", [])),
		"quay_poly_count": plan.quay_polys.size(),
		"asphalt_poly_count": plan.asphalt_polys.size(),
		"land_poly": _pts(plan.land_poly),
		"foundation_poly": _pts(plan.foundation_poly),
		"shore_poly": _pts(plan.shore_poly),
		"dock_face_poly": _pts(plan.dock_face_poly),
		"quay_polys": _poly_list(plan.quay_polys),
		"quay_meta": str(plan.quay_meta),
		"asphalt_polys": _poly_list(plan.asphalt_polys),
		"asphalt_meta": str(plan.asphalt_meta),
		"bounds": [plan.bounds.position.x, plan.bounds.position.y,
			plan.bounds.size.x, plan.bounds.size.y],
		"centre_world": [plan.centre_world().x, plan.centre_world().y],
		"suggested_span_m": plan.suggested_span_m(),
		"world_origin": [plan.world_origin.x, plan.world_origin.y, plan.world_origin.z],
		"rotation_y": plan.rotation_y,
	}


func _pts(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for p in poly:
		out.append([p.x, p.y])
	return out


func _poly_list(polys: Array) -> Array:
	var out: Array = []
	for poly in polys:
		out.append(_pts(poly as PackedVector2Array))
	return out


## Compares only `keys`, and FAILS LOUD on a key that is missing from either
## digest rather than skipping it — a comparison that silently drops a field is
## the vanished check of REALITY §4f wearing a diff's clothes.
func _diff(a: Dictionary, b: Dictionary, keys: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	for key in keys:
		if not a.has(key) or not b.has(key):
			out["MISSING:" + key] = true
			continue
		var av: Variant = a[key]
		var bv: Variant = b[key]
		if typeof(av) == TYPE_ARRAY or typeof(bv) == TYPE_ARRAY:
			if JSON.stringify(av) != JSON.stringify(bv):
				out[str(key)] = true
		elif str(av) != str(bv):
			out[str(key)] = true
	return out


## Every port id, in the loop's own order, so a register that names ALL of them is
## still a NAMED SET and not a count — if one port stops being wrong, the equality
## reds and says which.
func _all_port_ids(records: Array) -> Array[String]:
	var out: Array[String] = []
	for rec_raw in records:
		out.append(str(((rec_raw as Dictionary)["source"] as Dictionary).get("port_id", "")))
	return out


func _strings(values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append(str(v))
	return out


func _region_word(region_kind: int) -> String:
	match region_kind:
		int(PortDefinition.RegionKind.MAINLAND):
			return "mainland"
		int(PortDefinition.RegionKind.FJORD):
			return "fjord"
		int(PortDefinition.RegionKind.ARCHIPELAGO):
			return "archipelago"
	return "coastal"
