class_name WorldTerrainStreamer
extends Node3D

## Incremental, deterministic terrain streaming for the bounded Norway world.
## Chunk geometry is sampled only in world coordinates so independently built
## chunks (and power-of-two LODs) share bit-identical boundary vertices.

const WorldReferenceScript := preload("res://scripts/world/world_reference.gd")
const TERRAIN_SHADER := preload("res://resources/shaders/terrain.gdshader")
const TERRAIN_SURFACE_MAPS := preload("res://scripts/world/terrain_surface_maps.gd")

const CHUNK_SIZE_M := 1000.0
## The macro SDF itself is 156.25 m, so denser-than-40 m runtime tessellation adds
## build cost without coastline information. All steps divide 1 km exactly.
## Far rings use 500 m so a ~20 km visual radius stays affordable.
const DEFAULT_LOD_STEPS := [40.0, 50.0, 100.0, 200.0, 500.0]
const DEFAULT_LOD_DISTANCES := [2200.0, 4800.0, 9000.0, 15000.0]
const DEFAULT_VISUAL_RADIUS_M := 20000.0
const SKIRT_DEPTH_M := 12.0
const LOD_HYSTERESIS_M := 350.0
## Terrain datum sits below sea level so the rock shelf continues underwater.
## Port flatten zones still target y=0 and are therefore unchanged.
const TERRAIN_SINK_M := 2.5
const SUBMERGED_SHELF_EXTENT_M := 28.0
const COASTAL_COATING_MAX_LOD := 2
const COASTAL_COATING_OFFSET_M := 0.08
const BYTES_PER_VERTEX_ESTIMATE := 40
const BYTES_PER_INDEX_ESTIMATE := 4
const PORT_PAD_WIDTH_BY_SIZE := PortSizing.TERRAIN_PAD_WIDTH_BY_SIZE
const PORT_PAD_SEAWARD_SHIFT_M := PortSizing.PAD_SEAWARD_SHIFT_M

@export_range(1000.0, 28000.0, 250.0) var visual_radius_m := DEFAULT_VISUAL_RADIUS_M
@export_range(0.0, 5000.0, 100.0) var collision_radius_m := 1800.0
@export_range(0.25, 16.0, 0.25) var build_budget_ms := 4.5
@export_range(1, 8, 1) var max_jobs_per_frame := 1
@export_range(1, 16, 1) var queue_refresh_frames := 4
@export var lod_steps_m := PackedFloat32Array(DEFAULT_LOD_STEPS)
@export var lod_distances_m := PackedFloat32Array(DEFAULT_LOD_DISTANCES)
@export var sea_level_pad_height_m := 0.0

## Elevated budget while the loading gate waits on the spawn ring.
const BOOT_BUDGET_MS := 18.0
const BOOT_MAX_JOBS := 4

var _layout: Object
var _flatten_zones: Array[Dictionary] = []
var _chunks: Dictionary = {}
var _jobs: Array[Dictionary] = []
var _queued: Dictionary = {}
var _material: ShaderMaterial
var _coastal_slate_material: StandardMaterial3D
var _frame_index := 0
var _last_build_ms := 0.0
var _total_build_ms := 0.0
var _completed_builds := 0
var _boot_priority := false
var _boot_focus := Vector3.ZERO


func configure(layout: Object, port_definitions: Array = []) -> void:
	_clear_chunks()
	_layout = layout
	_material = null
	_coastal_slate_material = null
	_flatten_zones = make_flatten_zones(port_definitions, sea_level_pad_height_m)
	_frame_index = 0
	set_process(_layout != null)
	if _layout != null:
		# Bake surface maps up-front so the first streamed chunk stays cheap.
		_terrain_material()
		_refresh_requests(WorldReferenceScript.stream_position(get_viewport()))


func set_layout(layout: Object) -> void:
	configure(layout, [])


func set_port_definitions(port_definitions: Array) -> void:
	_flatten_zones = make_flatten_zones(port_definitions, sea_level_pad_height_m)
	_rebuild_loaded_chunks()


func _ready() -> void:
	set_process(_layout != null)


func _exit_tree() -> void:
	_clear_chunks()


func _process(_delta: float) -> void:
	if _layout == null:
		return
	var stream_position := _boot_focus if _boot_priority else WorldReferenceScript.stream_position(get_viewport())
	if _boot_priority or _frame_index % maxi(queue_refresh_frames, 1) == 0:
		_refresh_requests(stream_position)
	_process_jobs(stream_position)
	_sync_collisions(stream_position)
	_frame_index += 1


## Prefer nearby chunk builds and pin stream focus while LoadingGate is up.
func begin_boot_priority(focus: Vector3) -> void:
	_boot_priority = true
	_boot_focus = focus
	if _layout != null:
		_refresh_requests(focus)


func end_boot_priority() -> void:
	_boot_priority = false


func is_boot_priority() -> bool:
	return _boot_priority


func boot_focus() -> Vector3:
	return _boot_focus


