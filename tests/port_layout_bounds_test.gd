extends SceneTree

## `PortLayoutGraph.bounds()` MUST CONTAIN THE PORT.
##
## ── THE DEFECT THIS FILE EXISTS FOR ────────────────────────────────────────
##
## Trade quays moved out of `PortLayoutGraph.modules` and into
## `initial_attributes["berth_plan"]`. `modules` now holds exactly one entry,
## the coast root, which is correct and which `port_layout_brick_test:33`
## asserts on purpose. `bounds()` kept walking `module_ids()` plus the
## foundation spine, so **the piers were not in the loop** — the same stale read
## of an abandoned data model that made the capture rig photograph a size-4 port
## as one 8×10-pixel grey square (REALITY.md §3d), except this one is live in
## the running game. Measured before the fix, against the meshes the visualiser
## actually stamps:
##
##   | size | deck corners outside bounds() | worst overhang |
##   |------|-------------------------------|----------------|
##   | 0    | 2 of 4                        |  50.78 m       |
##   | 1–2  | 4 of 8                        |  93.30 / 130.05 m |
##   | 3–8  | 6 of 12                       | 192.23 – 226.75 m |
##
## Every metre of it seaward (−z), which is the direction a pier points.
##
## ── WHY THE CHECK LOOKS LIKE THIS AND NOT LIKE THE OBVIOUS ONE ─────────────
##
## The obvious check reads `berth_plan.quay_stations[].tip` and asks whether
## `bounds()` contains it. That is ONE DERIVATION TESTING ITSELF (REALITY.md
## §3b): `bounds()` reads the same field, so the check would pass for a
## `bounds()` that had merely copied the same wrong dictionary, and would keep
## passing if the plan and the drawing ever diverged.
##
## So the pier corners here come from the OTHER end of the pipeline — the
## `BerthTerminals/<station>/QuayPier/Deck` `MeshInstance3D` nodes that
## `PortLayoutGraphVisualizer._stamp_quay_pier_model` puts in the world, read
## through `global_transform * get_aabb()`. That is the pier a player walks on
## and a ship moors against. It is the same move `port_berth_plan_test` makes
## when it measures `|tip − origin| == length_m` rather than trusting one field,
## taken one layer further: past the plan, into what is drawn.
##
## Measured agreement between the two derivations, all 9 sizes / 21 decks:
## worst |drawn tip − plan tip| = 0.01 m. They agree TODAY; the point of the
## check is that nothing makes them agree tomorrow.
##
## ── LANE ───────────────────────────────────────────────────────────────────
##
## Lane A, `--script`. Nothing here names a bare autoload identifier; the
## visualiser instantiates and stamps fine under `--script` (verified — the
## `_port_layout_visual_capture` rig does the same in this lane). The autoload
## compile cascade in the log is noise (CONVENTIONS §1).
##
## ── WHAT THIS DOES NOT COVER, NAMED RATHER THAN IMPLIED ────────────────────
##
##   * `asphalt_stations`. `bounds()` was taught to include them too, but every
##     fixture here generates zero of them, so that branch is UNEXERCISED. Do
##     not read a green here as covering it.
##   * FJORD / ARCHIPELAGO region kinds. Both passes are MAINLAND.
##   * The Y extent. This is an XZ property; `bounds().size.y` is untested.
##   * `land_plan.apron_pads`. Not asserted here, but measured rather than
##     assumed (`tests/_port_stale_reader_probe.gd`, 18 ports, 1–5 pads each):
##     **0 pad corners fall outside `bounds()`** — they sit landward of the dock
##     face, inside the foundation spine envelope the old walk already covered.
##     So the pads were never part of this defect.

const TestReport := preload("res://tests/support/test_report.gd")
const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")

const SEED := 424242
## Slack for float round-trips through a Transform3D and an AABB, nothing more.
## The pre-fix overhang was 50–227 m, so this cannot hide the defect: measured
## worst residual after the fix is 0.01 m.
const CONTAINMENT_EPSILON_M := 0.05

