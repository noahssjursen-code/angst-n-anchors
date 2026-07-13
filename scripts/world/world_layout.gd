class_name WorldLayout
extends RefCounted

## Immutable-ish macro-geography snapshot. WorldLayoutGenerator is the only
## intended writer; consumers receive copy-on-write packed arrays and duplicated
## graph dictionaries. The 257² field spans 40 km at 156.25 m per sample.

enum Region {
	MAINLAND,
	FJORD,
	ARCHIPELAGO,
	OPEN_WATER,
}

var seed: int:
	get: return _seed
var world_size_m: float:
	get: return _world_size_m
var half_extent_m: float:
	get: return _world_size_m * 0.5
var raster_resolution: int:
	get: return _resolution
var cell_size_m: float:
	get: return _cell_size_m
var layout_checksum: String:
	get: return _checksum
var coastline_contours: Array[PackedVector2Array]:
	get: return _contours.duplicate()
var waterway_centerlines: Array[Dictionary]:
	get: return _waterways.duplicate(true)

var _seed := 0
var _world_size_m := 40000.0
var _resolution := 0
var _cell_size_m := 0.0
var _signed_distance := PackedFloat32Array()
var _regions := PackedByteArray()
var _contours: Array[PackedVector2Array] = []
var _waterways: Array[Dictionary] = []
var _checksum := ""
var _coast_noise: FastNoiseLite
var _shelf_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _mountain_noise: FastNoiseLite
var _detail_noise: FastNoiseLite


func _initialize(
		layout_seed: int,
		size_m: float,
		resolution: int,
		signed_distance: PackedFloat32Array,
		regions: PackedByteArray,
		contours: Array[PackedVector2Array],
		waterways: Array[Dictionary],
		checksum: String,
) -> void:
	assert(_resolution == 0, "WorldLayout may only be initialized once")
	assert(resolution >= 2)
	assert(signed_distance.size() == resolution * resolution)
	assert(regions.size() == resolution * resolution)
	_seed = layout_seed
	_world_size_m = size_m
	_resolution = resolution
	_cell_size_m = size_m / float(resolution - 1)
	_signed_distance = signed_distance.duplicate()
	_regions = regions.duplicate()
	_contours = contours.duplicate()
	_waterways = waterways.duplicate(true)
	_checksum = checksum
	_initialize_height_fields()


func _initialize_height_fields() -> void:
	# Separate deterministic fields keep the terrain geological at every scale:
	# kilometre mountain masses, sharp ridges, and exposed coastal bedrock.
	_coast_noise = _make_noise(_seed ^ 0x434f4153, 0.00055, 3, 0.52)
	_shelf_noise = _make_noise(_seed ^ 0x5348454c, 0.0045, 3, 0.48)
	_ridge_noise = _make_noise(_seed ^ 0x52494447, 0.00038, 3, 0.45)
	_mountain_noise = _make_noise(_seed ^ 0x4d4f554e, 0.00019, 5, 0.50)
	_detail_noise = _make_noise(_seed ^ 0x44455441, 0.006, 2, 0.42)