## True when every chunk within the spawn/collision ring is loaded (and collidable).
## Far visual rings may still be queued — that streaming continues after boot.
func is_ready_around(world_pos: Vector3, radius_m: float = -1.0) -> bool:
	if _layout == null:
		return true
	var r := _boot_ready_radius_m() if radius_m < 0.0 else radius_m
	if r <= 0.0:
		return true
	var stream_xz := Vector2(world_pos.x, world_pos.z)
	var desired := select_chunk_requests(
		stream_xz,
		float(_layout.half_extent_m),
		r,
		lod_distances_m,
	)
	for request in desired:
		var coord: Vector2i = request["coord"]
		var key := chunk_key(coord)
		if not _chunks.has(key):
			return false
		if _queued.has(key):
			return false
		if chunk_needs_collision(coord, stream_xz, collision_radius_m):
			var record := _chunks[key] as Dictionary
			if not _chunk_collision_ready(record):
				return false
	return true


func pending_near(world_pos: Vector3, radius_m: float = -1.0) -> int:
	if _layout == null:
		return 0
	var r := _boot_ready_radius_m() if radius_m < 0.0 else radius_m
	var stream_xz := Vector2(world_pos.x, world_pos.z)
	var count := 0
	for job in _jobs:
		if distance_to_chunk(job["coord"], stream_xz) <= r:
			count += 1
	var desired := select_chunk_requests(
		stream_xz,
		float(_layout.half_extent_m),
		r,
		lod_distances_m,
	)
	for request in desired:
		var key := chunk_key(request["coord"])
		if not _chunks.has(key) and not _queued.has(key):
			count += 1
	return count


func _boot_ready_radius_m() -> float:
	var lod0 := float(lod_distances_m[0]) if lod_distances_m.size() > 0 else collision_radius_m
	return maxf(collision_radius_m, lod0)


func get_debug_stats() -> Dictionary:
	var lod_counts := PackedInt32Array()
	lod_counts.resize(lod_steps_m.size())
	var vertices := 0
	var triangles := 0
	var collision_count := 0
	var memory_bytes := 0
	for value in _chunks.values():
		var record := value as Dictionary
		var lod := int(record.get("lod", 0))
		if lod >= 0 and lod < lod_counts.size():
			lod_counts[lod] += 1
		vertices += int(record.get("vertices", 0))
		triangles += int(record.get("triangles", 0))
		memory_bytes += int(record.get("memory_bytes", 0))
		if record.get("collision", null) != null:
			collision_count += 1
	return {
		"loaded": _chunks.size(),
		"pending": _jobs.size(),
		"lod_counts": lod_counts,
		"vertices": vertices,
		"triangles": triangles,
		"collision_count": collision_count,
		"last_build_ms": _last_build_ms,
		"average_build_ms": _total_build_ms / float(maxi(_completed_builds, 1)),
		"memory_estimate_bytes": memory_bytes,
	}


func _refresh_requests(stream_position: Vector3) -> void:
	var desired := select_chunk_requests(
		Vector2(stream_position.x, stream_position.z),
		float(_layout.half_extent_m),
		visual_radius_m,
		lod_distances_m,
	)
	var desired_keys := {}
	for request in desired:
		var coord: Vector2i = request["coord"]
		var key := chunk_key(coord)
		var loaded := _chunks.get(key, {}) as Dictionary
		if not loaded.is_empty():
			request["lod"] = stabilize_lod(
				int(request["lod"]),
				int(loaded.get("lod", 0)),
				float(request["distance"]),
				lod_distances_m,
				LOD_HYSTERESIS_M,
			)
		desired_keys[key] = int(request["lod"])
		if loaded.is_empty() or int(loaded.get("lod", -1)) != int(request["lod"]):
			_enqueue(request)

	var remove_keys: Array = []
	for key in _chunks:
		if not desired_keys.has(key):
			remove_keys.append(key)
	for key in remove_keys:
		_unload_chunk(StringName(key))

	var retained_jobs: Array[Dictionary] = []
	_queued.clear()
	for job in _jobs:
		var key := chunk_key(job["coord"])
		if desired_keys.has(key) and int(desired_keys[key]) == int(job["lod"]):
			retained_jobs.append(job)
			_queued[key] = int(job["lod"])
	_jobs = retained_jobs
	for request in desired:
		var coord: Vector2i = request["coord"]
		var key := chunk_key(coord)
		var loaded := _chunks.get(key, {}) as Dictionary
		if (loaded.is_empty() or int(loaded.get("lod", -1)) != int(request["lod"])) and not _queued.has(key):
			_enqueue(request)


func _enqueue(request: Dictionary) -> void:
	var key := chunk_key(request["coord"])
	var lod := int(request["lod"])
	if _queued.get(key, -1) == lod:
		return
	_queued[key] = lod
	_jobs.append(request)


