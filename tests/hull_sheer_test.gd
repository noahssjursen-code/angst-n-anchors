extends SceneTree

## Sheer, and the line the loft is not allowed to cross.
##
## `HullStations` derives a sheer curve per hull from catalog fields (see the sheer note
## in `scripts/ship/hull_stations.gd`). It does NOT extrude it. `deck_y` is simultaneously
## the flat build plane and the ceiling of the loft, because every other system's geometry
## starts at `deck_y` and goes up: the deck plate fills [deck_y, deck_y + 0.1], DeckGrid
## sits at deck_y + 0.12 with the whole StructurePlan on top of it, and BoatBody's walk
## slab tops out around deck_y + 0.23 with nothing on the player's mask above that.
##
## A wave that lifted the loft's section levels to draw the curve was measured, on
## hull_28x10, at: 0.666 m of walk-through plating at the stem, 308/34155 shell samples
## inside the deck plate spanning 84% of LOA, up to 0.098 m deep inside the box colliders
## of all three shipped fixtures, 4.2% under-reported displacement volume, and a 5.9%
## shrink in the per-station lateral lever. Control, with the curve not extruded: zero on
## every one of those. This file is what keeps it at zero.
##
## So the checks come in three parts and all of them matter:
##   • THE CEILING — nothing the loft emits may reach the deck plate, the plan's
##     colliders, or the space above the walking plane, on any hull.
##   • THE CURVE — it must still be derived, per hull, from `bow_keel_rise` /
##     `stern_keel_rise` and freeboard, and still be a bow-dominant parabola, because the
##     bulwark work that has to carry it takes its cap height from here.
##   • THE CURVE IS USED — added 2026-08-15. The two halves above were both green for
##     days while `sheer_forward_m` was computed on every hull and read by nothing that
##     draws, and every hull in the fleet rendered as the same flat slab. A derivation
##     with no consumer is REALITY §3d in miniature, and no check pointed at it. The
##     rubbing strake now carries the curve, and `_check_curve_is_drawn` holds it there:
##     the strake band must be HIGHER at the stem than amidships, by the sheer rise, on
##     every hull.
##
## `_check_deck_edge_matches_plate` is the other new one, and it closes a §3b split the
## STATE entry named and nobody had a check for: the loft cut the bow with a smoothstep
## while `pointed_deck_plate` and `DeckGrid` cut it with a straight 45 degree chamfer over
## the same interval, so the drawn deck edge and the drawn deck plate disagreed by
## 0.2181 m per side on hull_15x5 and 0.4788 m on hull_28x10.
##
## The collider half is an exact triangle-vs-oriented-box SAT, not a point sampler: the
## intrusion this guards against is a sliver a few centimetres wide along the deck edge,
## and a sampler dense enough to be sure of catching it is dense enough to be slow.

const TestReport := preload("res://tests/support/test_report.gd")

const FIXTURES := [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_trawler_bow_bulwark.json",
]
## Deck plate band drawn by every lofted vessel: `pointed_deck_plate` is called with
## `stations.deck_y + 0.1` and thickness 0.1, so it fills [deck_y, deck_y + 0.1].
const PLATE_THICKNESS := 0.1
const TOUCH_EPS := 0.00001


func _initialize() -> void:
	var t := TestReport.new("hull_sheer_test")
	var hulls := _hull_cases()
	t.check("hull cases available", hulls.size() >= 8)

	for case in hulls:
		_check_ceiling(t, case)
		_check_displacement(t, case)
		_check_lever(t, case)
		_check_curve(t, case)
		_check_curve_is_drawn(t, case)
		_check_stem_rakes(t, case)
		_check_strake_is_painted(t, case)
		_check_deck_edge_matches_plate(t, case)

	_check_baked_shell(t)
	_check_plan_clearance(t)
	t.finish(self)


# ── The ceiling ──────────────────────────────────────────────────────────────────

