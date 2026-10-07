class_name WorldForestStreamer
extends Node3D

## Streams decorative forest Multimeshes keyed to the independent 256 m patches over
## terrain. Geometry stops at WorldPropLod ranges; far canopy is shader-only.

const WorldReferenceScript := preload("res://scripts/world/world_reference.gd")
const PROP_LOD := preload("res://scripts/world/world_prop_lod.gd")
const TREE_MESH := preload("res://scripts/world/forest_tree_mesh.gd")
const STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")

const CHUNK_SIZE_M := 256.0
const NEAR_STEP_M := 6.5
const MID_STEP_M := 6.5
const MAX_NEAR_PER_CHUNK := 1521
const MAX_MID_PER_CHUNK := 1521
const DENSITY_GATE := 0.10
const LOD_HYSTERESIS_M := 60.0
## Authored metre-scale trees; no oversized silhouettes along the coastline.
const TREE_SCALE_MIN := 0.72
const TREE_SCALE_MAX := 1.45
const REQUEST_MOVE_THRESHOLD_M := 50.0

@export_range(0.25, 8.0, 0.25) var build_budget_ms := 2.0
@export_range(1, 4, 1) var max_jobs_per_frame := 1
@export_range(1, 16, 1) var queue_refresh_frames := 5

var _layout: Object
var _flatten_zones: Array = []
var _chunks: Dictionary = {}
var _jobs: Array[Dictionary] = []
var _queued: Dictionary = {}
var _frame_index := 0
var _last_request_xz := Vector2(INF, INF)
var _last_build_ms := 0.0
var _peak_build_ms := 0.0


func configure(layout: Object, flatten_zones: Array = []) -> void:
	_clear_chunks()
	_layout = layout
	_flatten_zones = flatten_zones
	_frame_index = 0
	_last_request_xz = Vector2(INF, INF)
	set_process(_layout != null)
	if _layout != null:
		TREE_MESH.request_assets()
		_refresh_requests(WorldReferenceScript.visual_position(get_viewport()))


func _ready() -> void:
	set_process(_layout != null)
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("register_provider"):
		telemetry.register_provider(&"world.forest", self, &"get_debug_stats", &"world")


func _exit_tree() -> void:
	TREE_MESH.finish_pending_requests()
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("unregister_provider"):
		telemetry.unregister_provider(&"world.forest", self)
	_clear_chunks()


func _process(_delta: float) -> void:
	if _layout == null:
		return
	var stream_position := WorldReferenceScript.visual_position(get_viewport())
	if _frame_index % maxi(queue_refresh_frames, 1) == 0 \
			and _should_refresh_requests(Vector2(stream_position.x, stream_position.z)):
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
		"last_build_ms": _last_build_ms,
		"peak_build_ms": _peak_build_ms,
	}


func _refresh_requests(stream_position: Vector3) -> void:
	var stream_xz := Vector2(stream_position.x, stream_position.z)
	_last_request_xz = stream_xz
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
		_unload_chunk(key)

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


func _should_refresh_requests(stream_xz: Vector2) -> bool:
	if not is_finite(_last_request_xz.x):
		return true
	return _last_request_xz.distance_squared_to(stream_xz) \
			>= REQUEST_MOVE_THRESHOLD_M * REQUEST_MOVE_THRESHOLD_M


func _enqueue(request: Dictionary) -> void:
	var key := STREAMER.chunk_key(request["coord"])
	var tier := int(request["tier"])
	if _queued.get(key, -1) == tier:
		return
	_queued[key] = tier
	_jobs.append(request)


func _process_jobs() -> void:
	if not TREE_MESH.assets_ready(): return
	var frame_started := Time.get_ticks_usec()
	var completed := 0
	while not _jobs.is_empty() and completed < maxi(max_jobs_per_frame, 1):
		if float(Time.get_ticks_usec() - frame_started) / 1000.0 >= build_budget_ms:
			break
		var job := _jobs[0] as Dictionary
		var coord: Vector2i = job["coord"]
		var key := STREAMER.chunk_key(coord)
		var started := Time.get_ticks_usec()
		var cached := _chunks.get(key, {}) as Dictionary
		if not cached.has("transforms"):
			if not job.has("placement"):
				job["placement"] = create_placement_job(coord, NEAR_STEP_M, MAX_NEAR_PER_CHUNK)
			var placement: Dictionary = job["placement"]
			# Bound the expensive terrain/coverage queries, not just the number
			# of entire patches. Keep incomplete work at the front of the queue.
			advance_placement_job(_layout, placement, _flatten_zones, 16, true)
			_last_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
			_peak_build_ms = maxf(_peak_build_ms, _last_build_ms)
			if not placement.done:
				continue
			_build_chunk(coord, int(job["tier"]), placement)
		else:
			_build_chunk(coord, int(job["tier"]))
		_jobs.pop_front()
		_queued.erase(key)
		_last_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
		_peak_build_ms = maxf(_peak_build_ms, _last_build_ms)
		completed += 1


