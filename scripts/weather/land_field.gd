class_name LandField
extends RefCounted

## Static macro-geography, wave-shelter, and coastal-exposure query.
##
## New worlds initialize this from a WorldLayout, whose macro signed-distance
## raster makes distance and shelter queries O(1). `initialize(islands)` remains
## accepted for old tools/tests; that compatibility backend retains its O(N)
## island scan and historical shelter falloff.

## Physical wave attenuation is deliberately local. Weather and sea-state use
## coastal_exposure/directional_fetch instead and therefore do not apply this
## attenuation a second time.
const WAVE_SHELTER_FALLOFF_M := 450.0
const LEGACY_SHELTER_FALLOFF_M := 3000.0
const COASTAL_DISTANCE_M := 1800.0
const FETCH_DISTANCE_M := 12000.0
const FETCH_RAY_COUNT := 16

## Extra padding around the visual island polygon — the polygon edge is noisy
## (see IslandMeshBuilder.build_polygon) so we treat the disk as slightly
## larger than the nominal half-width.
const ISLAND_RADIUS_PADDING_M : float = 25.0

## Baked wave-shelter texture size.
const BAKE_RESOLUTION : int = 512

## Padding around the island bounding box when sizing the baked texture so
## camera positions just outside still get a meaningful shelter value.
const BAKE_PADDING_M : float = 800.0

# ── Cached island collision (OBB in world XZ; disk radius for fast shelter) ───
static var _centers_xz : PackedVector2Array = PackedVector2Array()
static var _radii      : PackedFloat32Array = PackedFloat32Array()
static var _obb_half_x : PackedFloat32Array = PackedFloat32Array()
static var _obb_half_z : PackedFloat32Array = PackedFloat32Array()
static var _obb_rot_y  : PackedFloat32Array = PackedFloat32Array()
static var _initialized: bool = false
static var _layout: WorldLayout = null
## Geography-only exposure cache. Coastal openness does not depend on game time,
## so weather time-bucket misses must not redo 16 fetch rays every few seconds.
static var _exposure_cache: Dictionary = {}
const EXPOSURE_CACHE_CELL_M := 250.0
const EXPOSURE_CACHE_LIMIT := 2048

# ── Baked shelter texture (CPU-baked, GPU-sampled) ────────────────────────────
static var _baked_shelter_texture: ImageTexture = null
static var _baked_shelter_data := PackedFloat32Array()
## World-space (x, z) of the texel-(0, 0) lower-left corner.
static var _baked_world_origin   : Vector2 = Vector2.ZERO
## World-space extent (square) covered by the texture, in metres.
static var _baked_world_size     : float   = 0.0


## Seed the field from the preferred WorldLayout, or from the legacy island
## array. Accepting Variant preserves the historical initialize(islands) API
## while allowing the world bootstrap to call initialize(layout).
static func initialize(source: Variant) -> void:
	if source is WorldLayout:
		initialize_from_layout(source as WorldLayout)
		return
	## Was a bare `assert()`, and it is the clearest case of the sixteen.
	##
	## Measured, not assumed (`tests/_hole_facts_probe.gd`): the next line's
	## `source as Array` on a Variant holding an int, a String or `null` is not a
	## silent empty Array — it is `SCRIPT ERROR: Invalid cast: could not convert
	## value to 'Array'`, which ABORTS the enclosing function and leaves the
	## process alive. That is the same mechanism CONVENTIONS §2 records for a
	## failed `assert()`, so in the SceneTree lane a mistyped call here does not
	## fail: it idles to the gate's timeout, and everything it printed is lost
	## with the pipe buffer. In a release build the `assert` is compiled out and
	## the invalid cast is all that is left.
	##
	## In a DEBUG build the `assert` fired first and aborted just the same, and
	## what that leaves behind is the real damage. Measured against the pre-guard
	## file with one island installed and then a bad `initialize(5)`:
	##
	##   pre-guard:  distance_to_land(0,0) = -725.0   wave_shelter = 0.0
	##   with guard: distance_to_land(0,0) = inf      wave_shelter = 1.0
	##
	## An aborted `initialize` does not clear anything — the PREVIOUS world's
	## islands stay installed, so a new world is sheltered by land that is not
	## there any more, indefinitely and silently. The guard's fallback is not
	## "the same broken state with an error on top"; it is the state the caller
	## asked for and did not get.
	if not (source is Array):
		push_error(
			"LandField.initialize expects a WorldLayout or an Array of islands, got %s — initializing an EMPTY land field (every query will read as open ocean)" % type_string(typeof(source))
		)
		_initialize_legacy([])
		return
	_initialize_legacy(source as Array)


