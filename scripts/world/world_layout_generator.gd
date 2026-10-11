class_name WorldLayoutGenerator
extends RefCounted

## Deterministic macro generator for the Norway-inspired coast archetype.
## World size comes from WorldConfig (10–120 km). Never imports a real DEM.

const DEFAULT_CONFIG_PATH := "res://resources/data/world/norway_coast.json"
const LAYOUT_SCRIPT := preload("res://scripts/world/world_layout.gd")
const WORLD_CONFIG := preload("res://scripts/world/world_config.gd")
## Increment whenever deterministic generation logic changes incompatibly.
const GENERATION_VERSION := 8
const CACHE_LIMIT := 4

static var _layout_cache: Dictionary = {}
static var _cache_order := PackedStringArray()


static func generate(
		layout_seed: int,
		config_path: String = DEFAULT_CONFIG_PATH,
		world_size_m: float = -1.0,
) -> WorldLayout:
	var size_hint := world_size_m if world_size_m > 0.0 else WORLD_CONFIG.REFERENCE_SIZE_M
	var cache_key := "%d:%d:%.0f:%s" % [GENERATION_VERSION, layout_seed, size_hint, config_path]
	if _layout_cache.has(cache_key):
		return _layout_cache[cache_key] as WorldLayout
	var config := WORLD_CONFIG.resolve(size_hint, config_path)
	var size_m := float(config["world_size_m"])
	var resolution := int(config["raster_resolution"])
	var half := size_m * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var coast_phases := PackedFloat32Array()
	var harmonic_count := int((config["mainland"] as Dictionary)["coast_harmonics"])
	for _i in range(harmonic_count):
		coast_phases.append(rng.randf() * TAU)
	var coast_shape := {
		"phases": coast_phases,
		"offset_m": rng.randf_range(-1100.0, 1100.0) * WORLD_CONFIG.scale_factor(size_m),
		"tilt": rng.randf_range(-0.055, 0.055),
	}
	var waterways := _build_waterways(rng, config, coast_shape, half)
	var island_lobes := _build_island_lobes(rng, config, half)
	var field_data := _bake_field(layout_seed, config, coast_shape, waterways, island_lobes)
	var distances: PackedFloat32Array = field_data["distances"]
	var regions: PackedByteArray = field_data["regions"]
	var contours := _extract_contours(distances, resolution, size_m)
	var checksum := _checksum(layout_seed, resolution, size_m, distances, regions, contours, waterways)
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


