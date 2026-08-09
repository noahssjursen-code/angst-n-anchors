extends SceneTree

## Do the colliders occupy the volume the baker actually DRAWS — on every wall
## axis, including all four diagonals?
##
## This is the gate coverage the diagonal-wall fix never had. A previous wave
## shipped diagonal walls that rendered rotated and collided axis-aligned (you
## could walk through the bow); it was caught by a human critic, not by the
## suite, because nothing under tests/ constructed a diagonal wall at all.
##
## Ground truth for "rendered" is the triangle soup StructureBaker.bake()
## emits — deliberately NOT wall_boxes(), which is the same source the colliders
## come from and would make the whole comparison circular. Along a ray the
## rendered solid is recovered by signed crossing counting (winding >= 1), which
## is exact for a union of closed, consistently-oriented boxes even where they
## overlap (the two half-thickness skins of a two-sided wall always do).
##
## Uncovered material is scored by DEPTH into un-collided space, never by ray
## length: a ray grazing along the 1 cm render skin otherwise reports a long,
## shallow hole that is not a hole at all. The signed distance to the collider
## union says how far into nothing the drawn material really sits.
##
## Calibration (measured, `.probe/critic2/vol_probe.gd` on the bow bulwark):
## correct behaviour leaves deepest-uncovered at ~0.0098 m — exactly SKIN_EPS,
## the amount a two-sided skin stands proud of its collider — while forcing the
## collider yaw to 0 leaves 987.93 m uncovered, deepest 2.4596 m. DEEP_LIMIT
## sits between those with two orders of magnitude of room on the broken side.
##
## The fixture's walls are single-panel and openingless on purpose: opening
## casing stands FRAME_PROUD of the skin with no collider behind it anywhere in
## the project (pre-existing, measured identically on straight walls and
## diagonals), and that gap would swamp a threshold measured in centimetres.

const TestReport := preload("res://tests/support/test_report.gd")

const FIXTURE := "res://resources/data/structures/diagonal_axes_probe.json"
const SKIN_EPS := 0.01 ## StructureBaker.SKIN_EPS — how proud a skin sits
## Deepest run of drawn-but-uncollided material tolerated. 5x the render skin
## the correct bake legitimately leaves, ~1/40 of what a yaw-0 collider leaves.
const DEEP_LIMIT := 0.05
## Collider standing where nothing is drawn (the other half of the same bug:
## an un-rotated box juts out over open deck). Scored the same way.
const PHANTOM_LIMIT := 0.05
const SLIVER := 0.002 ## rendered runs thinner than this are skin artefacts
const TOL := 0.0005 ## slack on interval endpoints
const BIN := 0.25
const RAY_START := 30.0 ## rays begin this far outside the geometry
## Sample grids are nudged off the whole numbers the fixture is authored on. A
## ray lying exactly IN a face plane makes the crossing count degenerate and
## manufactures holes and phantoms out of nothing: the +X family on the z-wall's
## z == 0 end face reported 5 x 0.3 m of phantom collider before this offset,
## purely because the triangles it should have entered through were edge-on.
const NUDGE := 0.00713

var _a := PackedVector3Array()
var _b := PackedVector3Array()
var _c := PackedVector3Array()
var _n := PackedVector3Array()
var _ylo := PackedFloat32Array()
var _yhi := PackedFloat32Array()
var _klo := PackedFloat32Array()
var _khi := PackedFloat32Array()
var _bins: Dictionary = {}
var _key := Vector3.ZERO
var _cols: Array = []
var _t: RefCounted


func _initialize() -> void:
	_t = TestReport.new("plan_collision_test")
	var plan := _load(FIXTURE)
	if not _t.check("fixture parses as a structure plan", plan != null and plan.walls.size() == 6):
		_t.finish(self)
		return
	_gather(plan)
	_t.check("bake produced triangles", _a.size() > 0)
	_t.equal("one collider per wall panel", _cols.size(), 6)

	for wall_variant in plan.walls:
		_check_wall(wall_variant as Dictionary)

	## Oblique coverage: axis-aligned rays cross every diagonal at 45 degrees,
	## which is the direction a perpendicular sweep can never look from.
	_global_sweep("+X across the whole fixture", Vector3.RIGHT, Vector3.BACK, -6.0, 7.0, 0.05)
	_global_sweep("+Z across the whole fixture", Vector3.BACK, Vector3.RIGHT, -2.0, 107.0, 0.05)

	_t.finish(self)


