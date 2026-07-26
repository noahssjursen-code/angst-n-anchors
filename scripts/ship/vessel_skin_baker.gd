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


static func is_baked_brick(brick_id: String) -> bool:
	if not BrickCatalog.has(brick_id):
		return false
	for tag in LIVE_TAGS:
		if BrickCatalog.has_tag(brick_id, tag):
			return false
	return true


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
static func bake_items(grid: DeckGrid, items: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "SkinBake"
	if grid == null or items.is_empty():
		return root

	## Pass 1 — classify: voxel field for box bricks, exact-merge list for rest.
	var solid: Dictionary = {} ## Vector3i -> bucket key (String)
	var box_buckets: Dictionary = {} ## bucket key -> {"material": StandardMaterial3D, "st": SurfaceTool}
	var generic: Array = []
	for item_raw in items:
		var item := item_raw as Dictionary
		var brick_id := str(item.get("brick_id", ""))
		if not is_baked_brick(brick_id):
			continue
		if _is_box_family(brick_id):
			_register_box_cells(grid, item, solid, box_buckets)
		else:
			generic.append(item)

	## Pass 2 — voxel faces with AO, per color bucket.
	for cell_variant in solid.keys():
		var cell := cell_variant as Vector3i
		var bucket := box_buckets[solid[cell]] as Dictionary
		_emit_cell_faces(bucket["st"] as SurfaceTool, grid, cell, solid)

	## Pass 3 — applied trim: edge strips, base skirts, corner posts.
	var trim_st := SurfaceTool.new()
	trim_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trim_count := _emit_trim(trim_st, grid, solid) if EMIT_TRIM else 0

	## Pass 4 — exact-merge every other static brick per material bucket.
	var merge_buckets: Dictionary = {} ## material instance id -> {"material", "st"}
	for item_raw in generic:
		_merge_generic_brick(grid, item_raw as Dictionary, merge_buckets)

	## Commit all buckets.
	for key in box_buckets.keys():
		var bucket := box_buckets[key] as Dictionary
		_commit_bucket(root, "Boxes_%s" % str(key), bucket)
	if trim_count > 0:
		var trim_material := StandardMaterial3D.new()
		trim_material.albedo_color = TRIM_COLOR
		trim_material.roughness = 0.55
		trim_material.metallic = 0.25
		trim_st.set_material(trim_material)
		var trim_mesh := trim_st.commit()
		if trim_mesh != null and trim_mesh.get_surface_count() > 0:
			var trim_instance := MeshInstance3D.new()
			trim_instance.name = "Trim"
			trim_instance.mesh = trim_mesh
			root.add_child(trim_instance)
	for key in merge_buckets.keys():
		var bucket := merge_buckets[key] as Dictionary
		_commit_bucket(root, "Merged_%d" % int(key), bucket)
	return root


static func _commit_bucket(root: Node3D, instance_name: String, bucket: Dictionary) -> void:
	var st := bucket["st"] as SurfaceTool
	var material := bucket["material"] as Material
	if material != null:
		st.set_material(material)
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = mesh
	root.add_child(instance)


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