static func _make_noise(noise_seed: int, frequency: float, octaves: int, gain: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.05
	return noise


## Bilinear O(1) signed distance in metres. Negative is land, positive is water.
## Positions outside the bounded map return positive distance from its edge.
func sample_signed_distance(world_xz: Vector2) -> float:
	var half := _world_size_m * 0.5
	var outside_x := maxf(absf(world_xz.x) - half, 0.0)
	var outside_z := maxf(absf(world_xz.y) - half, 0.0)
	if outside_x > 0.0 or outside_z > 0.0:
		return sqrt(outside_x * outside_x + outside_z * outside_z)
	var grid := (world_xz + Vector2(half, half)) / _cell_size_m
	var x0 := clampi(int(floor(grid.x)), 0, _resolution - 1)
	var z0 := clampi(int(floor(grid.y)), 0, _resolution - 1)
	var x1 := mini(x0 + 1, _resolution - 1)
	var z1 := mini(z0 + 1, _resolution - 1)
	var fx := grid.x - float(x0)
	var fz := grid.y - float(z0)
	var a := lerpf(_signed_distance[z0 * _resolution + x0], _signed_distance[z0 * _resolution + x1], fx)
	var b := lerpf(_signed_distance[z1 * _resolution + x0], _signed_distance[z1 * _resolution + x1], fx)
	return lerpf(a, b, fz)


func is_land(world_xz: Vector2) -> bool:
	return sample_signed_distance(world_xz) < 0.0


## Nearest-cell O(1) macro region classification.
func classify_region(world_xz: Vector2) -> Region:
	var half := _world_size_m * 0.5
	if absf(world_xz.x) > half or absf(world_xz.y) > half:
		return Region.OPEN_WATER
	var grid := (world_xz + Vector2(half, half)) / _cell_size_m
	var x := clampi(int(round(grid.x)), 0, _resolution - 1)
	var z := clampi(int(round(grid.y)), 0, _resolution - 1)
	return _regions[z * _resolution + x] as Region


## Continuous deterministic terrain height. The coast starts as low exposed
## svaberg, then rises rapidly into noise-carved ridges. Signed distance supplies
## the fjord-wall shape; seeded fields break it into Norwegian-style rock masses.
func sample_height(world_xz: Vector2) -> float:
	var distance := sample_signed_distance(world_xz)
	if distance >= 0.0:
		# Shallow continuation of the rock shelf under water. The streamer may
		# still pin open ocean to y=0; near-shore samples keep a gentle taper.
		var shelf := clampf(1.0 - distance / 28.0, 0.0, 1.0)
		return -distance * 0.12 * shelf - (1.0 - shelf) * minf(140.0, 3.0 + distance * 0.02)
	var inland := minf(-distance, 6500.0)
	var coast_var := _noise_01(_coast_noise, world_xz)
	var shelf_shape := _noise_01(_shelf_noise, world_xz)
	# Alternating narrow rubble coves and broad glacially polished rock shelves.
	var shelf_width := lerpf(24.0, 105.0, coast_var)
	var shelf_height := lerpf(1.4, 6.5, coast_var)
	var shelf_t := clampf(inland / maxf(shelf_width, 1.0), 0.0, 1.0)
	var shelf := shelf_height * (1.0 - pow(1.0 - shelf_t, 2.15))
	var beach_rubble := (_detail_noise.get_noise_2d(world_xz.x, world_xz.y)) \
		* lerpf(1.2, 0.25, coast_var) * (0.25 + shelf_t * 0.75)
	var slab_roll := (shelf_shape - 0.5) * 2.2 * shelf_t
	if inland <= shelf_width:
		return maxf(0.04, shelf + beach_rubble + slab_roll)

	var past_shelf := maxf(inland - shelf_width, 0.0)
	var mountain := _noise_01(_mountain_noise, world_xz)
	var ridge_raw := absf(_ridge_noise.get_noise_2d(world_xz.x, world_xz.y))
	var ridge := pow(1.0 - clampf(ridge_raw, 0.0, 1.0), 2.5)
	var rise_t := 1.0 - exp(-past_shelf / 1450.0)
	# Fjord walls are decisive but bounded to plausible south/west Norway relief.
	var base_uplift := minf(past_shelf, 3600.0) * lerpf(0.10, 0.27, mountain)
	var ridge_relief := ridge * lerpf(24.0, 390.0, rise_t) * lerpf(0.62, 1.05, mountain)
	var rolling_relief := (shelf_shape - 0.5) * lerpf(8.0, 95.0, rise_t)
	var rock_detail := _detail_noise.get_noise_2d(world_xz.x, world_xz.y) \
		* lerpf(1.0, 6.0, rise_t)
	return maxf(shelf_height, shelf_height + base_uplift + ridge_relief + rolling_relief + rock_detail)


static func _noise_01(noise: FastNoiseLite, world_xz: Vector2) -> float:
	return clampf(noise.get_noise_2d(world_xz.x, world_xz.y) * 0.5 + 0.5, 0.0, 1.0)


func get_signed_distance_raster() -> PackedFloat32Array:
	return _signed_distance.duplicate()


func get_region_raster() -> PackedByteArray:
	return _regions.duplicate()