static func initialize_from_layout(layout: WorldLayout) -> void:
	## Was a bare `assert()`, and the same shape as the one above. In debug it
	## aborted and left the previous world's islands installed (measured:
	## `distance_to_land(0,0)` stayed at -725.0 after a null call); in a release
	## build, with the assert gone, `_layout` is set to null, `_initialized` is
	## set true, and `_bake_shelter_texture()` dereferences it. Falling back to
	## the empty legacy field keeps the class in a state its own queries define
	## — no islands, no shelter — rather than either of those.
	if layout == null:
		push_error("LandField.initialize_from_layout was given no WorldLayout — initializing an EMPTY land field (every query will read as open ocean)")
		_initialize_legacy([])
		return
	_clear_legacy_islands()
	_layout = layout
	_exposure_cache.clear()
	_initialized = true
	_bake_shelter_texture()


## Legacy island entries:
##   "center": Vector3 — port / island origin in world space
## Preferred (matches port island footprint):
##   "half_x", "half_z": float — local half-extents incl. organic margin (m)
##   "rotation_y": float — port plot yaw (radians)
## Legacy fallback:
##   "radius": float — circular island (deprecated; too small for routing)
static func _initialize_legacy(islands: Array) -> void:
	_clear_legacy_islands()
	_layout = null
	_exposure_cache.clear()
	for island in islands:
		var center_v: Vector3 = island.get("center", Vector3.ZERO)
		var center := Vector2(center_v.x, center_v.z)
		if island.has("half_x") and island.has("half_z"):
			var half_x := maxf(float(island.get("half_x", 0.0)), 1.0) + ISLAND_RADIUS_PADDING_M
			var half_z := maxf(float(island.get("half_z", 0.0)), 1.0) + ISLAND_RADIUS_PADDING_M
			var rot_y := float(island.get("rotation_y", 0.0))
			var route_r := sqrt(half_x * half_x + half_z * half_z)
			_centers_xz.append(center)
			_radii.append(route_r)
			_obb_half_x.append(half_x)
			_obb_half_z.append(half_z)
			_obb_rot_y.append(rot_y)
			continue
		var radius: float = float(island.get("radius", 0.0)) + ISLAND_RADIUS_PADDING_M
		if radius <= 0.0:
			continue
		_centers_xz.append(center)
		_radii.append(radius)
		_obb_half_x.append(radius)
		_obb_half_z.append(radius)
		_obb_rot_y.append(0.0)
	_initialized = true
	_bake_shelter_texture()


static func _clear_legacy_islands() -> void:
	_centers_xz.clear()
	_radii.clear()
	_obb_half_x.clear()
	_obb_half_z.clear()
	_obb_rot_y.clear()


static func is_initialized() -> bool:
	return _initialized


## The immutable layout reference is safe to expose: its public raster and
## contour accessors return copies.
static func get_layout() -> WorldLayout:
	return _layout


static func get_coastline_contours() -> Array[PackedVector2Array]:
	if _layout == null:
		return []
	return _layout.coastline_contours


## Signed distance (metres) from `world_pos` to the nearest island shore.
## Positive in open water, negative inside land. Returns +INF before init.
static func distance_to_land(world_pos: Vector3) -> float:
	if not _initialized:
		return INF
	if _layout != null:
		return _layout.sample_signed_distance(Vector2(world_pos.x, world_pos.z))
	if _centers_xz.is_empty():
		return INF
	var pos2 := Vector2(world_pos.x, world_pos.z)
	var best := INF
	for i in range(_centers_xz.size()):
		var d := _obb_signed_distance(
			pos2,
			_centers_xz[i],
			_obb_half_x[i],
			_obb_half_z[i],
			_obb_rot_y[i],
		)
		if d < best:
			best = d
	return best