func _process_jobs(stream_position: Vector3) -> void:
	var frame_started := Time.get_ticks_usec()
	var completed := 0
	var budget := BOOT_BUDGET_MS if _boot_priority else build_budget_ms
	var max_jobs := BOOT_MAX_JOBS if _boot_priority else max_jobs_per_frame
	if _boot_priority and _jobs.size() > 1:
		_jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0))
		)
	while not _jobs.is_empty() and completed < maxi(max_jobs, 1):
		if completed > 0 and float(Time.get_ticks_usec() - frame_started) / 1000.0 >= budget:
			break
		var job := _jobs.pop_front() as Dictionary
		var coord: Vector2i = job["coord"]
		_queued.erase(chunk_key(coord))
		var started := Time.get_ticks_usec()
		_build_chunk(coord, int(job["lod"]), stream_position)
		_last_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
		_total_build_ms += _last_build_ms
		_completed_builds += 1
		completed += 1


func _build_chunk(coord: Vector2i, lod: int, stream_position: Vector3) -> void:
	var key := chunk_key(coord)
	_unload_chunk(key)
	var step := float(lod_steps_m[clampi(lod, 0, lod_steps_m.size() - 1)])
	var data := build_chunk_mesh_data(_layout, coord, step, _flatten_zones, SKIRT_DEPTH_M)
	var root := Node3D.new()
	root.name = "Terrain_%d_%d_L%d" % [coord.x, coord.y, lod]
	add_child(root)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Visual"
	mesh_instance.mesh = _array_mesh_from_data(data)
	mesh_instance.material_override = _terrain_material()
	root.add_child(mesh_instance)

	# Svaberg is a continuous terrain coating, not a collection of rock props.
	# Only coastal triangles are copied, so inland chunks gain no extra draw.
	if lod <= COASTAL_COATING_MAX_LOD:
		var coating_data := build_coastal_coating_mesh_data(data)
		if not (coating_data["indices"] as PackedInt32Array).is_empty():
			var coating := MeshInstance3D.new()
			coating.name = "CoastalSlate"
			coating.mesh = _array_mesh_from_data(coating_data)
			coating.material_override = _coastal_coating_material()
			coating.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(coating)

	var record := {
		"node": root,
		"lod": lod,
		"vertices": (data["vertices"] as PackedVector3Array).size(),
		"triangles": (data["indices"] as PackedInt32Array).size() / 3,
		"memory_bytes": estimate_mesh_memory(data),
		"collision": null,
		"surface_data": data,
	}
	_chunks[key] = record
	if chunk_needs_collision(coord, Vector2(stream_position.x, stream_position.z), collision_radius_m):
		_add_collision(key)


