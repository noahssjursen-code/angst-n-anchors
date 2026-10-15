class_name ForestField
extends RefCounted

## Deterministic mainland forest coverage. Geometry instances sample this;
## the terrain shader uses a baked world-space coverage map for far canopy tint.

const PATCH_SCALE_M := 2800.0
const DETAIL_SCALE_M := 520.0
## Keep a thin bare rock strip at the shore, then let canopy start close inland.
const MIN_INLAND_M := 10.0
const FULL_INLAND_M := 55.0
const MAX_SLOPE := 0.80
const MAX_HEIGHT_M := 900.0
const COVERAGE_MAP_SIZE := 256
const EXCLUSION_CELL_M := 16.0
const MAX_INDEX_CELLS_PER_ZONE := 256


static var world_seed: int = 0
static var _layout: Object
static var _patch_noise: FastNoiseLite
static var _detail_noise: FastNoiseLite
static var _initialized := false
static var _coverage_texture: ImageTexture
static var _world_half_extent_m := 20000.0
static var _flatten_zones: Array = []
static var _base_flatten_zones: Array = []
static var _base_zone_chunks: Dictionary = {}
static var _custom_port_exclusions: Dictionary = {}
static var _custom_port_sources: Dictionary = {}
static var _custom_zone_index: Dictionary = {}


static func initialize(layout: Object, seed: int, flatten_zones: Array = []) -> void:
	_layout = layout
	world_seed = seed
	_base_flatten_zones = flatten_zones.duplicate(true)
	_flatten_zones = _base_flatten_zones.duplicate()
	_custom_port_exclusions.clear()
	_custom_port_sources.clear()
	_base_zone_chunks.clear()
	_custom_zone_index.clear()
	_world_half_extent_m = float(layout.half_extent_m) if layout != null else 20000.0
	_ensure_noise()
	_coverage_texture = bake_coverage_map()
	_initialized = true


static func clear() -> void:
	_layout = null
	_coverage_texture = null
	_flatten_zones = []
	_base_flatten_zones = []
	_custom_port_exclusions.clear()
	_custom_port_sources.clear()
	_base_zone_chunks.clear()
	_custom_zone_index.clear()
	_initialized = false


## Main-thread installation of infrastructure corridors after background planning.
## Worker canopy jobs own copies, so existing work never reads a mutated array.
static func add_exclusions(zones: Array) -> void:
	_base_flatten_zones = _base_flatten_zones.duplicate()
	_base_flatten_zones.append_array(zones.duplicate(true))
	_base_zone_chunks.clear()
	_rebuild_exclusions()


## Replaceable world-data layers, independent of a port's loaded scene. The
## coarse base coverage image/cache deliberately does not include these cuts.
static func set_custom_port_exclusions(owner_key: String, zones: Array, source_id := 0) -> bool:
	if owner_key.is_empty(): return false
	if zones.is_empty():
		# An old renderer may exit after its replacement has already published
		# the same port. Its teardown must not remove the replacement's layer.
		if source_id != 0 and int(_custom_port_sources.get(owner_key, 0)) != source_id:
			return false
		if not _custom_port_exclusions.has(owner_key): return false
		_custom_port_exclusions.erase(owner_key)
		_custom_port_sources.erase(owner_key)
	else:
		_custom_port_sources[owner_key] = source_id
		if _custom_port_exclusions.get(owner_key, []) == zones: return false
		_custom_port_exclusions[owner_key] = zones.duplicate(true)
	_rebuild_exclusions()
	return true


static func base_exclusions() -> Array:
	return _base_flatten_zones.duplicate(true)


static func _rebuild_exclusions() -> void:
	_flatten_zones = _base_flatten_zones.duplicate()
	var custom_zones: Array = []
	var owners := _custom_port_exclusions.keys()
	owners.sort()
	for owner in owners:
		_flatten_zones.append_array(_custom_port_exclusions[owner])
		custom_zones.append_array(_custom_port_exclusions[owner])
	_custom_zone_index = exclusion_index(custom_zones)