## No section level may sit above the build plane, and the top level must sit exactly on
## it — the second half matters as much as the first, because `half_beam_at(i, deck_y)`
## is the buoyancy lever and it reads whatever level is there.
func _check_ceiling(t: TestReport, case: Dictionary) -> void:
	var s: HullStations = case["stations"]
	var id: String = case["id"]
	var highest := -1e9
	var off_plane := 0
	for station in s.stations:
		var section: Array = station["section"]
		if section.is_empty():
			continue
		for level in section:
			highest = maxf(highest, (level as Vector2).x)
		if absf((section[section.size() - 1] as Vector2).x - s.deck_y) > 0.0001:
			off_plane += 1
	t.check(
		"%s: loft ceiling is the build plane (highest level %.4f, deck_y %.4f)"
			% [id, highest, s.deck_y],
		highest <= s.deck_y + 0.0001,
	)
	t.equal("%s: every station tops out exactly on deck_y" % id, off_plane, 0)


## `displacement_volume_m3` is integrated up to `depth`. If any geometry stands above
## `depth` the figure silently under-reports the hull it belongs to.
func _check_displacement(t: TestReport, case: Dictionary) -> void:
	var s: HullStations = case["stations"]
	var top := 0.0
	for station in s.stations:
		for level in (station["section"] as Array):
			top = maxf(top, (level as Vector2).x)
	var enclosed := s.volume_below(top + 0.001)
	var error := absf(enclosed - s.displacement_volume_m3) / maxf(enclosed, 0.0001)
	t.check(
		"%s: displacement_volume_m3 covers the whole loft (%.3f vs %.3f, %.3f%% out)"
			% [case["id"], s.displacement_volume_m3, enclosed, error * 100.0],
		error < 0.0001,
	)


## StripBuoyancyComponent's lateral lever arm is `half_beam_at(i, deck_y)`. It is the
## deck-edge half beam only while the deck edge is at `deck_y`.
func _check_lever(t: TestReport, case: Dictionary) -> void:
	var s: HullStations = case["stations"]
	var worst := 0.0
	for i in range(s.stations.size()):
		var section: Array = s.stations[i]["section"]
		if section.is_empty():
			continue
		var edge := (section[section.size() - 1] as Vector2).y
		if edge <= 0.001:
			continue
		worst = maxf(worst, absf(edge - s.half_beam_at(i, s.deck_y)) / edge)
	t.check(
		"%s: half_beam_at(i, deck_y) is the deck-edge half beam (worst %.4f%% out)"
			% [case["id"], worst * 100.0],
		worst < 0.0001,
	)


# ── The curve ────────────────────────────────────────────────────────────────────

func _check_curve(t: TestReport, case: Dictionary) -> void:
	var s: HullStations = case["stations"]
	var id: String = case["id"]
	var form: Dictionary = case["form"]
	var freeboard: float = maxf(float(case["depth"]) - float(case["draft"]), 0.0)
	t.near(
		"%s: sheer forward = freeboard x bow_keel_rise" % id,
		s.sheer_forward_m,
		freeboard * float(form.get("bow_keel_rise", 0.2)),
		0.0005,
	)
	t.near(
		"%s: sheer aft = freeboard x stern_keel_rise" % id,
		s.sheer_aft_m,
		freeboard * float(form.get("stern_keel_rise", 0.05)),
		0.0005,
	)
	t.check(
		"%s: sheer is bow-dominant (fwd %.4f, aft %.4f)" % [id, s.sheer_forward_m, s.sheer_aft_m],
		s.sheer_forward_m > 2.0 * s.sheer_aft_m,
	)
	t.check(
		"%s: sheer is worth carrying (%.4f m forward)" % [id, s.sheer_forward_m],
		s.sheer_forward_m > 0.2,
	)
	t.near("%s: sheer is zero amidships" % id, s.sheer_rise_at(0.0), 0.0, 0.000001)
	t.near("%s: cap y amidships is the build plane" % id, s.sheer_cap_y_at(0.0), s.deck_y, 0.000001)
	## Parabolic, not a linear ramp: at half the half-length the rise is (0.5)^2 = 25%
	## of the end rise. A ramp would read 50%.
	var quarter := -s.length_m * 0.25
	t.near(
		"%s: sheer curve is parabolic at z = %.2f" % [id, quarter],
		s.sheer_rise_at(quarter),
		s.sheer_forward_m * 0.25,
		0.0005,
	)
	## The cap stands above the loft by construction — that gap IS the bulwark, and the
	## thing a consumer has to build and collide for itself.
	t.check(
		"%s: the cap curve stands proud of the flat loft at the stem" % id,
		s.sheer_cap_y_at(-s.length_m * 0.5) > s.deck_y + 0.2,
	)