static func _obb_signed_distance(
	pos2: Vector2,
	center: Vector2,
	half_x: float,
	half_z: float,
	rot_y: float,
) -> float:
	var offset := pos2 - center
	var c := cos(-rot_y)
	var s := sin(-rot_y)
	var lx := offset.x * c - offset.y * s
	var lz := offset.x * s + offset.y * c
	var dx := absf(lx) - half_x
	var dz := absf(lz) - half_z
	var ox := maxf(dx, 0.0)
	var oz := maxf(dz, 0.0)
	return sqrt(ox * ox + oz * oz) + minf(maxf(dx, dz), 0.0)


## Local 0..1 wave attenuation. Zero on/inside land and effectively open water
## within a few hundred metres. This is the only field baked into the ocean
## shelter texture.
## Returns 1.0 before init so systems behave like "open ocean" until ready.
static func wave_shelter(world_pos: Vector3) -> float:
	if not _initialized:
		return 1.0
	if _layout != null:
		var distance := distance_to_land(world_pos)
		if distance <= 0.0:
			return 0.0
		return smoothstep(0.0, WAVE_SHELTER_FALLOFF_M, distance)
	if _centers_xz.is_empty():
		return 1.0
	var pos2 := Vector2(world_pos.x, world_pos.z)
	var best: float = INF
	for i in range(_centers_xz.size()):
		var r := _radii[i]
		var threshold := LEGACY_SHELTER_FALLOFF_M + r
		var d2 := pos2.distance_squared_to(_centers_xz[i])
		if d2 > threshold * threshold:
			continue  # this island is fully open-water (shelter=1) from here
		var d := _obb_signed_distance(
			pos2,
			_centers_xz[i],
			_obb_half_x[i],
			_obb_half_z[i],
			_obb_rot_y[i],
		)
		if d < best:
			best = d
			if best <= 0.0:
				return 0.0  # on or inside land — no other island can win
	if best == INF:
		return 1.0
	return smoothstep(0.0, LEGACY_SHELTER_FALLOFF_M, best)


## Compatibility alias. "Shore shelter" now has the unambiguous local,
## physical-wave semantics.
static func shore_shelter(world_pos: Vector3) -> float:
	return wave_shelter(world_pos)


## Normalized unobstructed fetch in one direction. A value of 1 means the ray
## remained over water for FETCH_DISTANCE_M. Layout sampling is bounded and
## deterministic; SDF-guided steps keep the fixed upper cost modest.
static func directional_fetch(world_pos: Vector3, direction: Vector2) -> float:
	if not _initialized:
		return 1.0
	if distance_to_land(world_pos) <= 0.0:
		return 0.0
	if direction.length_squared() < 0.000001:
		return 0.0
	var ray := direction.normalized()
	var origin := Vector2(world_pos.x, world_pos.z)
	var travelled := 0.0
	var minimum_step := 75.0
	if _layout != null:
		minimum_step = maxf(_layout.cell_size_m * 0.5, minimum_step)
	while travelled < FETCH_DISTANCE_M:
		var point := origin + ray * travelled
		var distance := distance_to_land(Vector3(point.x, world_pos.y, point.y))
		if distance <= 0.0:
			return clampf(travelled / FETCH_DISTANCE_M, 0.0, 1.0)
		# Cap the step so thin skerries represented by the macro raster cannot
		# be jumped over by a large open-water SDF value.
		travelled += clampf(distance * 0.7, minimum_step, 400.0)
	return 1.0


## Kilometre-scale openness/fetch proxy for weather, sea state, and open-water
## gameplay. It intentionally does not reuse wave_shelter.
static func coastal_exposure(world_pos: Vector3) -> float:
	if not _initialized:
		return 1.0
	var cache_key := Vector2i(
		roundi(world_pos.x / EXPOSURE_CACHE_CELL_M),
		roundi(world_pos.z / EXPOSURE_CACHE_CELL_M),
	)
	if _exposure_cache.has(cache_key):
		return float(_exposure_cache[cache_key])
	var coast_distance := distance_to_land(world_pos)
	var exposure := 0.0
	if coast_distance > 0.0:
		var fetch_sum := 0.0
		for ray_index in range(FETCH_RAY_COUNT):
			var angle := TAU * float(ray_index) / float(FETCH_RAY_COUNT)
			fetch_sum += directional_fetch(world_pos, Vector2(cos(angle), sin(angle)))
		var mean_fetch := fetch_sum / float(FETCH_RAY_COUNT)
		var coastal_opening := smoothstep(80.0, COASTAL_DISTANCE_M, coast_distance)
		exposure = clampf(coastal_opening * pow(mean_fetch, 0.65), 0.0, 1.0)
	if _exposure_cache.size() >= EXPOSURE_CACHE_LIMIT:
		_exposure_cache.clear()
	_exposure_cache[cache_key] = exposure
	return exposure


