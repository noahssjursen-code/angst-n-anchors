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
## Performance: O(N_islands) per query. With < 5000 islands the boat-position
## tick is cheap; if we ever need denser sampling (e.g. per-vertex in a
## compute shader) we'll bake a 2D distance texture from these disks.

## Distance from shore at which waves recover to 100 %.
const SHELTER_FALLOFF_M : float = 300.0

## Extra padding around the visual island polygon — the polygon edge is noisy
## (see IslandMeshBuilder.build_polygon) so we treat the disk as slightly
## larger than the nominal half-width.
const ISLAND_RADIUS_PADDING_M : float = 25.0

# ── Cached island disks ───────────────────────────────────────────────────────
static var _centers_xz : PackedVector2Array = PackedVector2Array()
static var _radii      : PackedFloat32Array = PackedFloat32Array()
static var _initialized: bool = false


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
## per island — the exact layout the ocean shader's `land_disks[]` uniform
## expects. Truncated to `max_count` so we never exceed the shader's
## MAX_LAND_DISKS bound. A world with more islands than the shader can hold
## will simply fall back to the nearest `max_count` for shelter (Phase: bake
## a 2D SDF texture instead, once port count justifies it).
static func get_disks_packed(max_count: int) -> PackedVector4Array:
	var out := PackedVector4Array()
	var n := mini(_centers_xz.size(), max_count)
	out.resize(n)
	for i in range(n):
		var c := _centers_xz[i]
		out[i] = Vector4(c.x, c.y, _radii[i], 0.0)
	return out
