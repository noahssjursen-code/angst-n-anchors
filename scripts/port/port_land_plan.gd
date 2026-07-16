class_name PortLandPlan
extends RefCounted

## Inland buildable land for port decoration / settlement.
## Trapezoid volume + terrain stake grid:
##   - house stakes (primitive cottages) on dry land past the beach band
##   - larger trade-decoration stakes sprinkled among houses, coloured by
##     import/export terminal family (mills, markets, yards — later)

const CoastTracer := preload("res://scripts/port/port_coast_tracer.gd")
const TerrainStreamer := preload("res://scripts/world/world_terrain_streamer.gd")

## How far inland past the town concrete the buildable volume reaches (hills).
## Intentionally larger than the coast-scan box — settlement sits behind the apron.
const HINTERLAND_EXTRA_M := 420.0
## Inland edge width as a multiple of dock-face span (inverse trapezoid bloom).
const INLAND_BLOOM_FACTOR := 1.9
## Extra metres added on top of the bloom factor so small ports still fan out.
const INLAND_BLOOM_EXTRA_M := 140.0
## Volume height at the dock face (m above apron surface).
const ZONE_HEIGHT_SEAWARD_M := 12.0
## Volume height at the inland edge — tall enough to clear nearby hills.
const ZONE_HEIGHT_INLAND_M := 110.0
## Spacing between grid stakes along the trapezoid UV (metres).
const GRID_STEP_M := 52.0
## Must sit this far inland of the coastline (negative SDF magnitude).
const BEACH_SETBACK_M := 18.0
## Terrain surface must clear the ocean by at least this much (no beach shelves).
const MIN_HEIGHT_ABOVE_WATER_M := 1.5

const KIND_HOUSE := "house"
const KIND_TRADE := "trade_decoration"

const HOUSE_RADIUS_M := 3.6
## Trade yards / mills cover a wider footprint than a single house plot.
const TRADE_RADIUS_M := 16.0
## Clear house stakes under a trade footprint so colours stay readable.
const TRADE_HOUSE_CLEAR_M := 22.0
## Minimum centre-to-centre spacing between trade decorations.
const TRADE_MIN_SPACING_M := 70.0
## Inflate the town trapezoid when clearing forest around the village.
const FOREST_CLEAR_PAD_M := 18.0
## Keep village decoration on the harbour-facing band of the buildable zone.
const HOUSE_MAX_INLAND_V := 0.55


