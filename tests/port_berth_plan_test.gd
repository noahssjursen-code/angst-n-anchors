extends SceneTree

## THE QUAY GEOMETRY A PORT ACTUALLY GENERATES — the seam `port_layout_brick_test`
## points at and does not cover. Its own header reads *"Trade berths live in
## berth_plan attrs"*, and until this file there was no check on the other side of
## that sentence (REALITY.md §3c: find the check for every guarantee a header makes).
##
## WHY IT MATTERS MORE THAN IT LOOKS. The port pipeline moved its quays out of
## `PortLayoutGraph.modules` and into `initial_attributes["berth_plan"]`.
## `port_layout_brick_test` asserts the module side — `modules.size() == 1`, the
## coast root, which is correct and current. Nothing asserted the side that now
## carries every berth. Measured consequence, found 2026-08-16:
## `tests/port_layout_visual_capture.gd` still drew its top-down map from
## `graph.modules`, so a size-4 port photographed as one 8-pixel square on an
## empty field, and that had been true for nine port generations without anyone
## seeing it, because the unit declared no verdict and wrote its frames into
## `user://` and `res://.godot/` — both outside git.
##
## THE FIVE PROPERTIES, and why each is a property and not a restated number
## (REALITY.md §4a). Every one was measured over sizes 0..8 in
## `tests/_port_berth_geometry_probe.gd` BEFORE it was asserted here.
##
##   1. A port of any size has somewhere to berth. The lowest bar there is, and
##      the one that catches "the plan silently produced nothing".
##   2. ONE DERIVATION (REALITY.md §3b). A station reports `length_m`, and it
##      also reports `origin` and `tip`, from which every drawing and every
##      spacing check measures the pier. Those are two derivations of one pier.
##      `port_berth_plan.gd` computes `tip = origin + seaward * length_m` as its
##      last act, so they agree today; move one line above another and the pier
##      a captain berths against stops being the pier on the chart. This repo has
##      fixed that exact class three times (DeckFitout yaw, the bulwark cap, the
##      railing barrier).
##   3. A pier has width. `quay_deck_width_for_arm_m` can be handed a degenerate
##      arm; a zero-width deck is a berth you cannot stand on and draws as nothing.
##   4. `primary_quay_pose()` is documented as the PRIMARY quay and is what
##      `PortExpander` hands the mooring code. The property is "it is the longest
##      one", not "it equals 240 m".
##   5. NO TWO PIER DECKS OVERLAP. `port_berth_plan.gd` says *"Ideal fairway
##      spacing; compress only enough to fit every family without overlap"* — so
##      not-overlapping is the stated contract and the fairway figure is the
##      ideal it compresses away from. Asserting the gap equals
##      `parallel_pier_center_spacing_m` would restate the ideal and go red on
##      correct, deliberately compressed layouts: `port_layout_visual_capture`
##      did exactly that and printed the phantom "parallel pier gap 138m <
##      required 175m fairway" on five of nine sizes. The overlap test is
##      computed by separating axis on the decks AS DRAWN, which is the same move
##      that fixed the railing barrier — measure the boxes, do not re-derive them.
##
## Lane A. Runs under `--script`; the autoload compile cascade is noise here
## (CONVENTIONS §1) — nothing in this file names a bare autoload identifier.

## ── WHAT THE FIXTURES DO NOT CONTAIN, AND WHAT WAS DONE ABOUT IT ───────────
##
## The first pass expands nine synthetic ports with NO `WorldLayout`. That means
## `soft_cap` is false in `port_berth_plan.gd`, `basin.max_arm_m` comes back
## `INF`, and the arm-shortening / spacing-compression branch — **the only branch
## that can push two piers together** — is never taken. A no-overlap check that
## has never seen the code capable of causing an overlap is a check pointed at
## the safe path (REALITY.md §3). Measured in `tests/_port_terrain_sweep_probe.gd`
## and then added here as a SECOND pass over the terrain-traced site
## `port_layout_brick_test` uses: `max_arm_m` is finite (156–204 m), `soft_cap`
## is true, the compression runs, and every property still holds.
##
## Still not covered, named rather than implied: FJORD and ARCHIPELAGO region
## kinds (both passes are MAINLAND), `probe_failed` basins, and `asphalt_stations`
## — the plan's other station list, empty on every fixture here.

const TestReport := preload("res://tests/support/test_report.gd")
const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")

const SEED := 424242
## Tip and length are the same float arithmetic one line apart, so this is a
## float-equality tolerance, not a modelling slack. Measured worst delta across
## all 9 sizes and 21 stations: 4e-5 m.
const DERIVATION_EPSILON_M := 0.005


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("port_berth_plan_test")
	PortModuleCatalog.clear_cache()

	var total_stations := 0
	## Pass 1 open water (max_arm_m INF, no compression); pass 2 the terrain-traced
	## site, where the basin probe shortens arms and the comb spacing compresses.
	var passes := [
		{"label": "open", "layout": null},
		{"label": "terrain", "layout": WORLD_LAYOUT_GENERATOR.generate(SEED)},
	]
	for pass_variant in passes:
		var context := pass_variant as Dictionary
		total_stations += _sweep(t, str(context["label"]), context["layout"])

	t.check("every size in both passes contributed a station to measure (%d)" % total_stations,
		total_stations >= (PortSizing.MAX_SIZE + 1) * 2)
	t.finish(self)


