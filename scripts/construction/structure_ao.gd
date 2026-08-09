class_name StructureAO
extends RefCounted

## Bake-time ambient occlusion for StructurePlan geometry, written into vertex
## COLOUR. No texture, no extra material, no extra surface, no extra draw call:
## the occlusion rides in the vertex stream of the surfaces the baker already
## emits, so a plan that bakes to 4 MeshInstance3D still bakes to 4.
##
## WHY THIS EXISTS. Every face of every box is uniformly lit, which is the main
## reason these vessels read as stacked cardboard. Corners, wall/deck junctions,
## the inside of a bulwark and the underside of an overhang all want to be
## darker than an open face, and none of that survives a flat albedo.
##
## WHAT CARRIES OVER FROM VesselSkinBaker (the retired voxel skin baker):
##  - the idea and the shape of the answer: per-vertex greyscale in vertex
##    colour, with the material flag `vertex_color_use_as_albedo = true` doing
##    the multiply. That flag is the whole runtime cost.
##  - the darkness ladder: its AO_LEVELS ran 1.0 -> 0.58 over four steps, so
##    MIN_AO here (0.42 at full strength, ~0.6 at typical junctions) sits in the
##    same range rather than inventing a new one.
##  - "occlusion is a neighbourhood query": its _corner_ao asked whether the two
##    edge cells and the diagonal cell touching a face corner were solid.
## WHAT DOES NOT CARRY OVER: everything that assumed a voxel grid. Its query was
## `solid.has(cell + dir)` — an O(1) lookup into a uniform lattice of equal
## cubes. StructurePlan has no lattice: it draws arbitrary oriented boxes of
## arbitrary size (a 30 m deck plate and a 0.1 m door jamb in the same plan), so
## "the neighbouring cell" is not a thing that exists. The generalisation kept
## is the *kernel*: sample a short-range hemisphere above the surface point and
## ask how much of it is inside solid geometry.
##
## THE SOLVER. Pure function of the box set: same boxes in, same floats out.
## No randomness, no jitter, no iteration over hash order.
##  - Occluders are oriented boxes {center, size, yaw_deg|basis} — exactly the
##    shape `StructureBaker.collect_colliders()` returns, which is the solid
##    mass of the plan (full-thickness walls, no proud opening frames).
##  - For a surface point p with outward normal n, 9 directions spanning the
##    hemisphere about n are probed at two shells (near, far). A near hit counts
##    full, a far hit counts partial, a miss counts nothing. The weighted sum
##    over the kernel is the occlusion in [0,1].
##  - Directions all keep a positive n component, so a box lying FLUSH beside
##    this one in the same plane (two wall panels either side of a door) never
##    occludes it. Only geometry standing off the surface does. That is the
##    difference between "concave junctions darken" and "everything darkens".
##  - A downward-facing normal picks up DOWNFACE_BIAS on top of the geometric
##    term. This one is not geometric occlusion, it is sky occlusion: ambient
##    light in this game arrives overwhelmingly from above, so an underside is
##    dark even with nothing under it. It is what makes an overhang read as an
##    overhang from below and a box read as a solid instead of a cutout.
##
## COST. Broad phase is a uniform hash grid of cell = 2 * radius, so a query
## touches at most 8 cells and tests a handful of boxes. Candidate lists and AO
## values are memoised per point, so a corner shared by three faces is solved
## once. Bake-time only; the studio re-bakes on every edit, so see stats().
##
## TESSELLATION. Vertex AO on an untessellated box is a lie at plan scale: a
## 30 m deck plate has four vertices per face, so a shadow at one corner ramps
## linearly across thirty metres. append_box() therefore splits each face into a
## grid of about TESSEL metres before shading it. Triangle count rises; surface
## count, material count and draw calls do not.
##
## HOW THE BAKER CALLS THIS (later wave — structure_baker.gd is not touched by
## this file). Three edits, in `StructureBaker`:
##
##   1. In `bake()`, once, before the bucket walk:
##          var ao := StructureAO.for_plan(plan, offset)
##      (or `StructureAO.from_boxes(StructureBaker.collect_colliders(plan, offset))`
##      if the collider list is already in hand.)
##
##   2. Thread it through `_bucket_layer(buckets, layer, offset, ao)` and swap
##      the geometry emitter — `_append_box` becomes:
##          ao.append_box(st, center + offset, size, basis)
##      `append_box` reproduces `_append_box`'s clockwise-front winding and flat
##      per-face normals exactly; it adds a vertex colour and, for faces larger
##      than TESSEL, more triangles. It must REPLACE `_append_box` rather than
##      run beside it: SurfaceTool fixes the vertex format from the first
##      vertex, so a surface fed by both emitters loses the colour channel.
##
##   3. In the bucket commit loop, the material must consume the colour:
##          material.vertex_color_use_as_albedo = true
##      Without it the vertex colours are carried and ignored, and the bake
##      looks exactly as flat as before. (Leave it OFF for `ghost` — an unshaded
##      x-ray does not want baked shadows.)
##
## `for_plan` is the only entry point that knows about StructurePlan; the solver
## itself takes a plain Array of box dictionaries, so DeckFitout, a headless
## service or a test can feed it anything box-shaped.