static func build(
		profile: PortTradeProfile,
		size: int,
		foundation: Dictionary,
		_berth_plan: Dictionary,
		site_seed: int,
		_port_area: Dictionary = {},
		world_layout: WorldLayout = null,
		world_position: Vector3 = Vector3.ZERO,
		rotation_y: float = 0.0,
) -> Dictionary:
	var n := PortSizing.normalized_size(size)
	var dock_face := _polyline_from_array(foundation.get("dock_face_polyline", []) as Array)
	if dock_face.size() < 2:
		dock_face = _polyline_from_array(foundation.get("spine", []) as Array)
	if dock_face.size() < 2:
		return {
			"buildable_zone": {},
			"terrain_grid": {},
			"structures": [],
			"notes": PackedStringArray(["no dock face for land zone"]),
		}

	var town_inland := float(foundation.get("town_inland_m", CoastTracer.FOUNDATION_TOWN_INLAND_M))
	## Apron + hinterland — do not clamp to port_area half-depth; hills sit further back.
	var size_boost := lerpf(0.0, 120.0, float(n) / float(PortSizing.MAX_SIZE))
	var inland_depth := town_inland + HINTERLAND_EXTRA_M + size_boost

	## Inverse trapezoid: dock-face width at the apron, bloom wider into the hills.
	var sea_a := dock_face[0]
	var sea_b := dock_face[dock_face.size() - 1]
	var mid_sea := (sea_a + sea_b) * 0.5
	var along := (sea_b - sea_a)
	var along_span_sea := maxf(along.length(), _polyline_length_m(dock_face))
	var along_dir := along.normalized() if along.length_squared() > 0.01 else CoastTracer.PORT_LOCAL_ALONGSHORE_DIR
	var inland_dir := CoastTracer.PORT_LOCAL_INLAND_DIR
	var mid_in := mid_sea + inland_dir * inland_depth
	var along_span_in := maxf(
		along_span_sea * INLAND_BLOOM_FACTOR,
		along_span_sea + INLAND_BLOOM_EXTRA_M,
	)
	var half_sea := along_span_sea * 0.5
	var half_in := along_span_in * 0.5
	## corners: 0 sea-left, 1 sea-right, 2 inland-right, 3 inland-left
	var corners := PackedVector2Array([
		mid_sea - along_dir * half_sea,
		mid_sea + along_dir * half_sea,
		mid_in + along_dir * half_in,
		mid_in - along_dir * half_in,
	])
	var seaward_edge := PackedVector2Array([corners[0], corners[1]])
	var inland_edge := PackedVector2Array([corners[3], corners[2]])
	var polygon := PackedVector2Array([corners[0], corners[1], corners[2], corners[3]])
	var center := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25

	var zone := {
		"seaward_edge": _polyline_to_array(seaward_edge),
		"inland_edge": _polyline_to_array(inland_edge),
		"polygon": _polyline_to_array(polygon),
		"corners": _polyline_to_array(corners),
		"origin": [mid_sea.x, mid_sea.y],
		"along_dir": [along_dir.x, along_dir.y],
		"inland_dir": [inland_dir.x, inland_dir.y],
		"inland_depth_m": inland_depth,
		"along_span_m": along_span_sea,
		"along_span_seaward_m": along_span_sea,
		"along_span_inland_m": along_span_in,
		"town_inland_m": town_inland,
		"height_seaward_m": ZONE_HEIGHT_SEAWARD_M,
		"height_inland_m": ZONE_HEIGHT_INLAND_M,
		"center": [center.x, center.y],
	}
	var terrain_grid := _build_terrain_grid(
		corners,
		along_span_sea,
		along_span_in,
		inland_depth,
		world_layout,
		world_position,
		rotation_y,
	)
	_sprinkle_trade_decorations(terrain_grid, profile, n, site_seed)

	var house_n := 0
	var trade_n := 0
	for raw in terrain_grid.get("points", []) as Array:
		match str((raw as Dictionary).get("kind", KIND_HOUSE)):
			KIND_TRADE:
				trade_n += 1
			_:
				house_n += 1
	var notes: PackedStringArray = PackedStringArray([
		"buildable land trapezoid  %.0f→%.0f m wide × %.0f m inland · height %.0f→%.0f m" % [
			along_span_sea,
			along_span_in,
			inland_depth,
			ZONE_HEIGHT_SEAWARD_M,
			ZONE_HEIGHT_INLAND_M,
		],
		"land stakes  %d house · %d trade · %d rejected (ocean/beach/ledge)" % [
			house_n,
			trade_n,
			int(terrain_grid.get("rejected_count", 0)),
		],
	])
	return {
		"buildable_zone": zone,
		"terrain_grid": terrain_grid,
		"structures": [],
		"structure_count": 0,
		"notes": notes,
	}


## UV grid over the trapezoid. Each kept corner is a house stake on buildable land.
## One-row ledge margin: if the seaward neighbour cell failed terrain checks,
## skip this cell too so stakes do not sit on the first lip above the beach.
static func _build_terrain_grid(
		corners: PackedVector2Array,
		span_sea: float,
		span_in: float,
		depth_m: float,
		world_layout: WorldLayout,
		world_position: Vector3,
		rotation_y: float,
) -> Dictionary:
	var step := GRID_STEP_M
	var u_count := maxi(2, int(ceil(maxf(span_sea, span_in) / step)) + 1)
	var v_count := maxi(2, int(ceil(depth_m / step)) + 1)
	var port_basis := Basis(Vector3.UP, rotation_y)
	var min_abs_surface_y := WaveSurface.WATER_LEVEL + MIN_HEIGHT_ABOVE_WATER_M

	## Pass 1 — terrain / beach fitness per cell (row-major: vi * u_count + ui).
	var terrain_ok: Array[bool] = []
	terrain_ok.resize(u_count * v_count)
	var local_xz_cache: Array[Vector2] = []
	local_xz_cache.resize(u_count * v_count)
	var rejected_terrain := 0
	for vi in range(v_count):
		var v := float(vi) / float(v_count - 1)
		for ui in range(u_count):
			var u := float(ui) / float(u_count - 1)
			var local_xz := _trapezoid_point(corners, u, v)
			var idx := vi * u_count + ui
			local_xz_cache[idx] = local_xz
			var ok := _is_buildable_stake(
				world_layout,
				world_position,
				port_basis,
				local_xz,
				min_abs_surface_y,
			)
			terrain_ok[idx] = ok
			if not ok:
				rejected_terrain += 1

	## Pass 2 — place on dry cells inside the harbour-facing band.
	## One-row ledge margin: skip a cell whose seaward neighbour failed, so the
	## first lip above beach/ocean is empty — but do not cascade forever.
	var points: Array = []
	var rejected_ledge := 0
	var rejected_far := 0
	for vi in range(v_count):
		var v := float(vi) / float(v_count - 1)
		for ui in range(u_count):
			var idx := vi * u_count + ui
			if not terrain_ok[idx]:
				continue
			if v > HOUSE_MAX_INLAND_V:
				rejected_far += 1
				continue
			if vi > 0 and not terrain_ok[(vi - 1) * u_count + ui]:
				rejected_ledge += 1
				continue
			points.append(_make_house_point(
				local_xz_cache[idx],
				float(ui) / float(u_count - 1),
				v,
				world_layout,
				world_position,
				port_basis,
			))

	## Steep / skinny coasts often wipe the grid. Fall back to any dry cell in
	## the harbour band (no ledge skip) so the village still stamps.
	if points.is_empty():
		for vi in range(v_count):
			var v := float(vi) / float(v_count - 1)
			if v > HOUSE_MAX_INLAND_V:
				continue
			for ui in range(u_count):
				var idx := vi * u_count + ui
				if not terrain_ok[idx]:
					continue
				points.append(_make_house_point(
					local_xz_cache[idx],
					float(ui) / float(u_count - 1),
					v,
					world_layout,
					world_position,
					port_basis,
				))
		rejected_ledge = 0

	return {
		"step_m": step,
		"u_count": u_count,
		"v_count": v_count,
		"points": points,
		"rejected_count": rejected_terrain + rejected_ledge + rejected_far,
		"rejected_terrain_count": rejected_terrain,
		"rejected_ledge_count": rejected_ledge,
		"rejected_far_count": rejected_far,
		"beach_setback_m": BEACH_SETBACK_M,
		"min_height_above_water_m": MIN_HEIGHT_ABOVE_WATER_M,
		"house_radius_m": HOUSE_RADIUS_M,
		"trade_radius_m": TRADE_RADIUS_M,
		"house_max_inland_v": HOUSE_MAX_INLAND_V,
	}