static func is_initialized() -> bool:
	return _initialized


static func coverage_texture() -> ImageTexture:
	if _coverage_texture == null:
		_coverage_texture = bake_coverage_map()
	return _coverage_texture


static func world_half_extent_m() -> float:
	return _world_half_extent_m


## 0 = bare rock / shore / pad, 1 = dense boreal canopy.
static func sample(world_xz: Vector2, include_custom_ports := true) -> float:
	if _layout == null:
		return 0.0
	_ensure_noise()
	var distance := float(_layout.sample_signed_distance(world_xz))
	if distance >= 0.0:
		return 0.0
	var inland := -distance
	if inland < MIN_INLAND_M:
		return 0.0
	if _inside_flatten_zone(world_xz, include_custom_ports):
		## Rectangular facility pads + port town forest_clear polygons.
		return 0.0

	var height := float(_layout.sample_height(world_xz))
	if height > MAX_HEIGHT_M:
		return 0.0

	var slope := _estimate_slope(world_xz)
	if slope > MAX_SLOPE:
		return 0.0

	var inland_w := smoothstep(MIN_INLAND_M, FULL_INLAND_M, inland)
	var slope_w := 1.0 - smoothstep(0.35, MAX_SLOPE, slope)
	var height_w := 1.0 - smoothstep(520.0, MAX_HEIGHT_M, height)

	var patch := _noise_01(_patch_noise, world_xz, PATCH_SCALE_M)
	var detail := _noise_01(_detail_noise, world_xz, DETAIL_SCALE_M)
	# Closed stands with broad clearings, rather than thinning every hillside
	# into isolated dots. Slope, exposure and altitude still shape their edges.
	var cover := smoothstep(0.30, 0.44, patch) * lerpf(0.85, 1.0, detail)
	return clampf(cover * inland_w * slope_w * height_w, 0.0, 1.0)


static func bake_coverage_map() -> ImageTexture:
	var image := Image.create(COVERAGE_MAP_SIZE, COVERAGE_MAP_SIZE, false, Image.FORMAT_R8)
	if _layout == null:
		image.generate_mipmaps()
		return ImageTexture.create_from_image(image)
	var cache_key := ""
	if _layout is WorldLayout:
		cache_key="forest-coverage-v1:%s:%d:%s" % [_layout.layout_checksum,world_seed,WorldGenerationCache.digest(_base_flatten_zones)]
		var cached := WorldGenerationCache.read(cache_key)
		if cached.get("pixels") is PackedByteArray and cached.pixels.size()==COVERAGE_MAP_SIZE*COVERAGE_MAP_SIZE:
			image=Image.create_from_data(COVERAGE_MAP_SIZE,COVERAGE_MAP_SIZE,false,Image.FORMAT_R8,cached.pixels)
			image.generate_mipmaps()
			return ImageTexture.create_from_image(image)
	var half := _world_half_extent_m
	var denom := float(COVERAGE_MAP_SIZE)
	for y in range(COVERAGE_MAP_SIZE):
		var world_z := lerpf(-half, half, (float(y) + 0.5) / denom)
		for x in range(COVERAGE_MAP_SIZE):
			var world_x := lerpf(-half, half, (float(x) + 0.5) / denom)
			var density := sample(Vector2(world_x, world_z), false)
			image.set_pixel(x, y, Color(density, density, density))
	if not cache_key.is_empty(): WorldGenerationCache.write(cache_key,{"pixels":image.get_data()})
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _estimate_slope(world_xz: Vector2) -> float:
	const OFFSET := 28.0
	var h := float(_layout.sample_height(world_xz))
	var hx := float(_layout.sample_height(world_xz + Vector2(OFFSET, 0.0)))
	var hz := float(_layout.sample_height(world_xz + Vector2(0.0, OFFSET)))
	var dx := (hx - h) / OFFSET
	var dz := (hz - h) / OFFSET
	return clampf(sqrt(dx * dx + dz * dz), 0.0, 1.0)


