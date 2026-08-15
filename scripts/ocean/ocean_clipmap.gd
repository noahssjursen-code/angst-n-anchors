class_name OceanClipmap
extends Node3D

## Camera-centred, crack-free 2:1 geometry clipmap for the rendered ocean.
##
## Every ring uses a 128-cell outer grid. The first row around each inner
## boundary is stitched to the previous level's half-sized cells with a 3:1
## triangle pattern. UV2 stores the collapsed coarse-grid target used by the
## shader's narrow transition geomorph.

const BASE_CELL_SIZE := 0.75
const PATCH_CELLS := 128
const RING_COUNT := 7
const HORIZON_HALF_EXTENT := 10000.0
const MAX_WAVE_HEIGHT := 48.0

const TIER_NEAR := 0
const TIER_MID := 1
const TIER_FAR := 2
const TIER_HORIZON := 3

var _meshes: Array[MeshInstance3D] = []
var _stats: Dictionary = {}
var _false_color := false


func build(materials: Array[ShaderMaterial]) -> void:
	## Was a bare `assert()`, and this is the WEAKEST of the sixteen conversions —
	## said plainly because a guard that buys nothing should not be sold as one.
	##
	## Measured in a debug build, `assert` and this guard are indistinguishable:
	## both refuse before the `queue_free()` loop, and the existing clipmap keeps
	## its 9 child meshes either way. What the guard adds is (a) the count in the
	## message and (b) coverage in a RELEASE build, where `assert` is compiled
	## out and `materials[TIER_HORIZON]` — index 3 — indexes out of bounds
	## AFTER the previous clipmap has been freed, leaving no ocean and a `_stats`
	## dictionary describing rings that were never built. That release half is
	## reasoned from Godot's documented behaviour, NOT measured: this container
	## has no export templates and cannot build one.
	##
	## Refusing before anything is torn down is the whole point. A `push_error`
	## that then fell through into the same indexing would be no fix at all.
	if materials.size() != TIER_HORIZON + 1:
		push_error(
			"OceanClipmap.build requires %d materials (near, mid, far, horizon), got %d — keeping the existing clipmap" % [
				TIER_HORIZON + 1, materials.size(),
			]
		)
		return
	for child in get_children():
		child.queue_free()
	_meshes.clear()
	_stats = {
		"active_rings": RING_COUNT + 2,
		"vertices": 0,
		"triangles": 0,
		"tier_vertices": PackedInt32Array([0, 0, 0, 0]),
		"tier_triangles": PackedInt32Array([0, 0, 0, 0]),
		"cascade_samples": PackedInt32Array([4, 3, 2, 1]),
		"base_cell": BASE_CELL_SIZE,
		"outer_extent": HORIZON_HALF_EXTENT * 2.0,
	}

	_add_level("OceanCenter", _build_center_patch(), TIER_NEAR, materials[TIER_NEAR])
	for level in range(1, RING_COUNT + 1):
		var tier := _tier_for_level(level)
		_add_level(
			"OceanRing%d" % level,
			_build_stitched_ring(BASE_CELL_SIZE * pow(2.0, level)),
			tier,
			materials[tier]
		)
	_add_level(
		"OceanHorizonCap",
		_build_horizon_cap(),
		TIER_HORIZON,
		materials[TIER_HORIZON]
	)


func follow_camera(camera_position: Vector3) -> void:
	# One shared quantised origin keeps every stitched boundary coincident.
	# The shader geomorphs transition vertices while FFT lookup remains in
	# world coordinates, so a snap never changes the sampled wave field.
	position.x = snappedf(camera_position.x, BASE_CELL_SIZE)
	position.z = snappedf(camera_position.z, BASE_CELL_SIZE)


func set_false_color(enabled: bool) -> void:
	_false_color = enabled
	var colors := [
		Color(0.10, 0.85, 0.35, 0.58),
		Color(0.95, 0.75, 0.08, 0.58),
		Color(0.95, 0.25, 0.12, 0.58),
		Color(0.35, 0.35, 1.0, 0.58),
	]
	for mesh in _meshes:
		var tier := int(mesh.get_meta("ocean_tier", TIER_NEAR))
		var material := mesh.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter(
				"debug_tint",
				colors[tier] if enabled else Color(0.0, 0.0, 0.0, 0.0)
			)


func get_debug_stats() -> Dictionary:
	var result := _stats.duplicate(true)
	result["false_color"] = _false_color
	return result


func _tier_for_level(level: int) -> int:
	if level <= 1:
		return TIER_NEAR
	if level <= 3:
		return TIER_MID
	if level <= 5:
		return TIER_FAR
	return TIER_HORIZON


