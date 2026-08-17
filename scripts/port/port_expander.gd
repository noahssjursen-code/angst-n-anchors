class_name PortExpander
extends RefCounted

## Deterministic converter: PortDefinition + world_seed → initial PortData.
## Pipeline: trade profile → coast-traced foundation + berth_plan → PortData.

## The world's own `features` list opens with this string. It is a note about how
## the harbour was generated, not a facility — no port stamp builds anything for
## it — and the pick panel filters it the way it filters `Export:`. Named here
## rather than spelled twice so the producer and the panel's filter cannot drift
## (`map_overlay.gd` matches on this constant).
const LAYOUT_FEATURE_NOTE := "Terrain-traced Port Layout"

const POPULATION_RANGE: Dictionary = {
	0: [50, 300],
	1: [300, 1500],
	2: [1500, 6000],
	3: [6000, 25000],
	4: [25000, 100000],
	5: [80000, 250000],
	6: [200000, 600000],
	7: [500000, 1200000],
	8: [1000000, 2500000],
}


## Both entry points below carried the same bare `assert()` on this. It is a
## genuine invariant — a definition written by generation N must not be expanded
## by generation N+k's rules — but `assert` was never enforcing it: it is
## compiled out of release builds, so a stale definition sailed straight through
## into `expand_uncached`, which then copies the STALE number onto the PortData
## it just built with CURRENT rules (`data.port_generation_version =
## definition.port_generation_version`) and hands that on to
## `PortLayoutGenerator`, where it becomes `graph.generation_version`. The assert
## was not merely absent; what it was absent from was a path that MISLABELS its
## own output. That label is the worse half: a v46 port claiming to be v43 is a
## wrong answer that survives being saved.
##
## There is no migration table in this repo and inventing one here would be
## fiction. So the guard does the only honest thing available: report the
## mismatch by both numbers, and re-stamp the definition at the version that is
## actually about to generate it, so whatever comes out is labelled with the
## rules that made it. Returns true when it had to intervene.
static func _restamp_generation(definition: PortDefinition, site: String) -> bool:
	var current := PortDefinition.CURRENT_PORT_GENERATION_VERSION
	if definition.port_generation_version == current:
		return false
	push_error(
		"PortExpander.%s: port \"%s\" was written at generation %d and there is no migration to %d — regenerating it at %d and re-stamping the definition, because the alternative is a port built by %d's rules that says it is %d" % [
			site, definition.port_id, definition.port_generation_version, current,
			current, current, definition.port_generation_version,
		]
	)
	definition.port_generation_version = current
	return true