func _load(path: String) -> StructurePlan:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary) or not StructurePlan.is_plan(data as Dictionary):
		return null
	return StructurePlan.from_dict(data as Dictionary)


# ── Ground truth: the triangle soup bake() draws ─────────────────────────────

func _gather(plan: StructurePlan) -> void:
	_a.clear(); _b.clear(); _c.clear(); _n.clear(); _ylo.clear(); _yhi.clear()
	var root := StructureBaker.bake(plan)
	for child in root.get_children():
		var mesh := (child as MeshInstance3D).mesh as ArrayMesh
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms_v: Variant = arrays[Mesh.ARRAY_NORMAL]
			var idx_v: Variant = arrays[Mesh.ARRAY_INDEX]
			var norms := PackedVector3Array() if norms_v == null else (norms_v as PackedVector3Array)
			var idx := PackedInt32Array() if idx_v == null else (idx_v as PackedInt32Array)
			var indexed := idx.size() > 0
			var count := idx.size() if indexed else verts.size()
			var i := 0
			while i + 2 < count:
				var i0 := idx[i] if indexed else i
				var i1 := idx[i + 1] if indexed else i + 1
				var i2 := idx[i + 2] if indexed else i + 2
				var p0 := verts[i0]
				var p1 := verts[i1]
				var p2 := verts[i2]
				var nrm := Vector3.ZERO
				if norms.size() > i0:
					nrm = norms[i0]
				if nrm.length_squared() < 0.5:
					nrm = (p1 - p0).cross(p2 - p0).normalized()
				_a.append(p0); _b.append(p1); _c.append(p2); _n.append(nrm)
				_ylo.append(minf(p0.y, minf(p1.y, p2.y)))
				_yhi.append(maxf(p0.y, maxf(p1.y, p2.y)))
				i += 3
	root.free()
	_cols.clear()
	for box_variant in StructureBaker.collect_colliders(plan):
		var box := box_variant as Dictionary
		_cols.append({
			"center": box["center"] as Vector3,
			"size": box["size"] as Vector3,
			"yaw": float(box.get("yaw_deg", 0.0)),
		})


## Bins triangles by their extent along `key` — the horizontal coordinate that
## stays CONSTANT along every ray of the family about to be swept. Passing the
## ray direction here silently empties every bucket.
func _prep(key: Vector3) -> void:
	_key = key
	_klo.clear(); _khi.clear()
	_bins.clear()
	for i in _a.size():
		var lo := minf(_a[i].dot(key), minf(_b[i].dot(key), _c[i].dot(key)))
		var hi := maxf(_a[i].dot(key), maxf(_b[i].dot(key), _c[i].dot(key)))
		_klo.append(lo)
		_khi.append(hi)
		for bucket in range(int(floor(lo / BIN)), int(floor(hi / BIN)) + 1):
			if not _bins.has(bucket):
				_bins[bucket] = PackedInt32Array()
			var arr: PackedInt32Array = _bins[bucket]
			arr.append(i)
			_bins[bucket] = arr


## Signed crossings along the ray -> the intervals where winding >= 1.
func _rendered(o: Vector3, d: Vector3) -> Array:
	var k := o.dot(_key)
	var bucket_v: Variant = _bins.get(int(floor(k / BIN)), null)
	if bucket_v == null:
		return []
	var bucket: PackedInt32Array = bucket_v
	var hits: Array = []
	var y := o.y
	for i in bucket:
		if y < _ylo[i] - 0.0001 or y > _yhi[i] + 0.0001:
			continue
		if k < _klo[i] - 0.0001 or k > _khi[i] + 0.0001:
			continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(o, d, _a[i], _b[i], _c[i])
		if hit == null:
			continue
		var facing := d.dot(_n[i])
		if absf(facing) < 1e-9:
			continue
		hits.append([((hit as Vector3) - o).dot(d), -1 if facing > 0.0 else 1])
	hits.sort_custom(func(x, y2): return float(x[0]) < float(y2[0]))
	var out: Array = []
	var winding := 0
	var start := 0.0
	for entry_variant in hits:
		var entry := entry_variant as Array
		var previous := winding
		winding += int(entry[1])
		if previous < 1 and winding >= 1:
			start = float(entry[0])
		elif previous >= 1 and winding < 1:
			out.append([start, float(entry[0])])
	return _merge(out)


