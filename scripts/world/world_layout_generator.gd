class_name WorldLayoutGenerator
extends RefCounted

## Deterministic macro generator for the bounded Norway-esque coast archetype.
## Generation bakes analytic mainland/island/fjord CSG into a 257² signed
## distance raster. The one-time bake is intentionally moderate; all runtime
## geography queries on WorldLayout are O(1).

const DEFAULT_CONFIG_PATH := "res://resources/data/world/norway_coast.json"
const LAYOUT_SCRIPT := preload("res://scripts/world/world_layout.gd")
## Increment whenever deterministic generation logic changes incompatibly.
const GENERATION_VERSION := 5
const CACHE_LIMIT := 4
const TARGET_WORLD_SIZE_M := 40000.0
const WORLD_HALF_EXTENT_M := TARGET_WORLD_SIZE_M * 0.5

static var _layout_cache: Dictionary = {}
static var _cache_order := PackedStringArray()


static func generate(layout_seed: int, config_path: String = DEFAULT_CONFIG_PATH) -> WorldLayout:
	var cache_key := "%d:%d:%s" % [GENERATION_VERSION, layout_seed, config_path]
	if _layout_cache.has(cache_key):
		return _layout_cache[cache_key] as WorldLayout
	var config := _load_config(config_path)
	var size_m := float(config["world_size_m"])
	var resolution := int(config["raster_resolution"])
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var coast_phases := PackedFloat32Array()
	var harmonic_count := int((config["mainland"] as Dictionary)["coast_harmonics"])
	for _i in range(harmonic_count):
		coast_phases.append(rng.randf() * TAU)
	var coast_shape := {
		"phases": coast_phases,
		"offset_m": rng.randf_range(-1100.0, 1100.0),
		"tilt": rng.randf_range(-0.055, 0.055),
	}
	var waterways := _build_waterways(rng, config, coast_shape)
	var island_lobes := _build_island_lobes(rng, config)
	var field_data := _bake_field(config, coast_shape, waterways, island_lobes)
	var distances: PackedFloat32Array = field_data["distances"]
	var regions: PackedByteArray = field_data["regions"]
	var contours := _extract_contours(distances, resolution, size_m)
	var checksum := _checksum(layout_seed, resolution, distances, regions, contours, waterways)
	var layout := LAYOUT_SCRIPT.new() as WorldLayout
	layout._initialize(layout_seed, size_m, resolution, distances, regions, contours, waterways, checksum)
	_layout_cache[cache_key] = layout
	_cache_order.append(cache_key)
	while _cache_order.size() > CACHE_LIMIT:
		_layout_cache.erase(_cache_order[0])
		_cache_order.remove_at(0)
	return layout


static func clear_cache() -> void:
	_layout_cache.clear()
	_cache_order.clear()