## ONE DERIVATION OF "THIS PORT LANDS FISH" (REALITY §3b) — 2026-08-17.
##
## `expand_uncached` below deliberately overwrites `has_fish_landing` with
## `_has_realized_fish_landing(layout_graph)`, commented *"prevents the chart/NPC
## from advertising a fish landing that the berth plan failed to create"*. This
## function used to print raw `PortFishingService.is_eligible` instead — and it is
## the ONLY producer the home-port pick panel ever sees, so the correction sat on
## the path no player reads. Measured over six world seeds, 210 ports, with the
## land field baked as the live world bakes it: 137 ports advertised a fish
## landing and 85 built one. All 52 divergences were size 0, and all 52 for the
## same reason (see `PortFishingService.apply_to_profile`).
##
## It was not cosmetic: `map_overlay.gd:469` gates the home-port CONFIRM button on
## this flag plus its feature string, and `CompanyContracts.DEFAULT_STARTER` is
## "fishing", so a fishing captain was allowed to choose a harbour with no fish
## landing in it.
##
## The fix asks the producer that KNOWS instead of re-deriving. A cheap local
## predicate was available and was rejected on purpose: every divergence today is
## the size-0 import ladder, so `import_slot_count_for_size(size) >= 1` would have
## agreed with the berth plan on all 210 ports measured — and it would be a THIRD
## copy of the fact, tuned to agree on the population it was tuned on, silently
## wrong the first time a berth plan drops a fishing quay for any other reason
## (`_place_quays` returns nothing on a degenerate dock face; the basin clamps arm
## length; `_cap_quay_families` can drop a family). That is REALITY §1's proxy
## trap. The only honest derivation of realized infrastructure is the realized
## layout graph.
##
## COST, MEASURED, because "too expensive for the picker" is the reason the second
## derivation existed and had never been checked: `chart_summary` was 0.24 ms per
## port and a full `expand` is 16.8 ms, so a 35-port preview pays ~590 ms once —
## against the 6–10 s the same call already spends generating the world layout.
## `PortDataCache` keys on the port + seed + layout checksum, so within the menu
## these are the same expansions `ChartHarbourPlan.for_port` already pays for on
## this very screen when it draws a harbour silhouette. They are NOT reused by the
## world afterwards — `world.gd:76` clears the cache at the top of `_rebuild`, so
## do not repeat that half of the argument; the picker pays this once and the world
## pays again.
##
## ⚠ THAT COST PAIR IS NO LONGER A CHOICE ANYONE IS MAKING — 2026-08-17. It reads
## as though a summary that asks the expander costs 70× a summary that re-derives.
## It does not, because THIS function put the full expansion inside `chart_summary`
## and the re-derivation went on running beside it. Re-measured over the same six
## seeds x 35 ports (`tests/_collapse_feasibility_probe.gd`): `chart_summary` cost
## **19.88 ms** per port, of which **19.75 ms** was this expansion — the parallel
## trade/size/RNG derivation was **0.13 ms**, 0.7% of the call. So collapsing it
## made the picker faster. Quote the 0.24 ms number only about the producer that
## existed before `84b8afa`.
##
## PASS THE LAYOUT. Dropping it was mutation M2 of the 2026-08-17 fix and IT
## PASSED FIRST TIME, which was recorded as a finding. The finding was real; the
## paragraph that used to sit here was not.
##
## ⚠ IT SAID *"`basin.max_arm_m` differs at 70 of 70 … but `has_fish_landing`, the
## quay families, the quay lengths, THE TRACED COAST and the trade slots came out
## IDENTICAL at all 70"*, and the traced-coast half was an artefact of the
## instrument. `tests/_layout_argument_probe.gd` compared
## `port_area.coast_polyline` by its `.size()` and the quays by a SUM of lengths —
## a synthetic coast with the same vertex count in entirely different places is
## invisible to both. Re-measured 2026-08-17 by diffing the WHOLE serialized
## result path by path (`tests/_layout_argument_deep_probe.gd`, `PortData
## .to_chart_dict()` + `PortLayoutGraph.to_dict()`, same 70 ports of the same two
## worlds):
##
##   70 of 70 ports differ, across 81 distinct paths.
##
## Not a cap on an arm: A DIFFERENT HARBOUR. Every vertex of `port_area
## .coast_polyline`, `foundation.dock_face_polyline` and the foundation segments;
## `port_area.terrain_coast_polyline` at 101 points against 4; every module's
## `position_m`; the whole `land_plan.buildable_zone`; `plot_depth` (365 m against
## 410 m); `apron_pads.pad_count` at 41 of 70 and even `pads[].pad_template_id` at
## 10 of 70 — the layout-less expansion lays out DIFFERENT BUILDINGS.
##
## What survives unchanged is precisely the fields `chart_summary` publishes:
## `has_fish_landing`, `size`, `berth_count`, `commodity_imports`, `features`,
## `population`, `max_ship_class` are identical at all 70. So the correct reading
## is not "the layout barely reaches this code" but "everything it reaches is
## discarded by the summary, except the fish verdict, which happens to come out the
## same on every port measured." That coincidence is REALITY §1's proxy trap seen
## from the inside: the answer is right for a reason that is not the reason it is
## asked for. `_has_realized_fish_landing` walks the berth plan of whichever
## harbour it is given, and without a layout that harbour does not exist.
##
## Held by a check since 2026-08-17 (`chart_rewrite_integration_test`): drawing
## every harbour the picker just summarised must cost ZERO new expansions, so the
## panel's verdict and the silhouette beside it come from one PortData and not two
## — and the same unit asserts the layout-less harbour really is a different
## harbour, so that check is not a perf nicety.
## ⚠ THE FUNCTION THIS HEADER USED TO SIT ON IS GONE — 2026-08-17, same day it was
## written. It was `realized_fish_landing(definition, seed, layout) -> bool`: it ran
## a full `expand` and returned one field of it. Collapsing `chart_summary`'s
## parallel derivation left it with **zero callers anywhere** — its own declaration
## was the only hit in `scripts/` and `tests/` — while five comments still pointed at
## it as "the shared derivation", which would have told every future reader that the
## pick panel goes through a function nothing calls (REALITY §3d; the house rule is
## that proved supersession is DELETED, not archived). Its record is kept here,
## because the fish-landing fix is the reason this seam exists at all, and the
## function that now does the asking is below.
##
## `expand_uncached` RESOLVES the definition in place — it clamps `size` and
## writes back `site_max_size`. `chart_summary` promises its caller an untouched
## definition (`port_fishing_service_test` asserts the recorded `port_definition`
## is byte-identical to the placed one), so both fields are restored here. The
## cache key is taken from the definition AS PASSED, so the world's own later
## `expand` of the same port still hits this entry.
##
## Do NOT read the resolved `site_max_size` back off the definition after this
## call: on a cache HIT `PortDataCache.expand` never enters `expand_uncached` and
## the definition is not resolved at all, so the value would be whatever the
## caller passed in. The resolved ceiling is published by the world at
## `layout_graph.initial_attributes["site_max_size"]` (`port_layout_generator.gd:92`),
## which is where `port_showcase.gd`'s ceiling readout takes it from.
##
## ⚠ `chart_summary` USED TO REPUBLISH IT AND NO LONGER DOES — 2026-08-17, REALITY
## §3d. The sentence that stood here said "and that is where `chart_summary` takes
## it from", which was true and pointless: the key had one reader in the project
## and that reader could never see it. See the deletion note in the returned
## dictionary below, and `chart_live_harbour_test` for what a player sees.
static func summary_expansion(
		definition: PortDefinition,
		world_seed: int,
		world_layout: WorldLayout = null,
) -> PortData:
	if definition == null:
		return null
	var size := definition.size
	var site_max_size := definition.site_max_size
	var world_data := expand(definition, world_seed, world_layout)
	definition.size = size
	definition.site_max_size = site_max_size
	return world_data