static func _build_waterways(
		rng: RandomNumberGenerator,
		config: Dictionary,
		coast_shape: Dictionary,
		half: float,
) -> Array[Dictionary]:
	var fjords := config["fjords"] as Dictionary
	var root_count := rng.randi_range(int(fjords["root_count_min"]), int(fjords["root_count_max"]))
	var usable_z := float(config["world_size_m"]) * 0.84
	var spacing := float(fjords.get("root_spacing_m", usable_z / float(maxi(root_count, 1))))
	var meander := float(fjords.get("meander_m", 1800.0))
	var width_noise := clampf(float(fjords.get("width_noise", 0.25)), 0.0, 0.6)
	var trunk_samples := maxi(int(fjords.get("trunk_samples", 12)), 6)
	var branch_samples := maxi(int(fjords.get("branch_samples", 7)), 4)
	## Poisson-ish mouths along Z using spacing + jitter (not equal bands).
	var mouths := _place_mouths(rng, root_count, usable_z, spacing)
	var waterways: Array[Dictionary] = []
	for root_idx in range(mouths.size()):
		var mouth_z := float(mouths[root_idx])
		var mouth_x := _coast_x(mouth_z, config["mainland"], coast_shape)
		var reach := rng.randf_range(
			float(fjords["inland_reach_min_m"]),
			float(fjords["inland_reach_max_m"]),
		)
		var trunk_width := rng.randf_range(
			float(fjords["trunk_width_min_m"]),
			float(fjords["trunk_width_max_m"]),
		)
		var bend := rng.randf_range(-meander, meander)
		var outer_shift := rng.randf_range(-meander * 0.55, meander * 0.55)
		var approach_shift := rng.randf_range(-meander * 0.45, meander * 0.45)
		var trunk := _sample_cubic(
			_clamp_to_half(Vector2(-half, mouth_z + outer_shift), half),
			_clamp_to_half(Vector2(mouth_x - reach * 0.22, mouth_z + approach_shift), half),
			_clamp_to_half(Vector2(mouth_x + reach * 0.48, mouth_z + bend * 0.55), half),
			_clamp_to_half(Vector2(minf(half - 900.0, mouth_x + reach), mouth_z + bend), half),
			trunk_samples,
			half,
		)
		trunk = _apply_meander(trunk, rng, meander * 0.35, half)
		var mouth_w := trunk_width * rng.randf_range(1.15, 1.55)
		var tip_w := trunk_width * rng.randf_range(0.42, 0.72)
		var trunk_widths := _path_widths(mouth_w, tip_w, trunk.size(), rng, width_noise)
		var trunk_id := "fjord_%02d" % root_idx
		waterways.append({
			"id": trunk_id,
			"kind": "trunk",
			"width_m": trunk_width * 0.75,
			"widths_m": trunk_widths,
			"points": trunk,
			"connects_to": PackedStringArray(["open_ocean"]),
		})
		var branch_count := 1 + int(rng.randi() % 3)
		for branch_idx in range(branch_count):
			var junction_index := clampi(
				int(round(float(trunk.size() - 1) * rng.randf_range(0.28, 0.72))),
				2,
				trunk.size() - 2,
			)
			var junction := trunk[junction_index]
			var direction := -1.0 if rng.randf() < 0.5 else 1.0
			var branch_length := rng.randf_range(reach * 0.18, reach * 0.38)
			var branch_wiggle := rng.randf_range(-meander * 0.4, meander * 0.4)
			var branch_width := rng.randf_range(
				float(fjords["branch_width_min_m"]),
				float(fjords["branch_width_max_m"]),
			)
			var branch_end := _clamp_to_half(Vector2(
				junction.x + branch_length * rng.randf_range(0.45, 0.95),
				junction.y + direction * branch_length + branch_wiggle,
			), half)
			var branch := _sample_cubic(
				junction,
				_clamp_to_half(junction + Vector2(
					branch_length * 0.28,
					direction * branch_length * 0.22 + branch_wiggle * 0.5,
				), half),
				_clamp_to_half(branch_end + Vector2(-branch_length * 0.18, -branch_wiggle * 0.35), half),
				branch_end,
				branch_samples,
				half,
			)
			waterways.append({
				"id": "%s_branch_%02d" % [trunk_id, branch_idx],
				"kind": "branch",
				"width_m": branch_width * 0.7,
				"widths_m": _path_widths(
					branch_width * 1.05,
					branch_width * 0.55,
					branch.size(),
					rng,
					width_noise,
				),
				"points": branch,
				"connects_to": PackedStringArray([trunk_id]),
			})
	return waterways


static func _place_mouths(
		rng: RandomNumberGenerator,
		count: int,
		usable_z: float,
		spacing: float,
) -> PackedFloat32Array:
	var mouths := PackedFloat32Array()
	var z_min := -usable_z * 0.5
	var z_max := usable_z * 0.5
	var cursor := z_min + spacing * rng.randf_range(0.35, 0.85)
	for _i in range(count):
		if cursor > z_max:
			break
		mouths.append(clampf(cursor + rng.randf_range(-spacing * 0.22, spacing * 0.22), z_min, z_max))
		cursor += spacing * rng.randf_range(0.72, 1.35)
	## Top up if spacing left gaps at the end.
	while mouths.size() < count:
		mouths.append(rng.randf_range(z_min, z_max))
	mouths.sort()
	return mouths


static func _apply_meander(
		points: PackedVector2Array,
		rng: RandomNumberGenerator,
		amplitude: float,
		half: float,
) -> PackedVector2Array:
	if points.size() < 3 or amplitude <= 1.0:
		return points
	var out := PackedVector2Array()
	out.append(points[0])
	for i in range(1, points.size() - 1):
		var prev := points[i - 1]
		var cur := points[i]
		var nxt := points[i + 1]
		var tangent := (nxt - prev).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var t := float(i) / float(points.size() - 1)
		var envelope := sin(t * PI) ## stronger mid-fjord, calm at mouth/tip
		var offset := normal * rng.randf_range(-amplitude, amplitude) * envelope
		out.append(_clamp_to_half(cur + offset, half))
	out.append(points[points.size() - 1])
	return out


