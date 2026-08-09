class_name StructureAO
extends RefCounted

## Bake-time ambient occlusion for StructurePlan geometry, multiplied into the
## vertex COLOUR the baker already writes. No texture, no extra material, no
## extra surface, no extra draw call: the occlusion rides in the vertex stream
## of the surfaces the bake emits anyway, so a plan that bakes to N
## MeshInstance3D still bakes to N.
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
## COST. Broad phase is a uniform hash grid of CELL_FACTOR * radius, so a query
## touches at most 8 cells. Each candidate is then rejected against the probe
## cloud's own bounding box before any point test runs. Candidate lists and AO
## values are memoised per point, so a corner shared by three faces is solved
## once. Bake-time only; the studio re-bakes on every edit, so see stats() and
## the measured ferry figure in tests/structure_ao_test.gd.
##
## TESSELLATION. Vertex AO on an untessellated box is a lie at plan scale: a
## 30 m deck plate has four vertices per face, so a shadow at one corner ramps
## linearly across thirty metres. append_box() therefore splits each face into a
## grid of about TESSEL metres before shading it. Triangle count rises; surface
## count, material count and draw calls do not.
##
## HOW THE BAKER CALLS THIS (later wave — structure_baker.gd is not touched by
## this file). As of the vertex-colour bucketing landed alongside this module,
## `StructureBaker._append_box(st, center, size, basis, color)` already writes
## the layer colour on every vertex and the bucket material already carries
## `albedo_color = WHITE` + `vertex_color_use_as_albedo = true`. So AO is TWO
## edits, and the emitter signature is deliberately identical to the one that is
## there now:
##
##   1. In `bake()`, once, before the bucket walk:
##          var ao := StructureAO.for_plan(plan, offset)
##      (or `StructureAO.from_boxes(StructureBaker.collect_colliders(plan, offset))`
##      if the collider list is already in hand.) Skip it when `ghost` is set —
##      an unshaded x-ray does not want baked shadows.
##
##   2. Thread `ao` through `_bucket_layer` and swap the emitter call:
##          _append_box(st, center + offset, size, basis, color)
##      becomes
##          ao.append_box(st, center + offset, size, basis, color)
##      Same argument order, same clockwise-front winding, same flat per-face
##      normals, same positions for any box under TESSEL. What changes: the
##      colour written is `color * occlusion` instead of `color`, and a face
##      longer than TESSEL is subdivided so the occlusion has vertices to live
##      on. It must REPLACE `_append_box` in that bucket rather than run beside
##      it — SurfaceTool fixes the vertex format from the first vertex.
##
## Nothing else changes: the bucket key stays keyed by material, the material
## stays white-albedo, and the draw-call count is untouched. If AO is ever wanted
## as an on/off switch, keep `_append_box` and branch on `ao == null`.
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
## Broad-phase cell size as a multiple of RADIUS. Measured on the ferry: 2.0
## costs 476 ms, 3.0 costs 455 ms, and the values are bit-identical either way.
const CELL_FACTOR := 3.0
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
var _cell := RADIUS * CELL_FACTOR
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
	_cell = _radius * CELL_FACTOR
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
	var count := candidates.size()
	if count > 0:
		## Hot loop, and it is the whole cost of a bake: candidates OUTER, probe
		## points INNER, box test inlined, one bit per probe. Written this way it
		## makes zero function calls per solve — the earlier one-call-per-probe
		## shape spent more than half its time in GDScript call overhead.
		var offsets := _offsets_for(n) as Array
		var ox := offsets[0] as PackedFloat32Array
		var oy := offsets[1] as PackedFloat32Array
		var oz := offsets[2] as PackedFloat32Array
		for j in _probes:
			_px[j] = point.x + ox[j]
			_py[j] = point.y + oy[j]
			_pz[j] = point.z + oz[j]
		var rmin := point + (offsets[3] as Vector3)
		var rmax := point + (offsets[4] as Vector3)
		var mask := 0
		var full := (1 << _probes) - 1
		for ci in count:
			if mask == full:
				break
			var index := candidates[ci]
			var box_lo := _bmin[index]
			var box_hi := _bmax[index]
			if box_lo.x > rmax.x or box_hi.x < rmin.x:
				continue
			if box_lo.y > rmax.y or box_hi.y < rmin.y:
				continue
			if box_lo.z > rmax.z or box_hi.z < rmin.z:
				continue
			if _rot[index] == 0:
				var lo := box_lo
				var hi := box_hi
				var lox := lo.x
				var loy := lo.y
				var loz := lo.z
				var hix := hi.x
				var hiy := hi.y
				var hiz := hi.z
				var bit := 1
				for j in _probes:
					if mask & bit == 0:
						var vy := _py[j]
						if vy >= loy and vy <= hiy:
							var vx := _px[j]
							if vx >= lox and vx <= hix:
								var vz := _pz[j]
								if vz >= loz and vz <= hiz:
									mask |= bit
					bit <<= 1
			else:
				var cen := _cen[index]
				var half := _half[index]
				var cs := _cos[index]
				var sn := _sin[index]
				var cx := cen.x
				var cy := cen.y
				var cz := cen.z
				var hx := half.x
				var hy := half.y
				var hz := half.z
				var rbit := 1
				for j in _probes:
					if mask & rbit == 0:
						var dy := _py[j] - cy
						if absf(dy) <= hy:
							var dx := _px[j] - cx
							var dz := _pz[j] - cz
							if absf(cs * dx - sn * dz) <= hx and absf(sn * dx + cs * dz) <= hz:
								mask |= rbit
					rbit <<= 1
		## Bit 2k is the near shell of direction k, bit 2k+1 the far shell.
		var hit := 0.0
		var kbit := 1
		for k in _weights.size():
			if mask & kbit != 0:
				hit += _weights[k] * NEAR_HIT
			elif mask & (kbit << 1) != 0:
				hit += _weights[k] * FAR_HIT
			kbit <<= 2
		occ = hit / _kernel_weight
	## Sky term: ambient arrives from above, so a downward face is dark even in
	## open air. Purely a function of the normal — it cannot mask the geometric
	## term, only add to it.
	occ += DOWNFACE_BIAS * maxf(-n.y, 0.0)
	return clampf(occ, 0.0, 1.0)