func _array_mesh_from_data(data: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	if not (data["indices"] as PackedInt32Array).is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _coastal_coating_material() -> StandardMaterial3D:
	if _coastal_slate_material == null:
		_coastal_slate_material = StandardMaterial3D.new()
		_coastal_slate_material.albedo_color = Color(0.095, 0.115, 0.135)
		_coastal_slate_material.roughness = 0.93
		_coastal_slate_material.metallic = 0.03
		_coastal_slate_material.metallic_specular = 0.18
	return _coastal_slate_material


func _terrain_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = TERRAIN_SHADER
		var bake_seed := 90210
		if _layout != null and _layout.get("seed") != null:
			bake_seed = int(_layout.get("seed"))
		TERRAIN_SURFACE_MAPS.bind_to_material(_material, bake_seed)
		_bind_forest_coverage(_material)
	return _material


func _bind_forest_coverage(material: ShaderMaterial) -> void:
	if ForestField.is_initialized():
		material.set_shader_parameter("forest_map", ForestField.coverage_texture())
		material.set_shader_parameter("forest_world_half_extent_m", ForestField.world_half_extent_m())
	else:
		var blank := Image.create(4, 4, false, Image.FORMAT_R8)
		blank.fill(Color(0, 0, 0))
		material.set_shader_parameter("forest_map", ImageTexture.create_from_image(blank))
		material.set_shader_parameter("forest_world_half_extent_m", 20000.0)


func _sync_collisions(stream_position: Vector3) -> void:
	var stream_xz := Vector2(stream_position.x, stream_position.z)
	for key in _chunks:
		var coord := parse_chunk_key(StringName(key))
		var record := _chunks[key] as Dictionary
		var wanted := chunk_needs_collision(coord, stream_xz, collision_radius_m)
		if wanted and not _has_collision_state(record):
			_add_collision(StringName(key))
		elif not wanted and _has_collision_state(record):
			var body: Variant = record["collision"]
			if body is StaticBody3D and is_instance_valid(body):
				(body as StaticBody3D).queue_free()
			record["collision"] = null


func _add_collision(key: StringName) -> void:
	if not _chunks.has(key):
		return
	var record := _chunks[key] as Dictionary
	if _has_collision_state(record):
		return
	var data := record["surface_data"] as Dictionary
	var faces := collision_faces(data)
	if faces.is_empty():
		# Open-water / fully submerged chunks have no walkable faces. Mark them
		# resolved so boot readiness does not wait forever on null collision.
		record["collision"] = true
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape_node := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape_node.shape = shape
	body.add_child(shape_node)
	(record["node"] as Node3D).add_child(body)
	record["collision"] = body


func _has_collision_state(record: Dictionary) -> bool:
	return record.get("collision", null) != null


## Boot/visual readiness: chunk is loaded and, if inside the collision ring,
## collision has been built or explicitly skipped (open water).
func _chunk_collision_ready(record: Dictionary) -> bool:
	return _has_collision_state(record)


func _unload_chunk(key: StringName) -> void:
	if not _chunks.has(key):
		return
	var record := _chunks[key] as Dictionary
	var node := record.get("node", null) as Node
	if is_instance_valid(node):
		node.queue_free()
	_chunks.erase(key)


func _clear_chunks() -> void:
	for key in _chunks.keys():
		_unload_chunk(StringName(key))
	_jobs.clear()
	_queued.clear()


func _rebuild_loaded_chunks() -> void:
	if _layout == null:
		return
	_jobs.clear()
	_queued.clear()
	for key in _chunks:
		var record := _chunks[key] as Dictionary
		_enqueue({"coord": parse_chunk_key(StringName(key)), "lod": int(record["lod"]), "distance": 0.0})


## Pure helper. Port records may be PortDefinition objects or dictionaries.
## Optional dictionary keys: flatten_shape ("ellipse"/"rectangle"), pad_size_m
## (Vector2 or [x,z]), flatten_falloff_m, and pad_height_m.
static func make_flatten_zones(port_definitions: Array, default_pad_height_m := 0.0) -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	for definition in port_definitions:
		var position := Vector3.ZERO
		var yaw := 0.0
		var size_class := 1
		var shape := "rectangle"
		var pad_size := Vector2.ZERO
		var falloff := -1.0
		var height := default_pad_height_m
		if definition is Dictionary:
			var d := definition as Dictionary
			var raw_position: Variant = d.get("world_position", Vector3.ZERO)
			if raw_position is Vector3:
				position = raw_position
			elif raw_position is Dictionary:
				position = Vector3(float(raw_position.get("x", 0.0)), float(raw_position.get("y", 0.0)), float(raw_position.get("z", 0.0)))
			yaw = float(d.get("rotation_y", 0.0))
			size_class = int(d.get("size", 1))
			shape = String(d.get("flatten_shape", "rectangle"))
			pad_size = _variant_to_vector2(d.get("pad_size_m", Vector2.ZERO))
			falloff = float(d.get("flatten_falloff_m", -1.0))
			height = float(d.get("pad_height_m", default_pad_height_m))
		elif definition is Object:
			position = definition.get("world_position") as Vector3
			yaw = float(definition.get("rotation_y"))
			size_class = int(definition.get("size"))
		if pad_size == Vector2.ZERO:
			# Mirrors PortExpander island/facility widths plus PortPlot's safe
			# margin. Depth remains compact because every plot is 140 m deep.
			pad_size = Vector2(
				PORT_PAD_WIDTH_BY_SIZE[PortSizing.normalized_size(size_class)],
				PortSizing.PAD_DEPTH_M,
			)
		if falloff < 0.0:
			falloff = 70.0 + float(clampi(size_class, 0, 4)) * 15.0
		var seaward := Vector2(-sin(yaw), -cos(yaw))
		var center := Vector2(position.x, position.z) + seaward * PORT_PAD_SEAWARD_SHIFT_M
		zones.append({
			"center": center,
			"yaw": yaw,
			"half_size": pad_size * 0.5,
			"falloff": falloff,
			"height": height,
			"shape": shape,
		})
	return zones


## Pure deterministic terrain sample including configured flatten pads.
static func sample_terrain_height(layout: Object, world_xz: Vector2, flatten_zones: Array = []) -> float:
	var signed_distance := float(layout.sample_signed_distance(world_xz))
	var height := 0.0 if signed_distance >= 0.0 \
		else float(layout.sample_height(world_xz)) - TERRAIN_SINK_M
	height = _apply_flatten_zones(height, signed_distance, world_xz, flatten_zones)
	return height


## Render sample includes a short submerged continuation beyond the SDF coast.
## This lets water cover the shelf instead of meeting a perfectly smooth edge.
static func sample_render_terrain_height(
		layout: Object,
		world_xz: Vector2,
		flatten_zones: Array = [],
) -> float:
	var signed_distance := float(layout.sample_signed_distance(world_xz))
	var height := float(layout.sample_height(world_xz)) - TERRAIN_SINK_M
	return _apply_flatten_zones(height, signed_distance, world_xz, flatten_zones)


static func _apply_flatten_zones(
		height: float,
		signed_distance: float,
		world_xz: Vector2,
		flatten_zones: Array,
) -> float:
	for zone_variant in flatten_zones:
		var zone := zone_variant as Dictionary
		var local := (world_xz - (zone["center"] as Vector2)).rotated(-float(zone["yaw"]))
		var half_size: Vector2 = zone["half_size"]
		var falloff := maxf(float(zone["falloff"]), 0.001)
		var edge_distance: float
		if String(zone.get("shape", "rectangle")) == "ellipse":
			var normalized := Vector2(local.x / maxf(half_size.x, 0.001), local.y / maxf(half_size.y, 0.001))
			edge_distance = (normalized.length() - 1.0) * minf(half_size.x, half_size.y)
		else:
			var q := Vector2(absf(local.x), absf(local.y)) - half_size
			edge_distance = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
		var blend := 1.0 - smoothstep(0.0, falloff, maxf(edge_distance, 0.0))
		if edge_distance <= 0.0:
			blend = 1.0
		# Pads keep land at the authored port datum. Their seaward overlap stays
		# submerged so it cannot create a water-level terrain sheet.
		if signed_distance < 0.0:
			height = lerpf(height, float(zone["height"]), blend)
	return height


## Pure helper returning render-ready packed arrays. Full land cells keep their
## two triangles. Mixed shoreline cells clip against a short submerged SDF
## offset, allowing the shelf to continue beneath the ocean.
static func build_chunk_mesh_data(
		layout: Object,
		coord: Vector2i,
		step_m: float,
		flatten_zones: Array = [],
		skirt_depth_m := SKIRT_DEPTH_M,
) -> Dictionary:
	assert(step_m > 0.0 and is_equal_approx(fmod(CHUNK_SIZE_M, step_m), 0.0))
	var cells := int(round(CHUNK_SIZE_M / step_m))
	var side := cells + 1
	var origin := chunk_origin(coord)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var signed_distances := PackedFloat32Array()
	var clip_distances := PackedFloat32Array()
	vertices.resize(side * side)
	colors.resize(side * side)
	signed_distances.resize(side * side)
	clip_distances.resize(side * side)
	for z in range(side):
		for x in range(side):
			var index := z * side + x
			var world_xz := origin + Vector2(float(x) * step_m, float(z) * step_m)
			var distance := float(layout.sample_signed_distance(world_xz))
			var height := sample_render_terrain_height(layout, world_xz, flatten_zones)
			vertices[index] = Vector3(world_xz.x, height, world_xz.y)
			signed_distances[index] = distance
			clip_distances[index] = distance - SUBMERGED_SHELF_EXTENT_M
			colors[index] = terrain_color(height, distance)

	var indices := PackedInt32Array()
	for z in range(cells):
		for x in range(cells):
			var a := z * side + x
			var b := a + 1
			var c := a + side
			var d := c + 1
			_append_cell_land(
				vertices,
				colors,
				indices,
				clip_distances,
				a, b, c, d,
			)

	var surface_vertex_count := vertices.size()
	var normals := calculate_terrain_normals(
		layout,
		vertices,
		indices,
		side,
		flatten_zones,
	)
	if not indices.is_empty():
		# Surface normals must be finished before skirts add vertical triangles;
		# otherwise every chunk edge becomes a dark one-kilometre frame.
		_append_skirts(vertices, colors, indices, clip_distances, side, skirt_depth_m, normals)
	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"signed_distances": signed_distances,
		"surface_side": side,
		"surface_vertex_count": surface_vertex_count,
		"coord": coord,
		"step_m": step_m,
	}


