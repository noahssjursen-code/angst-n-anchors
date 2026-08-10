extends SceneTree

## THE SHEER BAND — the primitive that decides whether a hull reads as a vessel.
##
## Run (SceneTree lane — StructureEdge, StructureBaker, HullStations,
## HullFormProfile and HullCatalog are all `class_name` scripts with no autoload
## dependency; nothing here names a vessel script, because BoatBody's dependency
## chain reaches autoload identifiers and `--script` registers none):
##
##   timeout 300 xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/structure_sheer_test.gd
##
## ── What this file is for ───────────────────────────────────────────────────
## The complaint was a picture: squinted, the vessel is two parallel horizontal
## bars. The deck edge runs dead straight from stem to transom and the bulwark
## above it is a constant-height band the full length. A working boat reads by
## its SHEER — the deck edge sweeping up toward the bow — and nothing in this
## project could draw that curve.
##
## Whether the fix reads is judged by LOOKING, at
## screenshots/studio/probe_sheer_bulwark__*.png against
## screenshots/studio/probe_sheer_bulwark_flat__*.png. There is deliberately no
## silhouette metric here: one was written and binned two hours ago because it
## passed all three vessels the owner had just called unrecognisable.
##
## What IS asserted here is everything a picture cannot show:
##   • the curve is DERIVED per hull from catalog fields, on seven hulls, and is
##     not a number anybody typed;
##   • the drawn band actually carries it, and the control actually does not;
##   • the band is solid from the deck to its cap — no slot to see the sea
##     through, and no plating breaking back out through the cap;
##   • nothing it emits enters the deck plate, which is the constraint that
##     stopped the loft from carrying sheer in the first place;
##   • its COLLISION is the geometry it drew, and a body is stopped at the bow
##     by 2.0 m of bulwark and not stopped amidships by 1.16 m of it — which is
##     the collider carrying the curve, not just the mesh;
##   • it costs no draw call.
##
## MUTATION-VERIFIED. Every check below was watched going RED against a
## deliberately broken StructureEdge; the mutants and both numbers are in the
## wave report. A check that has never failed measures nothing.

const TestReport := preload("res://tests/support/test_report.gd")

const FIXTURE := "res://resources/data/structures/probe_sheer_bulwark.json"
const CONTROL := "res://resources/data/structures/probe_sheer_bulwark_flat.json"

## A person, for the marches. Matches scenes/shared/player.tscn (1.8 m overall,
## CapsuleShape3D height is the FULL height in Godot 4).
const CAPSULE_RADIUS := 0.3
const CAPSULE_HEIGHT := 1.8
const MARCH_STEP := 0.05

var _t: RefCounted
var _fixture: Dictionary = {}
var _control: Dictionary = {}
var _stations: HullStations
var _spec: Dictionary = {}
var _boxes: Array = []
var _colliders: Array = []
var _body: StaticBody3D
var _space: PhysicsDirectSpaceState3D
var _camera: Camera3D
var _draw_baseline := 0


func _initialize() -> void:
	_t = TestReport.new("structure_sheer_test")
	if not _load():
		_t.finish(self)
		return

	_test_curve_is_derived_not_authored()
	_test_the_band_carries_the_curve()
	_test_the_control_is_the_bar()
	_test_no_slot_and_no_breakout()
	_test_nothing_enters_the_deck()
	_test_colliders_are_the_drawing()
	_test_trim_does_not_collide()
	await _test_a_body_is_stopped_by_it()
	await _test_it_costs_no_draw_call()

	print("---")
	_report_costs()
	_t.finish(self)


# ── Loading ─────────────────────────────────────────────────────────────────

func _load() -> bool:
	_fixture = _read(FIXTURE)
	_control = _read(CONTROL)
	if not _t.check("both fixtures parse", not _fixture.is_empty() and not _control.is_empty()):
		return false
	_t.check("the fixture is a structure plan", StructurePlan.is_plan(_fixture))
	_t.check(
		"the fixture is a hull and a bulwark and NOTHING else "
		+ "(%d walls, %d decks, %d stairs, %d items, %d edges)"
		% [
			(_fixture.get("walls", []) as Array).size(),
			(_fixture.get("decks", []) as Array).size(),
			(_fixture.get("stairs", []) as Array).size(),
			(_fixture.get("items", []) as Array).size(),
			(_fixture.get("edges", []) as Array).size(),
		],
		(_fixture.get("walls", []) as Array).is_empty()
		and (_fixture.get("decks", []) as Array).is_empty()
		and (_fixture.get("stairs", []) as Array).is_empty()
		and (_fixture.get("items", []) as Array).is_empty()
		and (_fixture.get("edges", []) as Array).size() == 1
	)

	_stations = _hull_of(_fixture)
	if not _t.check("the fixture's hull builds", _stations != null and not _stations.stations.is_empty()):
		return false
	_spec = StructureEdge.sheer_bulwark_spec(_stations, _edge_of(_fixture))
	_boxes = StructureEdge.sheer_band_boxes(_spec)
	_colliders = StructureEdge.sweep_collider_boxes(_spec)
	return _t.check("the bulwark emits geometry (%d boxes)" % _boxes.size(), _boxes.size() > 0)