static func _inside_flatten_zone(world_xz: Vector2, include_custom_ports := true) -> bool:
	if include_custom_ports and inside_exclusion_index(world_xz, _custom_zone_index):
		return true
	var coord := Vector2i(floori(world_xz.x / 1000.0), floori(world_xz.y / 1000.0))
	if not _base_zone_chunks.has(coord):
		_base_zone_chunks[coord] = WorldTerrainStreamer.zones_intersecting_chunk(_base_flatten_zones, coord, 1000.0)
	return inside_flatten_zones(world_xz, _base_zone_chunks[coord])


## Conservative candidate buckets only. The final predicate still evaluates
## each original polygon/rotated rectangle, including holes between tiles.
## Legacy rectangle/falloff zones and very large polygons stay in a fallback
## list; they keep their original predicate without allocating an unbounded
## grid. Jobs own their index; edits replace it rather than mutate it.
static func exclusion_index(zones: Array) -> Dictionary:
	if zones.is_empty(): return {}
	var buckets: Dictionary = {}
	var large: Array = []
	for zone in zones:
		if not zone.has("polygon"):
			large.append(zone)
			continue
		var bounds := WorldTerrainStreamer._zone_influence_bounds(zone)
		var first := Vector2i(floori(bounds.position.x / EXCLUSION_CELL_M), floori(bounds.position.y / EXCLUSION_CELL_M))
		var last := Vector2i(floori(bounds.end.x / EXCLUSION_CELL_M), floori(bounds.end.y / EXCLUSION_CELL_M))
		if bounds.size == Vector2.ZERO or (last.x-first.x+1)*(last.y-first.y+1) > MAX_INDEX_CELLS_PER_ZONE:
			large.append(zone)
			continue
		for z in range(first.y, last.y+1):
			for x in range(first.x, last.x+1):
				var key := Vector2i(x,z)
				if not buckets.has(key): buckets[key] = []
				buckets[key].append(zone)
	return {"buckets": buckets, "large": large}


static func inside_exclusion_index(world_xz: Vector2, index: Dictionary) -> bool:
	if index.is_empty(): return false
	var key := Vector2i(floori(world_xz.x / EXCLUSION_CELL_M), floori(world_xz.y / EXCLUSION_CELL_M))
	return inside_flatten_zones(world_xz, index.buckets.get(key, [])) \
		or inside_flatten_zones(world_xz, index.large)


static func inside_flatten_zones(world_xz: Vector2, zones: Array) -> bool:
	for zone_variant in zones:
		var zone := zone_variant as Dictionary
		## Town / polygon clears (forest only) and legacy rectangular pads.
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
		var pad := half_size + Vector2(falloff, falloff)
		if absf(local.x) <= pad.x and absf(local.y) <= pad.y:
			return true
	return false


static func _ensure_noise() -> void:
	var patch_seed := world_seed ^ 0x46524f53  # 'FROS'
	if _patch_noise != null and _patch_noise.seed == patch_seed:
		return
	_patch_noise = FastNoiseLite.new()
	_patch_noise.seed = patch_seed
	_patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_patch_noise.frequency = 1.0
	_patch_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_patch_noise.fractal_octaves = 3
	_patch_noise.fractal_gain = 0.5
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = world_seed ^ 0x46524454  # 'FRDT'
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail_noise.frequency = 1.0
	_detail_noise.fractal_octaves = 2


static func _noise_01(noise: FastNoiseLite, world_xz: Vector2, scale_m: float) -> float:
	return clampf(noise.get_noise_2d(world_xz.x / scale_m, world_xz.y / scale_m) * 0.5 + 0.5, 0.0, 1.0)