func _build_chunk(coord: Vector2i, tier: int, prepared: Dictionary = {}) -> void:
	var key := STREAMER.chunk_key(coord)
	var previous := _chunks.get(key, {}) as Dictionary
	_unload_chunk(key)
	if tier == PROP_LOD.Tier.CULLED:
		return
	var near := tier == PROP_LOD.Tier.FULL
	var transforms: Array[Transform3D] = []
	if prepared.has("transforms"):
		transforms.assign(prepared["transforms"])
	elif previous.has("transforms"):
		transforms.assign(previous["transforms"])
	else:
		transforms = build_chunk_transforms(
			_layout,
			coord,
			NEAR_STEP_M,
			MAX_NEAR_PER_CHUNK if near else MAX_MID_PER_CHUNK,
			_flatten_zones,
		)
	if transforms.is_empty():
		# Remember empty sea/cleared patches too, rather than resampling all
		# their candidates every time the observer moves.
		_chunks[key] = {"node": null, "tier": tier, "instances": 0, "transforms": transforms}
		return

	var root := Node3D.new()
	root.name = "Forest_%d_%d_T%d" % [coord.x, coord.y, tier]
	add_child(root)

	var groups: Array = prepared.get("groups", previous.get("groups", []))
	if groups.is_empty():
		groups = [[], [], [], []]
		for xf in transforms:
			groups[coastal_species(_layout, Vector2(xf.origin.x,xf.origin.z))].append(xf)
	for species in 4:
		var selected: Array = groups[species]
		if selected.is_empty(): continue
		var mmi := MultiMeshInstance3D.new()
		mmi.name = TREE_MESH.SPECIES[species]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = TREE_MESH.species_mesh(species, near)
		mm.instance_count = selected.size()
		for i in selected.size(): mm.set_instance_transform(i, selected[i])
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		mmi.set_instance_shader_parameter("forest_lod_enabled", 1.0)
		if near:
			# The near patch contains both representations. Their shared shader
			# hands over per tree at140-200m, before CPU patch LOD can unload it.
			var far := MultiMeshInstance3D.new()
			var far_mm := MultiMesh.new()
			far_mm.transform_format = MultiMesh.TRANSFORM_3D
			far_mm.mesh = TREE_MESH.species_mesh(species, false)
			far_mm.instance_count = selected.size()
			for i in selected.size(): far_mm.set_instance_transform(i, selected[i])
			far.multimesh = far_mm
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(far)
			far.set_instance_shader_parameter("forest_lod_enabled", 1.0)
			# Shadow the dense canopy with the matching two-triangle silhouette,
			# rather than rendering every twig into every sun cascade.
			var shadow := MultiMeshInstance3D.new()
			var shadow_mm := MultiMesh.new()
			shadow_mm.transform_format = MultiMesh.TRANSFORM_3D
			shadow_mm.mesh = TREE_MESH.species_mesh(species, false)
			shadow_mm.instance_count = selected.size()
			for i in selected.size(): shadow_mm.set_instance_transform(i, selected[i])
			shadow.multimesh = shadow_mm
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			root.add_child(shadow)

	_chunks[key] = {
		"node": root,
		"tier": tier,
		"instances": transforms.size(),
		"transforms": transforms,
		"groups": groups,
	}


func _unload_chunk(key: Variant) -> void:
	var record := _chunks.get(key, {}) as Dictionary
	if record.is_empty():
		return
	var node := record.get("node", null) as Node
	if node != null:
		node.queue_free()
	_chunks.erase(key)


func _clear_chunks() -> void:
	for key in _chunks.keys():
		_unload_chunk(key)
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
	var center := Vector2i(floori(stream_xz.x / CHUNK_SIZE_M), floori(stream_xz.y / CHUNK_SIZE_M))
	var chunk_radius := int(ceil(visual_radius / CHUNK_SIZE_M)) + 1
	for z in range(maxi(minimum, center.y - chunk_radius), mini(maximum, center.y + chunk_radius) + 1):
		for x in range(maxi(minimum, center.x - chunk_radius), mini(maximum, center.x + chunk_radius) + 1):
			var coord := Vector2i(x, z)
			var nearest := stream_xz.clamp(Vector2(coord) * CHUNK_SIZE_M, Vector2(coord + Vector2i.ONE) * CHUNK_SIZE_M)
			var distance := stream_xz.distance_to(nearest)
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
	var job := create_placement_job(coord, step_m, max_instances)
	advance_placement_job(layout, job, flatten_zones, 2147483647)
	var result: Array[Transform3D] = []
	result.assign(job.transforms)
	return result


