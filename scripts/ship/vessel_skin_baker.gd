class_name VesselSkinBaker
extends RefCounted

## Bakes a BrickLayout's static bricks into a handful of merged surfaces —
## the vessel's "skin" — instead of one scene node per brick.
##
## Two paths, chosen automatically per brick:
##  - BOX bricks (plain cuboids: block, floor, roof_flat, beam, …) are emitted
##    as culled voxel faces with baked corner ambient occlusion, plus applied
##    trim: contrast strips along exposed deck/roof edges, base skirts, and
##    vertical corner posts. This is what gives large flat builds surface
##    language (edges, shading) that per-brick rendering never had.
##  - Every other static brick (wedges, railings, stairs, props, windows) is
##    exact-merged: its catalog visual is instantiated once off-tree and its
##    mesh surfaces appended into per-material buckets, preserving today's
##    look at a fraction of the draw calls.
##
## Interactive/animated bricks (doors, helm, lights, fishing gear, ladders,
## moorings, signs) are NOT baked — DeckFitout keeps mounting them as live
## nodes. See is_baked_brick().
##
## Pure function of (layout, grid): no BoatBody or gameplay dependencies, so a
## headless service (e.g. the future build-moderation renderer) can call it.
##
## RESUMABLE. `bake_items()` is one call and, at 3000 bricks, one 140 ms call —
## 35x DeckFitoutJob's own 4 ms frame budget, which is why the staged path never
## called it and drew one MeshInstance3D per brick instead. `Session` is the same
## bake taken apart into units a frame-budgeted caller can spend one at a time:
## register an item (~0.05 ms), emit an item's faces (~0.01 ms), commit (2.5 ms
## for a whole 3000-brick skin, measured — the one indivisible step, and it fits
## inside the budget). `bake_items()` is now that Session driven to completion,
## so the staged and synchronous paths emit the same faces from the same code —
## no second derivation to drift (REALITY.md 3b).

const TRIM_COLOR := Color(0.13, 0.14, 0.16)
const TRIM_THICKNESS := 0.11
const TRIM_DEPTH := 0.13
const AO_LEVELS: Array[float] = [1.0, 0.82, 0.70, 0.58]

## Applied edge trim is disabled: strips on every exposed edge read as cartoon
## outlines and overlapping runs z-fight at corners. Trim returns later as a
## palette-driven accent on selected semantic edges (deck perimeter, bulwark
## caps) with mitered corners. Baked AO carries the surface depth meanwhile.
const EMIT_TRIM := false

## Tags that keep a brick as a live node (interaction, animation, light emission).
const LIVE_TAGS: Array[String] = [
	"door", "helm", "light", "ladder", "mooring", "text", "trommel", "fishing",
]

## brick_id -> true when the catalog visual is a single plain BoxMesh (cached).
static var _box_family_cache: Dictionary = {}

## brick_id -> is_baked_brick(). `BrickCatalog.has_tag` deep-copies the whole
## catalog entry per call, so the uncached eight-tag scan costs 21 us — 64 ms of
## a 3000-brick bake, measured, spent asking the same question about the same
## brick id 3000 times. The catalog is static data; one answer per id is enough.
static var _baked_brick_cache: Dictionary = {}


static func is_baked_brick(brick_id: String) -> bool:
	if _baked_brick_cache.has(brick_id):
		return bool(_baked_brick_cache[brick_id])
	var result := true
	if not BrickCatalog.has(brick_id):
		result = false
	else:
		for tag in LIVE_TAGS:
			if BrickCatalog.has_tag(brick_id, tag):
				result = false
				break
	_baked_brick_cache[brick_id] = result
	return result