## Compatibility inverse of local wave shelter.
## for systems that want a "near land" signal (tracker lerp speed, ambient
## bird SFX volume, etc).
static func shore_proximity(world_pos: Vector3) -> float:
	return 1.0 - wave_shelter(world_pos)


# ── Debug ─────────────────────────────────────────────────────────────────────

static func get_island_count() -> int:
	if _layout != null:
		return _layout.coastline_contours.size()
	return _centers_xz.size()


## Returns Array[Dictionary] of `{center: Vector2, radius: float}` — used by
## the map overlay so harbours visibly read as smooth shelter regions.
static func get_island_disks() -> Array:
	var out: Array = []
	for i in range(_centers_xz.size()):
		out.append({"center": _centers_xz[i], "radius": _radii[i]})
	return out


## Returns a `PackedVector4Array` packed as (center_x, center_z, radius, 0)
## per island. Kept for any debug/map consumer that still wants raw disks;
## the ocean shader now uses the baked shelter texture instead.
static func get_disks_packed(max_count: int) -> PackedVector4Array:
	var out := PackedVector4Array()
	var n := mini(_centers_xz.size(), max_count)
	out.resize(n)
	for i in range(n):
		var c := _centers_xz[i]
		out[i] = Vector4(c.x, c.y, _radii[i], 0.0)
	return out


# ── Baked shelter texture ─────────────────────────────────────────────────────

static func get_baked_shelter_texture() -> ImageTexture:
	return _baked_shelter_texture


## World-space (x, z) of the texel-(0, 0) lower-left corner of the bake.
static func get_baked_world_origin() -> Vector2:
	return _baked_world_origin


## Side length (square) of the world region covered by the baked texture.
static func get_baked_world_size() -> float:
	return _baked_world_size


## Bilinear CPU lookup of the exact same bake bound to ocean shaders.
static func sample_baked_shelter(world_pos: Vector3) -> float:
	if _baked_shelter_data.is_empty() or _baked_world_size <= 0.0:
		return wave_shelter(world_pos)
	var uv := (Vector2(world_pos.x, world_pos.z) - _baked_world_origin) / _baked_world_size
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return 1.0
	var px := uv.x * float(BAKE_RESOLUTION) - 0.5
	var py := uv.y * float(BAKE_RESOLUTION) - 0.5
	var x0 := clampi(int(floor(px)), 0, BAKE_RESOLUTION - 1)
	var y0 := clampi(int(floor(py)), 0, BAKE_RESOLUTION - 1)
	var x1 := mini(x0 + 1, BAKE_RESOLUTION - 1)
	var y1 := mini(y0 + 1, BAKE_RESOLUTION - 1)
	var fx := clampf(px - floor(px), 0.0, 1.0)
	var fy := clampf(py - floor(py), 0.0, 1.0)
	var a := lerpf(
		_baked_shelter_data[y0 * BAKE_RESOLUTION + x0],
		_baked_shelter_data[y0 * BAKE_RESOLUTION + x1],
		fx
	)
	var b := lerpf(
		_baked_shelter_data[y1 * BAKE_RESOLUTION + x0],
		_baked_shelter_data[y1 * BAKE_RESOLUTION + x1],
		fx
	)
	return lerpf(a, b, fy)