## ── THE SIZE LADDER IS A DISCOVERED POPULATION (REALITY.md §4f) ─────────────
##
## Every check in `_sweep` lives inside `for size in range(PortSizing.MAX_SIZE +
## 1)`, so this file's coverage is a function of a CONSTANT IN PRODUCTION
## SOURCE. Shrink the ladder and the checks do not fail — they stop existing.
##
## MEASURED 2026-08-17, not inferred: `PortSizing.MAX_SIZE` 8 → 7 took this unit
## from **73 checks to 65, PASS both times**. §4f's "a discovered population is
## not always a data file", third instance after `ship_hud_readout_test`'s regex
## scan and `port_apron_draw_test`'s `const` table.
##
## AND THE FLOOR THIS FILE ALREADY HAD COULD NOT HAVE CAUGHT IT — worse, it was
## never able to. `total_decks >= (PortSizing.MAX_SIZE + 1) * 2` is computed
## FROM THE CONSTANT THAT DEFINES THE POPULATION, so shrinking the ladder
## shrinks the floor by exactly as much and the comparison is unmoved. That is
## not the ordinary "a floor catches empty, not smaller" finding: a floor
## derived from its own population is a TAUTOLOGY and asserts nothing at any
## size. Both halves are fixed below — the ladder is declared and compared
## member by member, and the floor is anchored to the DECLARED count.
##
## Compared, not iterated in place of the real range. The sweep still walks
## `PortSizing.MAX_SIZE` so that a ladder which GROWS is exercised at its new
## top; this literal only says which rungs must be there.
const EXPECTED_SIZES := [0, 1, 2, 3, 4, 5, 6, 7, 8]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("port_layout_bounds_test")
	PortModuleCatalog.clear_cache()
	var world := Node3D.new()
	root.add_child(world)

	_check_the_size_ladder_is_intact(t)

	var total_decks := 0
	## Pass 1 open water; pass 2 the terrain-traced site, where the basin probe
	## shortens arms and the comb spacing compresses — the only branch that can
	## move a pier tip after it is first placed.
	for pass_variant in [
		{"label": "open", "layout": null},
		{"label": "terrain", "layout": WORLD_LAYOUT_GENERATOR.generate(SEED)},
	]:
		var context := pass_variant as Dictionary
		total_decks += await _sweep(t, world, str(context["label"]), context["layout"])

	## Anchored to EXPECTED_SIZES, not to `PortSizing.MAX_SIZE`. Against the
	## constant it was measuring, this floor moved with the population and could
	## not fire at any value — see EXPECTED_SIZES' header.
	t.check(
		"every one of the %d declared sizes in both passes contributed a drawn"
			% EXPECTED_SIZES.size()
			+ " pier deck to measure (%d decks)" % total_decks,
		total_decks >= EXPECTED_SIZES.size() * 2,
	)
	t.finish(self)


## The declared ladder against the one the sweep will actually walk. A rung that
## disappears from `PortSizing` is NAMED here; without this it only subtracts
## eight checks from a still-green verdict (REALITY.md §4f, shape 1).
func _check_the_size_ladder_is_intact(t) -> void:
	var swept := PackedInt32Array()
	for size in range(PortSizing.MAX_SIZE + 1):
		swept.append(size)
	for declared_raw in EXPECTED_SIZES:
		var declared := int(declared_raw)
		t.check(
			"port size class %d is still on PortSizing's ladder, so the four"
				% declared
				+ " checks this file runs at that size still run (MAX_SIZE=%d,"
				% PortSizing.MAX_SIZE
				+ " sweeping %d sizes)" % swept.size(),
			swept.has(declared),
		)
	var undeclared := PackedInt32Array()
	for size in swept:
		if not EXPECTED_SIZES.has(int(size)):
			undeclared.append(int(size))
	t.check(
		"no size class is swept that EXPECTED_SIZES does not name, so a new rung"
		+ " arrives with its coverage declared rather than silently unwalked"
		+ " (%d undeclared)" % undeclared.size(),
		undeclared.is_empty(),
	)