static func _make_house_point(
		local_xz: Vector2,
		u: float,
		v: float,
		world_layout: WorldLayout,
		world_position: Vector3,
		port_basis: Basis,
) -> Dictionary:
	return {
		"kind": KIND_HOUSE,
		"u": u,
		"v": v,
		"local": [local_xz.x, local_xz.y],
		"y": _sample_terrain_y(world_layout, world_position, port_basis, local_xz),
		"radius_m": HOUSE_RADIUS_M,
	}


## Promote a spaced subset of house stakes into larger trade decorations.
## One job per offered (role, commodity) from the live recipe — never invent the
## opposite direction (import fish ≠ export fish building).
static func _sprinkle_trade_decorations(
		grid: Dictionary,
		profile: PortTradeProfile,
		size: int,
		site_seed: int,
) -> void:
	var points: Array = grid.get("points", []) as Array
	if points.is_empty() or profile == null:
		return
	var jobs := _trade_decoration_jobs(profile)
	if jobs.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x7A1D5A7E
	## Prefer seaward / mid band for yards — still harbour-visible, not cliff-top.
	var candidates: Array[int] = []
	for index in range(points.size()):
		var entry: Dictionary = points[index]
		var v := float(entry.get("v", 0.0))
		if v < 0.12 or v > HOUSE_MAX_INLAND_V:
			continue
		candidates.append(index)
	if candidates.is_empty():
		for index in range(points.size()):
			candidates.append(index)
	## Shuffle candidates.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var placed_centres: Array[Vector2] = []
	var per_job := clampi(1 + size / 3, 1, 3)
	for job in jobs:
		var commodity_id := str(job.get("commodity_id", ""))
		var role := str(job.get("role", ""))
		if commodity_id.is_empty() or role.is_empty():
			continue
		var family := CommodityCatalog.commodity_terminal_family(commodity_id)
		var need := per_job
		for cand_i in candidates:
			if need <= 0:
				break
			var entry: Dictionary = points[cand_i]
			if str(entry.get("kind", "")) != KIND_HOUSE:
				continue
			var local_arr: Array = entry.get("local", [0.0, 0.0]) as Array
			if local_arr.size() < 2:
				continue
			var centre := Vector2(float(local_arr[0]), float(local_arr[1]))
			var ok := true
			for other in placed_centres:
				if centre.distance_to(other) < TRADE_MIN_SPACING_M:
					ok = false
					break
			if not ok:
				continue
			entry["kind"] = KIND_TRADE
			entry["commodity_id"] = commodity_id
			entry["family"] = family
			entry["radius_m"] = TRADE_RADIUS_M
			entry["role"] = role
			points[cand_i] = entry
			placed_centres.append(centre)
			need -= 1

	## Drop houses that sit under a trade footprint.
	if placed_centres.is_empty():
		return
	var kept: Array = []
	for raw in points:
		var entry: Dictionary = raw
		if str(entry.get("kind", "")) == KIND_TRADE:
			kept.append(entry)
			continue
		var local_arr: Array = entry.get("local", [0.0, 0.0]) as Array
		if local_arr.size() < 2:
			continue
		var centre := Vector2(float(local_arr[0]), float(local_arr[1]))
		var under_trade := false
		for trade_c in placed_centres:
			if centre.distance_to(trade_c) < TRADE_HOUSE_CLEAR_M:
				under_trade = true
				break
		if not under_trade:
			kept.append(entry)
	grid["points"] = kept


