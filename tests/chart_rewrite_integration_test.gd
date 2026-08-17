extends SceneTree

const SnapshotClass := preload("res://scripts/ui/chart/chart_data_snapshot.gd")
const BaseClass := preload("res://scripts/ui/chart/chart_base_raster.gd")
const RasterClass := preload("res://scripts/ui/chart/chart_raster_layer.gd")
const OverlayClass := preload("res://scripts/ui/map_overlay.gd")
const TestReport := preload("res://tests/support/test_report.gd")

var _picked := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("chart_rewrite_integration_test")
	_check_all(t)
	t.finish(self)


## ═══ THE PICK PANEL AGAINST THE WORLD ════════════════════════════════════════
##
## `PortExpander.chart_summary` and `PortExpander.expand` both publish a
## description of the same port, and the panel reads the first while the game
## builds the second. Every field they both publish is listed below. Surveyed
## 2026-08-17 over 210 ports (six seeds × 35, `tests/_fish_window_probe.gd`) and
## re-measured here at this unit's own seed.
##
## `MUST_AGREE` is the property. `KNOWN_DIVERGENT` is a register of DEFECTS held
## open, not a tolerance: each entry is a line the panel prints that the world
## contradicts, and each must still diverge or be struck off. A field appearing in
## neither list fails the unit, which is how a new divergence announces itself
## instead of shipping.
const MUST_AGREE: Array[String] = [
	"id", "display_name", "position", "size", "region", "commodity_export",
	"max_ship_class", "max_ship_class_name", "has_lighthouse", "has_fog_horn",
	"has_fish_landing",
	## STRUCK OFF THE REGISTER AND PROMOTED TO A PROPERTY, 2026-08-17. This was the
	## fourth registered divergence: the summary published one import beyond
	## `_import_count(size)` at 24 of 210 ports, because it applied the fishing
	## profile AFTER the size resync and never resynced again, and at 3 of those it
	## enabled the CONFIRM button for a bulk starter at a harbour with no bulk
	## berth. `chart_summary` now resyncs the way `PortLayoutGenerator` does. Cost
	## measured: bulk-foundable ports 5→4 and 11→9 in two of six worlds, no world
	## below four, fishing and general untouched.
	"commodity_imports",
	## STRUCK OFF THE REGISTER, 2026-08-17, and not by patching a field: the
	## PARALLEL DERIVATION UNDERNEATH the whole register was collapsed.
	## `chart_summary` used to recompute the trade profile, the size ladder and the
	## RNG draws beside `expand_uncached` while already holding the world's PortData
	## — it ran a full `expand` for the fish flag and kept one boolean. It now reads
	## that expansion. Measured: the re-derivation was 0.13 ms of a 19.88 ms call
	## (99.3% of which was the expansion it already paid for), and 18 of the 20
	## published keys already held the world's exact value at 210/210 ports.
	##
	## The register's own reason for THIS entry was its fix: *"the world prepends
	## `Terrain-traced Port Layout`, which map_overlay does not filter the way it
	## filters `Export:`"*. The panel now publishes the world's list verbatim and
	## `map_overlay` filters that note beside `Export:`, matching
	## `PortExpander.LAYOUT_FEATURE_NOTE` so producer and presenter cannot drift.
	## The FACILITIES line a player reads is unchanged — asserted through the real
	## presenter in `port_feature_promise_test`, which also fails if the note ever
	## reaches a player.
	"features",
]

## ONLY TWO ENTRIES REMAIN, AND BOTH ARE OWNER DECISIONS — 2026-08-17.
##
## Every other entry this register ever held came from ONE §3b instance, the
## parallel derivation in `chart_summary`, and was struck by collapsing it. These
## two were deliberately NOT collapsed: doing so would silently change a number a
## player reads, which is worse than the divergence. `chart_summary` keeps the
## panel's own value for both, verified byte-identical to the pre-collapse output
## at 210 of 210 ports, and the block that does it names what to delete once the
## owner decides.
const KNOWN_DIVERGENT: Dictionary = {
	## 210/210 ports. `_population(rng, size)` is drawn from an RNG the two
	## producers advance differently — the world spends one extra `randf()` on its
	## legacy rotation before drawing — so the POPULATION line on the pick panel is
	## a different number from the one the world's PortData carries for the same
	## port. Both are draws from the same band. Nobody has decided which is that
	## port's population, so the panel still prints its own.
	"population": "the two producers draw it from differently-advanced RNGs",
	## 72/210. The summary publishes `PortSizing.berth_count(size)` — the LADDER —
	## and the world publishes `_count_berths(layout_graph)` — what got BUILT. The
	## panel's own meta line reads "size N · M berths". Which of the two a player
	## should read is a product question, not a slip.
	"berth_count": "the summary prints the size ladder, the world counts quays",
}