static func _sample_cubic(
		a: Vector2,
		b: Vector2,
		c: Vector2,
		d: Vector2,
		count: int,
		half: float,
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(maxi(count, 2)):
		var t := float(i) / float(maxi(count - 1, 1))
		var omt := 1.0 - t
		points.append(_clamp_to_half(
			a * omt * omt * omt
			+ b * 3.0 * omt * omt * t
			+ c * 3.0 * omt * t * t
			+ d * t * t * t,
			half,
		))
	return points


static func _path_widths(
		start_width: float,
		end_width: float,
		count: int,
		rng: RandomNumberGenerator,
		noise_amt: float,
) -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	for i in range(maxi(count, 1)):
		var t := float(i) / float(maxi(count - 1, 1))
		## Mouth-wide basins mid-path, narrower tip — not a pure X lerp.
		var basin := 1.0 + 0.22 * sin(t * PI)
		var base := lerpf(start_width, end_width, smoothstep(0.0, 1.0, t)) * basin
		var n := 1.0 + rng.randf_range(-noise_amt, noise_amt)
		widths.append(maxf(base * n, end_width * 0.35))
	return widths


static func _clamp_to_half(point: Vector2, half: float) -> Vector2:
	return Vector2(
		clampf(point.x, -half, half),
		clampf(point.y, -half, half),
	)


static func _build_island_lobes(
		rng: RandomNumberGenerator,
		config: Dictionary,
		half: float,
) -> Array[Vector3]:
	var arch := config["archipelago"] as Dictionary
	var cluster_count := rng.randi_range(
		int(arch["cluster_count_min"]),
		int(arch["cluster_count_max"]),
	)
	var lobes: Array[Vector3] = []
	for _cluster_idx in range(cluster_count):
		var center := Vector2(
			rng.randf_range(float(arch["belt_x_min_m"]), float(arch["belt_x_max_m"])),
			rng.randf_range(-half * 0.925, half * 0.925),
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
		layout_seed: int,
		config: Dictionary,
		coast_shape: Dictionary,
		waterways: Array[Dictionary],
		island_lobes: Array[Vector3],
) -> Dictionary:
	var resolution := int(config["raster_resolution"])
	var size_m := float(config["world_size_m"])
	var half := size_m * 0.5
	var cell := size_m / float(resolution - 1)
	var scale := WORLD_CONFIG.scale_factor(size_m)
	var coast_erosion := _make_bake_noise(layout_seed ^ 0x45524f53, 0.00042 / maxf(scale, 0.25), 4, 0.55)
	var coast_fingers := _make_bake_noise(layout_seed ^ 0x46494e47, 0.00155 / maxf(scale, 0.25), 3, 0.50)
	var island_erosion := _make_bake_noise(layout_seed ^ 0x49534c45, 0.00095 / maxf(scale, 0.25), 3, 0.48)
	var island_bite := _make_bake_noise(layout_seed ^ 0x42495445, 0.0022 / maxf(scale, 0.25), 2, 0.45)
	var distances := PackedFloat32Array()
	var regions := PackedByteArray()
	distances.resize(resolution * resolution)
	regions.resize(resolution * resolution)
	var classification := config["classification"] as Dictionary
	var fjord_influence := float(classification["fjord_influence_m"])
	var open_water_x := float(classification["open_water_x_m"])
	var corridor_points: Array[PackedVector2Array] = []
	var corridor_widths: Array[PackedFloat32Array] = []
	var corridor_cumlen: Array[PackedFloat32Array] = []
	var corridor_bounds: Array[Rect2] = []
	var corridor_half_width := PackedFloat32Array()
	for waterway in waterways:
		var points: PackedVector2Array = waterway["points"]
		var widths: PackedFloat32Array = waterway.get("widths_m", PackedFloat32Array())
		var fallback := float(waterway["width_m"])
		if widths.size() != points.size():
			widths = PackedFloat32Array()
			for _i in range(points.size()):
				widths.append(fallback)
		corridor_points.append(points)
		corridor_widths.append(widths)
		corridor_cumlen.append(_polyline_cumlen(points))
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points: bounds = bounds.expand(point)
		# Conservative padding prevents boundary float rounding from rejecting a
		# curve which could still improve either the distance or the water cut.
		corridor_bounds.append(bounds.grow(1.0))
		var largest_width := 0.0
		for width in widths: largest_width = maxf(largest_width, width)
		corridor_half_width.append(largest_width * .5 + 1.0)
	for z_idx in range(resolution):
		var z := -half + float(z_idx) * cell
		var coast := _coast_x(z, config["mainland"], coast_shape)
		for x_idx in range(resolution):
			var x := -half + float(x_idx) * cell
			var point := Vector2(x, z)
			var land_distance := coast - x
			var erosion := coast_erosion.get_noise_2d(x, z) * 520.0 * scale
			var fingers := coast_fingers.get_noise_2d(x + 9000.0, z - 4200.0) * 190.0 * scale
			land_distance += erosion + fingers
			for lobe in island_lobes:
				# Simplex FBM is bounded by +/-1; bite only adds distance. This
				# L-infinity bound is deliberately looser than the eroded circle.
				var axis_distance := maxf(absf(x-lobe.x), absf(z-lobe.y))
				if axis_distance - lobe.z * 1.45 >= land_distance:
					continue
				var island_distance := _eroded_island_distance(
					point,
					Vector2(lobe.x, lobe.y),
					lobe.z,
					island_erosion,
					island_bite,
				)
				land_distance = minf(land_distance, island_distance)
			var nearest_waterway := INF
			var water_cut_distance := INF
			for waterway_index in range(corridor_points.size()):
				var bounds := corridor_bounds[waterway_index]
				var outside := Vector2(
					maxf(maxf(bounds.position.x-x, x-bounds.end.x), 0.0),
					maxf(maxf(bounds.position.y-z, z-bounds.end.y), 0.0),
				)
				var lower_distance := outside.length()
				if lower_distance >= nearest_waterway and lower_distance - corridor_half_width[waterway_index] >= water_cut_distance:
					continue
				var sample := _distance_and_width_on_polyline(
					point,
					corridor_points[waterway_index],
					corridor_widths[waterway_index],
					corridor_cumlen[waterway_index],
				)
				nearest_waterway = minf(nearest_waterway, float(sample["distance"]))
				water_cut_distance = minf(
					water_cut_distance,
					float(sample["distance"]) - float(sample["width"]) * 0.5,
				)
			var signed_distance := maxf(land_distance, -water_cut_distance)
			var index := z_idx * resolution + x_idx
			distances[index] = signed_distance
			if nearest_waterway <= fjord_influence and x > open_water_x:
				regions[index] = WorldLayout.Region.FJORD
			elif x >= coast - 900.0 * scale:
				regions[index] = WorldLayout.Region.MAINLAND
			elif x > open_water_x:
				regions[index] = WorldLayout.Region.ARCHIPELAGO
			else:
				regions[index] = WorldLayout.Region.OPEN_WATER
	return {"distances": distances, "regions": regions}


static func _polyline_cumlen(points: PackedVector2Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(points.size())
	cum[0] = 0.0
	for i in range(1, points.size()):
		cum[i] = cum[i - 1] + points[i].distance_to(points[i - 1])
	return cum


static func _distance_and_width_on_polyline(
		point: Vector2,
		points: PackedVector2Array,
		widths: PackedFloat32Array,
		cumlen: PackedFloat32Array,
) -> Dictionary:
	var best_d := INF
	var best_w := widths[0] if widths.size() > 0 else 1.0
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var length_squared := ab.length_squared()
		var t := 0.0
		if length_squared > 0.0001:
			t = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
		var d := point.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			var wa := widths[i] if i < widths.size() else best_w
			var wb := widths[i + 1] if i + 1 < widths.size() else wa
			best_w = lerpf(wa, wb, t)
	return {"distance": best_d, "width": best_w}


static func _coast_x(z: float, mainland: Dictionary, shape: Dictionary) -> float:
	var phases: PackedFloat32Array = shape["phases"]
	var x := float(mainland["coast_x_m"]) + float(shape["offset_m"]) + z * float(shape["tilt"])
	var amplitude := float(mainland["coast_amplitude_m"])
	for i in range(phases.size()):
		var frequency := float(i + 1)
		var damp := lerpf(1.18, 1.48, float(i) / maxf(float(phases.size() - 1), 1.0))
		x += sin(z * frequency * 0.00019 + phases[i]) * amplitude / (frequency * damp)
		## Extra irregularity so the outer coast is not one sine wall.
		if i == 0:
			x += sin(z * 0.00041 + phases[i] * 1.7) * amplitude * 0.18
	return x


static func _make_bake_noise(
		noise_seed: int,
		frequency: float,
		octaves: int,
		gain: float,
) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.08
	return noise


static func _eroded_island_distance(
		point: Vector2,
		center: Vector2,
		radius: float,
		erosion_noise: FastNoiseLite,
		bite_noise: FastNoiseLite,
) -> float:
	var offset := point - center
	var dist := offset.length()
	if dist < 0.01:
		return -radius
	var dir := offset / dist
	var coast_wobble := erosion_noise.get_noise_2d(dir.x * 4.4, dir.y * 4.4)
	var radius_mod := radius * (1.0 + coast_wobble * 0.44)
	var bite := maxf(0.0, bite_noise.get_noise_2d(point.x, point.y)) * radius * 0.30
	return dist - radius_mod + bite


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
		size_m: float,
		distances: PackedFloat32Array,
		regions: PackedByteArray,
		contours: Array[PackedVector2Array],
		waterways: Array[Dictionary],
) -> String:
	var bytes := PackedByteArray()
	bytes.resize(12)
	bytes.encode_s32(0, layout_seed)
	bytes.encode_s32(4, resolution)
	bytes.encode_s32(8, int(round(size_m)))
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
