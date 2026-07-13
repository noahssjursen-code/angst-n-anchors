class_name WorldForestStreamer
extends Node3D

## Streams decorative forest Multimeshes keyed to the same 1 km chunk grid as
## terrain. Geometry stops at WorldPropLod ranges; far canopy is shader-only.

const WorldReferenceScript := preload("res://scripts/world/world_reference.gd")
const PROP_LOD := preload("res://scripts/world/world_prop_lod.gd")
const TREE_MESH := preload("res://scripts/world/forest_tree_mesh.gd")
const STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")

const CHUNK_SIZE_M := 1000.0
const NEAR_STEP_M := 22.0
const MID_STEP_M := 34.0
const MAX_NEAR_PER_CHUNK := 160
const MAX_MID_PER_CHUNK := 90
const DENSITY_GATE := 0.10
const LOD_HYSTERESIS_M := 220.0
## Decorative overscale so spruce massing reads from boat / freecam altitude.
const TREE_SCALE_MIN := 1.92
const TREE_SCALE_MAX := 3.36

@export_range(0.25, 8.0, 0.25) var build_budget_ms := 2.0
@export_range(1, 4, 1) var max_jobs_per_frame := 1
@export_range(1, 16, 1) var queue_refresh_frames := 5

var _layout: Object
var _flatten_zones: Array = []
var _chunks: Dictionary = {}
var _jobs: Array[Dictionary] = []
var _queued: Dictionary = {}
var _frame_index := 0


func configure(layout: Object, flatten_zones: Array = []) -> void:
	_clear_chunks()
	_layout = layout
	_flatten_zones = flatten_zones
	_frame_index = 0
	set_process(_layout != null)
	if _layout != null:
		_refresh_requests(WorldReferenceScript.stream_position(get_viewport()))


func _ready() -> void:
	set_process(_layout != null)


func _exit_tree() -> void:
	_clear_chunks()


func _process(_delta: float) -> void:
	if _layout == null:
		return
	var stream_position := WorldReferenceScript.stream_position(get_viewport())
	if _frame_index % maxi(queue_refresh_frames, 1) == 0:
		_refresh_requests(stream_position)
	_process_jobs()
	_frame_index += 1


func get_debug_stats() -> Dictionary:
	var instances := 0
	for value in _chunks.values():
		instances += int((value as Dictionary).get("instances", 0))
	return {
		"loaded": _chunks.size(),
		"pending": _jobs.size(),
		"instances": instances,
	}


func _refresh_requests(stream_position: Vector3) -> void:
	var stream_xz := Vector2(stream_position.x, stream_position.z)
	var half := float(_layout.half_extent_m)
	var desired := select_chunk_requests(stream_xz, half, PROP_LOD.CULL_M)
	var desired_keys := {}
	for request in desired:
		var coord: Vector2i = request["coord"]
		var key := STREAMER.chunk_key(coord)
		var loaded := _chunks.get(key, {}) as Dictionary
		if not loaded.is_empty():
			request["tier"] = stabilize_tier(
				int(request["tier"]),
				int(loaded.get("tier", PROP_LOD.Tier.CULLED)),
				float(request["distance"]),
			)
		desired_keys[key] = int(request["tier"])
		if loaded.is_empty() or int(loaded.get("tier", -1)) != int(request["tier"]):
			if int(request["tier"]) != PROP_LOD.Tier.CULLED:
				_enqueue(request)

	var remove_keys: Array = []
	for key in _chunks:
		if not desired_keys.has(key) or int(desired_keys[key]) == PROP_LOD.Tier.CULLED:
			remove_keys.append(key)
	for key in remove_keys:
		_unload_chunk(StringName(key))

	var retained: Array[Dictionary] = []
	_queued.clear()
	for job in _jobs:
		var key := STREAMER.chunk_key(job["coord"])
		if desired_keys.has(key) and int(desired_keys[key]) == int(job["tier"]) \
				and int(job["tier"]) != PROP_LOD.Tier.CULLED:
			retained.append(job)
			_queued[key] = int(job["tier"])
	_jobs = retained
	for request in desired:
		var key := STREAMER.chunk_key(request["coord"])
		var loaded := _chunks.get(key, {}) as Dictionary
		if int(request["tier"]) == PROP_LOD.Tier.CULLED:
			continue
		if (loaded.is_empty() or int(loaded.get("tier", -1)) != int(request["tier"])) \
				and not _queued.has(key):
			_enqueue(request)


func _enqueue(request: Dictionary) -> void:
	var key := STREAMER.chunk_key(request["coord"])
	var tier := int(request["tier"])
	if _queued.get(key, -1) == tier:
		return
	_queued[key] = tier
	_jobs.append(request)


func _process_jobs() -> void:
	var frame_started := Time.get_ticks_usec()
	var completed := 0
	while not _jobs.is_empty() and completed < maxi(max_jobs_per_frame, 1):
		if completed > 0 and float(Time.get_ticks_usec() - frame_started) / 1000.0 >= build_budget_ms:
			break
		var job := _jobs.pop_front() as Dictionary
		var coord: Vector2i = job["coord"]
		_queued.erase(STREAMER.chunk_key(coord))
		_build_chunk(coord, int(job["tier"]))
		completed += 1