# ── The curve is USED ────────────────────────────────────────────────────────────

## The strake band is the level pair `stations.strake_level` names. Its Y must rise from
## amidships toward the stem by the sheer curve — that is the whole point of computing
## the curve, and it was computed and dropped on the floor until 2026-08-15.
##
## Stated as a PROPERTY and not as the formula (§4a): "the strake at the stem stands
## higher above the strake amidships, and by the amount `sheer_rise_at` asks for, up to
## the clearance clamp". Restating `strake_base + band + rise` would pass on any code
## that computes the same expression twice and draws neither.
func _check_curve_is_drawn(t: TestReport, case: Dictionary) -> void:
	var s: HullStations = case["stations"]
	var id: String = case["id"]
	if not t.check("%s: the loft names a strake level" % id, s.strake_level >= 0):
		return
	## The strake only exists where the hull has width: at the stem station every level
	## collapses onto the stem line by construction, so a sampler that reads the tip
	## reads `deck_y` and learns nothing. Read the drawn band instead.
	var live: Array = []
	for station in s.stations:
		var section: Array = station["section"]
		if (section[s.strake_level] as Vector2).y > 0.001:
			live.append(station)
	if not t.check("%s: the strake band is drawn at 3+ stations" % id, live.size() >= 3):
		return
	var clamp_y := s.deck_y - maxf(
		(float(case["depth"]) - float(case["draft"])) * HullStations.STRAKE_MIN_CLEAR_FRACTION,
		0.04,
	)
	var mid := 1e18
	var mid_z := 0.0
	var mid_abs := 1e18
	for station in live:
		if absf(float(station["z"])) < mid_abs:
			mid_abs = absf(float(station["z"]))
			mid_z = float(station["z"])
			mid = ((station["section"] as Array)[s.strake_level] as Vector2).x
	var fwd := ((live[0]["section"] as Array)[s.strake_level] as Vector2).x
	var aft := ((live[live.size() - 1]["section"] as Array)[s.strake_level] as Vector2).x
	t.check(
		"%s: the strake is higher forward than amidships (%.4f vs %.4f)" % [id, fwd, mid],
		fwd > mid + 0.02,
	)
	t.check(
		"%s: the strake is higher aft than amidships (%.4f vs %.4f)" % [id, aft, mid],
		aft > mid + 0.002,
	)
	t.check(
		"%s: the drawn rise is bow-dominant (fwd %.4f, aft %.4f)"
			% [id, fwd - mid, aft - mid],
		(fwd - mid) > (aft - mid),
	)
	## And it is THAT curve. Every station where the clearance clamp is not biting must
	## show exactly the rise `sheer_rise_at` asks for at that station's own Z — stated
	## against the curve, not against a re-typed copy of the formula (§4a).
	var off := 0
	var worst := 0.0
	var unclamped := 0
	for station in live:
		var y := ((station["section"] as Array)[s.strake_level] as Vector2).x
		if y >= clamp_y - 0.0001:
			continue
		unclamped += 1
		var want := s.sheer_rise_at(float(station["z"])) - s.sheer_rise_at(mid_z)
		var delta := absf((y - mid) - want)
		worst = maxf(worst, delta)
		if delta > 0.005:
			off += 1
	t.check("%s: unclamped strake stations exist to check" % id, unclamped >= 2)
	t.equal(
		"%s: every unclamped strake station rises by sheer_rise_at (worst %.5f m, of %d)"
			% [id, worst, unclamped],
		off,
		0,
	)
	## Nothing the strake does may reach the deck edge, anywhere it is drawn.
	var over := 0
	for station in live:
		if ((station["section"] as Array)[s.strake_level] as Vector2).x > clamp_y + 0.0001:
			over += 1
	t.equal("%s: the strake stays clear of the deck edge" % id, over, 0)


