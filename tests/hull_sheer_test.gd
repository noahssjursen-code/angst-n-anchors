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
## So the checks come in two halves and both matter:
##   • THE CEILING — nothing the loft emits may reach the deck plate, the plan's
##     colliders, or the space above the walking plane, on any hull.
##   • THE CURVE — it must still be derived, per hull, from `bow_keel_rise` /
##     `stern_keel_rise` and freeboard, and still be a bow-dominant parabola, because the
##     bulwark work that has to carry it takes its cap height from here.
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