## THE PICK PANEL'S DOSSIER, ASKED OF THE WORLD RATHER THAN RE-DERIVED — 2026-08-17.
##
## This function used to recompute the trade profile, the size ladder and the RNG
## draws in parallel with `expand_uncached`, **while holding the world's own
## `PortData` in hand and throwing it away**: it already called
## `realized_fish_landing`, which runs a full `expand`, and kept one boolean out
## of it. That single §3b instance produced every divergence the register ever
## held — `has_fish_landing` (52/210, fixed by asking), `commodity_imports`
## (24/210, fixed by resyncing the copy), `population` (210/210), `features`
## (210/210) and `berth_count` (72/210). Fixing a parallel derivation field by
## field is a losing game; this asks the producer instead.
##
## COST, MEASURED, because "too expensive for the picker" was the reason the second
## derivation existed and had never been re-checked after the fish fix put a full
## expansion inside this call anyway. Six seeds x 35 ports, sizes 0–4
## (`tests/_collapse_feasibility_probe.gd`), cold cache, per port:
##
##   chart_summary as it stood      19.88 ms
##   the expand() already inside it 19.75 ms   <- 99.3% of it
##   chart_summary on a warm cache   0.26 ms
##
## So the parallel derivation was **0.13 ms of a 19.88 ms call** and deleting it
## makes the picker faster, not slower. There is no cost argument left, and the
## 0.24 ms → 16.8 ms figure quoted before the fish fix is no longer the choice
## anyone is making: the expansion is already paid for.
##
## And it is the SAME expansion the chart beside the panel draws from: measured
## **0 new cache entries over 210 ports** when `ChartHarbourPlan.resolve_port_data`
## re-expands the port this summary just described. `chart_rewrite_integration_test`
## holds that as a check.
##
## PRODUCIBILITY, measured field by field before any of this was written: of the 20
## keys published then, **18 already held exactly the value the world's PortData
## carries, at 210 of 210 ports** — including the resolved `site_max_size`, the
## traced `rotation_y`, `export_slots`, `region` and the whole `features` list once
## the generation note is accounted for. Nothing here is a field the expander
## cannot produce at preview time. **`site_max_size` is now 19 keys, not 20:
## producible and read by nothing, so it is deleted rather than published** —
## 2026-08-17, see the note where it used to sit.
##
## TWO FIELDS ARE DELIBERATELY NOT COLLAPSED, AND THEY ARE OWNER DECISIONS —
## see the block below. Collapsing them would silently change a number a player
## reads, which is worse than the divergence (`chart_rewrite_integration_test`
## keeps both registered, and each must still diverge or be struck off).
static func chart_summary(
		definition: PortDefinition,
		world_seed: int,
		world_layout: WorldLayout = null,
) -> Dictionary:
	_restamp_generation(definition, "chart_summary")
	## Recorded BEFORE the expansion, which resolves the definition in place, so
	## the panel carries the placed site's exact geometry inputs. Reconstructing
	## from a summary loses measured quay clearance.
	var placed_definition := definition.to_dict()
	var world_data := summary_expansion(definition, world_seed, world_layout)
	if world_data == null:
		return {}
	var chart := world_data.to_chart_dict()
	var size := int(world_data.size)

	## ── THE TWO FIELDS THIS WAVE WAS TOLD NOT TO DECIDE ──────────────────────
	##
	## `population` and `berth_count` are the panel's OWN numbers, and they stay
	## the panel's own numbers on purpose. Both are registered divergences in
	## `chart_rewrite_integration_test` and both are product questions, not slips:
	##
	##   population  — 210/210. Two draws from the same POPULATION_RANGE band off
	##                 the same site seed; the world advances the stream one extra
	##                 `randf()` (its legacy rotation draw) before drawing. Which
	##                 number is that port's population has never been decided.
	##   berth_count — 72/210. The panel prints `PortSizing.berth_count(size)`,
	##                 the size LADDER; the world publishes `_count_berths`, the
	##                 quays actually BUILT. The panel's meta line reads
	##                 "size N · M berths". Which one a player should read has
	##                 never been decided.
	##
	## Reproducing the panel's population needs the RNG stream the old parallel
	## derivation advanced, so the two throwaway draws below are kept — and they
	## are stream advancement ONLY, mirroring `expand_uncached`'s short-circuits
	## (`or` does not evaluate its right side, and `size >= 0` is always true), not
	## a second derivation of the flags, which are read off the world above.
	## Verified against the pre-collapse output: both fields byte-identical at 210
	## of 210 ports.
	##
	## WHEN THE OWNER DECIDES, this whole block is deleted and the two keys read
	## `world_data.population` / `maxi(world_data.berth_count, 1)`; then strike the
	## two register entries. Do not decide it here.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world_data.layout_seed)
	if not definition.has_lighthouse and size >= 1:
		rng.randf()
	if not definition.has_fog_horn:
		rng.randf()
	var panel_population := _population(rng, size)
	var panel_berth_count := maxi(PortSizing.berth_count(size), 1)
	## ── end of the undecided block ───────────────────────────────────────────

	return {
		"id": world_data.port_id,
		"display_name": world_data.display_name,
		"position": world_data.world_position,
		"port_definition": placed_definition,
		## Chart harbour silhouettes expand from this summary — yaw + site seed
		## must match the placer or every quay faces world −Z (north-up). Both are
		## now the world's, which is what the placer handed it.
		"rotation_y": world_data.rotation_y,
		"layout_seed": world_data.layout_seed,
		## `site_max_size` USED TO BE PUBLISHED HERE AND IS DELETED — 2026-08-17,
		## REALITY §3d. It had exactly one reader in the project,
		## `ChartHarbourPlan.resolve_port_data`, on the branch it takes when the
		## port record carries no `port_definition` — and this dictionary always
		## carries one, three lines up, so that branch is never taken on a record
		## this function produced. The other producer of that record,
		## `PortCatalog.get_port_info`, carries neither key, so the read there
		## resolves to `PortDefinition`'s own default. No producer in the project
		## could make that line do anything, which is why the read went with it.
		## Held by `chart_live_harbour_test`, which asserts the DRAWN harbour on the
		## live-tree path is unchanged by the ceiling (0 of 210 ports over six seeds)
		## and that this key stays gone.
		"size": size,
		"region": str(chart.get("region", "coastal")),
		"commodity_export": world_data.commodity_export,
		"commodity_imports": world_data.commodity_imports.duplicate(),
		"export_slots": world_data.trade_profile.export_slots.duplicate() \
				if world_data.trade_profile != null else [],
		"population": panel_population,
		"berth_count": panel_berth_count,
		## The world's list VERBATIM, including `LAYOUT_FEATURE_NOTE`. The panel
		## filters that note the way it filters `Export:` — presentation belongs to
		## the presenter, and stripping it here would have been a second list.
		"features": world_data.features.duplicate(),
		"max_ship_class": int(world_data.max_ship_class),
		"max_ship_class_name": str(
			ShipClass.DISPLAY_NAME.get(world_data.max_ship_class, "Vessel")),
		"has_lighthouse": world_data.has_lighthouse,
		"has_fog_horn": world_data.has_fog_horn,
		"has_fish_landing": world_data.has_fish_landing,
	}