static func get_active_island_indices_for_segment(a: Vector2, b: Vector2, clearance: float) -> Array[int]:
	var out: Array[int] = []
	if not _initialized or _centers_xz.is_empty():
		return out
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	for i in range(_centers_xz.size()):
		var center := _centers_xz[i]
		var radius := _radii[i]
		var dist := 0.0
		if ab_len_sq == 0.0:
			dist = a.distance_to(center)
		else:
			var ap := center - a
			var t := clampf(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
			var proj := a + t * ab
			dist = center.distance_to(proj)
		if dist < radius + clearance:
			out.append(i)
	return out


static func distance_to_land_filter(world_pos: Vector3, active_islands: Array[int]) -> float:
	if not _initialized or _centers_xz.is_empty() or active_islands.is_empty():
		return INF
	var pos2 := Vector2(world_pos.x, world_pos.z)
	var best := INF
	for idx in active_islands:
		var d := _obb_signed_distance(
			pos2,
			_centers_xz[idx],
			_obb_half_x[idx],
			_obb_half_z[idx],
			_obb_rot_y[idx],
		)
		if d < best:
			best = d
	return best


static func is_island_ignored(idx: int, ignore_centers: Array[Vector2]) -> bool:
	if not _initialized or idx < 0 or idx >= _centers_xz.size():
		return false
	var center := _centers_xz[idx]
	for ic in ignore_centers:
		if center.distance_to(ic) < 10.0:
			return true
	return false


static func get_island_disk(idx: int) -> Dictionary:
	if not _initialized or idx < 0 or idx >= _centers_xz.size():
		return {}
	return {"center": _centers_xz[idx], "radius": _radii[idx]}



## Bake `wave_shelter` over a square world region into an R32F texture the
## ocean vertex shader can sample once per vertex. Replaces the per-vertex
## land_disks loop: with 35 islands × 68k verts that was ~2.4M distance() ops
## per frame. Texture sample is O(1).
##
## Bake cost is paid once at world init — ~262k shore_shelter() calls. With
## the early-out in shore_shelter the typical cost is ~50-150 ms on a
## modern CPU. The world is loading anyway; one extra hitch is invisible.
static func _bake_shelter_texture() -> void:
	if _layout == null and _centers_xz.is_empty():
		_baked_shelter_texture = null
		_baked_shelter_data.clear()
		_baked_world_size = 0.0
		return

	var min_x: float
	var min_z: float
	var max_x: float
	var max_z: float
	if _layout != null:
		# Macro map bounds are authoritative; each texel is one O(1) SDF query.
		min_x = -_layout.half_extent_m
		min_z = -_layout.half_extent_m
		max_x = _layout.half_extent_m
		max_z = _layout.half_extent_m
	else:
		min_x = INF
		min_z = INF
		max_x = -INF
		max_z = -INF
		for i in range(_centers_xz.size()):
			var c := _centers_xz[i]
			var influence := _radii[i] + LEGACY_SHELTER_FALLOFF_M
			min_x = minf(min_x, c.x - influence)
			min_z = minf(min_z, c.y - influence)
			max_x = maxf(max_x, c.x + influence)
			max_z = maxf(max_z, c.y + influence)
		min_x -= BAKE_PADDING_M
		min_z -= BAKE_PADDING_M
		max_x += BAKE_PADDING_M
		max_z += BAKE_PADDING_M

	# Square the region so a single uniform `size` defines both axes.
	var side : float = maxf(max_x - min_x, max_z - min_z)
	var cx   : float = (min_x + max_x) * 0.5
	var cz   : float = (min_z + max_z) * 0.5
	_baked_world_origin = Vector2(cx - side * 0.5, cz - side * 0.5)
	_baked_world_size   = side

	var bytes := PackedByteArray()
	bytes.resize(BAKE_RESOLUTION * BAKE_RESOLUTION * 4)  # R32F = 4 bytes/texel

	var step : float = side / float(BAKE_RESOLUTION)
	for j in range(BAKE_RESOLUTION):
		var wz : float = _baked_world_origin.y + (float(j) + 0.5) * step
		for i in range(BAKE_RESOLUTION):
			var wx : float = _baked_world_origin.x + (float(i) + 0.5) * step
			var shelter := wave_shelter(Vector3(wx, 0.0, wz))
			bytes.encode_float((j * BAKE_RESOLUTION + i) * 4, shelter)

	var img := Image.create_from_data(BAKE_RESOLUTION, BAKE_RESOLUTION,
									   false, Image.FORMAT_RF, bytes)
	_baked_shelter_data = bytes.to_float32_array()
	_baked_shelter_texture = ImageTexture.create_from_image(img)
