class_name PortExpander
extends RefCounted

## Deterministic converter: PortDefinition + world_seed → initial PortData.
## Pipeline: trade profile → coast-traced foundation + berth_plan → PortData.

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
static func realized_fish_landing(
		definition: PortDefinition,
		world_seed: int,
		world_layout: WorldLayout = null,
) -> bool:
	if definition == null:
		return false
	## `expand_uncached` RESOLVES the definition in place — it clamps `size` and
	## writes back `site_max_size`. `chart_summary` promises its caller an
	## untouched definition (`port_fishing_service_test` asserts the recorded
	## `port_definition` is byte-identical to the placed one), so both fields are
	## restored. The cache key is taken from the definition AS PASSED, so the
	## world's own later `expand` of the same port still hits this entry.
	var size := definition.size
	var site_max_size := definition.site_max_size
	var data := expand(definition, world_seed, world_layout)
	definition.size = size
	definition.site_max_size = site_max_size
	return data != null and data.has_fish_landing


## Chart / menu summary without coast tracing or PortLayoutGraph generation.
## Same trade + size rules as `expand`, cheap enough for dozens of ports —
## EXCEPT for `has_fish_landing`, which is realized infrastructure and cannot be
## derived from anything cheaper than the berth plan. See above.
static func chart_summary(
		definition: PortDefinition,
		world_seed: int,
		world_layout: WorldLayout = null,
) -> Dictionary:
	_restamp_generation(definition, "chart_summary")
	## Taken from the untouched definition, before the size clamping below, so the
	## expansion sees exactly what the world's `expand` will see.
	var has_fish_landing := realized_fish_landing(definition, world_seed, world_layout)
	var site_max := clampi(
		definition.site_max_size if definition.site_max_size > 0 else PortSizing.MAX_SIZE,
		PortSizing.MIN_SIZE,
		PortSizing.MAX_SIZE,
	)
	var size := mini(PortSizing.normalized_size(definition.size), site_max)
	var site_seed := definition.site_seed if definition.site_seed != 0 \
			else world_seed ^ _hash_id(definition.port_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	## Clone definition fields the trade profile may read without mutating caller size forever.
	var def_size := definition.size
	definition.size = size
	var trade := PortTradeProfile.derive(definition, world_seed)
	var trade_max := PortTradeProfile.max_size_for_profile(trade)
	site_max = mini(site_max, trade_max)
	if size > site_max:
		size = site_max
		definition.size = size
		PortTradeProfile.resync_for_size(trade, size)
	## Gated on the REALIZED flag, not on eligibility: a port whose berth plan has
	## no fish landing does not land fish, and the world's own trade profile
	## agrees — the size ladder trimmed `fresh_groundfish` back out of it. Keeping
	## eligibility here would have left the panel printing
	## `IMPORTS  Fresh groundfish` one line above a FACILITIES line that no longer
	## claims a fish landing.
	##
	## AND RESYNCED AFTER, BECAUSE THE WORLD DOES — 2026-08-17. Without the second
	## line this panel published ONE IMPORT MORE THAN THE WORLD BUILDS, at 24 of 210
	## ports over six seeds, and at 3 of them it ENABLED THE CONFIRM BUTTON for a
	## bulk starter at a harbour with no bulk berth. `apply_to_profile` pushes
	## `fresh_groundfish` onto the FRONT of `import_slots` and `destiny_import_slots`
	## without trimming, so the visible list ran one slot past `_import_count(size)`.
	## `expand_uncached` never had the defect: it applies the profile BEFORE
	## `PortLayoutGenerator`, whose own `resync_for_size` re-takes the head of the
	## destiny list and drops the commodity that no longer fits. This is the same
	## sequence, not a new predicate — the measured extras were diesel ×13,
	## containers ×5, crude_oil ×4 and grain ×3, and the three grain ports are the
	## three false CONFIRMs.
	##
	## Consequence measured before it was believed, the same way the fish landing
	## was: foundable home ports per 35-port world, panel → world truth, by starter
	## career. Fishing 16/11/12/13/14/20, unchanged in all six. General 35 in all
	## six, unchanged. Bulk 9, 8, 8, 8, **5→4**, **11→9** — three ports lost across
	## 210, and no world drops below four. The shape predates the 2026-08-17 fish
	## fix; it is in `c9abeda~1` unchanged.
	if has_fish_landing:
		PortFishingService.apply_to_profile(trade)
		PortTradeProfile.resync_for_size(trade, size)
	definition.size = def_size

	var has_lighthouse := definition.has_lighthouse or (size >= 1 and rng.randf() < 0.3)
	var has_fog_horn := definition.has_fog_horn or (size >= 0 and rng.randf() < 0.4)
	var features: Array[String] = []
	if has_lighthouse:
		features.append("Lighthouse")
	if has_fog_horn:
		features.append("Fog Horn")
	if has_fish_landing:
		features.append("Fish Landing")
	for commodity in trade.export_slots:
		features.append("Export:%s" % commodity)

	var region := "coastal"
	match definition.region_kind:
		PortDefinition.RegionKind.MAINLAND:
			region = "mainland"
		PortDefinition.RegionKind.FJORD:
			region = "fjord"
		PortDefinition.RegionKind.ARCHIPELAGO:
			region = "archipelago"
		_:
			region = "coastal"

	var berths := maxi(PortSizing.berth_count(size), 1)

	return {
		"id": definition.port_id,
		"display_name": definition.display_name,
		"position": definition.world_position,
		## Preserve the placed site's exact geometry inputs for the home-port
		## preview. Reconstructing from a summary loses measured quay clearance.
		"port_definition": definition.to_dict(),
		## Chart harbour silhouettes expand from this summary — yaw + site seed
		## must match the placer or every quay faces world −Z (north-up).
		"rotation_y": definition.rotation_y,
		"layout_seed": site_seed,
		"site_max_size": site_max,
		"size": size,
		"region": region,
		"commodity_export": trade.primary_export(),
		"commodity_imports": trade.import_slots.duplicate(),
		"export_slots": trade.export_slots.duplicate(),
		"population": _population(rng, size),
		"berth_count": berths,
		"features": features,
		"max_ship_class": int(_ship_class_for_size(size)),
		"max_ship_class_name": str(ShipClass.DISPLAY_NAME.get(_ship_class_for_size(size), "Vessel")),
		"has_lighthouse": has_lighthouse,
		"has_fog_horn": has_fog_horn,
		"has_fish_landing": has_fish_landing,
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
	data.features = ["Terrain-traced Port Layout"]
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