func _add_level(
	node_name: String,
	mesh: ArrayMesh,
	tier: int,
	material: ShaderMaterial
) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.set_meta("ocean_tier", tier)
	instance.custom_aabb = AABB(
		Vector3(-HORIZON_HALF_EXTENT, -MAX_WAVE_HEIGHT, -HORIZON_HALF_EXTENT),
		Vector3(HORIZON_HALF_EXTENT * 2.0, MAX_WAVE_HEIGHT * 2.0, HORIZON_HALF_EXTENT * 2.0)
	)
	add_child(instance)
	_meshes.append(instance)

	var arrays := mesh.surface_get_arrays(0)
	var vertex_count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var triangle_count := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_stats["vertices"] = int(_stats["vertices"]) + vertex_count
	_stats["triangles"] = int(_stats["triangles"]) + triangle_count
	var tier_vertices: PackedInt32Array = _stats["tier_vertices"]
	var tier_triangles: PackedInt32Array = _stats["tier_triangles"]
	tier_vertices[tier] += vertex_count
	tier_triangles[tier] += triangle_count
	_stats["tier_vertices"] = tier_vertices
	_stats["tier_triangles"] = tier_triangles


func _build_center_patch() -> ArrayMesh:
	var half := PATCH_CELLS / 2
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var morph_targets := PackedVector2Array()
	var indices := PackedInt32Array()

	for z in range(-half, half + 1):
		for x in range(-half, half + 1):
			vertices.append(Vector3(x * BASE_CELL_SIZE, 0.0, z * BASE_CELL_SIZE))
			normals.append(Vector3.UP)
			var tx := x - posmod(x, 2) if abs(z) == half else x
			var tz := z - posmod(z, 2) if abs(x) == half else z
			morph_targets.append(Vector2(tx * BASE_CELL_SIZE, tz * BASE_CELL_SIZE))

	for z in range(PATCH_CELLS):
		for x in range(PATCH_CELLS):
			var a := z * (PATCH_CELLS + 1) + x
			var b := a + 1
			var c := a + PATCH_CELLS + 1
			var d := c + 1
			# Godot's front face is clockwise. Normals remain explicitly +Y.
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))

	return _make_mesh(vertices, normals, morph_targets, indices)


func _build_stitched_ring(cell_size: float) -> ArrayMesh:
	# Coordinates are half coarse cells. Even coordinates are the regular
	# lattice; odd coordinates only occur along the stitched inner boundary.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var morph_targets := PackedVector2Array()
	var indices := PackedInt32Array()
	var cache: Dictionary = {}
	var half := PATCH_CELLS / 2
	var hole := PATCH_CELLS / 4

	for z in range(-half, half):
		for x in range(-half, half):
			if x >= -hole and x < hole and z >= -hole and z < hole:
				continue
			var transition := (
				(z == hole and x >= -hole and x < hole)
				or (z == -hole - 1 and x >= -hole and x < hole)
				or (x == hole and z >= -hole and z < hole)
				or (x == -hole - 1 and z >= -hole and z < hole)
			)
			if transition:
				continue
			_add_quad(
				Vector2i(x * 2, z * 2),
				Vector2i((x + 1) * 2, z * 2),
				Vector2i(x * 2, (z + 1) * 2),
				Vector2i((x + 1) * 2, (z + 1) * 2),
				cell_size, vertices, normals, morph_targets, indices, cache
			)

	for i in range(-hole, hole):
		# North and south transition rows.
		_add_transition(
			Vector2i(i * 2, hole * 2),
			Vector2i(i * 2 + 1, hole * 2),
			Vector2i((i + 1) * 2, hole * 2),
			Vector2i(i * 2, (hole + 1) * 2),
			Vector2i((i + 1) * 2, (hole + 1) * 2),
			cell_size, vertices, normals, morph_targets, indices, cache
		)
		_add_transition(
			Vector2i(i * 2, -hole * 2),
			Vector2i(i * 2 + 1, -hole * 2),
			Vector2i((i + 1) * 2, -hole * 2),
			Vector2i(i * 2, (-hole - 1) * 2),
			Vector2i((i + 1) * 2, (-hole - 1) * 2),
			cell_size, vertices, normals, morph_targets, indices, cache
		)

		# East and west transition rows.
		_add_transition(
			Vector2i(hole * 2, i * 2),
			Vector2i(hole * 2, i * 2 + 1),
			Vector2i(hole * 2, (i + 1) * 2),
			Vector2i((hole + 1) * 2, i * 2),
			Vector2i((hole + 1) * 2, (i + 1) * 2),
			cell_size, vertices, normals, morph_targets, indices, cache
		)
		_add_transition(
			Vector2i(-hole * 2, i * 2),
			Vector2i(-hole * 2, i * 2 + 1),
			Vector2i(-hole * 2, (i + 1) * 2),
			Vector2i((-hole - 1) * 2, i * 2),
			Vector2i((-hole - 1) * 2, (i + 1) * 2),
			cell_size, vertices, normals, morph_targets, indices, cache
		)

	return _make_mesh(vertices, normals, morph_targets, indices)


