class_name WorldLayout
extends RefCounted

## Immutable-ish macro-geography snapshot. WorldLayoutGenerator is the only
## intended writer; consumers receive copy-on-write packed arrays and duplicated
## graph dictionaries. The standard 513² field spans 40 km at 78.125 m per sample.

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
	get: return _contours.duplicate() + (_skerries.contours if _skerries != null else [])
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
const SEABED_VERSION := 6
## Included in chart caches; generator version also identifies bathymetry changes.
const TERRAIN_DATUM_OFFSET_M := 2.5
var _bottom_noise: FastNoiseLite
var _rock_features: Array[Dictionary] = []
var _rock_bins: Dictionary = {}
const ROCK_BIN_M := 1000.0

var _detail_noise: FastNoiseLite
var _skerries: CoastalSkerries
var _navigation_distances := PackedFloat32Array()


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
	_initialize_rock_features()
	_skerries = CoastalSkerries.new()
	_skerries.generate(self)
	# A newly exposed island supersedes a submerged outcrop at the same site.
	# Keep compact marked hazards separate from island feet, so a crest record
	# cannot silently turn into a broad connected shoreline.
	var submerged := _rock_features.duplicate()
	_rock_features.clear()
	_rock_bins.clear()
	for feature in submerged:
		var clearance := 100.0 if feature.kind == "crest" else 45.0
		if _skerries.signed_distance(feature.position,INF) < clearance: continue
		_register_rock_feature(feature)



func _initialize_height_fields() -> void:
	_bottom_noise = _make_noise(_seed ^ 0x424544, 0.00025, 3, 0.45)
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
	var base := sample_macro_signed_distance(world_xz)
	return _skerries.signed_distance(world_xz,base) if _skerries != null else base


func sample_macro_signed_distance(world_xz: Vector2) -> float:
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


## Continuous deterministic terrain height. The coastline itself is rock:
## either wide polished svaberg shelves or steep rock faces dropping to water.
## No separate rock props — the mesh/shader are the shore.
func sample_height(world_xz: Vector2) -> float:
	var base := _sample_height(world_xz, true)
	if _skerries != null: base = _skerries.elevation(world_xz,base)
	return base + TERRAIN_DATUM_OFFSET_M + WaveSurface.WATER_LEVEL


## Existing harbour identities depend on the historical backshore acceptance
## test. Keep that selection surface frozen while fixing the physical terrain.
## This is only for seeded site selection, never render/collision/tree roots.
func sample_port_site_height(world_xz: Vector2) -> float:
	return _sample_height(world_xz, false)


func _sample_height(world_xz: Vector2, continuous_backshore: bool) -> float:
	var distance := sample_macro_signed_distance(world_xz)
	if distance >= 0.0:
		if continuous_backshore:
			return _seabed_height(world_xz, distance)
		# Frozen harbour selection surface.
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
	var shelf_width := lerpf(36.0, 220.0, coast_var) if not continuous_backshore else lerpf(5.0, 35.0, coast_var)
	var shelf_height := lerpf(0.45, 4.2, coast_var) if not continuous_backshore else lerpf(9.0, 3.0, coast_var)
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
	var face_reach := lerpf(320.0, 110.0, face_amt) if not continuous_backshore else lerpf(110.0, 35.0, face_amt)
	var face_height := (lerpf(10.0, 52.0, face_amt) if not continuous_backshore else lerpf(35.0, 95.0, face_amt)) * lerpf(0.68, 1.0, shelf_shape)
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
	if continuous_backshore:
		return full_height
	# Cap early backshore rise so quay faces do not climb into cliff terrain.
	if inland <= shelf_width + 360.0:
		var gentle_cap := shelf_height \
				+ lerpf(8.0, 26.0, coast_var) \
				+ past_shelf * lerpf(0.04, 0.10, coast_var)
		var blend := smoothstep(0.0, 1.0, past_shelf / 300.0)
		var detail := slab_roll * 0.35 + micro * 0.5
		return maxf(0.04, lerpf(gentle_cap, full_height, blend) + detail)
	return full_height


static func _noise_01(noise: FastNoiseLite, world_xz: Vector2) -> float:
	return clampf(noise.get_noise_2d(world_xz.x, world_xz.y) * 0.5 + 0.5, 0.0, 1.0)