## The stem must lean, measured ON THE BAKED SURFACE.
##
## Not on the section widths, and that distinction is the whole check. The first version
## of this raked the half-beams and left every level at its nominal Y, so the loft still
## emitted a VERTEX at z = −L/2 at keel height and the rendered outline was exactly
## plumb — two renders of hull_15x5 apart and indistinguishable. A section-width sampler
## calls that a raked stem, because the widths did rake. It is what the triangles reach
## that draws the picture, so that is what is asserted: the forward-most point of the
## baked shell down at the keel must sit aft of the forward-most point at the deck edge.
##
## This mutation was run and PASSED against the width-only version (§8: a mutation that
## passes is a blind check, not a safe one) — which is how the check came to be pointed
## at the mesh instead.
func _check_stem_rakes(t: TestReport, case: Dictionary) -> void:
	var s: HullStations = case["stations"]
	var id: String = case["id"]
	var mesh: ArrayMesh = MeshBuilder.lofted_hull_shell(s).mesh
	if not t.check("%s: shell bakes for the stem check" % id, mesh != null):
		return
	var faces: PackedVector3Array = mesh.get_faces()
	## Measured at the DESIGN WATERLINE against the deck edge, because that is the span
	## a person sees. A band down at the keel cannot tell the two versions apart: the
	## forefoot is already lifted at the bow by `bow_keel_rise`, so keel-height vertices
	## are aft of the stem whether the stem rakes or not — that sampler was written,
	## mutated, and passed on the bug (§8) before this one replaced it.
	var wl_band := s.design_draft_m + (s.deck_y - s.keel_y) * 0.02
	var deck_band := s.deck_y - maxf((s.deck_y - s.design_draft_m) * 0.1, 0.02)
	var deck_front := 1e9
	var wl_front := 1e9
	for v in faces:
		if v.y >= deck_band:
			deck_front = minf(deck_front, v.z)
		if v.y <= wl_band:
			wl_front = minf(wl_front, v.z)
	t.check(
		"%s: the stem rakes — waterline reaches %.3f, the stem head %.3f"
			% [id, wl_front, deck_front],
		wl_front > deck_front + s.length_m * 0.01,
	)