## Neighbourhood the kernel can see, in metres. One world unit is one metre
## (CONVENTIONS.md 3a), so this is a ~0.75 m contact shadow: wide enough to
## read a wall/deck junction from across a deck, tight enough that a doorway
## does not smear.
const RADIUS := 0.75
## Darkest the geometric term may push a vertex: ao = 1 - STRENGTH * occlusion.
const STRENGTH := 0.62
const MIN_AO := 0.42
## Extra occlusion for a straight-down normal (sky occlusion, see above).
const DOWNFACE_BIAS := 0.30
## Target edge length for face subdivision, metres.
const TESSEL := 1.0
## Hard cap on splits per face axis — bounds the triangle count of a 40 m plate.
const MAX_SPLIT := 12
## Probe shells as a fraction of RADIUS, and what a hit at each is worth.
const NEAR_SHELL := 0.36
const FAR_SHELL := 0.85
const NEAR_HIT := 1.0
const FAR_HIT := 0.45

## Hemisphere kernel as (n, t1, t2) coefficients plus a weight; each direction
## is normalised at build time. Every entry has a positive n coefficient — see
## the flush-neighbour note above. The ring at 45 degrees carries the most
## weight because that is where a perpendicular neighbour lives.
const KERNEL := [
	[1.0, 0.0, 0.0, 0.60],
	[1.0, 1.0, 0.0, 1.00],
	[1.0, -1.0, 0.0, 1.00],
	[1.0, 0.0, 1.0, 1.00],
	[1.0, 0.0, -1.0, 1.00],
	[1.0, 1.0, 1.0, 0.75],
	[1.0, 1.0, -1.0, 0.75],
	[1.0, -1.0, 1.0, 0.75],
	[1.0, -1.0, -1.0, 0.75],
]

var _radius := RADIUS
var _cell := RADIUS * 2.0
var _near := RADIUS * NEAR_SHELL
var _far := RADIUS * FAR_SHELL
var _kernel_weight := 1.0

var _count := 0
var _cen := PackedVector3Array()
var _half := PackedVector3Array()
var _bmin := PackedVector3Array()
var _bmax := PackedVector3Array()
var _cos := PackedFloat32Array()
var _sin := PackedFloat32Array()
var _rot := PackedByteArray()
var _grid := {} ## Vector3i -> PackedInt32Array of box indices

var _stamp := PackedInt32Array()
var _query_id := 0
var _cand_memo := {} ## snapped Vector3 -> PackedInt32Array
var _ao_memo := {} ## snapped Vector3 -> Dictionary(Vector3 normal -> float)
var _dirs := {} ## Vector3 normal -> [PackedFloat32Array x, y, z] of probe offsets
var _weights := PackedFloat32Array()
var _probes := 0 ## KERNEL.size() * 2 — near and far shell per direction
var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _queries := 0
var _solved := 0

## Memo keys are snapped to a tenth of a millimetre so the corner a box shares
## with two other faces is one key, not three: the same corner reached by
## interpolating a face lattice and by `center + basis * half` differs in the
## last float bit. Snapping is only ever applied to the KEY — emitted vertex
## positions stay exactly where the baker put them.
const MEMO_SNAP := Vector3(0.0001, 0.0001, 0.0001)


# ── Construction ─────────────────────────────────────────────────────────────

## `boxes` entries are {center: Vector3, size: Vector3} plus EITHER
## `yaw_deg: float` (collider shape) OR `basis: Basis` (layer shape). Any other
## key is ignored, so a collider list and a layer list are both accepted as-is.
static func from_boxes(boxes: Array, radius := RADIUS) -> StructureAO:
	var solver := StructureAO.new()
	solver._build(boxes, radius)
	return solver