## Extracts one continuous, slightly raised surface from coastal terrain
## triangles. Vertex alpha already carries the world-space shore-band weight.
## The result uses only referenced coastal vertices, avoiding full-mesh copies.
static func build_coastal_coating_mesh_data(
		terrain_data: Dictionary,
		min_coast_weight: float = 0.32,
		max_height_m: float = 12.0,
) -> Dictionary:
	var source_vertices: PackedVector3Array = terrain_data["vertices"]
	var source_normals: PackedVector3Array = terrain_data["normals"]
	var source_colors: PackedColorArray = terrain_data["colors"]
	var source_indices: PackedInt32Array = terrain_data["indices"]
	var surface_limit := int(terrain_data["surface_vertex_count"])
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for triangle in range(0, source_indices.size(), 3):
		var ia := source_indices[triangle]
		var ib := source_indices[triangle + 1]
		var ic := source_indices[triangle + 2]
		# Exclude crack skirts. The coating belongs to the terrain top only.
		if ia >= surface_limit or ib >= surface_limit or ic >= surface_limit:
			continue
		# Cheap reject before allocating clipping dictionaries. Almost every
		# inland triangle exits here.
		if maxf(
			source_colors[ia].a,
			maxf(source_colors[ib].a, source_colors[ic].a),
		) < min_coast_weight:
			continue
		if minf(
			source_vertices[ia].y,
			minf(source_vertices[ib].y, source_vertices[ic].y),
		) > max_height_m:
			continue
		var polygon: Array[Dictionary] = [
			{
				"position": source_vertices[ia],
				"normal": source_normals[ia],
				"coast": source_colors[ia].a,
			},
			{
				"position": source_vertices[ib],
				"normal": source_normals[ib],
				"coast": source_colors[ib].a,
			},
			{
				"position": source_vertices[ic],
				"normal": source_normals[ic],
				"coast": source_colors[ic].a,
			},
		]
		polygon = _clip_coating_by_coast(polygon, min_coast_weight)
		polygon = _clip_coating_by_height(polygon, max_height_m)
		if polygon.size() < 3:
			continue
		for fan_index in range(1, polygon.size() - 1):
			for point in [polygon[0], polygon[fan_index], polygon[fan_index + 1]]:
				var normal := (point["normal"] as Vector3).normalized()
				vertices.append(
					(point["position"] as Vector3) + normal * COASTAL_COATING_OFFSET_M
				)
				colors.append(Color.WHITE)
				normals.append(normal)
				indices.append(vertices.size() - 1)

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
	}