func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_t.fail("cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_t.fail("%s is not a JSON object" % path)
		return {}
	return parsed as Dictionary


func _edge_of(plan: Dictionary) -> Dictionary:
	var edges := plan.get("edges", []) as Array
	return (edges[0] as Dictionary) if not edges.is_empty() else {}


## HullStations from a fixture's own `hull` block. Same shape as
## `structure_edge_test._hull`, and for the same reason: the SceneTree lane
## cannot name a vessel script.
func _hull_of(plan: Dictionary) -> HullStations:
	var cfg := plan.get("hull", {}) as Dictionary
	if cfg.is_empty():
		return null
	return HullStations.from_form(
		float(cfg["loa_m"]),
		float(cfg["beam_m"]),
		float(cfg["depth_m"]),
		float(cfg["draft_m"]),
		float(cfg["displacement_t"]),
		HullFormProfile.resolve(str(cfg.get("form", "fine_entry"))),
		1025.0,
		float(cfg["loa_m"]) * float(cfg.get("bow_taper_fraction", 0.0)),
		int(cfg.get("station_count", 12)),
	)


# ── 1. The curve is derived, on every hull, from catalog fields ─────────────

## "Six hulls, and a magic number per hull is not a solution."
##
## For every hull in the catalog plus the fixture's own, this recomputes the
## expected sheer INDEPENDENTLY — freeboard x the form preset's own
## bow_keel_rise, straight out of HullFormProfile and the hull catalog, never
## through HullStations — and then measures the rise of the band that is
## actually DRAWN. If the two agree on seven hulls with seven different answers,
## the curve is a rule and not a table of tuned numbers.
##
## Three distinct answers are demanded as well, because a constant would satisfy
## "drawn == expected" on any single hull and this check would still pass.
func _test_curve_is_derived_not_authored() -> void:
	var hulls: Array = [{"id": "hull_28x10", "stations": _stations, "form": "fine_entry",
		"depth": 5.6, "draft": 2.8}]
	HullCatalog.ensure_loaded()
	for id in HullCatalog.all_ids():
		var cfg := HullCatalog.get_by_id(str(id))
		if cfg.is_empty():
			continue
		var depth := float(cfg.get("depth_m", 0.0))
		var draft := float(cfg.get("draft_m", depth * 0.5))
		var loa := float(cfg.get("loa_m", 0.0))
		var beam := float(cfg.get("beam_m", 0.0))
		hulls.append({
			"id": str(id),
			"form": str(cfg.get("form", HullFormProfile.DEFAULT_ID)),
			"depth": depth,
			"draft": draft,
			"stations": HullStations.from_form(
				loa, beam, depth, draft,
				## Displacement sets the underwater widths and has no bearing on
				## sheer, which is a function of freeboard and form alone. The
				## catalog omits it; CatalogHullVessel's own fallback is used so
				## nothing here invents a hull the game does not build.
				float(cfg.get("displacement_t", loa * beam * draft * 0.52)),
				HullFormProfile.resolve(str(cfg.get("form", HullFormProfile.DEFAULT_ID))),
				1025.0,
				float(cfg.get("bow_taper_m", beam * 0.5)),
				clampi(int(round(loa / 8.0)), 8, 16),
			),
		})
	_t.check("seven hulls to check the rule against (%d)" % hulls.size(), hulls.size() >= 7)

	var seen: Dictionary = {}
	var worst := 0.0
	var worst_id := ""
	print("derived sheer, per hull — expected is recomputed from HullFormProfile, not read back")
	for entry_variant in hulls:
		var entry := entry_variant as Dictionary
		var stations := entry["stations"] as HullStations
		var form := HullFormProfile.resolve(str(entry["form"]))
		var freeboard: float = maxf(float(entry["depth"]) - float(entry["draft"]), 0.0)
		var expected: float = freeboard * float(form["bow_keel_rise"])
		var boxes := StructureEdge.sheer_band_boxes(
			StructureEdge.sheer_bulwark_spec(stations, {"side": "starboard"})
		)
		var drawn := _drawn_rise(boxes, 1.0)
		seen["%.4f" % expected] = true
		var error := absf(drawn - expected)
		if error > worst:
			worst = error
			worst_id = str(entry["id"])
		print("  %-12s freeboard %5.2f x %s %.2f = %.3f m   drawn %.3f m   (%d boxes)" % [
			str(entry["id"]), freeboard, str(entry["form"]),
			float(form["bow_keel_rise"]), expected, drawn, boxes.size(),
		])
	## The tolerance is the sampling step, not a fudge. A swept band is drawn as
	## boxes, and a box's top is a chord of the curve, so the measured rise can
	## differ from the ideal by at most one segment's rise — which is exactly the
	## bound `sheer_samples_for` solves the sample count against, and it is 40 mm
	## on a 60 mm cap. Anything wider than that is not discretisation.
	var step := StructureEdge.DEFAULT_CAP_THICKNESS_M * 2.0 / 3.0
	_t.check(
		"every hull's DRAWN sheer is freeboard x its form's bow_keel_rise "
		+ "(worst error %.4f m on %s, one sample step is %.3f m)" % [worst, worst_id, step],
		worst <= step,
	)
	_t.check(
		"...and the answers differ per hull, so it cannot be a constant (%d distinct)" % seen.size(),
		seen.size() >= 3,
	)


## Rise of the band that was drawn: how far its TOP EDGE moves between the
## highest station and the lowest. Measured off the emitted geometry, never off
## the spec that asked for it.
##
## Sampled along the run rather than taken as (max box top − min box top): the
## band is two rects, the plating and the cap, and the plating's top is 40 mm
## below the cap's by construction. Differencing raw box tops therefore reports
## 40 mm of "sheer" on a hull with none, which is how the control fixture caught
## the first version of this helper.
func _drawn_rise(boxes: Array, side: float = -1.0) -> float:
	var bounds := StructureEdge.boxes_aabb(boxes)
	var high := -INF
	var low := INF
	for i in 61:
		var z := lerpf(bounds.position.z + 0.4, bounds.end.z - 0.4, float(i) / 60.0)
		var top := _top_at_z(boxes, z, side)
		if is_inf(top):
			continue
		high = maxf(high, top)
		low = minf(low, top)
	return high - low if high > -INF and low < INF else 0.0


func _top_of(box: Dictionary) -> float:
	var centre := box["center"] as Vector3
	var half := (box["size"] as Vector3) * 0.5
	var basis := box.get("basis", Basis.IDENTITY) as Basis
	var reach := (
		absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z
	)
	return centre.y + reach


# ── 2. The band carries the curve ───────────────────────────────────────────

## The silhouette claim, made about geometry rather than about pixels: the top
## of the drawn band at ship-local z is deck_y + height + sheer_rise_at(z) +
## the cap's own thickness, everywhere along the run.
func _test_the_band_carries_the_curve() -> void:
	var height := float(_edge_of(_fixture).get("height", StructureEdge.DEFAULT_BULWARK_HEIGHT))
	var cap_h := float(_edge_of(_fixture).get("cap_h", StructureEdge.DEFAULT_CAP_THICKNESS_M))
	## Two-sided, and the two sides mean different things. The drawn cap may
	## never fall BELOW the hull's curve — that would be a band stopping short of
	## the sheer it is supposed to be. Above it, the bound is the cap's own
	## thickness: a box top is a chord of a curve and every box takes its height
	## at its higher end on purpose (see check 4), so the drawn top runs a little
	## proud, and the claim worth making is that the IDEAL CURVE NEVER LEAVES THE
	## BAND THAT WAS DRAWN. Measured 0.044 m of a 0.060 m cap — one sample step
	## (0.040) plus the mitre's own overshoot at the sharpest turn on the run.
	var over := -INF
	var under := INF
	var samples := 0
	for i in 57:
		var z := lerpf(-13.5, 13.5, float(i) / 56.0)
		var drawn := _top_at_z(_boxes, z)
		if is_inf(drawn):
			continue
		samples += 1
		var error := drawn - (_stations.sheer_cap_y_at(z) + height + cap_h)
		over = maxf(over, error)
		under = minf(under, error)
	_t.check("the run was sampled along its length (%d stations)" % samples, samples >= 50)
	_t.check(
		"the drawn cap never falls below deck_y + sheer_rise_at(z) + %.2f "
		% (height + cap_h) + "(worst shortfall %.4f m)" % minf(under, 0.0),
		under >= -1e-6,
	)
	_t.check(
		"...and the ideal curve never leaves the drawn cap band (%.4f m proud of a %.3f m cap)"
		% [over, cap_h],
		over <= cap_h,
	)

	var stem := _top_at_z(_boxes, -13.8)
	var mid := _top_at_z(_boxes, 0.0)
	var transom := _top_at_z(_boxes, 13.8)
	print("[sheer] cap above the deck: stem %.3f m, amidships %.3f m, transom %.3f m" % [
		stem - _stations.deck_y, mid - _stations.deck_y, transom - _stations.deck_y,
	])
	_t.check(
		"the cap is highest at the stem and lowest amidships (%.3f > %.3f < %.3f)"
		% [stem, mid, transom],
		stem > mid and transom > mid,
	)
	## The number that decides whether it reads: how much the top edge moves.
	## 0.896 m over a 28 m hull is the Load Line Convention's own order of
	## magnitude (its standard forward sheer for 28 m is 0.966 m).
	_t.check(
		"the top edge sweeps %.3f m over the length — a curve, not a line"
		% (stem - mid),
		stem - mid > _stations.sheer_forward_m * 0.9,
	)


## Top of the drawn band at ship-local z, on the port side. Reads the emitted
## boxes: a box counts when the sample plane falls inside its own Z span.
func _top_at_z(boxes: Array, z: float, side: float = -1.0) -> float:
	var best := -INF
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var centre := box["center"] as Vector3
		if signf(centre.x) != signf(side) and absf(centre.x) > 0.5:
			continue
		var half := (box["size"] as Vector3) * 0.5
		var basis := box.get("basis", Basis.IDENTITY) as Basis
		var span := (
			absf(basis.x.z) * half.x + absf(basis.y.z) * half.y + absf(basis.z.z) * half.z
		)
		if absf(centre.z - z) > span:
			continue
		best = maxf(best, _top_of(box))
	return best


# ── 3. The control really is the bar ────────────────────────────────────────

## A test that only ever sees the good case cannot tell you the check works.
## The control fixture differs by one boolean and must produce the flat band —
## if it does not, `follow_sheer` is not doing anything and check 2 above is
## passing for a reason nobody understands.
func _test_the_control_is_the_bar() -> void:
	var control_stations := _hull_of(_control)
	if not _t.check("the control's hull builds", control_stations != null):
		return
	var control_boxes := StructureEdge.sheer_band_boxes(
		StructureEdge.sheer_bulwark_spec(control_stations, _edge_of(_control))
	)
	var flat_rise := _drawn_rise(control_boxes)
	var sheer_rise := _drawn_rise(_boxes)
	var stem_flat := _top_at_z(control_boxes, -13.8) - _top_at_z(control_boxes, 0.0)
	print("[control] follow_sheer false: top edge moves %.4f m; true: %.4f m" % [
		flat_rise, sheer_rise,
	])
	_t.check(
		"the control's top edge is DEAD FLAT (%.6f m of movement, stem-to-mid %.6f m)"
		% [flat_rise, stem_flat],
		flat_rise < 1e-6 and absf(stem_flat) < 1e-6,
	)
	_t.check(
		"...and one boolean is the whole difference (%.3f m against %.3f m)"
		% [sheer_rise, flat_rise],
		sheer_rise > 0.8,
	)
	_t.equal(
		"...and it is the same emitter, box for box",
		control_boxes.size(),
		_boxes.size(),
	)


# ── 4. Solid from the deck to the cap ───────────────────────────────────────

## A bulwark with a slot along the top is a bulwark you can see the sea through,
## and it is what the cheap choice of per-segment height produces: taking the
## LOWER end of each segment leaves a gap of exactly that segment's rise between
## the plating and the cap it is supposed to meet.
##
## Marched as a solid column: every 10 mm from just above the deck to just under
## the cap's top face, at six stations INSIDE EVERY SEGMENT of the run.
##
## The six-per-segment part is not thoroughness for its own sake, it is the
## whole check. A first version sampled 120 stations at segment MIDPOINTS and
## the lower-end mutant sailed straight through it, because a band that takes
## its height at the segment's lower end is still 20 mm proud of the path at the
## midpoint — the slot it opens is at the segment's HIGH END and nowhere else.
## Measured: midpoints only, 0 holes of 15 124; ends included, 1 209 holes.
func _test_no_slot_and_no_breakout() -> void:
	var base := float(_spec["base_y"])
	var cap_h := float(_edge_of(_fixture).get("cap_h", StructureEdge.DEFAULT_CAP_THICKNESS_M))
	var path := _spec["path"] as PackedVector3Array
	## Boxes indexed by the segment that emitted them, so the column probe tests
	## six boxes rather than 362. Without it this is 20 million box tests.
	var by_segment: Dictionary = {}
	for box_variant in _boxes:
		var index := int((box_variant as Dictionary).get("segment", -1))
		if not by_segment.has(index):
			by_segment[index] = []
		(by_segment[index] as Array).append(box_variant)

	var holes := 0
	var probed := 0
	var first_hole := Vector3.INF
	for index in by_segment.keys():
		var here := path[index]
		var next := path[(index + 1) % path.size()]
		var near: Array = []
		for neighbour in [index - 1, index, index + 1]:
			if by_segment.has(neighbour):
				near.append_array(by_segment[neighbour] as Array)
		for step in 6:
			var point := here.lerp(next, lerpf(0.01, 0.99, float(step) / 5.0))
			var y := base + 0.01
			var ceiling := point.y + cap_h - 0.005
			while y < ceiling:
				probed += 1
				if not StructureEdge.point_inside_any(near, Vector3(point.x, y, point.z), 0.0):
					holes += 1
					if first_hole == Vector3.INF:
						first_hole = Vector3(point.x, y, point.z)
				y += 0.01
	_t.check(
		"the column probe sampled every segment, ends included (%d points over %d segments)"
		% [probed, by_segment.size()],
		probed > 100000 and by_segment.size() >= path.size() - 1,
	)
	_t.check(
		"no gap anywhere between the deck and the top of the cap (%d/%d empty, first %s)"
		% [holes, probed, "none" if first_hole == Vector3.INF else str(first_hole)],
		holes == 0,
	)

	## The other half of the same trade: taking the HIGHER end means the plating
	## over-runs the true curve inside its own segment. That over-run has to stay
	## buried in the cap, and `sheer_samples_for` is what sizes the run so it
	## does. Measured against the cap's own top face, per segment.
	var cap_top: Dictionary = {}
	var plate_top: Dictionary = {}
	for box_variant in _boxes:
		var box := box_variant as Dictionary
		var index := int(box.get("segment", -1))
		var top := _top_of(box)
		## The cap rides the tangent; the plating is plumb, so its basis has no
		## pitch at all. That is what tells them apart without a label.
		if absf((box.get("basis", Basis.IDENTITY) as Basis).z.y) > 1e-9:
			cap_top[index] = maxf(float(cap_top.get(index, -INF)), top)
		else:
			plate_top[index] = maxf(float(plate_top.get(index, -INF)), top)
	var breakouts := 0
	var worst := -INF
	for index in plate_top.keys():
		if not cap_top.has(index):
			continue
		var over: float = float(plate_top[index]) - float(cap_top[index])
		worst = maxf(worst, over)
		if over > 0.0:
			breakouts += 1
	print("[section] %d capped segments; worst plating protrusion past the cap top %.4f m" % [
		cap_top.size(), worst,
	])
	_t.check(
		"the sampling keeps the plating's step inside the cap (%d segments break out)" % breakouts,
		breakouts == 0,
	)
	## The sample count is re-derived HERE, from the parabola, rather than read
	## back out of `sheer_samples_for`. Calling the function under test to
	## produce its own expected value is a tautology: the coarse-sampling mutant
	## walked through exactly that version of this check, because it broke the
	## function and the check obligingly broke with it.
	##
	##     rise(z) = rise_end (|z| / (L/2))^2   =>   max |d rise / dz| = 2 rise_end / (L/2)
	##
	## and a segment may rise by no more than the cap's remaining headroom.
	var cap := float(_edge_of(_fixture).get("cap_h", StructureEdge.DEFAULT_CAP_THICKNESS_M))
	var headroom := cap * 2.0 / 3.0
	var slope := 2.0 * maxf(_stations.sheer_forward_m, _stations.sheer_aft_m) / (_stations.length_m * 0.5)
	var expected := maxi(
		int(ceil(_stations.length_m / (headroom / slope))) + 1,
		int(ceil(_stations.length_m / StructureEdge.PLAN_SAMPLE_M)) + 1,
	)
	_t.equal(
		"the sample count is solved from the hull's own sheer slope (%.4f m/m, %.3f m headroom)"
		% [slope, headroom],
		int(_spec["samples"]),
		expected,
	)


# ── 5. Nothing enters the deck ──────────────────────────────────────────────

## The constraint that stopped the LOFT from carrying sheer: `deck_y` is the
## floor of the deck plate, the DeckGrid, the walk colliders and the buoyancy
## sample, with zero headroom, so anything that rises above it cuts through all
## four. This layer is allowed above deck_y — that is the whole point of putting
## the curve in a bulwark — but it must never go BELOW it.
func _test_nothing_enters_the_deck() -> void:
	var base := float(_spec["base_y"])
	var lowest := INF
	for box_variant in _boxes:
		var box := box_variant as Dictionary
		var centre := box["center"] as Vector3
		var half := (box["size"] as Vector3) * 0.5
		var basis := box.get("basis", Basis.IDENTITY) as Basis
		var reach := (
			absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z
		)
		lowest = minf(lowest, centre.y - reach)
	_t.near("the band stands exactly on the deck plane", lowest, base, 1e-6)
	_t.equal("...which is the hull's own deck_y", base, _stations.deck_y)

	## And it stays inside the hull in plan: the cap overhangs the plating by
	## design, but nothing may hang out past the shell by more than that.
	var aabb := StructureEdge.boxes_aabb(_boxes)
	var overhang := aabb.size.x * 0.5 - _stations.beam_m * 0.5
	var cap_w := float(_edge_of(_fixture).get("cap_w", StructureEdge.DEFAULT_CAP_WIDTH_M))
	var plate := float(_edge_of(_fixture).get("plate_m", StructureEdge.DEFAULT_BULWARK_PLATE_M))
	## Tolerance is a mitre, not a fudge: a box extended into a joint sweeps its
	## outer corner a millimetre or so past the section's own half-width at the
	## sharpest turn on the run (the stem). Measured 1.1 mm.
	_t.near(
		"the cap overhangs the shell by half the difference of cap and plating",
		overhang,
		(cap_w - plate) * 0.5,
		3e-3,
	)


# ── 6. Collision IS the drawing ─────────────────────────────────────────────

## "A bulwark you can walk through is the bug class this project has already
## fixed twice." Both times the drawing and the collision were derived
## separately and one of them was edited. Here they are the same array, and this
## is where that is proved rather than asserted in a comment: every CORNER of
## every drawn box must lie inside some collider.
func _test_colliders_are_the_drawing() -> void:
	_t.check("the bulwark emits colliders (%d for %d boxes)" % [
		_colliders.size(), _boxes.size(),
	], _colliders.size() > 0)

	## Reported as a DISTANCE, not a count. A corner that lands exactly on a
	## collider face — which is what the plumb plating does, every time, because
	## the collider is that box — sits on the boundary, and whether a boundary
	## point counts as inside comes down to the last bits of two different
	## rotation paths. A count with a slack hides that; a worst-case escape in
	## millimetres does not, and it goes red by centimetres the moment the
	## collision stops being the drawing.
	var worst := -INF
	var corners := 0
	var first := Vector3.INF
	for box_variant in _boxes:
		for corner in _corners_of(box_variant as Dictionary):
			corners += 1
			var escape := _escape_from_colliders(corner)
			if escape > worst:
				worst = escape
				first = corner
	_t.check("every drawn corner was tested (%d)" % corners, corners == _boxes.size() * 8)
	_t.check(
		"every corner of every drawn box is inside a collider "
		+ "(worst escape %.4f mm, at %s)" % [worst * 1000.0, str(first)],
		worst < 1e-4,
	)

	## The other direction, because "covers everything" is trivially satisfied by
	## one enormous box. A stepped approximation may over-cover — it must not
	## over-cover by much. Tolerance is what merging is allowed to add
	## (COLLIDER_MERGE_M) plus the pitch bulge the yaw-only contract forces on
	## the sloping cap, which is bounded by half the cap's own diagonal.
	var cap_w := float(_edge_of(_fixture).get("cap_w", StructureEdge.DEFAULT_CAP_WIDTH_M))
	var cap_h := float(_edge_of(_fixture).get("cap_h", StructureEdge.DEFAULT_CAP_THICKNESS_M))
	var tolerance := StructureEdge.COLLIDER_MERGE_M + Vector2(cap_w, cap_h).length() * 0.5
	var phantom := 0
	var sampled := 0
	var phantom_at := Vector3.INF
	for collider_variant in _colliders:
		var collider := collider_variant as Dictionary
		var centre := collider["center"] as Vector3
		var size := collider["size"] as Vector3
		var frame := Basis(Vector3.UP, deg_to_rad(float(collider["yaw_deg"])))
		for ix in 3:
			for iy in 5:
				for iz in 5:
					var local := Vector3(
						size.x * (float(ix) / 2.0 - 0.5) * 0.98,
						size.y * (float(iy) / 4.0 - 0.5) * 0.98,
						size.z * (float(iz) / 4.0 - 0.5) * 0.98,
					)
					sampled += 1
					var point: Vector3 = centre + frame * local
					if not StructureEdge.point_inside_any(_boxes, point, tolerance):
						phantom += 1
						if phantom_at == Vector3.INF:
							phantom_at = point
	print("[collide] %d colliders for %d boxes (%.1fx fewer shapes than segments)" % [
		_colliders.size(), _boxes.size(), float(_boxes.size()) / maxf(float(_colliders.size()), 1.0),
	])
	## A gate on the probe itself, not a claim about the geometry: the merge
	## legitimately changes the collider count, and an earlier 1 000-point
	## threshold turned that into a spurious second failure on three
	## unrelated mutants. The claim below is the one that measures anything.
	_t.check("the over-cover probe sampled the colliders (%d points)" % sampled, sampled > 300)
	_t.check(
		"no collider volume sits more than %.3f m from something drawn (%d/%d, first %s)"
		% [tolerance, phantom, sampled, "none" if phantom_at == Vector3.INF else str(phantom_at)],
		phantom == 0,
	)


func _corners_of(box: Dictionary) -> Array:
	var centre := box["center"] as Vector3
	var half := (box["size"] as Vector3) * 0.5
	var basis := box.get("basis", Basis.IDENTITY) as Basis
	var out: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(centre + basis * Vector3(half.x * sx, half.y * sy, half.z * sz))
	return out


## How far outside the NEAREST collider a point falls, along the worst axis of
## that collider's own frame. Zero or negative means covered.
func _escape_from_colliders(point: Vector3) -> float:
	var best := INF
	for collider_variant in _colliders:
		var collider := collider_variant as Dictionary
		var local: Vector3 = Basis(
			Vector3.UP, deg_to_rad(float(collider["yaw_deg"]))
		).transposed() * (point - (collider["center"] as Vector3))
		var half := (collider["size"] as Vector3) * 0.5
		best = minf(best, maxf(
			absf(local.x) - half.x,
			maxf(absf(local.y) - half.y, absf(local.z) - half.z)
		))
	return best


# ── 7. Trim is not an obstruction ───────────────────────────────────────────

## A swept profile draws paint as well as plating. A 12 mm boot top that stops a
## player is a worse defect than one that does not collide at all, and there is
## no flag on those fixtures to say so — the rule has to come off the section.
func _test_trim_does_not_collide() -> void:
	var path := StructureEdge.sheer_path(_stations, -1.0, 21, 0.0, -1.2)
	var solid: Array[String] = []
	var trim: Array[String] = []
	for name in StructureEdge.PROFILE_LIBRARY.keys():
		var boxes := StructureEdge.sweep_collider_boxes({
			"path": path, "profile": str(name), "material": "painted",
		})
		if boxes.is_empty():
			trim.append(str(name))
		else:
			solid.append(str(name))
	print("[collide] solid sections: %s" % ", ".join(PackedStringArray(solid)))
	print("[collide] trim sections:  %s" % ", ".join(PackedStringArray(trim)))
	for name in ["cap_rail", "rubbing_strake", "d_fender", "pipe_run"]:
		_t.check("a %s is an obstruction" % name, solid.has(name))
	for name in ["boot_top", "sheer_strake", "chainplate", "toe_board"]:
		_t.check("a %s is paint or plating, and collides with nothing" % name, trim.has(name))
	_t.check(
		"`solid: false` opts a run out whatever its section",
		StructureEdge.sweep_collider_boxes(_with(_spec, {"solid": false})).is_empty(),
	)


# ── 8. A body is stopped by it, and only where it is ────────────────────────

## The march is explicit. `cast_motion()` returns a clean 1.0 for a shape that
## STARTS overlapping, which scores "began inside the bulwark" as "walked
## straight through it" — so every march reports `started_inside` separately and
## a march that begins stuck is scored VACUOUS rather than passed.
func _test_a_body_is_stopped_by_it() -> void:
	_body = StaticBody3D.new()
	_body.name = "BulwarkColliders"
	for index in _colliders.size():
		var collider := _colliders[index] as Dictionary
		var shape := BoxShape3D.new()
		shape.size = collider["size"] as Vector3
		var node := CollisionShape3D.new()
		node.name = "Bulwark_%d" % index
		node.shape = shape
		node.transform = Transform3D(
			Basis(Vector3.UP, deg_to_rad(float(collider["yaw_deg"]))),
			collider["center"] as Vector3
		)
		_body.add_child(node)
	root.add_child(_body)
	await physics_frame
	await physics_frame
	_space = root.world_3d.direct_space_state
	_t.equal(
		"every collider is a shape on the physics body",
		PhysicsServer3D.body_get_shape_count(_body.get_rid()),
		_colliders.size(),
	)

	var deck := _stations.deck_y
	## Amidships the deck edge is at the full half-beam.
	var half := StructureEdge.deck_half_beam_at(_stations, 0.0, deck)

	_free("an open-air march is free (the marcher can say the word)",
		Vector3(0.0, deck + 40.0, 0.0), Vector3(0, 0, 1) * 6.0)
	_free("...and the open deck is walkable: nothing phantom inboard",
		Vector3(0.0, deck + 0.9, -4.0), Vector3(0, 0, 1) * 8.0)

	## The bulwark itself, amidships, at hip height.
	_blocked("a body walking outboard amidships is stopped by the bulwark",
		Vector3(-half + 2.2, deck + 0.9, 0.0), Vector3(-1, 0, 0) * 2.6)

	## ── The pair that proves the COLLIDER carries the curve ──
	## The band is 1.16 m tall amidships and 2.06 m at the stem. A body at
	## 1.55 m above the deck therefore has its middle above the amidships cap and
	## well inside the bow one. If the collider were a constant-height slab —
	## the shape today's walls emit — both of these would report the same thing.
	var stem_half := StructureEdge.deck_half_beam_at(_stations, -12.0, deck)
	var high := deck + 1.55
	var over := _march(Vector3(-half + 2.2, high + 0.9, 0.0), Vector3(-1, 0, 0) * 2.6)
	var into := _march(Vector3(-stem_half - 1.6, high + 0.9, -12.0), Vector3(1, 0, 0) * 2.6)
	print("[collide] at %.2f m over the deck: amidships blocked=%s, at the bow blocked=%s"
		% [1.55 + 0.9, str(over["blocked"]), str(into["blocked"])])
	if bool(over["started_inside"]) or bool(into["started_inside"]):
		_t.fail("the sheer collider pair — VACUOUS: a march began inside a collider")
	else:
		_t.check(
			"at 2.45 m over the deck a body clears the bulwark amidships",
			not bool(over["blocked"]),
		)
		_t.check(
			"...and is STOPPED by the same run at the bow, where the sheer lifts it",
			bool(into["blocked"]),
		)

	## Nothing above the cap is solid: over-covering upward is bounded, not free.
	var cap_top := _top_at_z(_boxes, 0.0)
	_free("a body clears the cap amidships with %.2f m to spare"
		% StructureEdge.COLLIDER_MERGE_M,
		Vector3(-half + 2.2, cap_top + 1.2, 0.0), Vector3(-1, 0, 0) * 2.6)

	_body.queue_free()
	_body = null


func _blocked(label: String, from: Vector3, motion: Vector3) -> void:
	var march := _march(from, motion)
	if bool(march["started_inside"]):
		_t.fail("%s — VACUOUS: the march began inside a collider" % label)
		return
	_t.check(
		"%s (stopped at %.2f m of %.2f)" % [label, float(march["stop_m"]), motion.length()],
		bool(march["blocked"]),
	)


func _free(label: String, from: Vector3, motion: Vector3) -> void:
	var march := _march(from, motion)
	if bool(march["started_inside"]):
		_t.fail("%s — VACUOUS: the march began inside a collider" % label)
		return
	_t.check("%s (walked the full %.2f m)" % [label, motion.length()], not bool(march["blocked"]))


func _march(from: Vector3, motion: Vector3) -> Dictionary:
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	var length := motion.length()
	var steps := maxi(2, int(ceil(length / MARCH_STEP)))
	var out := {"started_inside": false, "blocked": false, "stop_m": length}
	for index in steps + 1:
		var f := float(index) / float(steps)
		query.transform = Transform3D(Basis.IDENTITY, from + motion * f)
		var overlapped := false
		for hit_variant in _space.intersect_shape(query, 8):
			if (hit_variant as Dictionary).get("collider") == _body:
				overlapped = true
				break
		if not overlapped:
			continue
		if index == 0:
			out["started_inside"] = true
			continue
		out["blocked"] = true
		out["stop_m"] = f * length
		break
	return out


# ── 9. It costs no draw call ────────────────────────────────────────────────

## A MeshInstance3D is not a draw call, so this is read off
## RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME after a real frame, with an empty
## scene measured first.
func _test_it_costs_no_draw_call() -> void:
	_camera = Camera3D.new()
	_camera.far = 40000.0
	root.add_child(_camera)
	_camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	root.add_child(light)

	_draw_baseline = await _draw_calls_now()
	_t.check("an empty scene has a measurable baseline (%d)" % _draw_baseline, _draw_baseline > 0)

	var node := StructureEdge.bake_boxes(_boxes)
	root.add_child(node)
	var calls := await _draw_calls_for(node)
	_t.equal(
		"a whole bulwark — %d boxes, two colours — is ONE draw call" % _boxes.size(),
		calls - _draw_baseline,
		1,
	)
	_t.equal("...carried by one MeshInstance3D", node.get_child_count(), 1)
	_t.equal("...holding one surface", _surface_count(node), 1)
	_t.check(
		"...whose single surface carries both colours (%d distinct)" % _distinct_colours(node),
		_distinct_colours(node) >= 2,
	)
	_t.equal(
		"...for exactly box count x 12 triangles",
		_triangles(node),
		StructureEdge.triangle_count(_boxes),
	)
	root.remove_child(node)
	node.free()


func _draw_calls_for(node: Node3D) -> int:
	var bounds := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var box: AABB = (child as MeshInstance3D).get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	if first:
		_t.fail("nothing to frame — the node holds no MeshInstance3D")
		return await _draw_calls_now()
	var centre := bounds.get_center()
	var distance := maxf(bounds.size.length(), 1.0) * 1.6
	_camera.position = centre + Vector3(0.35, 0.45, -1.0).normalized() * distance
	_camera.look_at(centre, Vector3.UP)
	var calls := await _draw_calls_now()
	_t.check(
		"the camera actually sees the geometry it is counting (%d > %d)"
		% [calls, _draw_baseline],
		calls > _draw_baseline,
	)
	return calls


func _draw_calls_now() -> int:
	for i in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	return int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	))


