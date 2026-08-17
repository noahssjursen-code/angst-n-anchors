extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## ONE QUESTION, IN TWO HALVES:
##
##  1. How far apart are the two derivations of `has_fish_landing`?
##     `chart_summary` prints `PortFishingService.is_eligible`; `expand_uncached`
##     overwrites the same field with `_has_realized_fish_landing(layout_graph)`.
##  2. If the pick panel stopped advertising the unrealized ones, HOW MANY PORTS
##     WOULD A FISHING CAPTAIN STILL BE ABLE TO CHOOSE — `CompanyContracts
##     .DEFAULT_STARTER` is "fishing" and `map_overlay.gd:469` gates CONFIRM on
##     exactly that pair.
##
## `tests/_fishport_survey.gd` answered (2) with `is_eligible` and its own header
## claims that "measures the production answer". It does not: it measures the
## UNCORRECTED producer, which is the defect. This re-runs its five seeds through
## the CORRECTED one and prints both numbers side by side, plus a diagnosis of
## WHY realization fails at a port that is eligible.
##
## ── THE INSTRUMENT, AND IT BIT BOTH EARLIER MEASUREMENTS ────────────────────
##
## `is_eligible` IS NOT A PURE FUNCTION OF (definition, world_seed). It samples
## `FishingField`, whose `open_water` term calls `LandField.distance_to_land` —
## and `LandField` is a GLOBAL initialized from a WorldLayout. So the same port
## in the same world answers differently depending on which world's land field
## was last baked, and with no land field at all `allows_trawling` returns true
## unconditionally, which is the most permissive answer of the three.
##
## `world.gd:157` bakes `LandField` from the live layout BEFORE it expands any
## port, so PASS A below is the live-game order and its numbers are the ones to
## quote. PASS B leaves the field empty — what an isolated probe measures by
## accident, and what `ChartDataSnapshot.for_preview` really does to its FIRST
## snapshot, because it summarises 35 ports at line 99 and bakes the land field
## at line 102. PASS C bakes the WRONG world's field, which is what happens to a
## unit that surveys two seeds in one process.
##
## Reports timings too, because "chart_summary is cheap and expand is not" is the
## whole argument for the divergence existing and it has never been measured.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
## `_fishport_survey`'s five, plus the two `port_feature_promise_test` declares.
const SEEDS := [90210, 424242, 7, 1337, 20260815, 20260817]

const REGION_NAME := {
	0: "legacy_island",
	1: "mainland",
	2: "fjord",
	3: "archipelago",
}

var _layouts: Dictionary = {}
var _ports: Dictionary = {}


func _initialize() -> void:
	for world_seed in SEEDS:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		_layouts[int(world_seed)] = layout
		_ports[int(world_seed)] = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))

	_pass("A — LIVE-GAME ORDER: land field baked from this world's layout", "self")
	_pass("B — no land field at all (an isolated probe; also for_preview's FIRST snapshot)", "none")
	_pass("C — the WRONG world's land field (a unit that surveys two seeds in one process)", "other")
	quit(0)