static func create_placement_job(coord: Vector2i, step_m: float, max_instances: int) -> Dictionary:
	var cells := int(floor(CHUNK_SIZE_M / step_m))
	# Visit a deterministic permutation, not southern rows first. The cap must
	# bound cost without concentrating every tree in one strip of the chunk.
	var order: Array[int] = []
	for i in cells*cells: order.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_hash01(coord.x,coord.y,73,19)*2147483647)
	for i in range(order.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var value := order[i]; order[i] = order[j]; order[j] = value
	return {"coord": coord, "step": step_m, "cap": max_instances, "cells": cells,
		"order": order, "cursor": 0, "transforms": [], "groups": [[], [], [], []], "done": false}


static func advance_placement_job(layout: Object, job: Dictionary, flatten_zones: Array,
		candidate_budget: int, group_species := false) -> void:
	var coord: Vector2i = job.coord
	if not job.has("zones"):
		job.zones = STREAMER.zones_intersecting_chunk(flatten_zones, coord, CHUNK_SIZE_M)
	var local_zones: Array = job.zones
	var origin := Vector2(coord) * CHUNK_SIZE_M
	var cells: int = job.cells
	var step_m: float = job.step
	var transforms: Array = job.transforms
	var stop := mini(int(job.cursor) + candidate_budget, job.order.size())
	while int(job.cursor) < stop and transforms.size() < int(job.cap):
		var index: int = job.order[job.cursor]
		job.cursor += 1
		var z := index / cells
		var x := index % cells
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
		if _in_flatten(world_xz, local_zones):
			continue
		var height := STREAMER.sample_terrain_height(layout, world_xz, local_zones)
		if height < 1.2:
			continue
		var yaw := _hash01(x, z, coord.y, coord.x + 117) * TAU
		var scale := lerpf(TREE_SCALE_MIN, TREE_SCALE_MAX, _hash01(x, z, coord.x, coord.y))
		var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0)).scaled(Vector3(scale * 1.2, scale, scale * 1.2))
		var xf := Transform3D(basis, Vector3(world_xz.x, height, world_xz.y))
		transforms.append(xf)
		if group_species:
			job.groups[coastal_species(layout, world_xz)].append(xf)
	job.done = int(job.cursor) >= job.order.size() or transforms.size() >= int(job.cap)


static func coastal_species(layout: Object, point: Vector2) -> int:
	var inland := -float(layout.sample_signed_distance(point))
	var height := float(layout.sample_height(point))
	var cell := point / 180.0
	var ix := floori(cell.x)
	var iz := floori(cell.y)
	var fx := smoothstep(0.0, 1.0, cell.x - ix)
	var fz := smoothstep(0.0, 1.0, cell.y - iz)
	var patch := lerpf(
		lerpf(_hash01(ix,iz,ForestField.world_seed,83),_hash01(ix+1,iz,ForestField.world_seed,83),fx),
		lerpf(_hash01(ix,iz+1,ForestField.world_seed,83),_hash01(ix+1,iz+1,ForestField.world_seed,83),fx),fz)
	var individual := _hash01(int(point.x),int(point.y),19,97)
	patch += (individual - .5) * .28
	# Exposed coastal scrub, pine on drier coastal ground, birch on upper
	# slopes, sheltered conifer groups inland. A visual heuristic, not a biome map.
	if inland < 75.0 or height > 600.0: return 3 if individual < .7 else 1
	if height > 350.0: return 1 if individual < .8 else 3
	if inland < 220.0: return 0 if individual < .65 else 1
	if patch < .32: return 1
	if patch < .68: return 0
	return 2


static func _in_flatten(world_xz: Vector2, flatten_zones: Array) -> bool:
	for zone_variant in flatten_zones:
		var zone := zone_variant as Dictionary
		if zone.has("polygon"):
			var polygon := zone.get("polygon", PackedVector2Array()) as PackedVector2Array
			if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(world_xz, polygon):
				return true
			continue
		if not zone.has("center") or not zone.has("half_size"):
			continue
		var local := (world_xz - (zone["center"] as Vector2)).rotated(-float(zone.get("yaw", 0.0)))
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