func _sweep(t, world: Node3D, label: String, layout: Variant) -> int:
	var total := 0
	for size in range(PortSizing.MAX_SIZE + 1):
		var definition := PortDefinition.new()
		definition.port_id = "%s-bounds-%d" % [label, size]
		definition.display_name = "SIZE %d" % size
		definition.size = size
		definition.region_kind = PortDefinition.RegionKind.MAINLAND
		definition.site_seed = SEED ^ (size * 9973)
		definition.has_lighthouse = size >= 2
		definition.has_fog_horn = size >= 1
		definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
		definition.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND
		var graph := PortExpander.expand(
			definition, SEED, layout as WorldLayout
		).layout_graph
		if graph == null:
			t.fail("%s size %d: expand returned no layout graph" % [label, size])
			continue

		var visualizer := PortLayoutGraphVisualizer.new()
		world.add_child(visualizer)
		visualizer.configure(graph)
		await process_frame
		var decks: Array = []
		var terminals := visualizer.find_child("BerthTerminals", true, false)
		if terminals != null:
			_collect_drawn_decks(terminals, decks)

		## Zero drawn decks would make every containment check below vacuous
		## (REALITY.md §4, "negatives against an empty universe").
		if not t.check(
				"%s size %d: the visualiser draws at least one pier deck to measure" % [label, size],
				not decks.is_empty()):
			visualizer.queue_free()
			await process_frame
			continue
		total += decks.size()

		var box := graph.bounds()
		var lo := Vector2(box.position.x, box.position.z)
		var hi := Vector2(box.position.x + box.size.x, box.position.z + box.size.z)
		var worst := 0.0
		var worst_id := ""
		for deck in decks:
			for raw_corner in deck["corners"]:
				var corner := raw_corner as Vector2
				var out_m := maxf(
					maxf(maxf(lo.x - corner.x, corner.x - hi.x), 0.0),
					maxf(maxf(lo.y - corner.y, corner.y - hi.y), 0.0),
				)
				if out_m > worst:
					worst = out_m
					worst_id = str(deck["name"])
		t.check(
			"%s size %d: bounds() x[%.1f..%.1f] z[%.1f..%.1f] contains all %d corners of the %d pier decks the game draws (worst outside: %.2f m%s)"
				% [label, size, lo.x, hi.x, lo.y, hi.y, decks.size() * 4, decks.size(), worst,
					"" if worst_id.is_empty() else " on " + worst_id],
			worst <= CONTAINMENT_EPSILON_M,
		)

		## The tip specifically — the far end of the run, which is what the old
		## walk lost and what a shortened box costs a chart or a plot.
		var tip_worst := 0.0
		for deck in decks:
			var tip := deck["tip"] as Vector2
			tip_worst = maxf(tip_worst, maxf(
				maxf(maxf(lo.x - tip.x, tip.x - hi.x), 0.0),
				maxf(maxf(lo.y - tip.y, tip.y - hi.y), 0.0),
			))
		t.check(
			"%s size %d: every drawn pier's seaward TIP is inside bounds() (worst outside %.2f m)"
				% [label, size, tip_worst],
			tip_worst <= CONTAINMENT_EPSILON_M,
		)

		## And bounds() must not be so loose that containment is free: it may
		## not exceed the drawn+foundation envelope by more than the foundation
		## reach itself. Without this, `AABB(-1e9, 2e9)` passes everything above.
		t.check(
			"%s size %d: bounds() is finite and no wider than 4 km (%.1f x %.1f m)"
				% [label, size, box.size.x, box.size.z],
			box.size.x > 1.0 and box.size.z > 1.0
				and box.size.x < 4000.0 and box.size.z < 4000.0,
		)

		visualizer.queue_free()
		await process_frame
	return total


## Every `QuayPier/Deck` MeshInstance3D under the stamped berth terminals, as
## world-space XZ quads. This is the pier as drawn — no berth-plan dictionary is
## consulted anywhere in this function.
func _collect_drawn_decks(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.name == "Deck" \
			and node.get_parent() != null and node.get_parent().name == "QuayPier":
		var mesh_node := node as MeshInstance3D
		var local_box := mesh_node.get_aabb()
		var xf := mesh_node.global_transform
		var centre_local := local_box.get_center()
		var half := Vector3(local_box.size.x, 0.0, local_box.size.z) * 0.5
		var corners: Array = []
		for raw_offset in [
			Vector3(-half.x, 0.0, -half.z),
			Vector3(half.x, 0.0, -half.z),
			Vector3(half.x, 0.0, half.z),
			Vector3(-half.x, 0.0, half.z),
		]:
			var world := xf * (centre_local + (raw_offset as Vector3))
			corners.append(Vector2(world.x, world.z))
		## Local +Z runs shore → tip (`_align_node_seaward`), so the seaward tip
		## is the +Z face centre. Landward end is the shore root.
		var centre_world := xf * centre_local
		var axis := (xf.basis * Vector3(0.0, 0.0, 1.0)).normalized()
		out.append({
			"name": str(mesh_node.get_parent().get_parent().name),
			"corners": corners,
			"tip": Vector2(centre_world.x, centre_world.z)
					+ Vector2(axis.x, axis.z) * (local_box.size.z * 0.5),
		})
	for child in node.get_children():
		_collect_drawn_decks(child, out)