static func _clip_coating_by_coast(
		polygon: Array[Dictionary],
		min_coast_weight: float,
) -> Array[Dictionary]:
	if polygon.is_empty():
		return []
	var result: Array[Dictionary] = []
	var previous: Dictionary = polygon.back()
	var previous_inside := float(previous["coast"]) >= min_coast_weight
	for current in polygon:
		var current_inside := float(current["coast"]) >= min_coast_weight
		if current_inside != previous_inside:
			var denominator := float(current["coast"]) - float(previous["coast"])
			var t := 0.5 if absf(denominator) < 0.000001 \
				else clampf(
					(min_coast_weight - float(previous["coast"])) / denominator,
					0.0,
					1.0,
				)
			result.append(_lerp_coating_point(previous, current, t))
		if current_inside:
			result.append(current)
		previous = current
		previous_inside = current_inside
	return result


static func _clip_coating_by_height(
		polygon: Array[Dictionary],
		max_height_m: float,
) -> Array[Dictionary]:
	if polygon.is_empty():
		return []
	var result: Array[Dictionary] = []
	var previous: Dictionary = polygon.back()
	var previous_height := (previous["position"] as Vector3).y
	var previous_inside := previous_height <= max_height_m
	for current in polygon:
		var current_height := (current["position"] as Vector3).y
		var current_inside := current_height <= max_height_m
		if current_inside != previous_inside:
			var denominator := current_height - previous_height
			var t := 0.5 if absf(denominator) < 0.000001 \
				else clampf((max_height_m - previous_height) / denominator, 0.0, 1.0)
			result.append(_lerp_coating_point(previous, current, t))
		if current_inside:
			result.append(current)
		previous = current
		previous_height = current_height
		previous_inside = current_inside
	return result


static func _lerp_coating_point(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"position": (a["position"] as Vector3).lerp(b["position"] as Vector3, t),
		"normal": (a["normal"] as Vector3).lerp(b["normal"] as Vector3, t).normalized(),
		"coast": lerpf(float(a["coast"]), float(b["coast"]), t),
	}


## Corner order for mask bits: a=bit0, b=bit1, d=bit2, c=bit3 (CW from -Z/-X).
static func _append_cell_land(
		vertices: PackedVector3Array,
		colors: PackedColorArray,
		indices: PackedInt32Array,
		signed_distances: PackedFloat32Array,
		a: int,
		b: int,
		c: int,
		d: int,
) -> void:
	var da := signed_distances[a]
	var db := signed_distances[b]
	var dc := signed_distances[c]
	var dd := signed_distances[d]
	var mask := int(da < 0.0) | (int(db < 0.0) << 1) | (int(dd < 0.0) << 2) | (int(dc < 0.0) << 3)
	if mask == 0:
		return
	if mask == 15:
		# Godot's spatial front face is clockwise from above.
		indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
		return

	var edge_ab := _shore_edge_vertex(vertices, colors, a, b, da, db)
	var edge_bd := _shore_edge_vertex(vertices, colors, b, d, db, dd)
	var edge_dc := _shore_edge_vertex(vertices, colors, d, c, dd, dc)
	var edge_ca := _shore_edge_vertex(vertices, colors, c, a, dc, da)
	var poly := PackedInt32Array()
	match mask:
		1: poly = PackedInt32Array([a, edge_ab, edge_ca])
		2: poly = PackedInt32Array([b, edge_bd, edge_ab])
		3: poly = PackedInt32Array([a, b, edge_bd, edge_ca])
		4: poly = PackedInt32Array([d, edge_dc, edge_bd])
		5:
			# Ambiguous saddle: fixed lower-left split matching contour extraction.
			_fan_poly(indices, PackedInt32Array([a, edge_ab, edge_ca]))
			_fan_poly(indices, PackedInt32Array([d, edge_dc, edge_bd]))
			return
		6: poly = PackedInt32Array([b, d, edge_dc, edge_ab])
		7: poly = PackedInt32Array([a, b, d, edge_dc, edge_ca])
		8: poly = PackedInt32Array([c, edge_ca, edge_dc])
		9: poly = PackedInt32Array([a, edge_ab, edge_dc, c])
		10:
			_fan_poly(indices, PackedInt32Array([b, edge_bd, edge_ab]))
			_fan_poly(indices, PackedInt32Array([c, edge_ca, edge_dc]))
			return
		11: poly = PackedInt32Array([a, b, edge_bd, edge_dc, c])
		12: poly = PackedInt32Array([d, c, edge_ca, edge_bd])
		13: poly = PackedInt32Array([a, edge_ab, edge_bd, d, c])
		14: poly = PackedInt32Array([b, d, c, edge_ca, edge_ab])
		_:
			return
	_fan_poly(indices, poly)


