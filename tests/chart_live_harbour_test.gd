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
## supplies fourteen of them — `region`, `max_ship_class_name` and
## `commodity_exports` keep their defaults — and it publishes no `PortDefinition` at
## all, so the rebuilt definition is missing most of the placed site. That was
## reported as a `site_max_size` defect, and measured 2026-08-17 over six seeds x 35
## ports (`tests/_chart_live_ceiling_probe.gd`) it is not one — see the properties
## below. The ceiling changes nothing anyone sees; the REGION WORD changes the
## harbour.
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
## P3  REGISTERED, NOT FIXED: the unstamped silhouette is a DIFFERENT HARBOUR from
##     the stamped one, and the cause is named rather than described. Injecting the
##     `region` word alone reproduces the stamp's every drawn path; injecting the
##     whole placed `port_definition` reproduces it exactly. So the fix is that the
##     catalog should carry the definition — a change to what a player sees at most
##     of the ports on the chart, which is an owner's frame to look at and not a
##     patch to sneak in behind a green gate.
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
## 20 ports x 4 per-port checks + 16 fixed.
const EXPECTED_CHECKS := 96

## The keys of a harbour digest that a player either sees drawn on the chart or
## reads off the same `PortData`. Declared so a digest field added later has to be
## classified rather than silently escaping both groups.
const PLAYER_FACING_KEYS: Array[String] = [
	"land_poly", "foundation_poly", "shore_poly", "dock_face_poly",
	"quay_polys", "quay_meta", "asphalt_polys", "asphalt_meta",
	"quay_poly_count", "asphalt_poly_count",
	"bounds", "centre_world", "suggested_span_m", "world_origin", "rotation_y",
	"data_size", "data_berth_count", "data_max_ship_class",
]

## THE REGISTERED DIVERGENCE, AS A NAMED SET RATHER THAN A COUNT — and that is
## not tidiness, it is the fix for a blind mutation this unit failed. The check
## used to read `stamp_divergent > 0`. Flipping the live chart's region fallback
## from `LEGACY_ISLAND` to `MAINLAND` took the divergence from **8 of 20 ports to
## 2** and the unit **passed**: a register that asserts only "still broken" cannot
## see itself getting better, and the same hole is on record for
## `chart_rewrite_integration_test`'s register (STATE.md 2026-08-17 — "the register
## asserts disagreement, so a different wrong number still passes it").
##
## Naming the members is strictly stronger than freezing the count: a set that
## changes reds and says WHICH port left it (REALITY §4f shape 1).
##
## HONESTY ABOUT HOW THIS LIST WAS OBTAINED. The COUNT was predicted — 8 of 20,
## measured twice by the `> 0` version of this check before the set existed, and
## by the six-seed probe at 133 of 210. The MEMBERSHIP was not: my first guess at
## the eight ids was wrong in six of eight (I copied them off a ceiling mutation's
## failure list, which is a different question), the check reded and named them,
## and the measured set is written here. So this is a recorded run, not a
## prediction — a distinction REALITY §4f is explicit about, and the reason it is
## acceptable here is that the number it multiplies out to was independently
## predicted and confirmed.
##
## MAINLAND is not a fix, incidentally, and must not be adopted as one: it agrees
## with the stamp more often at this seed because most sites here are fjord, which
## is REALITY §1's proxy trap — a number tuned on the population it was measured
## on. The fix is the placed definition.
const DIVERGENT_PORTS: Array[String] = [
	"port-home", "port-3", "port-5", "port-10", "port-11", "port-15", "port-17", "port-18",
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
	## definition, then hand `register_port` the fifteen scalars it takes.
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
		)
		records.append({
			"source": source,
			"resolved_ceiling": world_def.site_max_size,
			"data": world_data,
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
		+ " branch at all",
		not first_info.has("port_definition"),
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
	var region_closes := 0
	var definition_closes := 0
	var region_words: Dictionary = {}

	for index in range(records.size()):
		var rec: Dictionary = records[index]
		var pid := str((rec["source"] as Dictionary).get("port_id", ""))
		var region_word := _region_word(
			int((rec["source"] as Dictionary).get("region_kind", 0)))
		region_words[region_word] = int(region_words.get(region_word, 0)) + 1

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
		## F — the region word alone, everything else as the world registered it.
		var f := _draw_live(pid, snapshot, {"region": region_word}, catalog)
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

		## ── P3, the register ────────────────────────────────────────────────
		if not _diff(a, c, PLAYER_FACING_KEYS).is_empty():
			stamp_divergent.append(pid)
		if _diff(f, c, PLAYER_FACING_KEYS).is_empty():
			region_closes += 1
		if _diff(h, c, PLAYER_FACING_KEYS).is_empty():
			definition_closes += 1
		t.check(
			"port %s: handing the live chart the placed `port_definition`" % pid
			+ " reproduces the STAMPED harbour's every drawn path — so the"
			+ " unstamped silhouette is not an approximation, it is a rebuild"
			+ " missing its inputs",
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

	## ── P3, registered ───────────────────────────────────────────────────────
	##
	## A REGISTERED DEFECT, NOT A TOLERANCE, and the same rule
	## `chart_rewrite_integration_test`'s register runs on: it must still diverge
	## or be struck off. Making this green by teaching `register_port` the placed
	## definition changes the silhouette a player sees at most of the ports on the
	## chart. That is a frame for the owner to look at (REALITY §2), not a patch.
	t.equal(
		"REGISTERED, BY NAME: exactly these ports draw a DIFFERENT harbour on the"
		+ " live chart from the one their stamp builds — `register_port` carries no"
		+ " definition and `world.gd` leaves its `region` parameter defaulted. Strike"
		+ " this entry when the catalog carries the definition; a stale entry sends"
		+ " the next reader after a defect that is gone",
		stamp_divergent, DIVERGENT_PORTS,
	)
	t.equal(
		"and the CAUSE is the `region` word, not the ceiling: injecting the region"
		+ " alone reproduces the stamped harbour's every drawn path. Region words"
		+ " the placer assigned here: %s — all of which the catalog flattens to"
			% str(region_words)
		+ " \"coastal\", i.e. LEGACY_ISLAND, which picks a different trade theme",
		region_closes, PORT_COUNT,
	)
	t.equal(
		"and the whole placed definition closes it at every port, which is what"
		+ " names the fix",
		definition_closes, PORT_COUNT,
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
	## `register_port` always writes `region`, defaulted to "coastal", so this one
	## is overwritten rather than erased.
	entry["region"] = str(inject.get("region", "coastal"))
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


func _region_word(region_kind: int) -> String:
	match region_kind:
		int(PortDefinition.RegionKind.MAINLAND):
			return "mainland"
		int(PortDefinition.RegionKind.FJORD):
			return "fjord"
		int(PortDefinition.RegionKind.ARCHIPELAGO):
			return "archipelago"
	return "coastal"