static func expand(
		definition: PortDefinition,
		world_seed: int,
		world_layout: WorldLayout = null,
		extra_attributes: Dictionary = {},
) -> PortData:
	## Before the cache, not after: `PortDataCache` mixes
	## `definition.port_generation_version` into its key, so re-stamping inside
	## `expand_uncached` alone would file v46 data under a v43 key.
	_restamp_generation(definition, "expand")
	return PortDataCache.expand(definition, world_seed, world_layout, extra_attributes)


static func expand_uncached(
		definition: PortDefinition,
		world_seed: int,
		world_layout: WorldLayout = null,
		extra_attributes: Dictionary = {},
) -> PortData:
	_restamp_generation(definition, "expand_uncached")
	var data := PortData.new()
	data.port_id = definition.port_id
	data.display_name = definition.display_name
	data.world_position = definition.world_position
	data.site_id = definition.site_id
	data.port_generation_version = definition.port_generation_version
	## Geography ceiling first — trade unlocks follow the allowed size.
	definition.site_max_size = clampi(
		definition.site_max_size if definition.site_max_size > 0 else PortSizing.MAX_SIZE,
		PortSizing.MIN_SIZE,
		PortSizing.MAX_SIZE,
	)
	data.size = mini(
		PortSizing.normalized_size(definition.size),
		definition.site_max_size,
	)
	definition.size = data.size

	var site_seed := definition.site_seed if definition.site_seed != 0 \
			else world_seed ^ _hash_id(definition.port_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	data.trade_profile = PortTradeProfile.derive(definition, world_seed)
	## Economy volume caps growth: sparse destinies cannot inflate into hubs.
	var trade_max := PortTradeProfile.max_size_for_profile(data.trade_profile)
	definition.site_max_size = mini(definition.site_max_size, trade_max)
	if data.size > definition.site_max_size:
		data.size = definition.site_max_size
		definition.size = data.size
		PortTradeProfile.resync_for_size(data.trade_profile, data.size)
	## ONE ASSIGNMENT OF THE PUBLIC FLAG (REALITY §3b) — 2026-08-17.
	##
	## This line used to read `data.has_fish_landing = PortFishingService
	## .is_eligible(...)`, and the realized answer overwrote it 28 lines down. For
	## those 28 lines the PUBLIC field held ELIGIBILITY, which is the precise value
	## whose escape to the pick panel promised 52 fish landings the world never
	## built. Nothing outside this function could read it there — `data` is a local
	## that is not published until `return`, and the generator is handed the trade
	## profile and an attribute dictionary, never the PortData — so the trap was
	## latent rather than live. It is still the shape that produced the bug, and
	## the two values are not the same fact: eligibility is an INPUT the berth plan
	## needs in order to try, and `has_fish_landing` is what it managed to build.
	##
	## They now live in different places. `fish_eligible` is a local, the public
	## field is assigned exactly once (after generation, from the realized layout),
	## and `port_fishing_service_test` fails if a second assignment reappears in
	## this function.
	var fish_eligible := PortFishingService.is_eligible(definition, world_seed)
	if fish_eligible:
		PortFishingService.apply_to_profile(data.trade_profile)
	data.has_fuel_point = true
	data.has_lighthouse = definition.has_lighthouse or (data.size >= 1 and rng.randf() < 0.3)
	data.has_fog_horn = definition.has_fog_horn or (data.size >= 0 and rng.randf() < 0.4)
	var layout_attrs := {
		"has_fuel_point": data.has_fuel_point,
		"has_lighthouse": data.has_lighthouse,
		"has_fog_horn": data.has_fog_horn,
		## The PRECURSOR, deliberately: the berth plan cannot be told what it
		## realized before it runs. Measured 2026-08-17 over 210 ports — no
		## production script reads this key out of `initial_attributes` during
		## generation, and the line below `generate` replaces it with the realized
		## answer before the graph is published, so the graph's own copy of the fact is
		## single-valued to every reader outside this call.
		"has_fish_landing": fish_eligible,
		"world_layout": world_layout,
		"trade_max_size": trade_max,
	}
	layout_attrs.merge(extra_attributes, true)
	data.layout_graph = PortLayoutGenerator.generate(
		definition,
		data.trade_profile,
		site_seed,
		layout_attrs,
	)
	## Public facility flags describe realized infrastructure, never eligibility.
	## This prevents the chart/NPC from advertising a fish landing that the berth
	## plan failed to create — and since 2026-08-17 it is the ONLY derivation of
	## that fact: `chart_summary` reads this value back through
	## `realized_fish_landing` rather than re-deriving it from eligibility, which
	## is what let the pick panel promise 52 fish landings the world never built.
	## Do not add a second corrected copy anywhere; ask this one.
	##
	## THE ONLY ASSIGNMENT of this field in this function, and it must stay that
	## way. `port_fishing_service_test` reads this source back and fails if any
	## public `PortData` field is written twice here, because writing eligibility
	## into it first and correcting it later is the exact shape that shipped the
	## bug above.
	data.has_fish_landing = _has_realized_fish_landing(data.layout_graph)
	data.layout_graph.initial_attributes["has_fish_landing"] = data.has_fish_landing
	## Basin may record a water hint; live size stays whatever Expander clamped.
	data.size = PortSizing.normalized_size(definition.size)

	var graph_bounds := data.layout_graph.bounds()
	var quay_pose := data.layout_graph.primary_quay_pose()
	data.dock_length = maxf(
		float(quay_pose.get("length_m", 0.0)),
		PortSizing.dock_length_m(data.size),
	)
	data.island_width = maxf(graph_bounds.size.x + 36.0, PortSizing.island_width_m(data.size))
	data.plot_depth = maxf(graph_bounds.size.z + 36.0, PortSizing.PLOT_DEPTH_M)
	data.max_ship_class = _ship_class_for_size(data.size)
	data.berth_count = _count_berths(data.layout_graph)
	data.commodity_export = data.trade_profile.primary_export()
	data.commodity_imports = data.trade_profile.import_slots.duplicate()
	data.layout_seed = site_seed
	var legacy_rotation := rng.randf() * TAU
	data.rotation_y = definition.rotation_y if definition.has_explicit_rotation else legacy_rotation
	data.region_kind = definition.region_kind
	data.ground_mode = definition.ground_mode
	data.population = _population(rng, data.size)
	data.features = [LAYOUT_FEATURE_NOTE]
	if data.has_lighthouse:
		data.features.append("Lighthouse")
	if data.has_fog_horn:
		data.features.append("Fog Horn")
	if data.has_fish_landing:
		data.features.append("Fish Landing")
	for commodity in data.trade_profile.export_slots:
		data.features.append("Export:%s" % commodity)
	return data


static func _has_realized_fish_landing(graph: PortLayoutGraph) -> bool:
	if graph == null:
		return false
	var plan := graph.initial_attributes.get("berth_plan", {}) as Dictionary
	for raw in plan.get("quay_stations", []) as Array:
		var station := raw as Dictionary
		if _quay_station_has_fish_landing(station):
			return true
	for raw in plan.get("asphalt_stations", []) as Array:
		var station := raw as Dictionary
		if str(station.get("family", "")) == "fishing" \
				and str(station.get("commodity_id", "")) == PortFishingService.COMMODITY_ID \
				and str(station.get("equipment_kind", "")) == "equip_fish_derrick":
			return true
	return false


static func _quay_station_has_fish_landing(station: Dictionary) -> bool:
	if str(station.get("family", "")) == "fishing" \
			and (station.get("commodities", []) as Array).has(PortFishingService.COMMODITY_ID) \
			and str(station.get("equipment_kind", "")) == "equip_fish_derrick":
		return true
	for raw_side in station.get("sides", []) as Array:
		var side := raw_side as Dictionary
		if str(side.get("family", "")) == "fishing" \
				and (side.get("commodities", []) as Array).has(PortFishingService.COMMODITY_ID) \
				and str(side.get("equipment_kind", "")) == "equip_fish_derrick":
			return true
	return false


static func _population(rng: RandomNumberGenerator, size: int) -> int:
	var band: Array = POPULATION_RANGE.get(size, [100, 500])
	return rng.randi_range(int(band[0]), int(band[1]))


static func _hash_id(port_id: String) -> int:
	return port_id.hash()


static func _count_berths(graph: PortLayoutGraph) -> int:
	var plan := graph.initial_attributes.get("berth_plan", {}) as Dictionary
	var planned := int(plan.get("quay_count", 0)) + int(plan.get("asphalt_slot_count", 0))
	if planned > 0:
		return planned
	var count := 0
	for instance_id in graph.module_ids():
		var placed := graph.modules[instance_id] as PortPlacedModule
		var definition := graph.module_definition(placed.module_id)
		if definition != null and definition.kind == "quay":
			count += 1
	return maxi(count, 1)


static func _ship_class_for_size(size: int) -> ShipClass.Type:
	return PortSizing.design_ship_class(size)