# ── Cost ────────────────────────────────────────────────────────────────────

func _report_costs() -> void:
	var length := StructureEdge.path_length_m(_spec["path"], bool(_spec["closed"]))
	print("cost — one bulwark on a %.0f m hull" % _stations.length_m)
	print("  path        %6.2f m over %d samples" % [length, int(_spec["samples"])])
	print("  drawn       %4d boxes  %5d triangles  1 surface  1 draw call" % [
		_boxes.size(), StructureEdge.triangle_count(_boxes),
	])
	print("  collided    %4d boxes (merged from %d segment colliders)" % [
		_colliders.size(),
		StructureEdge.sweep_collider_boxes(_with(_spec, {"collider_merge_m": 0.0})).size(),
	])


func _with(spec: Dictionary, overrides: Dictionary) -> Dictionary:
	var out := spec.duplicate(true)
	for key in overrides.keys():
		out[key] = overrides[key]
	return out


func _surface_count(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh
			if mesh != null:
				total += mesh.get_surface_count()
	return total


func _triangles(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh as ArrayMesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var verts: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				if verts != null:
					total += (verts as PackedVector3Array).size() / 3
	return total


func _distinct_colours(node: Node) -> int:
	var most := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh as ArrayMesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var seen: Dictionary = {}
				var colours: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
				if colours != null:
					for c in colours as PackedColorArray:
						seen[c.to_rgba32()] = true
				most = maxi(most, seen.size())
	return most