static func _fan_poly(indices: PackedInt32Array, poly: PackedInt32Array) -> void:
	if poly.size() < 3:
		return
	for i in range(1, poly.size() - 1):
		indices.append_array(PackedInt32Array([poly[0], poly[i], poly[i + 1]]))


static func _shore_edge_vertex(
		vertices: PackedVector3Array,
		colors: PackedColorArray,
		ia: int,
		ib: int,
		da: float,
		db: float,
) -> int:
	var denominator := da - db
	var t := 0.5 if absf(denominator) < 0.000001 else clampf(da / denominator, 0.0, 1.0)
	var pa := vertices[ia]
	var pb := vertices[ib]
	var point := pa.lerp(pb, t)
	vertices.append(point)
	colors.append(terrain_color(point.y, SUBMERGED_SHELF_EXTENT_M))
	return vertices.size() - 1


## Pure ordered border samples, excluding skirts. These are useful for seam tests.
static func sample_chunk_border(layout: Object, coord: Vector2i, step_m: float, edge: StringName, flatten_zones: Array = []) -> PackedVector3Array:
	var data := build_chunk_mesh_data(layout, coord, step_m, flatten_zones, 0.0)
	var vertices: PackedVector3Array = data["vertices"]
	var side := int(data["surface_side"])
	var result := PackedVector3Array()
	for i in range(side):
		match edge:
			&"north":
				result.append(vertices[i])
			&"south":
				result.append(vertices[(side - 1) * side + i])
			&"west":
				result.append(vertices[i * side])
			&"east":
				result.append(vertices[i * side + side - 1])
			_:
				assert(false, "edge must be north, south, west, or east")
	return result


static func select_chunk_requests(
		stream_xz: Vector2,
		half_extent_m: float,
		visual_radius: float,
		lod_distances = DEFAULT_LOD_DISTANCES,
) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var minimum := int(floor(-half_extent_m / CHUNK_SIZE_M))
	var maximum := int(ceil(half_extent_m / CHUNK_SIZE_M)) - 1
	var center_coord := world_to_chunk(stream_xz)
	var chunk_radius := int(ceil(visual_radius / CHUNK_SIZE_M)) + 1
	for z in range(maxi(minimum, center_coord.y - chunk_radius), mini(maximum, center_coord.y + chunk_radius) + 1):
		for x in range(maxi(minimum, center_coord.x - chunk_radius), mini(maximum, center_coord.x + chunk_radius) + 1):
			var coord := Vector2i(x, z)
			var distance := distance_to_chunk(coord, stream_xz)
			if distance > visual_radius:
				continue
			var lod := 0
			while lod < lod_distances.size() and distance > lod_distances[lod]:
				lod += 1
			requests.append({"coord": coord, "lod": lod, "distance": distance})
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	return requests


static func chunk_needs_collision(coord: Vector2i, stream_xz: Vector2, radius_m: float) -> bool:
	return radius_m > 0.0 and distance_to_chunk(coord, stream_xz) <= radius_m


## Pure queue-budget helper mirrored by _process_jobs.
static func job_count_for_frame(pending_count: int, max_jobs: int) -> int:
	return mini(maxi(pending_count, 0), maxi(max_jobs, 1))


## Prevents chunks near an LOD ring from rebuilding whenever the camera moves a
## few metres back and forth across the threshold.
static func stabilize_lod(
		requested_lod: int,
		loaded_lod: int,
		distance_m: float,
		lod_distances,
		hysteresis_m: float,
) -> int:
	if requested_lod == loaded_lod or lod_distances.is_empty():
		return requested_lod
	if requested_lod > loaded_lod:
		var outward_boundary := float(lod_distances[clampi(loaded_lod, 0, lod_distances.size() - 1)])
		if distance_m < outward_boundary + hysteresis_m:
			return loaded_lod
	else:
		var inward_boundary := float(lod_distances[clampi(requested_lod, 0, lod_distances.size() - 1)])
		if distance_m > inward_boundary - hysteresis_m:
			return loaded_lod
	return requested_lod


static func distance_to_chunk(coord: Vector2i, world_xz: Vector2) -> float:
	var origin := chunk_origin(coord)
	var nearest := Vector2(
		clampf(world_xz.x, origin.x, origin.x + CHUNK_SIZE_M),
		clampf(world_xz.y, origin.y, origin.y + CHUNK_SIZE_M),
	)
	return world_xz.distance_to(nearest)


static func world_to_chunk(world_xz: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_xz.x / CHUNK_SIZE_M)), int(floor(world_xz.y / CHUNK_SIZE_M)))


static func chunk_origin(coord: Vector2i) -> Vector2:
	return Vector2(float(coord.x) * CHUNK_SIZE_M, float(coord.y) * CHUNK_SIZE_M)


static func chunk_key(coord: Vector2i) -> StringName:
	return StringName("%d:%d" % [coord.x, coord.y])


static func parse_chunk_key(key: StringName) -> Vector2i:
	var parts := String(key).split(":")
	return Vector2i(int(parts[0]), int(parts[1]))