static func _load_config(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "Unable to open world-layout config: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "World-layout config must be a JSON object")
	var config := parsed as Dictionary
	assert(
		is_equal_approx(float(config.get("world_size_m", 0.0)), TARGET_WORLD_SIZE_M),
		"World layout must match the generation contract",
	)
	var resolution := int(config.get("raster_resolution", 0))
	assert(resolution >= 129 and resolution <= 513 and resolution % 2 == 1, "Raster resolution must be odd and practical")
	return config


static func _build_waterways(
	rng: RandomNumberGenerator,
	config: Dictionary,
	coast_shape: Dictionary,
) -> Array[Dictionary]:
	var fjords := config["fjords"] as Dictionary
	var root_count := rng.randi_range(int(fjords["root_count_min"]), int(fjords["root_count_max"]))
	var usable_z := float(config["world_size_m"]) * 0.84
	var band_height := usable_z / float(root_count)
	var first_band_z := -usable_z * 0.5
	var waterways: Array[Dictionary] = []
	for root_idx in range(root_count):
		var mouth_z := first_band_z + (float(root_idx) + 0.5) * band_height \
			+ rng.randf_range(-band_height * 0.30, band_height * 0.30)
		var mouth_x := _coast_x(mouth_z, config["mainland"], coast_shape)
		var reach := rng.randf_range(
			float(fjords["inland_reach_min_m"]),
			float(fjords["inland_reach_max_m"])
		)
		var bend := rng.randf_range(-band_height * 0.48, band_height * 0.48)
		var outer_shift := rng.randf_range(-band_height * 0.38, band_height * 0.38)
		var approach_shift := rng.randf_range(-band_height * 0.32, band_height * 0.32)
		var inner_wiggle := rng.randf_range(-band_height * 0.26, band_height * 0.26)
		var trunk_width := rng.randf_range(
			float(fjords["trunk_width_min_m"]),
			float(fjords["trunk_width_max_m"])
		)
		var trunk := _sample_cubic(
			Vector2(-WORLD_HALF_EXTENT_M, mouth_z + outer_shift),
			Vector2(mouth_x - 3600.0, mouth_z + approach_shift),
			Vector2(mouth_x + reach * 0.48, mouth_z + bend * 0.46 + inner_wiggle),
			Vector2(minf(WORLD_HALF_EXTENT_M - 900.0, mouth_x + reach), mouth_z + bend),
			7,
		)
		var trunk_widths := _taper_widths(trunk_width * 1.35, trunk_width * 0.52, trunk.size())
		var trunk_id := "fjord_%02d" % root_idx
		waterways.append({
			"id": trunk_id,
			"kind": "trunk",
			"width_m": trunk_width * 0.55,
			"widths_m": trunk_widths,
			"points": trunk,
			"connects_to": PackedStringArray(["open_ocean"]),
		})
		var branch_count := 1 + int(rng.randi() % 2)
		for branch_idx in range(branch_count):
			var junction_index := 3 if branch_idx == 0 else 4
			var junction := trunk[junction_index]
			var direction := -1.0 if rng.randf() < 0.5 else 1.0
			var branch_length := rng.randf_range(2400.0, 4300.0)
			var branch_wiggle := rng.randf_range(-520.0, 520.0)
			var branch_width := rng.randf_range(
				float(fjords["branch_width_min_m"]),
				float(fjords["branch_width_max_m"])
			)
			var branch_end_z := clampf(
				junction.y + direction * branch_length,
				first_band_z + float(root_idx) * band_height + 300.0,
				first_band_z + float(root_idx + 1) * band_height - 300.0,
			)
			var branch_end := _clamp_to_map(Vector2(
				junction.x + branch_length * rng.randf_range(0.52, 0.82),
				branch_end_z,
			))
			var branch := _sample_cubic(
				junction,
				_clamp_to_map(junction + Vector2(
					branch_length * 0.24,
					direction * branch_length * 0.24 + branch_wiggle,
				)),
				_clamp_to_map(branch_end + Vector2(
					-branch_length * 0.20,
					-branch_wiggle * 0.45,
				)),
				branch_end,
				4,
			)
			waterways.append({
				"id": "%s_branch_%02d" % [trunk_id, branch_idx],
				"kind": "branch",
				"width_m": branch_width * 0.62,
				"widths_m": _taper_widths(branch_width, branch_width * 0.62, branch.size()),
				"points": branch,
				"connects_to": PackedStringArray([trunk_id]),
			})
	return waterways


static func _sample_cubic(
		a: Vector2,
		b: Vector2,
		c: Vector2,
		d: Vector2,
		count: int,
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(maxi(count, 2)):
		var t := float(i) / float(maxi(count - 1, 1))
		var omt := 1.0 - t
		points.append(_clamp_to_map(
			a * omt * omt * omt
			+ b * 3.0 * omt * omt * t
			+ c * 3.0 * omt * t * t
			+ d * t * t * t
		))
	return points


static func _taper_widths(start_width: float, end_width: float, count: int) -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	for i in range(maxi(count, 1)):
		var t := float(i) / float(maxi(count - 1, 1))
		widths.append(lerpf(start_width, end_width, smoothstep(0.0, 1.0, t)))
	return widths


static func _clamp_to_map(point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, -WORLD_HALF_EXTENT_M, WORLD_HALF_EXTENT_M),
		clampf(point.y, -WORLD_HALF_EXTENT_M, WORLD_HALF_EXTENT_M),
	)


## The western island belt is generated as clustered overlapping circles
## (metaball lobes). Their min-union SDF creates irregular skerries without
## authored geometry or imported assets.
static func _build_island_lobes(rng: RandomNumberGenerator, config: Dictionary) -> Array[Vector3]:
	var arch := config["archipelago"] as Dictionary
	var cluster_count := rng.randi_range(
		int(arch["cluster_count_min"]),
		int(arch["cluster_count_max"])
	)
	var lobes: Array[Vector3] = []
	for _cluster_idx in range(cluster_count):
		var center := Vector2(
			rng.randf_range(float(arch["belt_x_min_m"]), float(arch["belt_x_max_m"])),
			rng.randf_range(-WORLD_HALF_EXTENT_M * 0.925, WORLD_HALF_EXTENT_M * 0.925)
		)
		var base_radius := rng.randf_range(float(arch["radius_min_m"]), float(arch["radius_max_m"]))
		var lobe_count := rng.randi_range(int(arch["lobes_min"]), int(arch["lobes_max"]))
		for lobe_idx in range(lobe_count):
			var angle := rng.randf() * TAU
			var offset := Vector2(cos(angle), sin(angle)) * rng.randf_range(0.0, base_radius * 0.72)
			var radius := base_radius * rng.randf_range(0.48, 0.92)
			if lobe_idx == 0:
				offset = Vector2.ZERO
				radius = base_radius
			lobes.append(Vector3(center.x + offset.x, center.y + offset.y, radius))
	return lobes


static func _bake_field(
	config: Dictionary,
	coast_shape: Dictionary,
	waterways: Array[Dictionary],
	island_lobes: Array[Vector3],
) -> Dictionary:
	var resolution := int(config["raster_resolution"])
	var size_m := float(config["world_size_m"])
	var half := size_m * 0.5
	var cell := size_m / float(resolution - 1)
	var distances := PackedFloat32Array()
	var regions := PackedByteArray()
	distances.resize(resolution * resolution)
	regions.resize(resolution * resolution)
	var classification := config["classification"] as Dictionary
	var fjord_influence := float(classification["fjord_influence_m"])
	var open_water_x := float(classification["open_water_x_m"])
	var corridor_points: Array[PackedVector2Array] = []
	var corridor_width_start := PackedFloat32Array()
	var corridor_width_end := PackedFloat32Array()
	var corridor_start_x := PackedFloat32Array()
	var corridor_inv_span_x := PackedFloat32Array()
	for waterway in waterways:
		var points: PackedVector2Array = waterway["points"]
		var widths: PackedFloat32Array = waterway.get("widths_m", PackedFloat32Array())
		var fallback := float(waterway["width_m"])
		corridor_points.append(points)
		corridor_width_start.append(widths[0] if widths.size() == points.size() else fallback)
		corridor_width_end.append(widths[-1] if widths.size() == points.size() else fallback)
		corridor_start_x.append(points[0].x)
		corridor_inv_span_x.append(1.0 / maxf(points[-1].x - points[0].x, 1.0))
	for z_idx in range(resolution):
		var z := -half + float(z_idx) * cell
		var coast := _coast_x(z, config["mainland"], coast_shape)
		for x_idx in range(resolution):
			var x := -half + float(x_idx) * cell
			var point := Vector2(x, z)
			# Negative east of the mainland coast.
			var land_distance := coast - x
			for lobe in island_lobes:
				var island_distance := point.distance_to(Vector2(lobe.x, lobe.y)) - lobe.z
				land_distance = minf(land_distance, island_distance)
			var nearest_waterway := INF
			var water_cut_distance := INF
			for waterway_index in range(corridor_points.size()):
				var waterway_points := corridor_points[waterway_index]
				var center_distance := _distance_to_polyline(point, waterway_points)
				nearest_waterway = minf(nearest_waterway, center_distance)
				var progress := clampf(
					(point.x - corridor_start_x[waterway_index])
					* corridor_inv_span_x[waterway_index],
					0.0,
					1.0,
				)
				var effective_width := lerpf(
					corridor_width_start[waterway_index],
					corridor_width_end[waterway_index],
					progress,
				)
				water_cut_distance = minf(
					water_cut_distance,
					center_distance - effective_width * 0.5,
				)
			# CSG difference: land minus guaranteed navigable water corridors.
			var signed_distance := maxf(land_distance, -water_cut_distance)
			var index := z_idx * resolution + x_idx
			distances[index] = signed_distance
			if nearest_waterway <= fjord_influence and x > open_water_x:
				regions[index] = WorldLayout.Region.FJORD
			elif x >= coast - 900.0:
				regions[index] = WorldLayout.Region.MAINLAND
			elif x > open_water_x:
				regions[index] = WorldLayout.Region.ARCHIPELAGO
			else:
				regions[index] = WorldLayout.Region.OPEN_WATER
	return {"distances": distances, "regions": regions}


static func _coast_x(z: float, mainland: Dictionary, shape: Dictionary) -> float:
	var phases: PackedFloat32Array = shape["phases"]
	var x := float(mainland["coast_x_m"]) + float(shape["offset_m"]) + z * float(shape["tilt"])
	var amplitude := float(mainland["coast_amplitude_m"])
	for i in range(phases.size()):
		var frequency := float(i + 1)
		x += sin(z * frequency * 0.00019 + phases[i]) * amplitude / (frequency * 1.55)
	return x


static func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	var best := INF
	for i in range(points.size() - 1):
		best = minf(best, _distance_to_segment(point, points[i], points[i + 1]))
	return best


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


## Deterministic marching-squares segments. Every two-point entry is directly
## chart-renderable; ambiguous saddles use a fixed lower-left connection rule.
static func _extract_contours(
	field: PackedFloat32Array,
	resolution: int,
	size_m: float,
) -> Array[PackedVector2Array]:
	var contours: Array[PackedVector2Array] = []
	var half := size_m * 0.5
	var cell := size_m / float(resolution - 1)
	for z in range(resolution - 1):
		for x in range(resolution - 1):
			var d0 := field[z * resolution + x]
			var d1 := field[z * resolution + x + 1]
			var d2 := field[(z + 1) * resolution + x + 1]
			var d3 := field[(z + 1) * resolution + x]
			var mask := int(d0 < 0.0) | (int(d1 < 0.0) << 1) | (int(d2 < 0.0) << 2) | (int(d3 < 0.0) << 3)
			if mask == 0 or mask == 15:
				continue
			var origin := Vector2(-half + float(x) * cell, -half + float(z) * cell)
			var edge := PackedVector2Array([
				_interp(origin, origin + Vector2(cell, 0.0), d0, d1),
				_interp(origin + Vector2(cell, 0.0), origin + Vector2(cell, cell), d1, d2),
				_interp(origin + Vector2(cell, cell), origin + Vector2(0.0, cell), d2, d3),
				_interp(origin + Vector2(0.0, cell), origin, d3, d0),
			])
			match mask:
				1, 14: _add_segment(contours, edge[3], edge[0])
				2, 13: _add_segment(contours, edge[0], edge[1])
				3, 12: _add_segment(contours, edge[3], edge[1])
				4, 11: _add_segment(contours, edge[1], edge[2])
				5:
					_add_segment(contours, edge[3], edge[2])
					_add_segment(contours, edge[0], edge[1])
				6, 9: _add_segment(contours, edge[0], edge[2])
				7, 8: _add_segment(contours, edge[3], edge[2])
				10:
					_add_segment(contours, edge[3], edge[0])
					_add_segment(contours, edge[1], edge[2])
	return contours


static func _interp(a: Vector2, b: Vector2, da: float, db: float) -> Vector2:
	var denominator := da - db
	var t := 0.5 if absf(denominator) < 0.000001 else clampf(da / denominator, 0.0, 1.0)
	return a.lerp(b, t)


static func _add_segment(contours: Array[PackedVector2Array], a: Vector2, b: Vector2) -> void:
	contours.append(PackedVector2Array([a, b]))


static func _checksum(
	layout_seed: int,
	resolution: int,
	distances: PackedFloat32Array,
	regions: PackedByteArray,
	contours: Array[PackedVector2Array],
	waterways: Array[Dictionary],
) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s32(0, layout_seed)
	bytes.encode_s32(4, resolution)
	for distance in distances:
		var offset := bytes.size()
		bytes.resize(offset + 4)
		bytes.encode_s32(offset, int(round(distance * 10.0)))
	bytes.append_array(regions)
	for contour in contours:
		for point in contour:
			var offset := bytes.size()
			bytes.resize(offset + 8)
			bytes.encode_s32(offset, int(round(point.x * 10.0)))
			bytes.encode_s32(offset + 4, int(round(point.y * 10.0)))
	for waterway in waterways:
		bytes.append_array(String(waterway["id"]).to_utf8_buffer())
		var width_offset := bytes.size()
		bytes.resize(width_offset + 4)
		bytes.encode_s32(width_offset, int(round(float(waterway["width_m"]) * 10.0)))
		var widths: PackedFloat32Array = waterway.get("widths_m", PackedFloat32Array())
		for width in widths:
			var taper_offset := bytes.size()
			bytes.resize(taper_offset + 4)
			bytes.encode_s32(taper_offset, int(round(width * 10.0)))
		for point in waterway["points"]:
			var point_offset := bytes.size()
			bytes.resize(point_offset + 8)
			bytes.encode_s32(point_offset, int(round(point.x * 10.0)))
			bytes.encode_s32(point_offset + 4, int(round(point.y * 10.0)))
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()