func _check_all(t: TestReport) -> void:
	var registry := root.get_node_or_null("PortCatalog")
	var registry_ids: Array = registry.call("get_port_ids") if registry != null else []
	## Cleared so the count below describes THIS preview and nothing left over.
	PortDataCache.clear()
	var snapshot = SnapshotClass.for_preview(90210, 20)
	var cache_after_preview: int = PortDataCache._cache.size()
	if not t.check("the preview snapshot is valid", snapshot.is_valid()):
		return
	if not t.check("the preview snapshot holds 20 ports", snapshot.ports.size() == 20):
		return
	t.check(
		"the snapshot checksum matches its layout",
		snapshot.layout_checksum == str(snapshot.layout.layout_checksum),
	)
	if registry != null:
		t.check("building the preview leaves the port registry alone", (registry.call("get_port_ids") as Array) == registry_ids)
	## Onboarding and runtime must consume the same world identity and placed
	## port records. A preview may not silently fall back to the 40 km default.
	t.check(
		"the preview world size matches the layout",
		is_equal_approx(float(snapshot.world_size_m), float(snapshot.layout.world_size_m)),
	)
	var live_definitions := CoastalPortPlacer.place_ports(
		snapshot.layout,
		20,
		PackedStringArray(WorldPortNames.NAMES),
	)
	## Agreement between two all-false columns is agreement about nothing (REALITY
	## §4). Counted so the per-port checks above cannot pass vacuously.
	var world_fish_landings := 0
	var preview_fish_landings := 0
	var field_diverged: Dictionary = {}
	var unclassified: Dictionary = {}
	for index in range(live_definitions.size()):
		var preview_record := (snapshot.ports[index] as Dictionary).get(
			"port_definition", {},
		) as Dictionary
		if not t.check("preview port %d carries a definition" % index, not preview_record.is_empty()):
			continue
		t.check(
			"preview port %d matches the live placement" % index,
			preview_record == (live_definitions[index] as PortDefinition).to_dict(),
		)
		## ⚠ THIS CHECK USED TO COMPARE THE PREVIEW AGAINST
		## `PortFishingService.is_eligible`, AND THAT IS THE DEFECT IT WENT RED ON
		## (REALITY §3e — when a check reddens as you fix something, ask what it was
		## passing on). Eligibility is a PRECURSOR: `expand_uncached` overwrites
		## `has_fish_landing` with `_has_realized_fish_landing(layout_graph)`
		## because the size ladder can trim the fish berth back out of a small
		## harbour. Asserting the panel matched eligibility was asserting that the
		## panel matched the uncorrected producer — 5 of these 20 ports advertised a
		## fish landing the world does not build, and this unit called that agreement.
		##
		## The property is that the picker and the WORLD agree, so the right-hand
		## side is the world's own expansion of the same placed definition — the
		## producer `PortPlot` and the harbour master read — and not a re-derivation
		## of either side.
		var world_data := PortExpander.expand(
			live_definitions[index] as PortDefinition, 90210, snapshot.layout,
		)
		var world_flag := world_data.has_fish_landing
		var preview_flag := bool((snapshot.ports[index] as Dictionary).get("has_fish_landing", false))
		## Classify every field the two producers both publish (see the register above).
		var world_chart := world_data.to_chart_dict()
		var summary_dict := snapshot.ports[index] as Dictionary
		for key in world_chart:
			if not summary_dict.has(key):
				continue
			if not MUST_AGREE.has(str(key)) and not KNOWN_DIVERGENT.has(str(key)):
				unclassified[str(key)] = true
			if str(summary_dict[key]) != str(world_chart[key]):
				field_diverged[str(key)] = int(field_diverged.get(str(key), 0)) + 1
		if world_flag:
			world_fish_landings += 1
		if preview_flag:
			preview_fish_landings += 1
		t.check(
			"preview port %d agrees with the WORLD on fish landing (preview %s, world %s)"
			% [index, str(preview_flag), str(world_flag)],
			preview_flag == world_flag,
		)
	t.check(
		"the 20 previewed ports really split on fish landing (%d of 20 in the world,"
		% world_fish_landings
		+ " %d in the preview) — twenty agreeing falses would make every check"
			% preview_fish_landings
		+ " above pass while asking nothing",
		world_fish_landings > 0 and world_fish_landings < live_definitions.size()
	)

	## ── the register, evaluated ───────────────────────────────────────────────
	t.check(
		"every field the panel and the world both publish is classified (%s"
			% str(unclassified.keys())
		+ " is not) — a new shared field must be declared MUST_AGREE or registered",
		unclassified.is_empty(),
	)
	for key in MUST_AGREE:
		if not t.check(
			"the panel and the world agree on `%s` at all %d ports (%d differ)"
				% [str(key), live_definitions.size(), int(field_diverged.get(str(key), 0))],
			int(field_diverged.get(str(key), 0)) == 0,
		):
			continue
	for key in KNOWN_DIVERGENT:
		t.check(
			"registered divergence `%s` is STILL live (%d of %d ports) — %s."
				% [str(key), int(field_diverged.get(str(key), 0)), live_definitions.size(),
					str(KNOWN_DIVERGENT[key])]
			+ " Strike the entry when it is fixed; a stale entry sends the next"
			+ " reader looking for a defect that is gone",
			int(field_diverged.get(str(key), 0)) > 0,
		)

	## ── the layout argument `for_preview` hands to `chart_summary` ────────────
	##
	## `PortExpander.summary_expansion` runs a FULL expansion — since the
	## parallel-derivation collapse it answers the panel's WHOLE dossier, not just
	## the fish question — and `ChartHarbourPlan.resolve_port_data` runs one again to
	## draw the harbour beside the panel. If the picker's expansion took different
	## inputs from the chart's, the screen holds two different harbours for one port
	## — the verdict from one, the silhouette from the other — and pays for both.
	## The cache keys on the layout checksum, so this is the property that the
	## `world_layout` argument was added (`c9abeda`) to buy, and it is still the only
	## measured consequence of that argument.
	##
	## RE-MEASURED ON THE NEW PUBLISHED SET, 2026-08-17, because the old measurement
	## was taken over the fields the summary published BEFORE the collapse and four
	## more now come off the world's PortData (`rotation_y`, `layout_seed`,
	## `site_max_size`, `export_slots`). Over the full base — six seeds x 35 ports,
	## `tests/_layout_arg_publish_probe.gd` — **not one published key moves** when the
	## layout is dropped, so the claim survives the change rather than being carried
	## forward on trust. What DOES move is the harbour underneath: 81 paths at 70 of
	## 70 ports, asserted below.
	t.check(
		"the preview really cached its expansions (%d entries) — a delta of zero"
			% cache_after_preview
		+ " against an empty cache would assert nothing",
		cache_after_preview > 0,
	)
	var cache_after_world: int = PortDataCache._cache.size()
	t.equal(
		"expanding all %d ports the way the chart draws them costs ZERO new"
			% live_definitions.size()
		+ " expansions — the panel's verdict and the harbour beside it are one"
		+ " PortData, not two",
		cache_after_world,
		cache_after_preview,
	)
	## And the reason that matters: without the layout it is not the same harbour.
	## Measured 2026-08-17 by diffing the whole serialized expansion — 81 paths move
	## at 70 of 70 ports, including every coast vertex, every module position and
	## which apron pad templates get laid. So a fish verdict taken from a
	## layout-less expansion is an answer about a harbour that does not exist; it
	## agrees today by coincidence, not by construction (REALITY §1).
	var coast_differs := 0
	var pads_differ := 0
	for index in range(live_definitions.size()):
		var source := (live_definitions[index] as PortDefinition).to_dict()
		var traced := PortExpander.expand_uncached(
			PortDefinition.from_dict(source), 90210, snapshot.layout)
		var synthetic := PortExpander.expand_uncached(
			PortDefinition.from_dict(source), 90210, null)
		if str(_coast_of(traced)) != str(_coast_of(synthetic)):
			coast_differs += 1
		if _pad_count_of(traced) != _pad_count_of(synthetic):
			pads_differ += 1
	t.equal(
		"an expansion without the world layout traces a DIFFERENT coast at every"
		+ " port — the layout is not decoration on this call",
		coast_differs,
		live_definitions.size(),
	)
	t.check(
		"and lays out a different number of apron pads at %d of %d ports — the"
			% [pads_differ, live_definitions.size()]
		+ " layout-less harbour is a different harbour, not a rescaled one",
		pads_differ > 0,
	)

	## ── the definition `chart_summary` promises not to touch ───────────────────
	##
	## ⚠ THIS CHECK EXISTS BECAUSE A BLIND MUTATION PASSED — 2026-08-17. Dropping
	## the `definition.size` restore in `PortExpander.summary_expansion` passed this
	## unit AND `port_fishing_service_test` first time, so it is recorded as a
	## finding and closed here.
	##
	## It was not a check that vanished; it was a question nobody asked (REALITY
	## §4b), and the collapse is what exposed it. `chart_summary` used to record
	## `port_definition` at the END of the call, AFTER the restore, so a broken
	## restore corrupted the recorded dict and the per-port placement check above
	## caught it by accident. It now records the definition at ENTRY, which is
	## strictly more correct — the recorded dict is the placed one whatever the
	## restore does — and that accidental coverage went with it. So the property
	## gets its own check: `expand_uncached` RESOLVES a definition in place (clamps
	## `size`, writes back `site_max_size`) and a caller who summarises a port must
	## get its definition back as it handed it over, because the world expands the
	## same object afterwards.
	##
	## THE CACHE IS THE TRAP HERE, AND IT TOOK A SECOND MUTATION TO SEE IT. The
	## first version of this check ran on the warm cache left by everything above,
	## so every `chart_summary` call was a `PortDataCache` HIT, `expand_uncached`
	## was never entered, and NOTHING RESOLVED THE DEFINITION AT ALL — the mutation
	## passed again, against a check written specifically for it. A cache hit cannot
	## corrupt a definition, so the property is only ever at risk on a MISS, and a
	## check for it has to force one. The cache is cleared below and the misses are
	## COUNTED, so a future change that makes these calls hit again reds this rather
	## than quietly emptying it.
	##
	## Floored twice over, because either floor alone is passable: every port must
	## really have expanded here, and an unrestored expansion must really have moved
	## something at some of them — at this seed and port count it resolves
	## `site_max_size` at 15 of 20 and `size` at 1 (`tests/_restore_witness_probe.gd`),
	## re-measured below rather than trusted from this sentence.
	PortDataCache.clear()
	var definition_touched: Array[String] = []
	var unrestored_would_move := 0
	var summary_expansions := 0
	for index in range(live_definitions.size()):
		var source := (live_definitions[index] as PortDefinition).to_dict()
		var handed_over := PortDefinition.from_dict(source)
		var cache_before: int = PortDataCache._cache.size()
		PortExpander.chart_summary(handed_over, 90210, snapshot.layout)
		if PortDataCache._cache.size() > cache_before:
			summary_expansions += 1
		if handed_over.to_dict() != source:
			definition_touched.append(str(source.get("port_id", index)))
		var unrestored := PortDefinition.from_dict(source)
		PortExpander.expand_uncached(unrestored, 90210, snapshot.layout)
		if unrestored.to_dict() != source:
			unrestored_would_move += 1
	t.check(
		"`chart_summary` hands every definition back exactly as it received it (%d"
			% definition_touched.size()
		+ " resolved in place: %s) — the expansion inside it clamps `size` and"
			% str(definition_touched)
		+ " writes back `site_max_size`, and the world expands the same object next",
		definition_touched.is_empty(),
	)
	t.equal(
		"and every one of those summaries really expanded rather than hitting the"
		+ " cache — a hit never touches the definition, so a warm cache makes the"
		+ " check above ask nothing at all, which is how this exact mutation passed"
		+ " twice",
		summary_expansions,
		live_definitions.size(),
	)
	t.check(
		"and the expansion really would have resolved %d of %d of them without the"
			% [unrestored_would_move, live_definitions.size()]
		+ " restore — otherwise the check above is agreeing about a definition"
		+ " nothing was going to touch",
		unrestored_would_move > 0,
	)

	var base = BaseClass.new()
	base.prepare(snapshot.layout)
	t.check("the base raster produces a texture", base.texture != null)
	t.check("the base raster builds in under 2 s", base.build_usec < 2000000)
	## Zoom tile path samples layout SDF only (no terrain meshes).
	base.prepare_visible(Rect2(-2500.0, -2500.0, 5000.0, 5000.0))
	t.check("the zoom tile produces a texture", base.texture != null)
	t.check(
		"the zoom tile covers less than the whole world",
		base.world_rect.size.x < float(snapshot.layout.world_size_m),
	)

	var weather = RasterClass.new(RasterClass.Kind.WEATHER)
	var bounds := Rect2(-20000.0, -20000.0, 40000.0, 40000.0)
	weather.prepare(snapshot, bounds, 0.0)
	t.check("the weather raster produces a texture", weather.texture != null)
	t.check("the weather raster builds in under 750 ms", int(weather.debug_stats()["build_usec"]) < 750000)

	var overlay = OverlayClass.new()
	root.add_child(overlay)
	overlay.set_data_snapshot(snapshot)
	overlay.enter_home_port_pick_mode()
	overlay.layers.set_visible("weather", true)
	overlay.layers.set_visible("fishing", true)
	overlay.renderer.prepare_overlays(bounds, overlay.layers, 0.0)
	var readout: Array[String] = overlay.renderer.overlay_readout(Vector2.ZERO, overlay.layers, 0.0)
	t.check("the readout carries a wind row", readout.any(func(row: String) -> bool: return row.begins_with("Wind")))
	t.check("the readout carries a fishing row", readout.any(func(row: String) -> bool: return row.begins_with("Fishing")))
	overlay.home_port_confirmed.connect(func(port_id: String) -> void: _picked = port_id)
	var first: Dictionary = snapshot.ports[0]
	var position := first["position"] as Vector3
	var chart := Rect2(0.0, 0.0, 1000.0, 1000.0)
	var context := {"chart_rect": chart, "world_bounds": bounds, "world_span": 40000.0}
	overlay.last_ctx = context
	var screen := chart.position + Vector2(
		(position.x - bounds.position.x) / bounds.size.x * chart.size.x,
		(position.z - bounds.position.y) / bounds.size.y * chart.size.y,
	)
	## Picking a home port is TWO steps, and has been since `d2a484d` moved the
	## emit out of `_click_chart` and behind the "SAIL FROM HERE" button. This
	## test kept asserting the one-step flow it was written against in `a0811ca`,
	## and a bare `assert()` swallowed the failure until the suite converted.
	## Assert both steps: a click selects and does NOT commit; confirming commits.
	overlay.call("_click_chart", screen)
	t.equal("clicking a port selects it", overlay.get_selected_port_id(), str(first["id"]))
	t.check("clicking alone does not commit the home port", _picked.is_empty())
	overlay.call("_confirm_home_port")
	t.check("confirming the selection commits the home port", _picked == str(first["id"]))
	print(
		"Marine chart rewrite integration/performance timings (base=%d us weather=%d us)"
		% [base.build_usec, int(weather.debug_stats()["build_usec"])]
	)


func _coast_of(data: PortData) -> Array:
	var area := data.layout_graph.initial_attributes.get("port_area", {}) as Dictionary
	return area.get("coast_polyline", []) as Array


func _pad_count_of(data: PortData) -> int:
	var land := data.layout_graph.initial_attributes.get("land_plan", {}) as Dictionary
	return int((land.get("apron_pads", {}) as Dictionary).get("pad_count", -1))