# ── The colliders, read exactly as a consumer must read them ─────────────────

func _box_interval(o: Vector3, d: Vector3, col: Dictionary) -> Array:
	var inv := Basis(Vector3.UP, deg_to_rad(float(col["yaw"]))).transposed()
	var local := inv * (o - (col["center"] as Vector3))
	var dir := inv * d
	var half := (col["size"] as Vector3) * 0.5
	var t0 := -1e18
	var t1 := 1e18
	for axis in 3:
		if absf(dir[axis]) < 1e-9:
			if local[axis] < -half[axis] or local[axis] > half[axis]:
				return []
			continue
		var ta := (-half[axis] - local[axis]) / dir[axis]
		var tb := (half[axis] - local[axis]) / dir[axis]
		if ta > tb:
			var swap := ta; ta = tb; tb = swap
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return []
	return [t0, t1]


func _collided(o: Vector3, d: Vector3) -> Array:
	var out: Array = []
	for col_variant in _cols:
		var interval := _box_interval(o, d, col_variant as Dictionary)
		if not interval.is_empty() and float(interval[1]) - float(interval[0]) > 1e-9:
			out.append(interval)
	return _merge(out)


## Signed distance from a point to the collider UNION (negative inside). This is
## the number that matters: it says how DEEP into un-collided space a run of
## drawn material sits, so a graze along the render skin cannot masquerade as a
## hole the player walks through.
func _sd_union(p: Vector3) -> float:
	var best := 1e18
	for col_variant in _cols:
		var col := col_variant as Dictionary
		var inv := Basis(Vector3.UP, deg_to_rad(float(col["yaw"]))).transposed()
		var q := (inv * (p - (col["center"] as Vector3))).abs() - (col["size"] as Vector3) * 0.5
		var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
		best = minf(best, outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0))
	return best


func _merge(intervals: Array) -> Array:
	if intervals.is_empty():
		return []
	intervals.sort_custom(func(x, y): return float((x as Array)[0]) < float((y as Array)[0]))
	var out: Array = []
	var current := [float((intervals[0] as Array)[0]), float((intervals[0] as Array)[1])]
	for i in range(1, intervals.size()):
		var interval := intervals[i] as Array
		if float(interval[0]) <= current[1] + 1e-7:
			current[1] = maxf(current[1], float(interval[1]))
		else:
			out.append(current)
			current = [float(interval[0]), float(interval[1])]
	out.append(current)
	return out


## Every run of `a` that no interval of `b` covers, as [start_t, length].
func _holes(a: Array, b: Array) -> Array:
	var out: Array = []
	for interval_variant in a:
		var interval := interval_variant as Array
		var t := float(interval[0])
		var end := float(interval[1])
		if end - t < SLIVER:
			continue
		for cover_variant in b:
			var cover := cover_variant as Array
			var c0 := float(cover[0]) - TOL
			var c1 := float(cover[1]) + TOL
			if c1 <= t:
				continue
			if c0 >= end:
				break
			if c0 > t:
				out.append([t, c0 - t])
			t = maxf(t, c1)
			if t >= end:
				break
		if t < end:
			out.append([t, end - t])
	return out


# ── Sweeps ───────────────────────────────────────────────────────────────────

## Clips intervals to [lo, hi] along the ray. A per-wall sweep uses this to see
## ONE wall: the rays are infinite, so without it a family aimed at the z-wall
## also crosses two diagonals further down the fixture and reports their defects
## under the wrong axis's name.
func _clip(intervals: Array, lo: float, hi: float) -> Array:
	var out: Array = []
	for interval_variant in intervals:
		var interval := interval_variant as Array
		var a := maxf(float(interval[0]), lo)
		var b := minf(float(interval[1]), hi)
		if b - a > 1e-9:
			out.append([a, b])
	return out