func _pass(title: String, land: String) -> void:
	print("")
	print("════ PASS %s ════" % title)
	var total := 0
	var elig_total := 0
	var real_total := 0
	var by_region: Dictionary = {}
	var by_size: Dictionary = {}
	var diagnosis: Dictionary = {}
	var summary_ms := 0.0
	var expand_ms := 0.0
	var expand_n := 0
	var per_world: Array[int] = []

	for world_seed in SEEDS:
		var layout: WorldLayout = _layouts[int(world_seed)]
		var ports: Array = _ports[int(world_seed)]
		_bake(land, int(world_seed))
		var elig := 0
		var real := 0
		var home_elig := false
		var home_real := false
		var divergent: Array[String] = []
		for raw in ports:
			var port := raw as PortDefinition
			total += 1
			var region := str(REGION_NAME.get(int(port.region_kind), "?"))

			var t0 := Time.get_ticks_usec()
			var summary := PortExpander.chart_summary(_clone(port), int(world_seed))
			summary_ms += float(Time.get_ticks_usec() - t0) / 1000.0
			var advertised := bool(summary.get("has_fish_landing", false))

			PortDataCache.clear()
			var t1 := Time.get_ticks_usec()
			var data := PortExpander.expand_uncached(_clone(port), int(world_seed), layout)
			expand_ms += float(Time.get_ticks_usec() - t1) / 1000.0
			expand_n += 1
			var realized := data.has_fish_landing

			var size := int(data.size)
			if not by_region.has(region):
				by_region[region] = [0, 0, 0]
			var rrow: Array = by_region[region]
			rrow[0] = int(rrow[0]) + 1
			if not by_size.has(size):
				by_size[size] = [0, 0, 0]
			var srow: Array = by_size[size]
			srow[0] = int(srow[0]) + 1

			if advertised:
				elig += 1
				elig_total += 1
				rrow[1] = int(rrow[1]) + 1
				srow[1] = int(srow[1]) + 1
			if realized:
				real += 1
				real_total += 1
				rrow[2] = int(rrow[2]) + 1
				srow[2] = int(srow[2]) + 1
			if port.port_id == "port-home":
				home_elig = advertised
				home_real = realized
			if advertised and not realized:
				divergent.append(port.port_id)
				var why := _why(data)
				diagnosis[why] = int(diagnosis.get(why, 0)) + 1
			if realized and not advertised:
				diagnosis["REALIZED WITHOUT BEING ADVERTISED"] = \
					int(diagnosis.get("REALIZED WITHOUT BEING ADVERTISED", 0)) + 1

		per_world.append(real)
		print("seed %-9d ports=%2d  advertised(eligible)=%2d  REALIZED=%2d  lost=%2d   port-home adv=%s real=%s" % [
			int(world_seed), ports.size(), elig, real, elig - real,
			"yes" if home_elig else "NO", "yes" if home_real else "NO",
		])
		print("            divergent: %s" % str(divergent))

	print("TOTAL over %d seeds, %d ports: advertised %d (%.1f%%) · REALIZED %d (%.1f%%)" % [
		SEEDS.size(), total, elig_total,
		100.0 * float(elig_total) / maxf(float(total), 1.0),
		real_total,
		100.0 * float(real_total) / maxf(float(total), 1.0),
	])
	var lo := 99
	for n in per_world:
		lo = mini(lo, n)
	print("FEWEST realized fish landings in any one world: %d of %d ports" % [lo, PORT_COUNT])
	print("by region  (ports / advertised / realized):")
	for key in by_region:
		var row: Array = by_region[key]
		print("   %-14s %3d / %3d / %3d" % [key, int(row[0]), int(row[1]), int(row[2])])
	print("by size    (ports / advertised / realized):")
	var sizes: Array = by_size.keys()
	sizes.sort()
	for key in sizes:
		var row: Array = by_size[key]
		print("   size %-9d %3d / %3d / %3d" % [int(key), int(row[0]), int(row[1]), int(row[2])])
	print("why realization failed, at the %d divergent ports:" % (elig_total - real_total))
	for key in diagnosis:
		print("   %-58s %d" % [key, int(diagnosis[key])])
	print("COST: chart_summary %.2f ms/port · expand_uncached %.2f ms/port (%d expansions)" % [
		summary_ms / maxf(float(total), 1.0),
		expand_ms / maxf(float(expand_n), 1.0),
		expand_n,
	])
	print("      one 35-port preview: summaries %.0f ms vs expansions %.0f ms" % [
		35.0 * summary_ms / maxf(float(total), 1.0),
		35.0 * expand_ms / maxf(float(expand_n), 1.0),
	])


func _bake(land: String, world_seed: int) -> void:
	FishingField.initialize(world_seed)
	match land:
		"self":
			LandField.initialize(_layouts[world_seed] as WorldLayout)
		"other":
			var other := int(SEEDS[0]) if world_seed != int(SEEDS[0]) else int(SEEDS[1])
			LandField.initialize(_layouts[other] as WorldLayout)
		_:
			## No un-initialize exists; an EMPTY field answers `distance_to_land`
			## with `inf`, which is the same `allows_trawling` verdict a fresh
			## un-initialized process gives (measured: both permit trawling).
			LandField.initialize([])


## Definitions are RESOLVED IN PLACE by both producers (`expand_uncached` clamps
## `size` and writes back `site_max_size`; `chart_summary` restores size but not
## site_max_size). Hand each producer its own copy or the second one measures the
## first one's leftovers.
func _clone(definition: PortDefinition) -> PortDefinition:
	return PortDefinition.from_dict(definition.to_dict())


func _why(data: PortData) -> String:
	if data.layout_graph == null:
		return "no layout graph at all"
	var plan := data.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary
	if plan.is_empty():
		return "berth_plan empty"
	var quays: Array = plan.get("quay_stations", []) as Array
	var asphalt: Array = plan.get("asphalt_stations", []) as Array
	if quays.is_empty() and asphalt.is_empty():
		return "berth plan placed NO station of any kind"
	var families: Array[String] = []
	var has_fishing_family := false
	for raw in quays:
		var st := raw as Dictionary
		var fam := str(st.get("family", ""))
		families.append(fam)
		if fam == "fishing":
			has_fishing_family = true
		for raw_side in st.get("sides", []) as Array:
			var sfam := str((raw_side as Dictionary).get("family", ""))
			families.append("side:%s" % sfam)
			if sfam == "fishing":
				has_fishing_family = true
	var wanted := false
	if data.trade_profile != null:
		wanted = data.trade_profile.import_slots.has(PortFishingService.COMMODITY_ID) \
			or data.trade_profile.export_slots.has(PortFishingService.COMMODITY_ID)
	if not wanted:
		return "fresh_groundfish is not in the port's trade slots (%d quays: %s)" \
			% [quays.size(), str(families)]
	if not has_fishing_family:
		return "trade slot present, NO fishing quay placed (%d quays: %s)" \
			% [quays.size(), str(families)]
	return "fishing quay placed but predicate rejected it (%s)" % str(families)