func _sweep(t, label: String, layout: Variant) -> int:
	var total_stations := 0
	for size in range(PortSizing.MAX_SIZE + 1):
		var graph := _expand(size, label, layout)
		if graph == null:
			t.fail("%s size %d: expand returned no layout graph" % [label, size])
			continue
		var plan := graph.initial_attributes.get("berth_plan", {}) as Dictionary
		var stations: Array = plan.get("quay_stations", []) as Array

		## 1. Somewhere to berth.
		if not t.check("%s size %d: the berth plan places at least one quay station" % [label, size],
				not stations.is_empty()):
			continue

		var decks: Array = []
		var longest := 0.0
		for raw in stations:
			var station := raw as Dictionary
			var id := str(station.get("id", "<unnamed>"))
			var origin := _point(station.get("origin", []))
			var tip := _point(station.get("tip", []))
			var length_m := float(station.get("length_m", 0.0))
			var width_m := float(station.get("width_m", 0.0))
			total_stations += 1
			longest = maxf(longest, length_m)

			## 2. One derivation: the drawn run IS the berthing length.
			var drawn := origin.distance_to(tip)
			t.check(
				"%s size %d %s: the pier as drawn (%.3f m origin→tip) is the length it reports (%.3f m)"
					% [label, size, id, drawn, length_m],
				absf(drawn - length_m) <= DERIVATION_EPSILON_M,
			)
			## 3. A berth you can stand on.
			t.check("%s size %d %s: quay deck width is positive (%.2f m)" % [label, size, id, width_m],
				width_m > 0.0)
			decks.append({"id": id, "origin": origin, "tip": tip, "width_m": width_m})

		## 4. "Primary" means the longest, not a number.
		var pose_length := float(graph.primary_quay_pose().get("length_m", 0.0))
		t.check(
			"%s size %d: primary_quay_pose is the longest station (%.3f m of %.3f m)"
				% [label, size, pose_length, longest],
			absf(pose_length - longest) <= DERIVATION_EPSILON_M,
		)

		## 5. The decks the map draws do not lie on top of each other.
		for i in range(decks.size()):
			for j in range(i + 1, decks.size()):
				var a := decks[i] as Dictionary
				var b := decks[j] as Dictionary
				var penetration := _deck_overlap_m(a, b)
				t.check(
					"%s size %d: %s and %s do not share deck area (%.3f m penetration)"
						% [label, size, str(a["id"]), str(b["id"]), penetration],
					penetration <= 0.0,
				)

	return total_stations


func _expand(size: int, label: String, layout: Variant) -> PortLayoutGraph:
	var definition := PortDefinition.new()
	definition.port_id = "berth-plan-%s-%d" % [label, size]
	definition.display_name = "SIZE %d" % size
	definition.size = size
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.site_seed = SEED ^ (size * 9973)
	definition.has_lighthouse = size >= 2
	definition.has_fog_horn = size >= 1
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	definition.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND
	if layout != null:
		## The terrain-traced site `port_layout_brick_test` uses, so the basin
		## probe finds real water and the arm budget is finite.
		definition.world_position = Vector3(12000.0, 0.0, -8000.0)
		definition.rotation_y = 0.4
		definition.has_explicit_rotation = true
	var data := PortExpander.expand(definition, SEED, layout)
	return data.layout_graph if data != null else null


func _point(raw: Variant) -> Vector2:
	var arr := raw as Array
	if arr == null or arr.size() < 2:
		return Vector2.ZERO
	return Vector2(float(arr[0]), float(arr[1]))


## The four corners of a pier deck as the map draws it: the origin→tip run,
## `width_m` across. Derived from the same three fields a renderer reads, so a
## deck that draws wrong fails here too.
func _deck_corners(deck: Dictionary) -> Array:
	var origin := deck["origin"] as Vector2
	var tip := deck["tip"] as Vector2
	var axis := tip - origin
	if axis.length() < 0.0001:
		axis = Vector2(0.0, 1.0)
	axis = axis.normalized()
	var across := Vector2(-axis.y, axis.x) * (float(deck["width_m"]) * 0.5)
	return [origin - across, origin + across, tip + across, tip - across]


## Separating-axis penetration depth in metres between two pier decks; 0.0 when
## a separating axis exists, i.e. when they are disjoint.
func _deck_overlap_m(a: Dictionary, b: Dictionary) -> float:
	var quad_a := _deck_corners(a)
	var quad_b := _deck_corners(b)
	var least := INF
	for quad in [quad_a, quad_b]:
		for i in range(4):
			var p1 := quad[i] as Vector2
			var p2 := quad[(i + 1) % 4] as Vector2
			var normal := Vector2(-(p2.y - p1.y), p2.x - p1.x)
			if normal.length() < 0.0001:
				continue
			normal = normal.normalized()
			var a_lo := INF
			var a_hi := -INF
			for corner in quad_a:
				var proj := normal.dot(corner as Vector2)
				a_lo = minf(a_lo, proj)
				a_hi = maxf(a_hi, proj)
			var b_lo := INF
			var b_hi := -INF
			for corner_b in quad_b:
				var proj_b := normal.dot(corner_b as Vector2)
				b_lo = minf(b_lo, proj_b)
				b_hi = maxf(b_hi, proj_b)
			var gap := minf(a_hi, b_hi) - maxf(a_lo, b_lo)
			if gap <= 0.0:
				return 0.0
			least = minf(least, gap)
	return 0.0 if least == INF else least