## Returns {rays_hit, rendered, deepest, deepest_at, uncovered, over_limit,
## phantom_deepest, phantom}. `key` must be horizontal and PERPENDICULAR to `dir`.
## `window` bounds how far either side of the aim point at t == RAY_START the
## sweep looks; INF means the whole ray.
func _sweep(key: Vector3, dir: Vector3, rays: Array, window := INF) -> Dictionary:
	var lo := -INF if window == INF else RAY_START - window
	var hi := INF if window == INF else RAY_START + window
	_prep(key)
	var result := {
		"rays_hit": 0, "rendered": 0.0, "deepest": 0.0, "deepest_at": Vector3.ZERO,
		"uncovered": 0.0, "over_limit": 0, "phantom": 0.0, "phantom_deepest": 0.0,
		"phantom_at": Vector3.ZERO,
	}
	for ray_variant in rays:
		var o := ray_variant as Vector3
		var solid := _clip(_rendered(o, dir), lo, hi)
		if solid.is_empty():
			continue
		result["rays_hit"] = int(result["rays_hit"]) + 1
		var collided := _clip(_collided(o, dir), lo, hi)
		for interval_variant in solid:
			var interval := interval_variant as Array
			result["rendered"] = float(result["rendered"]) + float(interval[1]) - float(interval[0])
		for hole_variant in _holes(solid, collided):
			var hole := hole_variant as Array
			var length := float(hole[1])
			result["uncovered"] = float(result["uncovered"]) + length
			var deepest := 0.0
			var deepest_at := Vector3.ZERO
			for s in 9:
				var p := o + dir * (float(hole[0]) + length * (float(s) + 0.5) / 9.0)
				var sd := _sd_union(p)
				if sd > deepest:
					deepest = sd
					deepest_at = p
			if deepest > DEEP_LIMIT:
				result["over_limit"] = int(result["over_limit"]) + 1
			if deepest > float(result["deepest"]):
				result["deepest"] = deepest
				result["deepest_at"] = deepest_at
		## The mirror defect: a collider standing where nothing is drawn. Depth
		## here is measured out of the rendered solid, by how far the phantom run
		## reaches beyond the nearest drawn surface along the ray.
		for ghost_variant in _holes(collided, solid):
			var ghost := ghost_variant as Array
			result["phantom"] = float(result["phantom"]) + float(ghost[1])
			if float(ghost[1]) > float(result["phantom_deepest"]):
				result["phantom_deepest"] = float(ghost[1])
				result["phantom_at"] = o + dir * float(ghost[0])
	return result


func _report(label: String, sweep: Dictionary) -> void:
	print("  [%s] rays_hit=%d rendered=%.3fm | uncovered=%.4fm deepest=%.4fm at %s (runs over %.2fm: %d) | phantom=%.4fm deepest=%.4fm"
		% [label, int(sweep["rays_hit"]), float(sweep["rendered"]), float(sweep["uncovered"]),
			float(sweep["deepest"]), str(sweep["deepest_at"]), DEEP_LIMIT, int(sweep["over_limit"]),
			float(sweep["phantom"]), float(sweep["phantom_deepest"])])


func _assert_sweep(label: String, sweep: Dictionary, min_rendered: float) -> void:
	_report(label, sweep)
	## Without this the whole sweep is a false green: a family of rays that hits
	## nothing has no holes either.
	_t.check("%s: the sweep actually crossed drawn material (%.3f m >= %.3f m)"
		% [label, float(sweep["rendered"]), min_rendered], float(sweep["rendered"]) >= min_rendered)
	_t.check("%s: no drawn material sits deeper than %.2f m into un-collided space (deepest %.4f m at %s)"
		% [label, DEEP_LIMIT, float(sweep["deepest"]), str(sweep["deepest_at"])],
		float(sweep["deepest"]) <= DEEP_LIMIT)
	_t.equal("%s: zero uncovered runs over the depth limit" % label, int(sweep["over_limit"]), 0)
	_t.check("%s: no run of collider longer than %.2f m has nothing drawn in it (worst %.4f m at %s)"
		% [label, PHANTOM_LIMIT, float(sweep["phantom_deepest"]), str(sweep["phantom_at"])],
		float(sweep["phantom_deepest"]) <= PHANTOM_LIMIT)


# ── Per-wall checks ──────────────────────────────────────────────────────────

## The yaw the PLAN's run direction demands, derived from StructurePlan.wall_run
## rather than from the baker's own wall_yaw_deg. A +Y rotation of theta takes
## +X to (cos theta, 0, -sin theta).
func _plan_yaw(axis: String) -> float:
	if not StructurePlan.is_diagonal_axis(axis):
		return 0.0
	var run := StructurePlan.wall_run(axis)
	return rad_to_deg(atan2(-run.z, run.x))