func get_signed_distance_raster() -> PackedFloat32Array:
	if _navigation_distances.is_empty():
		_navigation_distances = _signed_distance.duplicate()
		if _skerries != null:
			# Conservative occupancy of every grid cell touched by exposed land.
			var half_cell_diagonal := _cell_size_m * .707107
			for f in _skerries.features:
				var extent: float = float(f.radius)+half_cell_diagonal+20
				var lo: Vector2 = (f.position-Vector2.ONE*extent+Vector2.ONE*half_extent_m)/_cell_size_m
				var hi: Vector2 = (f.position+Vector2.ONE*extent+Vector2.ONE*half_extent_m)/_cell_size_m
				for z in range(maxi(0,floori(lo.y)),mini(_resolution-1,ceili(hi.y))+1):
					for x in range(maxi(0,floori(lo.x)),mini(_resolution-1,ceili(hi.x))+1):
						var at := Vector2(x,z)*_cell_size_m-Vector2.ONE*half_extent_m
						var idx := z*_resolution+x
						_navigation_distances[idx] = minf(_navigation_distances[idx],CoastalSkerries.polygon_distance(at,f.polygon)-half_cell_diagonal)
	return _navigation_distances.duplicate()


func get_region_raster() -> PackedByteArray:
	return _regions.duplicate()


## 1 when the nearest macro shore belongs to a compact island, 0 on the mainland.
## A body of land that runs out within a couple of kilometres gets the shelf.
func _island_shore_weight(at: Vector2, shore_distance: float) -> float:
	var step := 24.0
	var east := sample_macro_signed_distance(at+Vector2(step,0.0))-sample_macro_signed_distance(at-Vector2(step,0.0))
	var north := sample_macro_signed_distance(at+Vector2(0.0,step))-sample_macro_signed_distance(at-Vector2(0.0,step))
	var grad := Vector2(east,north)
	if grad.length_squared() < 0.04:
		return 0.0
	var inland := -grad/grad.length()
	var cursor := at+inland*shore_distance
	var run := 0.0
	while run < 2800.0:
		run += 280.0
		cursor += inland*280.0
		if sample_macro_signed_distance(cursor) > 0.0:
			return 1.0-smoothstep(1800.0,2800.0,run)
	return 0.0


## Continuous rock faces, basins and indexed submerged bedrock formations.
## Rendering, charts and marker placement all sample this elevation.
func _seabed_height(at: Vector2, shore_distance: float) -> float:
	var distance := maxf(shore_distance, 0.0)
	var basin := _noise_01(_bottom_noise, at)
	# Variable rock faces continue below sea level, without the old 3 m apron.
	# Mainland and fjord walls keep the short reach. A compact island holds
	# 16–32 m, then falls into the same 140–420 m basin over a few hundred metres.
	var coast := smoothstep(-0.35,0.4,_coast_noise.get_noise_2dv(at))
	var reach := lerpf(60.0,380.0,coast)
	var basin_depth := lerpf(140.0,420.0,basin)
	var depth := basin_depth*(1.0-exp(-distance/reach))
	if distance < 2400.0:
		var island := _island_shore_weight(at,distance)
		if island > 0.0:
			var shelf_width := lerpf(120.0,260.0,coast)
			var shelf_depth := lerpf(16.0,32.0,basin)
			var held := shelf_depth*smoothstep(0.0,42.0,distance)
			var island_depth := held
			if distance > shelf_width:
				var fall_reach := lerpf(280.0,560.0,coast)
				island_depth = shelf_depth+(basin_depth-shelf_depth)*(1.0-exp(-(distance-shelf_width)/fall_reach))
			depth = lerpf(depth,island_depth,island)
	var bottom := -depth
	var bin := Vector2i(floori(at.x/ROCK_BIN_M),floori(at.y/ROCK_BIN_M))
	for index in _rock_bins.get(bin,[]):
		bottom = maxf(bottom, rock_feature_height(_rock_features[index],at))
	# Offshore formations remain submerged. One elevation feeds mesh and soundings.
	return bottom


func rock_features() -> Array[Dictionary]:
	return _rock_features.duplicate(true)


static func rock_feature_height(feature: Dictionary, at: Vector2) -> float:
	var offset: Vector2 = at - feature.position
	var axis: Vector2 = feature.axis
	var u: float = offset.dot(axis) / feature.length
	var v: float = offset.dot(Vector2(-axis.y, axis.x)) / feature.width
	# Skewed, faceted bedrock: a short crest, a steeper face and a longer back.
	# Linear relief at the crest avoids the previous broad, almost-level dome.
	var bend: float = feature.get("bend", 0.0)
	v += bend * sin(u * 2.7)
	u *= 1.3 if u > 0.0 else 0.8
	v *= 1.25 if v > 0.0 else 0.85
	var q := maxf(absf(u), absf(v)) + minf(absf(u), absf(v)) * 0.35
	var relief := 7.0 * q + 25.0 * q * q
	# Submerged ledge below the hazardous crest, rather than a surface-level apron.
	relief += 8.0 * smoothstep(0.65, 0.85, q)
	return -float(feature.depth) - relief