## Occluders = the plan's solid mass, in the same space the baker emits into.
## Pass the SAME offset the bake uses or every shadow lands somewhere else.
static func for_plan(plan: StructurePlan, offset := Vector3.ZERO, radius := RADIUS) -> StructureAO:
	return from_boxes(StructureBaker.collect_colliders(plan, offset), radius)


func _build(boxes: Array, radius: float) -> void:
	_radius = maxf(radius, 0.01)
	_cell = _radius * 2.0
	_near = _radius * NEAR_SHELL
	_far = _radius * FAR_SHELL
	_kernel_weight = 0.0
	_weights.resize(KERNEL.size())
	for k in KERNEL.size():
		var weight := float((KERNEL[k] as Array)[3])
		_weights[k] = weight
		_kernel_weight += weight
	_probes = KERNEL.size() * 2
	_px.resize(_probes)
	_py.resize(_probes)
	_pz.resize(_probes)
	_count = boxes.size()
	_cen.resize(_count)
	_half.resize(_count)
	_bmin.resize(_count)
	_bmax.resize(_count)
	_cos.resize(_count)
	_sin.resize(_count)
	_rot.resize(_count)
	_stamp.resize(_count)
	for index in _count:
		var box := boxes[index] as Dictionary
		var center: Vector3 = box.get("center", Vector3.ZERO)
		var size: Vector3 = box.get("size", Vector3.ONE)
		var half := size.abs() * 0.5
		var yaw := 0.0
		if box.has("basis"):
			## Basis(Vector3.UP, t) has third column (sin t, 0, cos t).
			var basis := box["basis"] as Basis
			yaw = atan2(basis.z.x, basis.z.z)
		else:
			yaw = deg_to_rad(float(box.get("yaw_deg", 0.0)))
		var cs := cos(yaw)
		var sn := sin(yaw)
		_cen[index] = center
		_half[index] = half
		_cos[index] = cs
		_sin[index] = sn
		_rot[index] = 1 if absf(sn) > 1e-6 else 0
		## World extent of a Y-rotated box.
		var ex := absf(cs) * half.x + absf(sn) * half.z
		var ez := absf(sn) * half.x + absf(cs) * half.z
		var extent := Vector3(ex, half.y, ez)
		_bmin[index] = center - extent
		_bmax[index] = center + extent
		_stamp[index] = -1
	_build_grid()


func _build_grid() -> void:
	_grid.clear()
	## Accumulate into Arrays, not PackedInt32Arrays: a Packed*Array is a VALUE
	## type, so `(_grid[key] as PackedInt32Array).append(i)` appends to a copy
	## and throws it away — which silently leaves one box per cell and turns the
	## whole solver into "nothing occludes anything".
	var scratch := {}
	for index in _count:
		var lo := _bmin[index]
		var hi := _bmax[index]
		var x0 := floori(lo.x / _cell)
		var x1 := floori(hi.x / _cell)
		var y0 := floori(lo.y / _cell)
		var y1 := floori(hi.y / _cell)
		var z0 := floori(lo.z / _cell)
		var z1 := floori(hi.z / _cell)
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				for cz in range(z0, z1 + 1):
					var key := Vector3i(cx, cy, cz)
					if scratch.has(key):
						(scratch[key] as Array).append(index)
					else:
						scratch[key] = [index]
	for key in scratch.keys():
		_grid[key] = PackedInt32Array(scratch[key] as Array)


# ── Queries ──────────────────────────────────────────────────────────────────

## Raw occlusion in [0,1] at a surface point: 0 = fully open, 1 = fully buried.
## This is the number to assert on — `vertex_ao` is just its remap.
func occlusion_at(point: Vector3, normal: Vector3) -> float:
	_queries += 1
	var key := point.snapped(MEMO_SNAP)
	var by_normal: Variant = _ao_memo.get(key, null)
	if by_normal == null:
		var first := _solve(point, normal)
		_ao_memo[key] = {normal: first}
		return first
	var cached := by_normal as Dictionary
	if cached.has(normal):
		return float(cached[normal])
	var value := _solve(point, normal)
	cached[normal] = value
	return value


## Vertex colour multiplier in [MIN_AO, 1]. 1 = untouched albedo.
func vertex_ao(point: Vector3, normal: Vector3) -> float:
	return maxf(1.0 - STRENGTH * occlusion_at(point, normal), MIN_AO)