static func collision_faces(data: Dictionary) -> PackedVector3Array:
	var vertices: PackedVector3Array = data["vertices"]
	var indices: PackedInt32Array = data["indices"]
	var surface_limit := int(data["surface_vertex_count"])
	var faces := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		if indices[i] < surface_limit and indices[i + 1] < surface_limit and indices[i + 2] < surface_limit:
			faces.append(vertices[indices[i]])
			faces.append(vertices[indices[i + 1]])
			faces.append(vertices[indices[i + 2]])
	return faces


static func estimate_mesh_memory(data: Dictionary) -> int:
	return (data["vertices"] as PackedVector3Array).size() * BYTES_PER_VERTEX_ESTIMATE \
		+ (data["indices"] as PackedInt32Array).size() * BYTES_PER_INDEX_ESTIMATE


static func terrain_color(height: float, signed_distance: float = -999.0) -> Color:
	# Shader owns albedo. Vertex colour alpha = coastal rock weight
	# (1 = waterline / svaberg / rock-face band, 0 = deep inland).
	var inland := maxf(-signed_distance, 0.0) if signed_distance > -900.0 else maxf(height * 8.0, 0.0)
	var coast_w := 1.0 - smoothstep(6.0, 130.0, inland)
	var tint := Color(0.32, 0.33, 0.325).lerp(Color(0.18, 0.26, 0.14), 1.0 - coast_w)
	tint.a = coast_w
	return tint


static func calculate_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		# Geometry uses Godot's clockwise front face; reverse the conventional
		# cross product so top-surface shading normals still point upward.
		var normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in range(normals.size()):
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 0.0 else Vector3.UP
	return normals


## World-sampled surface normals remain identical across chunk and LOD borders.
## Triangle-averaged chunk normals expose the 1 km streaming grid, especially
## when skirts contribute vertical faces to a border vertex.
static func calculate_terrain_normals(
		layout: Object,
		vertices: PackedVector3Array,
		indices: PackedInt32Array,
		side: int,
		flatten_zones: Array = [],
) -> PackedVector3Array:
	var normals := calculate_normals(vertices, indices)
	const SAMPLE_OFFSET_M := 40.0
	# Interior normals already share adjacent triangles and are cheap. Only the
	# outer grid ring lacks neighbours from the next chunk / LOD.
	var border_indices := PackedInt32Array()
	for i in range(side):
		border_indices.append(i)
		border_indices.append((side - 1) * side + i)
	for i in range(1, side - 1):
		border_indices.append(i * side)
		border_indices.append(i * side + side - 1)
	for vertex_index in border_indices:
		if vertex_index >= vertices.size():
			continue
		var vertex := vertices[vertex_index]
		var xz := Vector2(vertex.x, vertex.z)
		var left := sample_render_terrain_height(
			layout, xz - Vector2(SAMPLE_OFFSET_M, 0.0), flatten_zones
		)
		var right := sample_render_terrain_height(
			layout, xz + Vector2(SAMPLE_OFFSET_M, 0.0), flatten_zones
		)
		var north := sample_render_terrain_height(
			layout, xz - Vector2(0.0, SAMPLE_OFFSET_M), flatten_zones
		)
		var south := sample_render_terrain_height(
			layout, xz + Vector2(0.0, SAMPLE_OFFSET_M), flatten_zones
		)
		normals[vertex_index] = Vector3(
			left - right,
			SAMPLE_OFFSET_M * 2.0,
			north - south,
		).normalized()
	return normals


static func _append_skirts(
		vertices: PackedVector3Array,
		colors: PackedColorArray,
		indices: PackedInt32Array,
		signed_distances: PackedFloat32Array,
		side: int,
		depth: float,
		normals := PackedVector3Array(),
) -> void:
	if depth <= 0.0:
		return
	var edges: Array[PackedInt32Array] = []
	var north := PackedInt32Array()
	var east := PackedInt32Array()
	var south := PackedInt32Array()
	var west := PackedInt32Array()
	for i in range(side):
		north.append(i)
		east.append(i * side + side - 1)
		south.append((side - 1) * side + (side - 1 - i))
		west.append((side - 1 - i) * side)
	edges.assign([north, east, south, west])
	# Soften chunk-edge "grid" lines: skirts exist to hide cracks, but dark
	# vertical walls read as a kilometre lattice from altitude. Tint them to
	# the surface colour and keep them short.
	for edge in edges:
		var skirt_start := vertices.size()
		for surface_index in edge:
			var vertex := vertices[surface_index]
			vertices.append(Vector3(vertex.x, vertex.y - depth, vertex.z))
			colors.append(colors[surface_index])
			if not normals.is_empty():
				# Matching the top normal makes a short crack-hiding skirt read
				# as a continuation rather than a separately lit wall.
				normals.append(normals[surface_index])
		for i in range(edge.size() - 1):
			var a := edge[i]
			var b := edge[i + 1]
			if signed_distances[a] >= 0.0 or signed_distances[b] >= 0.0:
				continue
			var c := skirt_start + i
			var d := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))


static func _variant_to_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", value.get("z", 0.0))))
	return Vector2.ZERO