## The strake band has to be PAINTED, not merely shaped.
##
## This check exists because the mutation that deletes the material split passed the
## whole suite, and then passed the FIRST version of this check too (§8 twice over: a
## mutation that passes is a blind check, not a safe one). Every other check here is
## about where the band SITS, and the band sits in the same place painted or not —
## while the thing the change was made for, a sheer line a person can see in profile,
## exists only where there is a material boundary. Rendered without the split, at
## `topsides_color` (0.14, 0.16, 0.18), the band is invisible: near-black compresses
## every shading difference to a few RGB units.
##
## The first version asked "does surface 1 reach the freeboard anywhere" and "is it
## higher forward than amidships", and both were vacuous: near the stem every section
## level collapses onto the stem line at `deck_y`, so surface 1 touches the deck edge
## at the bow whether the strake is painted or not. Measured on hull_15x5 —
## `fwd_top` is 2.600 either way. AMIDSHIPS is the only place the stem collapse cannot
## reach, so that is where the property is stated, and it is stated as an equality
## against the level the loft NAMES rather than as "higher than the waterline".
func _check_strake_is_painted(t: TestReport, case: Dictionary) -> void:
	var s: HullStations = case["stations"]
	var id: String = case["id"]
	if s.strake_level < 0:
		return
	var mesh: ArrayMesh = MeshBuilder.lofted_hull_shell(s).mesh
	if not t.check(
		"%s: shell bakes with 2 surfaces" % id,
		mesh != null and mesh.get_surface_count() == 2,
	):
		return
	## The midships station and the band top the loft says it drew there.
	var mid_station := {}
	var mid_abs := 1e18
	for station in s.stations:
		var section: Array = station["section"]
		if (section[s.strake_level] as Vector2).y <= 0.001:
			continue
		if absf(float(station["z"])) < mid_abs:
			mid_abs = absf(float(station["z"]))
			mid_station = station
	if not t.check(
		"%s: a midships station exists inside the sample window" % id,
		not mid_station.is_empty() and mid_abs < s.length_m * 0.20,
	):
		return
	var want := (
		(mid_station["section"] as Array)[s.strake_level + 1] as Vector2
	).x
	var window := maxf(s.length_m * 0.02, 0.05)
	var verts: PackedVector3Array = mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	var mid_top := -1e9
	var sampled := 0
	for v in verts:
		if absf(v.z - float(mid_station["z"])) <= window:
			sampled += 1
			mid_top = maxf(mid_top, v.y)
	t.check("%s: surface 1 has vertices at midships (%d)" % [id, sampled], sampled > 0)
	t.near(
		"%s: the second colour tops out on the strake band amidships (%.4f)" % [id, mid_top],
		mid_top,
		want,
		0.0001,
	)
	## Painting the WHOLE freeboard would satisfy "the strake is painted" — the
	## equality above is what rules it out, because it pins the boundary on the level
	## the loft names rather than merely somewhere above the waterline.


## §3b. The drawn deck edge and the drawn deck plate are two derivations of one line.
## `pointed_deck_plate` and `DeckGrid.cell_shape` chamfer the bow linearly over
## `bow_taper_m`; the loft has to do the same, and a station has to land on the corner
## or the chord cuts it. Sampled along the CONTINUOUS drawn curves, not at the stations,
## because a station-only sampler reports whatever the spacing happens to hit.
func _check_deck_edge_matches_plate(t: TestReport, case: Dictionary) -> void:
	var s: HullStations = case["stations"]
	var ring := MeshBuilder._pointed_plan_ring(
		s.length_m, s.beam_m, clampf(float(case["bow_taper_m"]) / s.length_m, 0.0, 0.5)
	)
	var worst := 0.0
	var worst_z := 0.0
	for k in range(801):
		var z := lerpf(-s.length_m * 0.5, s.length_m * 0.5, float(k) / 800.0)
		var d := _deck_edge_half_beam(s, z) - _ring_half_beam(ring, z)
		if absf(d) > absf(worst):
			worst = d
			worst_z = z
	t.check(
		"%s: deck edge and deck plate agree (worst %+.4f m per side at z=%.3f)"
			% [case["id"], worst, worst_z],
		absf(worst) < 0.01,
	)


func _strake_y(s: HullStations, z: float) -> float:
	var best := 0.0
	var best_d := 1e18
	for station in s.stations:
		var d := absf(float(station["z"]) - z)
		if d < best_d:
			best_d = d
			var section: Array = station["section"]
			best = (section[s.strake_level] as Vector2).x
	return best


## What the loft DRAWS at the deck edge between stations: it lofts linearly, so the edge
## between two stations is the straight line between their top levels.
func _deck_edge_half_beam(s: HullStations, z: float) -> float:
	var n := s.stations.size()
	if n == 0:
		return 0.0
	for i in range(n - 1):
		var za := float(s.stations[i]["z"])
		var zb := float(s.stations[i + 1]["z"])
		if z >= za and z <= zb:
			var ha := ((s.stations[i]["section"] as Array).back() as Vector2).y
			var hb := ((s.stations[i + 1]["section"] as Array).back() as Vector2).y
			return lerpf(ha, hb, (z - za) / maxf(zb - za, 1e-6))
	return ((s.stations[n - 1]["section"] as Array).back() as Vector2).y