func _solve(point: Vector3, normal: Vector3) -> float:
	_solved += 1
	var n := normal.normalized()
	if n.length_squared() < 0.5:
		n = Vector3.UP
	var candidates := _candidates(point)
	var occ := 0.0
	if candidates.size() > 0:
		var offsets := _offsets_for(n)
		var hit := 0.0
		for k in KERNEL.size():
			var weight := float((KERNEL[k] as Array)[3])
			if _inside_any(point + offsets[k * 2], candidates):
				hit += weight * NEAR_HIT
			elif _inside_any(point + offsets[k * 2 + 1], candidates):
				hit += weight * FAR_HIT
		occ = hit / _kernel_weight
	## Sky term: ambient arrives from above, so a downward face is dark even in
	## open air. Purely a function of the normal — it cannot mask the geometric
	## term, only add to it.
	occ += DOWNFACE_BIAS * maxf(-n.y, 0.0)
	return clampf(occ, 0.0, 1.0)


## Probe offsets (near, far) per kernel entry for one normal, built once. A
## plan's faces are axis-aligned apart from the diagonal walls, so this caches
## down to a handful of entries and takes the trig out of the inner loop.
func _offsets_for(n: Vector3) -> PackedVector3Array:
	var cached: Variant = _dirs.get(n, null)
	if cached != null:
		return cached as PackedVector3Array
	## Deterministic tangent frame. The kernel is symmetric in +/-t1 and +/-t2,
	## so which way the frame lands only ever rotates the sample set within the
	## plane — it never changes an axis-aligned result.
	var helper := Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD
	var t1 := n.cross(helper).normalized()
	var t2 := n.cross(t1).normalized()
	var offsets := PackedVector3Array()
	offsets.resize(KERNEL.size() * 2)
	for k in KERNEL.size():
		var entry := KERNEL[k] as Array
		var dir := (n * float(entry[0]) + t1 * float(entry[1]) + t2 * float(entry[2])).normalized()
		offsets[k * 2] = dir * _near
		offsets[k * 2 + 1] = dir * _far
	_dirs[n] = offsets
	return offsets


func _inside_any(p: Vector3, candidates: PackedInt32Array) -> bool:
	for index in candidates:
		if _rot[index] == 0:
			var lo := _bmin[index]
			if p.x < lo.x or p.y < lo.y or p.z < lo.z:
				continue
			var hi := _bmax[index]
			if p.x > hi.x or p.y > hi.y or p.z > hi.z:
				continue
			return true
		else:
			var d := p - _cen[index]
			var h := _half[index]
			if absf(d.y) > h.y:
				continue
			var cs := _cos[index]
			var sn := _sin[index]
			if absf(cs * d.x - sn * d.z) > h.x:
				continue
			if absf(sn * d.x + cs * d.z) > h.z:
				continue
			return true
	return false


## Box indices whose AABB could reach within RADIUS of `point`. Memoised: a box
## corner is shared by three faces and a tessellation vertex by four quads.
func _candidates(point: Vector3) -> PackedInt32Array:
	var memo_key := point.snapped(MEMO_SNAP)
	var cached: Variant = _cand_memo.get(memo_key, null)
	if cached != null:
		return cached as PackedInt32Array
	_query_id += 1
	var out := PackedInt32Array()
	var lo := point - Vector3(_radius, _radius, _radius)
	var hi := point + Vector3(_radius, _radius, _radius)
	var x0 := floori(lo.x / _cell)
	var x1 := floori(hi.x / _cell)
	var y0 := floori(lo.y / _cell)
	var y1 := floori(hi.y / _cell)
	var z0 := floori(lo.z / _cell)
	var z1 := floori(hi.z / _cell)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			for cz in range(z0, z1 + 1):
				var bucket: Variant = _grid.get(Vector3i(cx, cy, cz), null)
				if bucket == null:
					continue
				for index in bucket as PackedInt32Array:
					if _stamp[index] == _query_id:
						continue
					_stamp[index] = _query_id
					var bl := _bmin[index]
					if bl.x > hi.x or bl.y > hi.y or bl.z > hi.z:
						continue
					var bh := _bmax[index]
					if bh.x < lo.x or bh.y < lo.y or bh.z < lo.z:
						continue
					out.append(index)
	_cand_memo[memo_key] = out
	return out