## Detects full-cell cuboid bricks by inspecting their catalog visual once:
## exactly one MeshInstance3D carrying a BoxMesh whose size fills the brick's
## footprint (thin plates and slender beams must NOT be inflated to full
## cubes — they take the exact-merge path instead). Works for any future
## catalog additions without maintaining an id list.
static func _is_box_family(brick_id: String) -> bool:
	if _box_family_cache.has(brick_id):
		return bool(_box_family_cache[brick_id])
	var sample := BrickCatalog.create_visual(brick_id, {})
	var result := false
	if sample.get_child_count() == 1:
		var only := sample.get_child(0) as MeshInstance3D
		if only != null and only.mesh is BoxMesh and only.get_child_count() == 0:
			var size := (only.mesh as BoxMesh).size
			var fp := BrickCatalog.footprint_of(brick_id)
			var full := Vector3(fp) * DeckGrid.CELL_M
			result = (
				size.x >= full.x * 0.9 and size.x <= full.x * 1.05
				and size.y >= full.y * 0.9 and size.y <= full.y * 1.05
				and size.z >= full.z * 0.9 and size.z <= full.z * 1.05
			)
	sample.free()
	_box_family_cache[brick_id] = result
	return result


## Bakes the given primary items (subset of layout.iter_primary_cells()) into
## one Node3D holding a few MeshInstance3D children (one per material bucket).
## Convenience wrapper: a Session driven straight to completion.
static func bake_items(grid: DeckGrid, items: Array) -> Node3D:
	var session := Session.new(grid)
	for item_raw in items:
		session.register_item(item_raw as Dictionary)
	for item_raw in items:
		session.emit_item(item_raw as Dictionary)
	session.commit()
	return session.root


## Writes a bucket's accumulated geometry into `bucket["node"]`, creating the
## MeshInstance3D on first commit and REPLACING its mesh on later ones. A
## SurfaceTool keeps its vertices after commit() (verified), so a staged caller
## can show the exterior, keep adding interior faces into the same tool, and
## re-commit — the final mesh is the one the synchronous path would have built.
static func _commit_bucket(root: Node3D, instance_name: String, bucket: Dictionary) -> void:
	var st := bucket["st"] as SurfaceTool
	var material := bucket["material"] as Material
	if material != null:
		st.set_material(material)
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var instance := bucket.get("node", null) as MeshInstance3D
	if instance == null or not is_instance_valid(instance):
		instance = MeshInstance3D.new()
		instance.name = instance_name
		root.add_child(instance)
		bucket["node"] = instance
	instance.mesh = mesh


# ── Box voxel path ───────────────────────────────────────────────────────────

static func _register_box_cells(
	grid: DeckGrid,
	item: Dictionary,
	solid: Dictionary,
	box_buckets: Dictionary,
) -> void:
	var brick_id := str(item.get("brick_id", ""))
	var origin: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	var yaw := int(item.get("yaw", 0))
	var color: Color = BrickLayout.color_from_entry(item, brick_id)
	var key := "%02x%02x%02x" % [int(color.r * 255.0), int(color.g * 255.0), int(color.b * 255.0)]
	if not box_buckets.has(key):
		var material := _sample_material(brick_id, color)
		box_buckets[key] = {"material": material, "st": _new_surface()}
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	if yaw_steps < 0:
		yaw_steps += 4
	for cell_variant in grid.footprint_cells(origin, fp, yaw_steps):
		solid[cell_variant as Vector3i] = key


