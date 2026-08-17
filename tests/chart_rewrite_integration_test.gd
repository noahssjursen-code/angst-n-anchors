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


func _check_all(t: TestReport) -> void:
	var registry := root.get_node_or_null("PortCatalog")
	var registry_ids: Array = registry.call("get_port_ids") if registry != null else []
	var snapshot = SnapshotClass.for_preview(90210, 20)
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
		var world_flag := PortExpander.expand(
			live_definitions[index] as PortDefinition, 90210, snapshot.layout,
		).has_fish_landing
		var preview_flag := bool((snapshot.ports[index] as Dictionary).get("has_fish_landing", false))
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