## Live unlocks only. Export and import are separate offers (containers share one yard).
static func _trade_decoration_jobs(profile: PortTradeProfile) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	var seen_bidirectional: Dictionary = {}
	for commodity_id in profile.export_slots:
		var id := str(commodity_id)
		if id.is_empty():
			continue
		if PortTradeProfile.is_bidirectional_trade(id):
			if seen_bidirectional.has(id):
				continue
			seen_bidirectional[id] = true
			jobs.append({"commodity_id": id, "role": "bidirectional"})
			continue
		jobs.append({"commodity_id": id, "role": "export"})
	for commodity_id in profile.import_slots:
		var id := str(commodity_id)
		if id.is_empty():
			continue
		if PortTradeProfile.is_bidirectional_trade(id):
			if seen_bidirectional.has(id):
				continue
			seen_bidirectional[id] = true
			jobs.append({"commodity_id": id, "role": "bidirectional"})
			continue
		## One-way imports only — never invent an export building for these.
		jobs.append({"commodity_id": id, "role": "import"})
	return jobs


static func _trapezoid_point(corners: PackedVector2Array, u: float, v: float) -> Vector2:
	## corners: 0 sea-left, 1 sea-right, 2 inland-right, 3 inland-left
	var sea := corners[0].lerp(corners[1], u)
	var inland := corners[3].lerp(corners[2], u)
	return sea.lerp(inland, v)


## Land only, inland of the beach band, and high enough above the ocean.
static func _is_buildable_stake(
		world_layout: WorldLayout,
		world_position: Vector3,
		port_basis: Basis,
		local_xz: Vector2,
		min_abs_surface_y: float,
) -> bool:
	if world_layout == null:
		## No layout in unit tests — keep the full UV lattice.
		return true
	var world := world_position + port_basis * Vector3(local_xz.x, 0.0, local_xz.y)
	var world_xz := Vector2(world.x, world.z)
	var signed := float(world_layout.sample_signed_distance(world_xz))
	## Positive SDF = water; need enough negative depth inland past the beach.
	if signed >= -BEACH_SETBACK_M:
		return false
	## Compare absolute terrain height to water — not port-local Y.
	var abs_y := TerrainStreamer.sample_terrain_height(world_layout, world_xz, [])
	if abs_y < min_abs_surface_y:
		return false
	return true


static func _sample_terrain_y(
		world_layout: WorldLayout,
		world_position: Vector3,
		port_basis: Basis,
		local_xz: Vector2,
) -> float:
	if world_layout == null:
		return float(CoastTracer.FOUNDATION_SURFACE_Y_M)
	var world := world_position + port_basis * Vector3(local_xz.x, 0.0, local_xz.y)
	## Natural streamed height only — no flatten/grade post-process.
	return TerrainStreamer.sample_terrain_height(
		world_layout,
		Vector2(world.x, world.z),
		[],
	) - world_position.y


static func _polyline_from_array(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in raw:
		var arr := point as Array
		if arr.size() >= 2:
			out.append(Vector2(float(arr[0]), float(arr[1])))
	return out


static func _polyline_to_array(path: PackedVector2Array) -> Array:
	var out: Array = []
	for point in path:
		out.append([point.x, point.y])
	return out


static func _polyline_length_m(path: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(path.size() - 1):
		total += path[index].distance_to(path[index + 1])
	return total


## Transform buildable_zone local polygon to world XZ and inflate for tree clear.
static func world_buildable_polygon(
		zone: Dictionary,
		world_position: Vector3,
		rotation_y: float,
		pad_m: float = FOREST_CLEAR_PAD_M,
) -> PackedVector2Array:
	var local := _polyline_from_array(zone.get("polygon", []) as Array)
	if local.size() < 3:
		local = _polyline_from_array(zone.get("corners", []) as Array)
	if local.size() < 3:
		return PackedVector2Array()
	var port_basis := Basis(Vector3.UP, rotation_y)
	var world := PackedVector2Array()
	var center := Vector2.ZERO
	for point in local:
		var wp := world_position + port_basis * Vector3(point.x, 0.0, point.y)
		var xz := Vector2(wp.x, wp.z)
		world.append(xz)
		center += xz
	center /= float(world.size())
	if pad_m <= 0.01:
		return world
	var inflated := PackedVector2Array()
	for point in world:
		var delta := point - center
		var length := delta.length()
		if length < 0.01:
			inflated.append(point)
		else:
			inflated.append(center + delta * ((length + pad_m) / length))
	return inflated