# ── Geometry emission ────────────────────────────────────────────────────────

## Drop-in replacement for `StructureBaker._append_box` that carries AO in the
## vertex colour and subdivides faces longer than TESSEL so the occlusion has
## somewhere to live. Same clockwise-front winding, same flat per-face normals,
## same `basis`-about-own-centre convention. Returns the triangle count emitted.
func append_box(st: SurfaceTool, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> int:
	var h := size * 0.5
	var corners := [
		center + basis * Vector3(-h.x, -h.y, -h.z), center + basis * Vector3(h.x, -h.y, -h.z),
		center + basis * Vector3(h.x, -h.y, h.z), center + basis * Vector3(-h.x, -h.y, h.z),
		center + basis * Vector3(-h.x, h.y, -h.z), center + basis * Vector3(h.x, h.y, -h.z),
		center + basis * Vector3(h.x, h.y, h.z), center + basis * Vector3(-h.x, h.y, h.z),
	]
	## Identical face table and vertex order to StructureBaker._append_box.
	var faces := [
		[[0, 1, 5, 4], Vector3(0, 0, -1)],
		[[2, 3, 7, 6], Vector3(0, 0, 1)],
		[[1, 2, 6, 5], Vector3(1, 0, 0)],
		[[3, 0, 4, 7], Vector3(-1, 0, 0)],
		[[4, 5, 6, 7], Vector3(0, 1, 0)],
		[[3, 2, 1, 0], Vector3(0, -1, 0)],
	]
	var triangles := 0
	for face in faces:
		var idx: Array = face[0]
		var normal: Vector3 = basis * (face[1] as Vector3)
		triangles += _emit_face(
			st,
			corners[idx[0]] as Vector3,
			corners[idx[1]] as Vector3,
			corners[idx[3]] as Vector3,
			normal,
		)
	return triangles


## One rectangular face given its origin corner `a`, the corner reached along
## the first edge `b`, and the corner reached along the second edge `d`. The
## quad a->b->c->d is wound exactly as _append_box wound [i0,i1,i2,i3].
func _emit_face(st: SurfaceTool, a: Vector3, b: Vector3, d: Vector3, normal: Vector3) -> int:
	var edge_u := b - a
	var edge_v := d - a
	var nu := clampi(int(ceilf(edge_u.length() / TESSEL)), 1, MAX_SPLIT)
	var nv := clampi(int(ceilf(edge_v.length() / TESSEL)), 1, MAX_SPLIT)
	## Build the lattice once, shade it once: an interior vertex is shared by
	## four quads and every quad must reuse the same position AND the same
	## shade, or the surface cracks and the shading stipples.
	var stride := nv + 1
	var lattice := PackedVector3Array()
	var shade := PackedFloat32Array()
	lattice.resize((nu + 1) * stride)
	shade.resize((nu + 1) * stride)
	for iu in nu + 1:
		var su := float(iu) / float(nu)
		var along_u := a + edge_u * su
		for iv in stride:
			var point := along_u + edge_v * (float(iv) / float(nv))
			lattice[iu * stride + iv] = point
			shade[iu * stride + iv] = vertex_ao(point, normal)
	for iu in nu:
		for iv in nv:
			var i00 := iu * stride + iv
			var i10 := (iu + 1) * stride + iv
			var i11 := i10 + 1
			var i01 := i00 + 1
			_vertex(st, normal, lattice[i00], shade[i00])
			_vertex(st, normal, lattice[i10], shade[i10])
			_vertex(st, normal, lattice[i11], shade[i11])
			_vertex(st, normal, lattice[i00], shade[i00])
			_vertex(st, normal, lattice[i11], shade[i11])
			_vertex(st, normal, lattice[i01], shade[i01])
	return nu * nv * 2


func _vertex(st: SurfaceTool, normal: Vector3, point: Vector3, shade: float) -> void:
	st.set_normal(normal)
	st.set_color(Color(shade, shade, shade))
	st.add_vertex(point)


# ── Introspection ────────────────────────────────────────────────────────────

## Bake-time budget evidence. `solved` is the number of kernel evaluations that
## actually ran; `queries - solved` is what the memo saved.
func stats() -> Dictionary:
	return {
		"boxes": _count,
		"cells": _grid.size(),
		"radius": _radius,
		"queries": _queries,
		"solved": _solved,
		"memo_points": _cand_memo.size(),
	}
