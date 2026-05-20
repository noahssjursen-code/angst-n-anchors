class_name LandField
extends RefCounted

## Static distance-to-land query — the deterministic replacement for PORT_CALM.
##
## At world generation, `initialize(islands)` is called with one entry per
## island: `{ center: Vector3, radius: float }`. After that, any system can
## ask:
##   LandField.distance_to_land(world_pos)   →   metres to nearest shore
##                                               (negative inside land)
##   LandField.shore_shelter(world_pos)      →   0.0 on shore, 1.0 fully open water
##
## The wave system multiplies its amplitude by `shore_shelter`, so storms can
## rage in open water while harbours stay placid — without the brittle
## PORT_CALM zones that used to hard-override weather.
##
## Performance: CPU calls are O(N_islands) per query. The ocean vertex shader
## was doing the same loop per vertex (68k verts × up to 64 islands = ~4.4M
## distance() ops/frame). `initialize()` now also bakes a 2D shelter texture
## the shader samples once per vertex — constant cost regardless of island
## count, frees the GPU vertex stage.

## Distance from shore at which waves recover to 100 %.
const SHELTER_FALLOFF_M : float = 300.0

## Extra padding around the visual island polygon — the polygon edge is noisy
## (see IslandMeshBuilder.build_polygon) so we treat the disk as slightly
## larger than the nominal half-width.
const ISLAND_RADIUS_PADDING_M : float = 25.0

## Baked shelter texture size. 512² → ~30 m per texel for a 15 km-wide world.
## Bilinear sampling on the GPU smooths the texel grid; the underlying
## `shore_shelter` field has a 300 m falloff so 30 m resolution is plenty.
const BAKE_RESOLUTION : int = 512

## Padding around the island bounding box when sizing the baked texture so
## camera positions just outside still get a meaningful shelter value.
const BAKE_PADDING_M : float = 800.0

# ── Cached island disks ───────────────────────────────────────────────────────
static var _centers_xz : PackedVector2Array = PackedVector2Array()
static var _radii      : PackedFloat32Array = PackedFloat32Array()
static var _initialized: bool = false

# ── Baked shelter texture (CPU-baked, GPU-sampled) ────────────────────────────
static var _baked_shelter_texture: ImageTexture = null
## World-space (x, z) of the texel-(0, 0) lower-left corner.
static var _baked_world_origin   : Vector2 = Vector2.ZERO
## World-space extent (square) covered by the texture, in metres.
static var _baked_world_size     : float   = 0.0


## Seed the field. Each entry must be a Dictionary with:
##   "center": Vector3   — world-space island centre
##   "radius": float     — nominal island half-width (we add a padding margin)
static func initialize(islands: Array) -> void:
	_centers_xz.clear()
	_radii.clear()
	for island in islands:
		var center : Vector3 = island.get("center", Vector3.ZERO)
		var radius : float   = float(island.get("radius", 0.0)) + ISLAND_RADIUS_PADDING_M
		if radius <= 0.0:
			continue
		_centers_xz.append(Vector2(center.x, center.z))
		_radii.append(radius)
	_initialized = true
	_bake_shelter_texture()


static func is_initialized() -> bool:
	return _initialized


## Signed distance (metres) from `world_pos` to the nearest island shore.
## Positive in open water, negative inside land. Returns +INF before init.
static func distance_to_land(world_pos: Vector3) -> float:
	if not _initialized or _centers_xz.is_empty():
		return INF
	var pos2 := Vector2(world_pos.x, world_pos.z)
	var best := INF
	for i in range(_centers_xz.size()):
		var d := sqrt(pos2.distance_squared_to(_centers_xz[i])) - _radii[i]
		if d < best:
			best = d
	return best


## 0..1 shelter factor. 0 = on land / right at the shore, 1 = fully open water.
## Smooth transition over `SHELTER_FALLOFF_M` from the shore outwards.
## Returns 1.0 before init so systems behave like "open ocean" until ready.
##
## Fast path: in the common case (boat far from all islands) we skip the
## `sqrt` per island and short-circuit to 1.0. With ~35 islands sampled
## ~20× per physics frame, that's a big saving when sailing the open sea.
static func shore_shelter(world_pos: Vector3) -> float:
	if not _initialized or _centers_xz.is_empty():
		return 1.0
	var pos2 := Vector2(world_pos.x, world_pos.z)
	var best : float = INF
	for i in range(_centers_xz.size()):
		var r := _radii[i]
		var threshold := SHELTER_FALLOFF_M + r
		var d2 := pos2.distance_squared_to(_centers_xz[i])
		if d2 > threshold * threshold:
			continue  # this island is fully open-water (shelter=1) from here
		var d := sqrt(d2) - r
		if d < best:
			best = d
			if best <= 0.0:
				return 0.0  # on or inside land — no other island can win
	if best == INF:
		return 1.0
	return smoothstep(0.0, SHELTER_FALLOFF_M, best)


## How "close to shore" we are, in 0..1 — inverse of `shore_shelter`. Handy
## for systems that want a "near land" signal (tracker lerp speed, ambient
## bird SFX volume, etc).
static func shore_proximity(world_pos: Vector3) -> float:
	return 1.0 - shore_shelter(world_pos)


# ── Debug ─────────────────────────────────────────────────────────────────────

static func get_island_count() -> int:
	return _centers_xz.size()


## Returns Array[Dictionary] of `{center: Vector2, radius: float}` — used by
## the map overlay so harbours visibly read as shelter zones, not as the old
## hard-coded PORT_CALM circles.
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


## Bake `shore_shelter` over a square world region into an R32F texture the
## ocean vertex shader can sample once per vertex. Replaces the per-vertex
## land_disks loop: with 35 islands × 68k verts that was ~2.4M distance() ops
## per frame. Texture sample is O(1).
##
## Bake cost is paid once at world init — ~262k shore_shelter() calls. With
## the early-out in shore_shelter the typical cost is ~50-150 ms on a
## modern CPU. The world is loading anyway; one extra hitch is invisible.
static func _bake_shelter_texture() -> void:
	if _centers_xz.is_empty():
		_baked_shelter_texture = null
		_baked_world_size = 0.0
		return

	# Bounding box of all island shore-influence zones (radius + falloff).
	var min_x :=  INF
	var min_z :=  INF
	var max_x := -INF
	var max_z := -INF
	for i in range(_centers_xz.size()):
		var c := _centers_xz[i]
		var influence := _radii[i] + SHELTER_FALLOFF_M
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
			var shelter := shore_shelter(Vector3(wx, 0.0, wz))
			bytes.encode_float((j * BAKE_RESOLUTION + i) * 4, shelter)

	var img := Image.create_from_data(BAKE_RESOLUTION, BAKE_RESOLUTION,
									   false, Image.FORMAT_RF, bytes)
	_baked_shelter_texture = ImageTexture.create_from_image(img)
