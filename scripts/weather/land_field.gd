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

# ── Cached island collision (OBB in world XZ; disk radius for fast shelter) ───
static var _centers_xz : PackedVector2Array = PackedVector2Array()
static var _radii      : PackedFloat32Array = PackedFloat32Array()
static var _obb_half_x : PackedFloat32Array = PackedFloat32Array()
static var _obb_half_z : PackedFloat32Array = PackedFloat32Array()
static var _obb_rot_y  : PackedFloat32Array = PackedFloat32Array()
static var _initialized: bool = false

# ── Baked shelter texture (CPU-baked, GPU-sampled) ────────────────────────────
static var _baked_shelter_texture: ImageTexture = null
## World-space (x, z) of the texel-(0, 0) lower-left corner.
static var _baked_world_origin   : Vector2 = Vector2.ZERO
## World-space extent (square) covered by the texture, in metres.
static var _baked_world_size     : float   = 0.0


## Seed the field. Each entry is a Dictionary with:
##   "center": Vector3 — port / island origin in world space
## Preferred (matches port island footprint):
##   "half_x", "half_z": float — local half-extents incl. organic margin (m)
##   "rotation_y": float — port plot yaw (radians)
## Legacy fallback:
##   "radius": float — circular island (deprecated; too small for routing)
static func initialize(islands: Array) -> void:
	_centers_xz.clear()
	_radii.clear()
	_obb_half_x.clear()
	_obb_half_z.clear()
	_obb_rot_y.clear()
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