static func _new_surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Base material for merged box surfaces: the brick's own catalog material with
## vertex colors enabled so baked AO darkens the albedo.
static func _sample_material(brick_id: String, color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = null
	var sample := BrickCatalog.create_visual(brick_id, {"color": color})
	if sample.get_child_count() > 0:
		var mesh_child := sample.get_child(0) as MeshInstance3D
		if mesh_child != null and mesh_child.material_override is StandardMaterial3D:
			material = (mesh_child.material_override as StandardMaterial3D).duplicate()
	sample.free()
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
	material.vertex_color_use_as_albedo = true
	return material


const _DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


static func _cell_min(grid: DeckGrid, cell: Vector3i) -> Vector3:
	var base := grid.cell_base_local(cell)
	var half := DeckGrid.CELL_M * 0.5
	return Vector3(base.x - half, base.y, base.z - half)


static func _emit_cell_faces(st: SurfaceTool, grid: DeckGrid, cell: Vector3i, solid: Dictionary) -> void:
	var cell_size := DeckGrid.CELL_M
	var minp := _cell_min(grid, cell)
	for dir in _DIRS:
		if solid.has(cell + dir):
			continue
		_emit_face(st, minp, cell_size, cell, dir, solid)


## Emits one culled voxel face as two triangles with per-vertex corner AO.
## Godot front faces wind CLOCKWISE (verified: right-hand cross of the vertex
## order is opposite the outward normal), so for outward normal n the triangle
## order must have right-hand normal -n.
static func _emit_face(
	st: SurfaceTool,
	minp: Vector3,
	s: float,
	cell: Vector3i,
	dir: Vector3i,
	solid: Dictionary,
) -> void:
	var u_axis: Vector3i
	var v_axis: Vector3i
	if dir.x != 0:
		u_axis = Vector3i(0, 0, 1)
		v_axis = Vector3i(0, 1, 0)
	elif dir.y != 0:
		u_axis = Vector3i(1, 0, 0)
		v_axis = Vector3i(0, 0, 1)
	else:
		u_axis = Vector3i(1, 0, 0)
		v_axis = Vector3i(0, 1, 0)
	var u_vec := Vector3(u_axis) * s
	var v_vec := Vector3(v_axis) * s
	var base := minp + Vector3(
		s if dir.x > 0 else 0.0,
		s if dir.y > 0 else 0.0,
		s if dir.z > 0 else 0.0,
	)
	var p00 := base
	var p10 := base + u_vec
	var p01 := base + v_vec
	var p11 := base + u_vec + v_vec
	var ao00 := _corner_ao(cell, dir, u_axis, v_axis, -1, -1, solid)
	var ao10 := _corner_ao(cell, dir, u_axis, v_axis, 1, -1, solid)
	var ao01 := _corner_ao(cell, dir, u_axis, v_axis, -1, 1, solid)
	var ao11 := _corner_ao(cell, dir, u_axis, v_axis, 1, 1, solid)
	## Order A has right-hand normal cross(u,v) = (-X | -Y | +Z) per axis case,
	## which under clockwise-front renders toward (+X | +Y | -Z).
	var order: Array
	if dir.x > 0 or dir.y > 0 or dir.z < 0:
		order = [
			[p00, ao00], [p10, ao10], [p11, ao11],
			[p00, ao00], [p11, ao11], [p01, ao01],
		]
	else:
		order = [
			[p00, ao00], [p11, ao11], [p10, ao10],
			[p00, ao00], [p01, ao01], [p11, ao11],
		]
	for entry in order:
		st.set_normal(Vector3(dir))
		st.set_color(Color(entry[1], entry[1], entry[1]))
		st.add_vertex(entry[0])


## Classic voxel corner AO: occlusion from the two edge neighbors and the
## diagonal neighbor that touch this face corner.
static func _corner_ao(
	cell: Vector3i,
	dir: Vector3i,
	u_axis: Vector3i,
	v_axis: Vector3i,
	du: int,
	dv: int,
	solid: Dictionary,
) -> float:
	var above := cell + dir
	var side_u := solid.has(above + u_axis * du)
	var side_v := solid.has(above + v_axis * dv)
	var corner := solid.has(above + u_axis * du + v_axis * dv)
	var occlusion: int
	if side_u and side_v:
		occlusion = 3
	else:
		occlusion = (1 if side_u else 0) + (1 if side_v else 0) + (1 if corner else 0)
	return AO_LEVELS[occlusion]


# ── Applied trim (edge strips, skirts, corner posts) ─────────────────────────

const _SIDE_DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


static func _emit_trim(st: SurfaceTool, grid: DeckGrid, solid: Dictionary) -> int:
	var count := 0
	var cell_size := DeckGrid.CELL_M
	var up := Vector3i(0, 1, 0)
	## Horizontal edge strips (top = gunwale/coaming look, bottom = base skirt),
	## merged into runs along the edge direction.
	for vertical in [true, false]:
		for dir in _SIDE_DIRS:
			var edge_cells: Dictionary = {}
			for cell_variant in solid.keys():
				var cell := cell_variant as Vector3i
				var open_vertical := not solid.has(cell + (up if vertical else -up))
				if open_vertical and not solid.has(cell + dir):
					edge_cells[cell] = true
			var run_axis := Vector3i(0, 0, 1) if dir.x != 0 else Vector3i(1, 0, 0)
			count += _emit_edge_runs(st, grid, edge_cells, run_axis, dir, vertical, cell_size)
	## Vertical corner posts where two exposed side faces meet, merged in Y runs.
	var corner_pairs: Array = [
		[Vector3i(1, 0, 0), Vector3i(0, 0, 1)],
		[Vector3i(1, 0, 0), Vector3i(0, 0, -1)],
		[Vector3i(-1, 0, 0), Vector3i(0, 0, 1)],
		[Vector3i(-1, 0, 0), Vector3i(0, 0, -1)],
	]
	for pair in corner_pairs:
		var dir_a := pair[0] as Vector3i
		var dir_b := pair[1] as Vector3i
		var post_cells: Dictionary = {}
		for cell_variant in solid.keys():
			var cell := cell_variant as Vector3i
			if not solid.has(cell + dir_a) and not solid.has(cell + dir_b) and not solid.has(cell + dir_a + dir_b):
				post_cells[cell] = true
		count += _emit_post_runs(st, grid, post_cells, dir_a, dir_b, cell_size)
	return count


static func _emit_edge_runs(
	st: SurfaceTool,
	grid: DeckGrid,
	edge_cells: Dictionary,
	run_axis: Vector3i,
	dir: Vector3i,
	top: bool,
	s: float,
) -> int:
	var count := 0
	var visited: Dictionary = {}
	for cell_variant in edge_cells.keys():
		var cell := cell_variant as Vector3i
		if visited.has(cell):
			continue
		## Walk backwards to the run start, then forwards to its end.
		var start := cell
		while edge_cells.has(start - run_axis):
			start -= run_axis
		var length := 1
		var walker := start
		visited[walker] = true
		while edge_cells.has(walker + run_axis):
			walker += run_axis
			visited[walker] = true
			length += 1
		_emit_trim_box(st, grid, start, run_axis, length, dir, top, s)
		count += 1
	return count


static func _emit_trim_box(
	st: SurfaceTool,
	grid: DeckGrid,
	start: Vector3i,
	run_axis: Vector3i,
	length: int,
	dir: Vector3i,
	top: bool,
	s: float,
) -> void:
	var a := _cell_min(grid, start)
	var b := _cell_min(grid, start + run_axis * (length - 1)) + Vector3.ONE * s
	var run_min := Vector3(minf(a.x, b.x - s), a.y, minf(a.z, b.z - s))
	var run_max := Vector3(maxf(a.x + s, b.x), a.y + s, maxf(a.z + s, b.z))
	## Position the strip straddling the exposed edge.
	var y := run_max.y - TRIM_THICKNESS * 0.5 if top else run_min.y + TRIM_THICKNESS * 0.5
	var center := (run_min + run_max) * 0.5
	center.y = y
	if dir.x > 0:
		center.x = run_max.x
	elif dir.x < 0:
		center.x = run_min.x
	if dir.z > 0:
		center.z = run_max.z
	elif dir.z < 0:
		center.z = run_min.z
	var size := Vector3(
		(run_max.x - run_min.x) if run_axis.x != 0 else TRIM_DEPTH,
		TRIM_THICKNESS,
		(run_max.z - run_min.z) if run_axis.z != 0 else TRIM_DEPTH,
	)
	_append_box(st, center, size)


static func _emit_post_runs(
	st: SurfaceTool,
	grid: DeckGrid,
	post_cells: Dictionary,
	dir_a: Vector3i,
	dir_b: Vector3i,
	s: float,
) -> int:
	var count := 0
	var visited: Dictionary = {}
	var up := Vector3i(0, 1, 0)
	for cell_variant in post_cells.keys():
		var cell := cell_variant as Vector3i
		if visited.has(cell):
			continue
		var start := cell
		while post_cells.has(start - up):
			start -= up
		var length := 1
		var walker := start
		visited[walker] = true
		while post_cells.has(walker + up):
			walker += up
			visited[walker] = true
			length += 1
		var base := _cell_min(grid, start)
		var center := grid.cell_base_local(start)
		center.y = base.y + float(length) * s * 0.5
		center.x += float(dir_a.x) * s * 0.5
		center.z += float(dir_b.z) * s * 0.5
		_append_box(st, center, Vector3(TRIM_DEPTH, float(length) * s, TRIM_DEPTH))
		count += 1
	return count


## Appends an axis-aligned box (12 triangles) with flat normals, full white color.
static func _append_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var corners := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	var faces := [
		[[0, 1, 5, 4], Vector3(0, 0, -1)],
		[[2, 3, 7, 6], Vector3(0, 0, 1)],
		[[1, 2, 6, 5], Vector3(1, 0, 0)],
		[[3, 0, 4, 7], Vector3(-1, 0, 0)],
		[[4, 5, 6, 7], Vector3(0, 1, 0)],
		[[3, 2, 1, 0], Vector3(0, -1, 0)],
	]
	for face in faces:
		var idx: Array = face[0]
		var normal: Vector3 = face[1]
		## Clockwise front (see winding_probe): the old [0,2,1] order was
		## inverted — inward normals were part of why trim strips shaded black.
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_normal(normal)
				st.set_color(Color.WHITE)
				st.add_vertex(corners[idx[k]])


# ── Exact-merge path for non-box static bricks ───────────────────────────────

static func _merge_generic_brick(grid: DeckGrid, item: Dictionary, buckets: Dictionary) -> void:
	var brick_id := str(item.get("brick_id", ""))
	var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	var yaw := int(item.get("yaw", 0))
	var opts: Dictionary = {"color": BrickLayout.color_from_entry(item, brick_id)}
	var sample := BrickCatalog.create_visual(brick_id, opts)
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	if yaw_steps < 0:
		yaw_steps += 4
	var occupied := grid.footprint_cells(cell, fp, yaw_steps)
	var sum := Vector3.ZERO
	for c in occupied:
		sum += grid.cell_center_local(c)
	var placement := Transform3D(
		Basis(Vector3.UP, deg_to_rad(float(yaw))),
		sum / float(maxi(occupied.size(), 1)) if not occupied.is_empty() else grid.cell_center_local(cell),
	)
	_merge_node_tree(sample, placement, buckets)
	sample.free()


static func _merge_node_tree(node: Node, accumulated: Transform3D, buckets: Dictionary) -> void:
	var next := accumulated
	if node is Node3D:
		next = accumulated * (node as Node3D).transform
	var instance := node as MeshInstance3D
	if instance != null and instance.mesh != null:
		var mesh := instance.mesh
		for surface in mesh.get_surface_count():
			var material: Material = instance.material_override
			if material == null:
				material = mesh.surface_get_material(surface)
			var key := material.get_instance_id() if material != null else 0
			if not buckets.has(key):
				buckets[key] = {"material": material, "st": _new_surface()}
			((buckets[key] as Dictionary)["st"] as SurfaceTool).append_from(mesh, surface, next)
	for child in node.get_children():
		_merge_node_tree(child, next, buckets)


# ── Resumable bake ───────────────────────────────────────────────────────────


## One vessel's skin, built a unit at a time.
##
## Order matters and is the whole reason this is two methods and not one:
## `register_item` populates the solid field, `emit_item` culls faces and shades
## corners AGAINST that field. A caller must register every item it intends to
## bake — including bricks it will only reveal later — before emitting the first
## face, or the faces between an early brick and a late one are drawn instead of
## culled and the AO at those corners is wrong. DeckFitoutJob registers the
## interior with the exterior for exactly that reason, and emits it a stage later.
##
## `commit()` may be called repeatedly: each call re-commits every bucket into
## its own MeshInstance3D, so the node set is a function of the material buckets,
## never of the brick count.
class Session:
	extends RefCounted

	var root: Node3D

	var _grid: DeckGrid
	## Vector3i -> box bucket key. The culling/AO field, global to the vessel.
	var _solid: Dictionary = {}
	## bucket key -> {"material", "st", "node"}
	var _box_buckets: Dictionary = {}
	## material instance id -> {"material", "st", "node"}
	var _merge_buckets: Dictionary = {}
	## cell key -> true for box-family items, false for exact-merge items.
	var _box_item: Dictionary = {}
	var _trim_node: MeshInstance3D = null

	func _init(grid: DeckGrid) -> void:
		_grid = grid
		root = Node3D.new()
		root.name = "SkinBake"

	## True when this item's geometry belongs to the skin (caller must NOT also
	## create a scene node for it). False for live bricks and for anything the
	## grid rejects — the caller keeps those as individual visuals.
	func register_item(item: Dictionary) -> bool:
		if _grid == null:
			return false
		var brick_id := str(item.get("brick_id", ""))
		if not VesselSkinBaker.is_baked_brick(brick_id):
			return false
		var key := BrickLayout.cell_key(item.get("cell", Vector3i(-1, -1, -1)))
		if _box_item.has(key):
			return true
		if VesselSkinBaker._is_box_family(brick_id):
			VesselSkinBaker._register_box_cells(_grid, item, _solid, _box_buckets)
			_box_item[key] = true
		else:
			_box_item[key] = false
		return true

	## Emits one registered item's geometry into its bucket. Returns false for
	## items this session never took (live bricks), so the caller can fall back
	## to a scene node with no second is_baked_brick test to keep in sync.
	func emit_item(item: Dictionary) -> bool:
		if _grid == null:
			return false
		var key := BrickLayout.cell_key(item.get("cell", Vector3i(-1, -1, -1)))
		if not _box_item.has(key):
			return false
		if not bool(_box_item[key]):
			VesselSkinBaker._merge_generic_brick(_grid, item, _merge_buckets)
			return true
		var brick_id := str(item.get("brick_id", ""))
		var origin: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
		var yaw_steps := int(round(float(int(item.get("yaw", 0))) / 90.0)) % 4
		if yaw_steps < 0:
			yaw_steps += 4
		for cell_variant in _grid.footprint_cells(
			origin, BrickCatalog.footprint_of(brick_id), yaw_steps
		):
			var cell := cell_variant as Vector3i
			if not _solid.has(cell):
				continue
			var bucket := _box_buckets[_solid[cell]] as Dictionary
			VesselSkinBaker._emit_cell_faces(bucket["st"] as SurfaceTool, _grid, cell, _solid)
		return true

	## Publishes everything emitted so far. Safe to call after every stage.
	func commit() -> void:
		for bucket_key in _box_buckets.keys():
			VesselSkinBaker._commit_bucket(
				root, "Boxes_%s" % str(bucket_key), _box_buckets[bucket_key] as Dictionary
			)
		for bucket_key in _merge_buckets.keys():
			VesselSkinBaker._commit_bucket(
				root, "Merged_%d" % int(bucket_key), _merge_buckets[bucket_key] as Dictionary
			)
		_commit_trim()

	## Trim is a function of the whole solid field rather than of any one brick,
	## so it is rebuilt from scratch on each commit rather than appended to.
	func _commit_trim() -> void:
		if not VesselSkinBaker.EMIT_TRIM:
			return
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		if VesselSkinBaker._emit_trim(st, _grid, _solid) <= 0:
			return
		var material := StandardMaterial3D.new()
		material.albedo_color = VesselSkinBaker.TRIM_COLOR
		material.roughness = 0.55
		material.metallic = 0.25
		st.set_material(material)
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			return
		if _trim_node == null or not is_instance_valid(_trim_node):
			_trim_node = MeshInstance3D.new()
			_trim_node.name = "Trim"
			root.add_child(_trim_node)
		_trim_node.mesh = mesh