func _ring_half_beam(ring: PackedVector2Array, z: float) -> float:
	var best := 0.0
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if absf(b.y - a.y) < 1e-6:
			continue
		if z < minf(a.y, b.y) or z > maxf(a.y, b.y):
			continue
		best = maxf(best, absf(a.x + (z - a.y) / (b.y - a.y) * (b.x - a.x)))
	return best


# ── The baked shell ──────────────────────────────────────────────────────────────

## Exact, not sampled: a triangle's interior cannot reach higher than its highest vertex,
## so a vertex bound on the baked soup proves the whole surface stays under the deck
## plate. The sampled count is kept alongside it because that is the number the
## regression was originally measured in.
func _check_baked_shell(t: TestReport) -> void:
	var stations := FishingTrawlerSmall.make_physics_profile().make_stations()
	var mesh: ArrayMesh = MeshBuilder.lofted_hull_shell(stations).mesh
	if not t.check("trawler shell bakes", mesh != null and mesh.get_surface_count() > 0):
		return
	## Two, and the budget tests are why: a third surface for the strake measured
	## +2 draw calls a vessel. `HullLivery` addresses these by index, so the COUNT is
	## load-bearing and not decoration.
	t.equal("shell is still 2 surfaces", mesh.get_surface_count(), 2)
	var faces: PackedVector3Array = mesh.get_faces()
	var max_y := -1e9
	for v in faces:
		max_y = maxf(max_y, v.y)
	t.near("baked shell tops out on the build plane", max_y, stations.deck_y, 0.0001)

	var ring := MeshBuilder._pointed_plan_ring(
		FishingTrawlerSmall.LOA_M, FishingTrawlerSmall.BEAM_M, FishingTrawlerSmall.BOW_FRAC
	)
	var samples := _sample_faces(faces, 24)
	var inside := 0
	for p in samples:
		if p.y <= stations.deck_y + TOUCH_EPS or p.y > stations.deck_y + PLATE_THICKNESS:
			continue
		if _in_ring(ring, p.x, p.z):
			inside += 1
	t.equal(
		"no shell sample inside the deck plate (of %d)" % samples.size(), inside, 0
	)
	## The walking plane the player actually stands on: WalkDeck sits at DeckGrid's plane
	## + 0.04 and is 0.14 thick, and WalkHullCollider stops at 0.85 x depth well below it.
	## Plating between those two carries no collider on the player's mask.
	var walk_top := FishingTrawlerSmall.make_grid().deck_y + 0.04 + 0.07
	var proud := 0
	for v in faces:
		if v.y > walk_top + TOUCH_EPS:
			proud += 1
	t.equal("no shell vertex above the walking plane (%.3f)" % walk_top, proud, 0)


## Every shipped fixture, against the shell it is bolted to. Exact triangle-vs-OBB.
func _check_plan_clearance(t: TestReport) -> void:
	var stations := FishingTrawlerSmall.make_physics_profile().make_stations()
	var mesh: ArrayMesh = MeshBuilder.lofted_hull_shell(stations).mesh
	if mesh == null:
		t.fail("trawler shell bakes for the plan clearance check")
		return
	var faces: PackedVector3Array = mesh.get_faces()
	var grid := FishingTrawlerSmall.make_grid()
	var offset := Vector3(-grid.half_beam, grid.deck_y, -grid.half_loa)
	for path in FIXTURES:
		var raw := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(raw)
		if not t.check("fixture parses: %s" % path.get_file(), typeof(parsed) == TYPE_DICTIONARY):
			continue
		var plan := StructurePlan.from_dict(parsed as Dictionary)
		var boxes := StructureBaker.collect_colliders(plan, offset)
		if not t.check("fixture has colliders: %s" % path.get_file(), boxes.size() > 0):
			continue
		var overlaps := 0
		for i in range(0, faces.size(), 3):
			for box_variant in boxes:
				if _triangle_hits_box(faces[i], faces[i + 1], faces[i + 2], box_variant as Dictionary):
					overlaps += 1
		t.equal(
			"hull shell clears %s (%d triangles x %d boxes)"
				% [path.get_file(), faces.size() / 3, boxes.size()],
			overlaps,
			0,
		)