func _build_horizon_cap() -> ArrayMesh:
	var inner := BASE_CELL_SIZE * pow(2.0, RING_COUNT) * PATCH_CELLS * 0.5
	var outer := HORIZON_HALF_EXTENT
	var vertices := PackedVector3Array([
		Vector3(-outer, 0.0, -outer), Vector3(outer, 0.0, -outer),
		Vector3(-inner, 0.0, -inner), Vector3(inner, 0.0, -inner),
		Vector3(-outer, 0.0, outer), Vector3(outer, 0.0, outer),
		Vector3(-inner, 0.0, inner), Vector3(inner, 0.0, inner),
	])
	var normals := PackedVector3Array()
	var morph_targets := PackedVector2Array()
	for vertex in vertices:
		normals.append(Vector3.UP)
		morph_targets.append(Vector2(vertex.x, vertex.z))
	var indices := PackedInt32Array([
		0, 1, 2, 1, 3, 2,
		2, 0, 6, 0, 4, 6,
		3, 7, 1, 1, 7, 5,
		6, 4, 7, 4, 5, 7,
	])
	return _make_mesh(vertices, normals, morph_targets, indices)


func _add_quad(
	a: Vector2i, b: Vector2i, c: Vector2i, d: Vector2i,
	cell_size: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	morph_targets: PackedVector2Array,
	indices: PackedInt32Array,
	cache: Dictionary
) -> void:
	_add_triangle(a, c, b, cell_size, vertices, normals, morph_targets, indices, cache)
	_add_triangle(b, c, d, cell_size, vertices, normals, morph_targets, indices, cache)


func _add_transition(
	inner_a: Vector2i,
	inner_mid: Vector2i,
	inner_b: Vector2i,
	outer_a: Vector2i,
	outer_b: Vector2i,
	cell_size: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	morph_targets: PackedVector2Array,
	indices: PackedInt32Array,
	cache: Dictionary
) -> void:
	_add_triangle(inner_a, outer_a, inner_mid, cell_size, vertices, normals, morph_targets, indices, cache)
	_add_triangle(inner_mid, outer_a, outer_b, cell_size, vertices, normals, morph_targets, indices, cache)
	_add_triangle(inner_mid, outer_b, inner_b, cell_size, vertices, normals, morph_targets, indices, cache)


func _add_triangle(
	a: Vector2i, b: Vector2i, c: Vector2i,
	cell_size: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	morph_targets: PackedVector2Array,
	indices: PackedInt32Array,
	cache: Dictionary
) -> void:
	var pa := Vector3(a.x * cell_size * 0.5, 0.0, a.y * cell_size * 0.5)
	var pb := Vector3(b.x * cell_size * 0.5, 0.0, b.y * cell_size * 0.5)
	var pc := Vector3(c.x * cell_size * 0.5, 0.0, c.y * cell_size * 0.5)
	if (pb - pa).cross(pc - pa).y > 0.0:
		var swap := b
		b = c
		c = swap
	indices.append(_vertex_index(a, cell_size, vertices, normals, morph_targets, cache))
	indices.append(_vertex_index(b, cell_size, vertices, normals, morph_targets, cache))
	indices.append(_vertex_index(c, cell_size, vertices, normals, morph_targets, cache))


func _vertex_index(
	coord: Vector2i,
	cell_size: float,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	morph_targets: PackedVector2Array,
	cache: Dictionary
) -> int:
	if cache.has(coord):
		return int(cache[coord])
	var index := vertices.size()
	var p := Vector2(coord.x, coord.y) * cell_size * 0.5
	vertices.append(Vector3(p.x, 0.0, p.y))
	normals.append(Vector3.UP)
	var target_coord := Vector2i(coord.x - posmod(coord.x, 2), coord.y - posmod(coord.y, 2))
	# At the outer boundary, collapse every odd coarse-grid point so it
	# exactly matches the next ring's collapsed half-step inner edge.
	if abs(coord.x) == PATCH_CELLS:
		target_coord.y = coord.y - posmod(coord.y, 4)
	if abs(coord.y) == PATCH_CELLS:
		target_coord.x = coord.x - posmod(coord.x, 4)
	var target := Vector2(target_coord.x, target_coord.y) * cell_size * 0.5
	morph_targets.append(target)
	cache[coord] = index
	return index


func _make_mesh(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	morph_targets: PackedVector2Array,
	indices: PackedInt32Array
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = morph_targets
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