func _check_wall(wall: Dictionary) -> void:
	var axis := str(wall.get("axis", "x"))
	var start := StructurePlan.vec3_of(wall.get("start"))
	var length := float(wall.get("length", 1.0))
	var height := float(wall.get("height", 3.0))
	var thickness := float(wall.get("thickness", 0.1667))
	var run := StructurePlan.wall_run(axis)
	var perp := Vector3(-run.z, 0.0, run.x)
	var centre := start + run * (length * 0.5) + Vector3(0.0, height * 0.5, 0.0)
	print("wall axis=%s start=%s" % [axis, str(start)])

	## 1. The drawn geometry really lies along the plan's run. Measured off the
	## triangle soup, so a bake() that quietly went axis-aligned to make the
	## volume sweep agree with a yaw-0 collider still turns this red.
	var along := _soup_extent(centre, run, maxf(length, thickness) + 1.0)
	var across := _soup_extent(centre, perp, maxf(length, thickness) + 1.0)
	_t.near("%s: drawn extent ALONG the run is the wall length" % axis, along, length, 0.02)
	_t.near("%s: drawn extent ACROSS the run is thickness + 2 skins" % axis,
		across, thickness + 2.0 * SKIN_EPS, 0.02)

	## 2. A collider exists on this wall, with the plan's yaw and the plan's
	## extents measured in its own rotated frame.
	var col := _collider_at(centre)
	if not _t.check("%s: a collider is centred on the wall at %s" % [axis, str(centre)], not col.is_empty()):
		return
	_t.near("%s: collider yaw matches the plan's run direction" % axis, float(col["yaw"]), _plan_yaw(axis), 0.001)
	var size := col["size"] as Vector3
	var expected_size := Vector3(thickness, height, length) if axis == "z" else Vector3(length, height, thickness)
	_t.check("%s: collider extents are %s in its own frame (got %s)" % [axis, str(expected_size), str(size)],
		size.is_equal_approx(expected_size))

	## 3. The volume test. Rays square to the run, marched along it: for a
	## diagonal these are the rays an axis-aligned collider cannot cover.
	var rays: Array = []
	var heights := [0.0531, 0.3517, 0.6523, 0.9213, 1.1431]
	var u := 0.06 + NUDGE
	while u <= length - 0.06:
		var on_run := start + run * u
		for h_variant in heights:
			rays.append(Vector3(on_run.x, float(h_variant), on_run.z) - perp * RAY_START)
		u += 0.05
	## Every ray crosses one wall of `thickness`; demand 90% of them land.
	var expected_rendered := float(rays.size()) * (thickness + 2.0 * SKIN_EPS) * 0.9
	## 1.5 m window: wide enough to hold the whole 0.32 m drawn thickness and the
	## axis-aligned box a yaw-0 collider would put there, narrow enough that no
	## other wall in the fixture is inside it.
	_assert_sweep("%s square to the run" % axis, _sweep(run, perp, rays, 1.5), expected_rendered)


## Widest extent of the drawn soup along `dir`, over triangles within `radius`
## of `centre` — i.e. the drawn footprint of one wall, from the mesh alone.
func _soup_extent(centre: Vector3, dir: Vector3, radius: float) -> float:
	var lo := 1e18
	var hi := -1e18
	for i in _a.size():
		for p in [_a[i], _b[i], _c[i]]:
			var point := p as Vector3
			if point.distance_to(centre) > radius:
				continue
			var d := (point - centre).dot(dir)
			lo = minf(lo, d)
			hi = maxf(hi, d)
	return 0.0 if hi < lo else hi - lo


func _collider_at(centre: Vector3) -> Dictionary:
	for col_variant in _cols:
		var col := col_variant as Dictionary
		if (col["center"] as Vector3).distance_to(centre) < 0.0001:
			return col
	return {}


func _global_sweep(label: String, dir: Vector3, key: Vector3, from: float, to: float, step: float) -> void:
	var rays: Array = []
	var heights := [0.0531, 0.3517, 0.6523, 0.9213, 1.1431]
	var c := from + NUDGE
	while c <= to:
		for h_variant in heights:
			rays.append((key * c) + Vector3(0.0, float(h_variant), 0.0) - dir * RAY_START)
		c += step
	## Loose floor: this family sweeps mostly empty space, so it is calibrated
	## only to catch a sweep that has stopped seeing the fixture at all.
	_assert_sweep(label, _sweep(key, dir, rays), 20.0)