## Probe offsets (near, far) per kernel entry for one normal, built once. A
## plan's faces are axis-aligned apart from the diagonal walls, so this caches
## down to a handful of entries and takes the trig out of the inner loop.
func _offsets_for(n: Vector3) -> Array:
	var cached: Variant = _dirs.get(n, null)
	if cached != null:
		return cached as Array
	## Deterministic tangent frame. The kernel is symmetric in +/-t1 and +/-t2,
	## so which way the frame lands only ever rotates the sample set within the
	## plane — it never changes an axis-aligned result.
	var helper := Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD
	var t1 := n.cross(helper).normalized()
	var t2 := n.cross(t1).normalized()
	var ox := PackedFloat32Array()
	var oy := PackedFloat32Array()
	var oz := PackedFloat32Array()
	ox.resize(_probes)
	oy.resize(_probes)
	oz.resize(_probes)
	for k in KERNEL.size():
		var entry := KERNEL[k] as Array
		var dir := (n * float(entry[0]) + t1 * float(entry[1]) + t2 * float(entry[2])).normalized()
		var near := dir * _near
		var far := dir * _far
		ox[k * 2] = near.x
		oy[k * 2] = near.y
		oz[k * 2] = near.z
		ox[k * 2 + 1] = far.x
		oy[k * 2 + 1] = far.y
		oz[k * 2 + 1] = far.z
	## Bounding box of the probe cloud itself. Every kernel direction has a
	## positive n component, so this box starts strictly OUTSIDE the surface —
	## which is what lets _solve reject the point's own box (and every flush
	## neighbour) in six comparisons instead of eighteen point tests. The point's
	## own box is a candidate of every single query, so this is not a micro-
	## optimisation: it is most of the work.
	var omin := Vector3(ox[0], oy[0], oz[0])
	var omax := omin
	for j in _probes:
		var o := Vector3(ox[j], oy[j], oz[j])
		omin = omin.min(o)
		omax = omax.max(o)
	var offsets: Array = [ox, oy, oz, omin, omax]
	_dirs[n] = offsets
	return offsets


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
func append_box(
	st: SurfaceTool,
	center: Vector3,
	size: Vector3,
	basis := Basis.IDENTITY,
	tint := Color.WHITE,
) -> int:
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
			tint,
		)
	return triangles


## One rectangular face given its origin corner `a`, the corner reached along
## the first edge `b`, and the corner reached along the second edge `d`. The
## quad a->b->c->d is wound exactly as _append_box wound [i0,i1,i2,i3].
func _emit_face(st: SurfaceTool, a: Vector3, b: Vector3, d: Vector3, normal: Vector3, tint: Color) -> int:
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
			_vertex(st, normal, lattice[i00], shade[i00], tint)
			_vertex(st, normal, lattice[i10], shade[i10], tint)
			_vertex(st, normal, lattice[i11], shade[i11], tint)
			_vertex(st, normal, lattice[i00], shade[i00], tint)
			_vertex(st, normal, lattice[i11], shade[i11], tint)
			_vertex(st, normal, lattice[i01], shade[i01], tint)
	return nu * nv * 2


## Vertex colour is albedo TIMES occlusion. StructureBaker already carries the
## layer colour per vertex (albedo_color is white and vertex_color_use_as_albedo
## is on), so AO cannot be written as a bare greyscale — that would repaint every
## surface grey. It multiplies. Alpha is carried through untouched.
func _vertex(st: SurfaceTool, normal: Vector3, point: Vector3, shade: float, tint: Color) -> void:
	st.set_color(Color(tint.r * shade, tint.g * shade, tint.b * shade, tint.a))
	st.set_normal(normal)
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