func _build_chunk(coord: Vector2i, tier: int) -> void:
	var key := STREAMER.chunk_key(coord)
	_unload_chunk(key)
	if tier == PROP_LOD.Tier.CULLED or tier == PROP_LOD.Tier.BILLBOARD_OR_SKIP:
		return
	var near := tier == PROP_LOD.Tier.FULL
	var transforms := build_chunk_transforms(
		_layout,
		coord,
		NEAR_STEP_M if near else MID_STEP_M,
		MAX_NEAR_PER_CHUNK if near else MAX_MID_PER_CHUNK,
		_flatten_zones,
	)
	if transforms.is_empty():
		return

	var root := Node3D.new()
	root.name = "Forest_%d_%d_T%d" % [coord.x, coord.y, tier]
	add_child(root)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = TREE_MESH.near_mesh() if near else TREE_MESH.mid_mesh()
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	mmi.multimesh = mm
	mmi.material_override = TREE_MESH.near_material() if near else TREE_MESH.mid_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)

	_chunks[key] = {
		"node": root,
		"tier": tier,
		"instances": transforms.size(),
	}


func _unload_chunk(key: StringName) -> void:
	var record := _chunks.get(key, {}) as Dictionary
	if record.is_empty():
		return
	var node := record.get("node", null) as Node
	if node != null:
		node.queue_free()
	_chunks.erase(key)


func _clear_chunks() -> void:
	for key in _chunks.keys():
		_unload_chunk(StringName(key))
	_chunks.clear()
	_jobs.clear()
	_queued.clear()


static func select_chunk_requests(
		stream_xz: Vector2,
		half_extent_m: float,
		visual_radius: float,
) -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var minimum := int(floor(-half_extent_m / CHUNK_SIZE_M))
	var maximum := int(ceil(half_extent_m / CHUNK_SIZE_M)) - 1
	var center := STREAMER.world_to_chunk(stream_xz)
	var chunk_radius := int(ceil(visual_radius / CHUNK_SIZE_M)) + 1
	for z in range(maxi(minimum, center.y - chunk_radius), mini(maximum, center.y + chunk_radius) + 1):
		for x in range(maxi(minimum, center.x - chunk_radius), mini(maximum, center.x + chunk_radius) + 1):
			var coord := Vector2i(x, z)
			var distance := STREAMER.distance_to_chunk(coord, stream_xz)
			if distance > visual_radius:
				continue
			var tier := int(PROP_LOD.tier_for_distance(distance))
			requests.append({"coord": coord, "tier": tier, "distance": distance})
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"])
	)
	return requests


static func stabilize_tier(requested: int, loaded: int, distance_m: float) -> int:
	if requested == loaded:
		return requested
	# Keep geometry a bit longer when leaving FULL / PROXY so freecam does not thrash.
	if requested > loaded:
		if loaded == PROP_LOD.Tier.FULL and distance_m < PROP_LOD.LOD_NEAR_M + LOD_HYSTERESIS_M:
			return loaded
		if loaded == PROP_LOD.Tier.PROXY and distance_m < PROP_LOD.LOD_FAR_M + LOD_HYSTERESIS_M:
			return loaded
	else:
		if requested == PROP_LOD.Tier.FULL and distance_m > PROP_LOD.LOD_NEAR_M - LOD_HYSTERESIS_M:
			return loaded
		if requested == PROP_LOD.Tier.PROXY and distance_m > PROP_LOD.LOD_MID_M - LOD_HYSTERESIS_M:
			return loaded
	return requested


static func build_chunk_transforms(
		layout: Object,
		coord: Vector2i,
		step_m: float,
		max_instances: int,
		flatten_zones: Array = [],
) -> Array[Transform3D]:
	var origin := STREAMER.chunk_origin(coord)
	var transforms: Array[Transform3D] = []
	var cells := int(floor(CHUNK_SIZE_M / step_m))
	for z in range(cells):
		for x in range(cells):
			if transforms.size() >= max_instances:
				return transforms
			var cell := Vector2(
				origin.x + (float(x) + 0.5) * step_m,
				origin.y + (float(z) + 0.5) * step_m,
			)
			var h := _hash01(coord.x, coord.y, x, z)
			var jitter := Vector2((h - 0.5) * step_m * 0.7, (_hash01(coord.y, coord.x, z, x) - 0.5) * step_m * 0.7)
			var world_xz := cell + jitter
			var density := ForestField.sample(world_xz)
			if density < DENSITY_GATE:
				continue
			if h > density:
				continue
			# Flatten pads already zero ForestField; keep a hard reject for safety.
			if _in_flatten(world_xz, flatten_zones):
				continue
			var height := STREAMER.sample_terrain_height(layout, world_xz, flatten_zones)
			if height < 1.2:
				continue
			var yaw := h * TAU
			var scale := lerpf(TREE_SCALE_MIN, TREE_SCALE_MAX, _hash01(x, z, coord.x, coord.y))
			var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0)).scaled(Vector3(scale, scale, scale))
			transforms.append(Transform3D(basis, Vector3(world_xz.x, height, world_xz.y)))
	return transforms


static func _in_flatten(world_xz: Vector2, flatten_zones: Array) -> bool:
	for zone_variant in flatten_zones:
		var zone := zone_variant as Dictionary
		var local := (world_xz - (zone["center"] as Vector2)).rotated(-float(zone["yaw"]))
		var half_size: Vector2 = zone["half_size"]
		var falloff := maxf(float(zone.get("falloff", 0.0)), 0.0)
		var pad := half_size + Vector2(falloff * 0.5, falloff * 0.5)
		if absf(local.x) <= pad.x and absf(local.y) <= pad.y:
			return true
	return false


static func _hash01(a: int, b: int, c: int, d: int) -> float:
	var n := a * 374761393 + b * 668265263 + c * 1274126177 + d * 2246822519
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0x7fffffff) / float(0x7fffffff)
