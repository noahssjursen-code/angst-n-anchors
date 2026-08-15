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
	## These four were bare `assert()`s until 2026-08-15. All four are real
	## invariants, not developer notes, and `assert` was the wrong tool for every
	## one of them: Godot compiles `assert` out of release builds, and in a
	## SceneTree script a failed one aborts this function while the CALLER carries
	## on — so the layout the generator hands out is half-built, and every sampler
	## reads it forever after.
	##
	## What each one is holding up:
	##  - re-initialization would swap the raster under live consumers that hold
	##    this object (the streamer caches chunk meshes keyed on it);
	##  - `resolution < 2` divides by zero below (`size_m / float(res - 1)`);
	##    measured, that is `inf`, not an error, so `_cell_size_m` is `inf` and
	##    every `grid` coordinate collapses to 0;
	##  - a raster whose length disagrees with `resolution²` then indexes out of
	##    bounds. Measured against the pre-guard file: `Out of bounds get index
	##    '0' (on base: 'PackedFloat32Array')`, after which
	##    `sample_signed_distance` returns **0.0** — which reads as "exactly on
	##    the coastline" everywhere in the world.
	##
	## The guard refuses the input and leaves the object in its documented empty
	## state — `_resolution == 0` — which the two samplers below now answer as
	## open water instead of dividing by zero. A refused layout is loud, inert and
	## survivable; a half-built one is silent and wrong.
	if _resolution != 0:
		push_error("WorldLayout may only be initialized once (already %d²)" % _resolution)
		return
	if resolution < 2:
		push_error("WorldLayout requires resolution >= 2, got %d — layout left empty" % resolution)
		return
	var expected_cells := resolution * resolution
	if signed_distance.size() != expected_cells or regions.size() != expected_cells:
		push_error(
			"WorldLayout raster size mismatch at resolution %d: expected %d cells, got %d signed-distance and %d region entries — layout left empty" % [
				resolution, expected_cells, signed_distance.size(), regions.size(),
			]
		)
		return
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
	## An empty layout (never initialized, or refused by the guard in
	## `_initialize`) has no raster to bilinear-sample and `_cell_size_m == 0.0`.
	## Answering "open water, far from land" is the only defined answer available
	## and it is the safe one: `is_land` says false, the terrain streamer builds
	## flat sea, and nothing indexes an empty PackedFloat32Array.
	if _resolution == 0:
		return _world_size_m
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
	## Same empty-layout branch as `sample_signed_distance` — see the note there.
	if _resolution == 0:
		return Region.OPEN_WATER
	var half := _world_size_m * 0.5
	if absf(world_xz.x) > half or absf(world_xz.y) > half:
		return Region.OPEN_WATER
	var grid := (world_xz + Vector2(half, half)) / _cell_size_m
	var x := clampi(int(round(grid.x)), 0, _resolution - 1)
	var z := clampi(int(round(grid.y)), 0, _resolution - 1)
	return _regions[z * _resolution + x] as Region


## Continuous deterministic terrain height. The coastline itself is rock:
## either wide polished svaberg shelves or steep rock faces dropping to water.
## No separate rock props — the mesh/shader are the shore.
func sample_height(world_xz: Vector2) -> float:
	var distance := sample_signed_distance(world_xz)
	if distance >= 0.0:
		# Shallow continuation of the rock shelf under water. The streamer may
		# still pin open ocean to y=0; near-shore samples keep a gentle taper.
		var shelf := clampf(1.0 - distance / 28.0, 0.0, 1.0)
		return -distance * 0.12 * shelf - (1.0 - shelf) * minf(140.0, 3.0 + distance * 0.02)
	var inland := minf(-distance, 6500.0)
	# Bias toward broad svaberg shelves so harbours get workable backshore grades.
	var coast_var := pow(_noise_01(_coast_noise, world_xz), 0.68)
	var shelf_shape := _noise_01(_shelf_noise, world_xz)
	# High coast_var = broad svaberg slabs; low = cliffy rock-face shoreline.
	var face_amt := 1.0 - coast_var
	var shelf_width := lerpf(36.0, 220.0, coast_var)
	var shelf_height := lerpf(0.45, 4.2, coast_var)
	var shelf_t := clampf(inland / maxf(shelf_width, 1.0), 0.0, 1.0)
	# Svaberg eases convex/flat; face coasts stay low then climb hard after the lip.
	var shelf_ease := 1.0 - pow(1.0 - shelf_t, lerpf(1.1, 1.65, coast_var))
	var shelf := shelf_height * shelf_ease
	var slab_roll := (shelf_shape - 0.5) * lerpf(0.28, 1.8, coast_var) * shelf_t
	var micro := _detail_noise.get_noise_2d(world_xz.x, world_xz.y) \
		* lerpf(0.28, 0.65, face_amt) * (1.0 - shelf_t * 0.5)
	if inland <= shelf_width:
		return maxf(0.04, shelf + slab_roll + micro)

	var past_shelf := maxf(inland - shelf_width, 0.0)
	# Continuous rock face: gentler rise off the shelf so terminals are not cliff-backed.
	var face_reach := lerpf(320.0, 110.0, face_amt)
	var face_height := lerpf(10.0, 52.0, face_amt) * lerpf(0.68, 1.0, shelf_shape)
	var face_t := 1.0 - exp(-past_shelf / maxf(face_reach, 1.0))
	var rock_face := face_height * face_t

	var mountain := _noise_01(_mountain_noise, world_xz)
	var ridge_raw := absf(_ridge_noise.get_noise_2d(world_xz.x, world_xz.y))
	var ridge := pow(1.0 - clampf(ridge_raw, 0.0, 1.0), 2.5)
	var rise_t := 1.0 - exp(-past_shelf / 1850.0)
	var near_coast_damp := smoothstep(0.0, 420.0, past_shelf)
	var base_uplift := minf(past_shelf, 3600.0) * lerpf(0.05, 0.20, mountain) * near_coast_damp
	var ridge_relief := ridge * lerpf(16.0, 320.0, rise_t) * lerpf(0.58, 1.0, mountain) * near_coast_damp
	var rolling_relief := (shelf_shape - 0.5) * lerpf(4.0, 72.0, rise_t) * near_coast_damp
	var rock_detail := _detail_noise.get_noise_2d(world_xz.x, world_xz.y) \
		* lerpf(0.8, 5.0, rise_t) * near_coast_damp
	var full_height := maxf(
		shelf_height,
		shelf_height + rock_face + base_uplift + ridge_relief + rolling_relief + rock_detail,
	)
	# Cap early backshore rise so quay faces do not climb into cliff terrain.
	if inland <= shelf_width + 360.0:
		var gentle_cap := shelf_height \
				+ lerpf(8.0, 26.0, coast_var) \
				+ past_shelf * lerpf(0.04, 0.10, coast_var)
		var blend := smoothstep(0.0, 1.0, past_shelf / 300.0)
		return maxf(0.04, lerpf(gentle_cap, full_height, blend) + slab_roll * 0.35 + micro * 0.5)
	return full_height


static func _noise_01(noise: FastNoiseLite, world_xz: Vector2) -> float:
	return clampf(noise.get_noise_2d(world_xz.x, world_xz.y) * 0.5 + 0.5, 0.0, 1.0)


func get_signed_distance_raster() -> PackedFloat32Array:
	return _signed_distance.duplicate()


func get_region_raster() -> PackedByteArray:
	return _regions.duplicate()