# ── Helpers ──────────────────────────────────────────────────────────────────────

func _hull_cases() -> Array:
	var cases: Array = []
	for entry in HullCatalog.catalog_entries():
		cases.append({
			"id": str(entry.get("id", "")),
			"depth": float(entry.get("depth_m", 1.0)),
			"draft": float(entry.get("draft_m", 1.0)),
			"bow_taper_m": float(entry.get("bow_taper_m", 0.0)),
			"form": entry.get("hull_form", {}) as Dictionary,
			"stations": HullStations.from_form(
				float(entry.get("loa_m", 1.0)),
				float(entry.get("beam_m", 1.0)),
				float(entry.get("depth_m", 1.0)),
				float(entry.get("draft_m", 1.0)),
				float(entry.get("displacement_t", 1.0)),
				entry.get("hull_form", {}) as Dictionary,
				1025.0,
				float(entry.get("bow_taper_m", 0.0)),
				clampi(int(round(float(entry.get("loa_m", 1.0)) / 8.0)), 8, 16),
			),
		})
	for profile in [
		FishingTrawlerSmall.make_physics_profile(),
		PassengerCatamaran.make_physics_profile(),
	]:
		cases.append({
			"id": "%.0fx%.0f" % [profile.length_m, profile.beam_m],
			"depth": profile.depth_m,
			"draft": profile.design_draft_m,
			"bow_taper_m": profile.length_m * profile.bow_taper_fraction,
			"form": profile.hull_form,
			"stations": profile.make_stations(),
		})
	return cases


## Barycentric lattice over every triangle, interior points only.
func _sample_faces(faces: PackedVector3Array, order: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		for u in range(1, order):
			for v in range(1, order - u):
				var w := order - u - v
				out.append((a * float(u) + b * float(v) + c * float(w)) / float(order))
	return out


func _in_ring(ring: PackedVector2Array, x: float, z: float) -> bool:
	var inside := false
	var n := ring.size()
	var j := n - 1
	for i in range(n):
		var pi := ring[i]
		var pj := ring[j]
		if (pi.y > z) != (pj.y > z):
			var crossing := pi.x + (z - pi.y) / (pj.y - pi.y) * (pj.x - pi.x)
			if x < crossing:
				inside = not inside
		j = i
	return inside


## Separating-axis test, triangle against one `collect_colliders` box. The box's own yaw
## travels with it — a diagonal bulwark tested axis-aligned is a different box entirely.
## Touching counts as clear: the shell's deck ring is coplanar with things by design.
func _triangle_hits_box(a: Vector3, b: Vector3, c: Vector3, box: Dictionary) -> bool:
	var yaw := deg_to_rad(float(box.get("yaw_deg", 0.0)))
	var to_local := Basis(Vector3.UP, -yaw)
	var center := box["center"] as Vector3
	var half := (box["size"] as Vector3) * 0.5
	var v0 := to_local * (a - center)
	var v1 := to_local * (b - center)
	var v2 := to_local * (c - center)
	var edges := [v1 - v0, v2 - v1, v0 - v2]
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for edge in edges:
		for basis_axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			axes.append((basis_axis as Vector3).cross(edge as Vector3))
	axes.append((edges[0] as Vector3).cross(edges[1] as Vector3))
	for axis in axes:
		if axis.length_squared() < 1e-12:
			continue
		var p0 := axis.dot(v0)
		var p1 := axis.dot(v1)
		var p2 := axis.dot(v2)
		var lo := minf(p0, minf(p1, p2))
		var hi := maxf(p0, maxf(p1, p2))
		var reach := (
			half.x * absf(axis.x) + half.y * absf(axis.y) + half.z * absf(axis.z)
		)
		if lo >= reach - TOUCH_EPS or hi <= -reach + TOUCH_EPS:
			return false
	return true