func _initialize_rock_features() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed ^ 0x524f434b
	var scale := _world_size_m/40000.0
	# Features are terrain data, not rendered props or a separate chart overlay.
	# Shelf outcrops cluster around islands; a sparser outer belt lies offshore.
	for z in range(-int(half_extent_m)+500,int(half_extent_m)-500,450):
		for x in range(-int(half_extent_m)+500,int(half_extent_m)-500,450):
			var at := Vector2(x+rng.randf_range(-150,150),z+rng.randf_range(-150,150))
			var shore := sample_signed_distance(at)
			if shore < 90.0 or shore > 6000.0*scale: continue
			var chance := .065 if shore < 1600.0*scale else .012
			if rng.randf() > chance: continue
			# Avoid the central traffic spine, but allow hazards on its flanks.
			var on_spine := false
			for way in _waterways:
				var points: PackedVector2Array = way.points
				for i in range(1,points.size()):
					if Geometry2D.get_closest_point_to_segment(at,points[i-1],points[i]).distance_to(at) < 100.0:
						on_spine = true
						break
				if on_spine: break
			if on_spine: continue
			# Regional direction varies smoothly; neighbouring outcrops share structure.
			var angle := _bottom_noise.get_noise_2dv(at) * TAU + rng.randf_range(-.25, .25)
			var bank := rng.randf() < 0.25
			var feature := {"position":at,"axis":Vector2.from_angle(angle),
				"length":rng.randf_range(100,220) if bank else rng.randf_range(45,85),
				"width":rng.randf_range(60,110) if bank else rng.randf_range(30,50),
				"depth":rng.randf_range(9,24) if bank else rng.randf_range(.7,2.4),
				"bend":rng.randf_range(-.4,.4), "kind":"bank" if bank else "crest"}
			_register_rock_feature(feature)
			# Lower companion ridges form a broken bedrock group. Their saddles stay
			# submerged well below the crest, allowing water between adjacent highs.
			for part in rng.randi_range(1,3):
				var axis := Vector2.from_angle(angle + rng.randf_range(-.5,.5))
				var position: Vector2 = at + axis * rng.randf_range(100,230) * (-1.0 if part % 2 else 1.0)
				if sample_signed_distance(position) < 70.0: continue
				_register_rock_feature({"position":position,"axis":axis,
					"length":rng.randf_range(70,160),"width":rng.randf_range(35,75),
					"depth":rng.randf_range(12,40),"bend":rng.randf_range(-.5,.5),"kind":"ridge"})


func _register_rock_feature(feature: Dictionary) -> void:
	var index := _rock_features.size()
	_rock_features.append(feature)
	var at: Vector2 = feature.position
	# Conservative support out to below the deepest base basin. Outside this
	# radius the feature cannot raise the base, avoiding spatial-bin seams.
	var extent: float = maxf(feature.length,feature.width) * 6.5
	for bz in range(floori((at.y-extent)/ROCK_BIN_M),floori((at.y+extent)/ROCK_BIN_M)+1):
		for bx in range(floori((at.x-extent)/ROCK_BIN_M),floori((at.x+extent)/ROCK_BIN_M)+1):
			var bin := Vector2i(bx,bz)
			if not _rock_bins.has(bin): _rock_bins[bin] = []
			_rock_bins[bin].append(index)




## World-space bottom datum used by rendering and future sounders/navigation.
## Port terrain overrides belong to WorldTerrainStreamer.sample_render_terrain_height.
func sample_seabed_elevation(at: Vector2) -> float:
	return sample_height(at) - TERRAIN_DATUM_OFFSET_M


## Water level is explicit so callers can use mean sea level or a local wave.
func sample_water_depth(at: Vector2, water_level_m: float = WaveSurface.WATER_LEVEL) -> float:
	return maxf(0.0, water_level_m - sample_seabed_elevation(at))


func sample_bottom_type(at: Vector2) -> String:
	var distance := sample_signed_distance(at)
	if distance < 0.0: return "land"
	var depth := sample_water_depth(at)
	if distance < 100.0 or depth < 25.0: return "rock"
	return "mud" if depth > 100.0 else "sand"


func skerry_features() -> Array[Dictionary]:
	return _skerries.features.duplicate(true) if _skerries != null else []

func skerries_in_rect(rect: Rect2) -> Array[Dictionary]:
	return _skerries.in_rect(rect) if _skerries != null else []

func skerry_segment_clear(a: Vector2,b: Vector2,margin: float) -> bool:
	return _skerries == null or _skerries.segment_clear(a,b,margin)

func macro_coastline_contours() -> Array[PackedVector2Array]:
	return _contours.duplicate()
