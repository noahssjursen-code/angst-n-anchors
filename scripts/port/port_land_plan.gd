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

## Flat apron band between dock face and inland village — small service props only.
const APRON_KIND_LAMP := "lamp_post"
const APRON_KIND_CRATES := "crate_stack"
const APRON_KIND_PALLETS := "pallet_row"
const APRON_KIND_DRUMS := "drum_pair"
const APRON_KIND_HOSE := "hose_reel"
const APRON_KIND_BOLLARD := "bollard"
const APRON_KIND_SIGN := "sign_post"
const APRON_KIND_HATCH := "hatch_cover"

const APRON_DECOR_STEP_M := 20.0
const APRON_DECOR_EDGE_PAD_M := 14.0
const APRON_DECOR_INLAND_MIN_M := 12.0
const APRON_DECOR_INLAND_MAX_FRAC := 0.50
const APRON_STATION_ARC_CLEAR_M := 10.0
const APRON_QUAY_RADIUS_CLEAR_M := 16.0
const APRON_DECOR_MIN_SPACING_M := 9.0

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
		berth_plan: Dictionary,
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
			"apron_decor": {"points": [], "point_count": 0},
			"apron_pads": {"pads": [], "pad_count": 0},
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
	var apron_decor := _build_apron_decor(foundation, berth_plan, profile, size, site_seed)
	var apron_pads := _build_apron_pads(foundation, berth_plan, profile, size, site_seed)

	var house_n := 0
	var trade_n := 0
	for raw in terrain_grid.get("points", []) as Array:
		match str((raw as Dictionary).get("kind", KIND_HOUSE)):
			KIND_TRADE:
				trade_n += 1
			_:
				house_n += 1
	var apron_n := int(apron_decor.get("point_count", 0))
	var pad_n := int(apron_pads.get("pad_count", 0))
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
		"apron decor  %d props on grey pavement (berth keep-clear respected)" % apron_n,
		"apron pads  %d brick templates on %d host cells (%.0f m uniform clipped)" % [
			pad_n,
			int(apron_pads.get("host_count", 0)),
			PortApronPadCatalog.CELL_M,
		],
	])
	return {
		"buildable_zone": zone,
		"terrain_grid": terrain_grid,
		"apron_decor": apron_decor,
		"apron_pads": apron_pads,
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


## Brick-pad footprints on the uniform clipped apron host grid.
static func _build_apron_pads(
		foundation: Dictionary,
		berth_plan: Dictionary,
		profile: PortTradeProfile,
		_size: int,
		site_seed: int,
) -> Dictionary:
	var grid := PortApronPadCatalog.build_host_grid(foundation, berth_plan)
	var host_count := int(grid.get("host_count", 0))
	if host_count < 1:
		return {
			"pads": [],
			"pad_count": 0,
			"cell_m": PortApronPadCatalog.CELL_M,
			"host_count": 0,
			"grid": grid,
		}

	var pads: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0xA55EED01
	var jobs := PortApronPadCatalog.placement_jobs(profile)
	_annotate_jobs_with_preferred_i(jobs, berth_plan, grid)
	_place_pads_on_host_grid(pads, jobs, grid, rng)

	return {
		"pads": pads,
		"pad_count": pads.size(),
		"cell_m": float(grid.get("cell_m", PortApronPadCatalog.CELL_M)),
		"along_count": int(grid.get("along_count", 0)),
		"inland_count": int(grid.get("inland_count", 0)),
		"host_count": host_count,
		"grid": {
			"origin": grid.get("origin", [0.0, 0.0]),
			"along_dir": grid.get("along_dir", [1.0, 0.0]),
			"inland_dir": grid.get("inland_dir", [0.0, 1.0]),
			"cell_m": grid.get("cell_m", PortApronPadCatalog.CELL_M),
			"along_count": grid.get("along_count", 0),
			"inland_count": grid.get("inland_count", 0),
			"host_count": host_count,
			"host_j_min": grid.get("host_j_min", 0),
			"host_j_max": grid.get("host_j_max", 0),
			"polygon": grid.get("polygon", []),
		},
	}


## Project asphalt berth origins onto the uniform along-axis for trade preference.
static func _annotate_jobs_with_preferred_i(
		jobs: Array[Dictionary],
		berth_plan: Dictionary,
		grid: Dictionary,
) -> void:
	var origin := _xz2(grid.get("origin", [0.0, 0.0]))
	var along := _xz2(grid.get("along_dir", [1.0, 0.0])).normalized()
	var cell := float(grid.get("cell_m", PortApronPadCatalog.CELL_M))
	var stations: Array = berth_plan.get("asphalt_stations", []) as Array
	var used: Dictionary = {}
	for index in range(jobs.size()):
		var job: Dictionary = jobs[index]
		if not bool(job.get("prefer_berth", false)):
			continue
		var commodity_id := str(job.get("commodity_id", ""))
		var station: Dictionary = {}
		for si in range(stations.size()):
			if used.has(si):
				continue
			var cand: Dictionary = stations[si]
			if str(cand.get("commodity_id", "")) == commodity_id or commodity_id.is_empty():
				station = cand
				used[si] = true
				break
		if station.is_empty():
			continue
		var station_xz := _xz2(station.get("origin", [0.0, 0.0]))
		job["preferred_i"] = PortApronPadCatalog.project_to_cell_i(station_xz, origin, along, cell)
		jobs[index] = job


## Gap between pads inside a precinct (tight cluster).
const APRON_PAD_GAP_CELLS := 2
## Extra empty columns reserved between precinct centroids.
const APRON_PRECINCT_SEP_CELLS := 3
## Members of one precinct stay within this many columns of the precinct centre.
const APRON_PRECINCT_CLUSTER_RADIUS := 3


static func _place_pads_on_host_grid(
		pads: Array,
		jobs: Array[Dictionary],
		grid: Dictionary,
		rng: RandomNumberGenerator,
) -> void:
	var host_mask: Dictionary = grid.get("mask", {}) as Dictionary
	if jobs.is_empty() or host_mask.is_empty():
		return
	var along_count := int(grid.get("along_count", 0))
	var inland_count := int(grid.get("inland_count", 0))
	var host_j_min := int(grid.get("host_j_min", 0))
	var host_j_max := int(grid.get("host_j_max", 0))
	var occupied: Dictionary = {}

	## Required pads first (harbour office) — hard guarantee before decorative/trade.
	var soft_jobs: Array[Dictionary] = []
	for job in jobs:
		if bool(job.get("required", false)):
			_place_required_job(
				pads, job, host_mask, grid, along_count, inland_count,
				host_j_min, host_j_max, occupied,
			)
		else:
			soft_jobs.append(job)

	var precincts := _group_jobs_by_precinct(soft_jobs)
	var centroids := _assign_precinct_centroids(precincts, host_mask, along_count, inland_count)

	var precinct_order: Array[String] = []
	for key in precincts.keys():
		precinct_order.append(str(key))
	precinct_order.sort_custom(func(a: String, b: String) -> bool:
		return _precinct_sort_key(a) < _precinct_sort_key(b)
	)

	for precinct_id in precinct_order:
		var members: Array = precincts[precinct_id] as Array
		var centre_i := int(centroids.get(precinct_id, along_count >> 1))
		_place_precinct_cluster(
			pads, members, centre_i, host_mask, grid,
			along_count, inland_count, host_j_min, host_j_max, occupied, rng,
		)


## Harbour office etc. — try preferred size/zone, then any free host 1×1.
static func _place_required_job(
		pads: Array,
		job: Dictionary,
		host_mask: Dictionary,
		grid: Dictionary,
		along_count: int,
		inland_count: int,
		host_j_min: int,
		host_j_max: int,
		occupied: Dictionary,
) -> void:
	var mid_i := along_count >> 1
	if _place_job_with_fallbacks(
		pads, job, host_mask, grid, along_count, inland_count,
		host_j_min, host_j_max, occupied, mid_i,
	):
		return
	## Absolute last resort: first free host cell as 1×1 (ignore zone/gap).
	var try_job := job.duplicate(true)
	try_job["pad_template_id"] = "pad_1x1"
	for j in range(host_j_max, host_j_min - 1, -1):
		for i in range(along_count):
			var key := "%d,%d" % [i, j]
			if not host_mask.has(key) or occupied.has(key):
				continue
			occupied[key] = true
			pads.append(_make_apron_grid_pad(
				try_job, "pad_1x1", Vector2i(1, 1), i, j, grid, pads.size(),
			))
			return


static func _group_jobs_by_precinct(jobs: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for job in jobs:
		var pid := str(job.get("precinct", job.get("role", "misc")))
		if not out.has(pid):
			out[pid] = [] as Array
		(out[pid] as Array).append(job)
	return out


static func _precinct_sort_key(precinct_id: String) -> int:
	if precinct_id.begins_with("trade_"):
		return 0
	match precinct_id:
		"parking":
			return 1
		"storage":
			return 2
		"admin":
			return 3
		"marine_services":
			return 4
		_:
			return 5


static func _assign_precinct_centroids(
		precincts: Dictionary,
		host_mask: Dictionary,
		along_count: int,
		inland_count: int,
) -> Dictionary:
	var free_cols: Array[int] = []
	for i in range(along_count):
		var has := false
		for j in range(inland_count):
			if host_mask.has("%d,%d" % [i, j]):
				has = true
				break
		if has:
			free_cols.append(i)
	if free_cols.is_empty():
		return {}

	var trade_ids: Array[String] = []
	var other_ids: Array[String] = []
	for key in precincts.keys():
		var pid := str(key)
		if pid.begins_with("trade_"):
			trade_ids.append(pid)
		else:
			other_ids.append(pid)
	other_ids.sort()
	trade_ids.sort()

	var centroids: Dictionary = {}
	for pid in trade_ids:
		var members: Array = precincts[pid] as Array
		var pref := -1
		for raw in members:
			pref = int((raw as Dictionary).get("preferred_i", -1))
			if pref >= 0:
				break
		centroids[pid] = _nearest_free_col(pref, free_cols, along_count)

	var reserved: Array[int] = []
	for pid in trade_ids:
		reserved.append(int(centroids[pid]))
	var slots := _even_slots_avoiding(other_ids.size(), free_cols, reserved)
	for index in range(other_ids.size()):
		var slot_i := slots[index] if index < slots.size() else free_cols[free_cols.size() >> 1]
		centroids[other_ids[index]] = slot_i
	return centroids


static func _nearest_free_col(preferred_i: int, free_cols: Array[int], along_count: int) -> int:
	if free_cols.is_empty():
		return clampi(preferred_i, 0, maxi(along_count - 1, 0))
	if preferred_i < 0:
		return free_cols[free_cols.size() >> 1]
	var best := free_cols[0]
	var best_d := absi(best - preferred_i)
	for col in free_cols:
		var d := absi(col - preferred_i)
		if d < best_d:
			best = col
			best_d = d
	return best


static func _even_slots_avoiding(
		count: int,
		free_cols: Array[int],
		reserved: Array[int],
) -> Array[int]:
	var out: Array[int] = []
	if count <= 0 or free_cols.is_empty():
		return out
	var usable: Array[int] = []
	for col in free_cols:
		var near_trade := false
		for r in reserved:
			if absi(col - r) < APRON_PRECINCT_SEP_CELLS:
				near_trade = true
				break
		if not near_trade:
			usable.append(col)
	if usable.is_empty():
		usable = free_cols.duplicate()
	for k in range(count):
		var ideal_t := float(k + 1) / float(count + 1)
		var ideal_col := usable[clampi(
			int(round(ideal_t * float(usable.size() - 1))),
			0,
			usable.size() - 1,
		)]
		var best := usable[0]
		var best_score := -1.0
		for col in usable:
			if out.has(col):
				continue
			var min_d := _col_span(usable)
			for r in reserved:
				min_d = mini(min_d, absi(col - r))
			for p in out:
				min_d = mini(min_d, absi(col - p))
			var score := float(min_d) * 1000.0 - float(absi(col - ideal_col))
			if score > best_score:
				best_score = score
				best = col
		out.append(best)
	return out


static func _col_span(cols: Array[int]) -> int:
	if cols.is_empty():
		return 1
	return maxi(absi(cols[cols.size() - 1] - cols[0]), 1)


static func _place_precinct_cluster(
		pads: Array,
		members: Array,
		centre_i: int,
		host_mask: Dictionary,
		grid: Dictionary,
		along_count: int,
		inland_count: int,
		host_j_min: int,
		host_j_max: int,
		occupied: Dictionary,
		rng: RandomNumberGenerator,
) -> void:
	var offsets: Array[int] = [0, 2, -2, 4, -4, 6, -6]
	var offset_index := 0
	for raw in members:
		var job: Dictionary = raw
		var target_i := clampi(
			centre_i + offsets[offset_index % offsets.size()],
			0,
			maxi(along_count - 1, 0),
		)
		offset_index += 1
		if rng.randf() < 0.2:
			target_i = clampi(target_i + rng.randi_range(-1, 1), 0, maxi(along_count - 1, 0))
		if absi(target_i - centre_i) > APRON_PRECINCT_CLUSTER_RADIUS:
			target_i = clampi(
				centre_i + (1 if target_i > centre_i else -1) * APRON_PRECINCT_CLUSTER_RADIUS,
				0,
				maxi(along_count - 1, 0),
			)
		var placed := _place_job_with_fallbacks(
			pads, job, host_mask, grid, along_count, inland_count,
			host_j_min, host_j_max, occupied, target_i,
		)
		if not placed:
			var try_job := job.duplicate(true)
			try_job["pad_template_id"] = "pad_1x1"
			_place_job_on_host_cells(
				pads, try_job, host_mask, grid, along_count, inland_count,
				host_j_min, host_j_max, occupied, target_i, false,
			)


static func _place_job_with_fallbacks(
		pads: Array,
		job: Dictionary,
		host_mask: Dictionary,
		grid: Dictionary,
		along_count: int,
		inland_count: int,
		host_j_min: int,
		host_j_max: int,
		occupied: Dictionary,
		preferred_i: int,
) -> bool:
	if host_mask.is_empty():
		return false
	var preferred := str(job.get("pad_template_id", "pad_1x1"))
	for template_id in PortApronPadCatalog.template_fallbacks(preferred):
		var try_job := job.duplicate(true)
		try_job["pad_template_id"] = template_id
		if _place_job_on_host_cells(
			pads, try_job, host_mask, grid, along_count, inland_count,
			host_j_min, host_j_max, occupied, preferred_i, true,
		):
			return true
		if _place_job_on_host_cells(
			pads, try_job, host_mask, grid, along_count, inland_count,
			host_j_min, host_j_max, occupied, preferred_i, false,
		):
			return true
	return false


static func _place_job_on_host_cells(
		pads: Array,
		job: Dictionary,
		host_mask: Dictionary,
		grid: Dictionary,
		along_count: int,
		inland_count: int,
		host_j_min: int,
		host_j_max: int,
		occupied: Dictionary,
		preferred_i: int,
		use_gap: bool,
) -> bool:
	var template_id := str(job.get("pad_template_id", "pad_1x1"))
	var cells := PortApronPadCatalog.template_cells(template_id)
	var zone := str(job.get("zone", PortApronPadCatalog.ZONE_MID))
	var preferred_j := PortApronPadCatalog.preferred_j_for_zone(
		zone, host_j_min, host_j_max, cells.y,
	)
	var origins := _host_origins_for_size(
		host_mask, occupied, along_count, inland_count, cells.x, cells.y,
		preferred_i, preferred_j, host_j_min, host_j_max, use_gap,
	)
	if origins.is_empty():
		return false
	var pick: Vector2i = origins[0]
	_occupy_apron_rect_with_gap(
		occupied, pick.x, pick.y, cells.x, cells.y, along_count, inland_count, use_gap,
	)
	pads.append(_make_apron_grid_pad(job, template_id, cells, pick.x, pick.y, grid, pads.size()))
	return true


static func _host_origins_for_size(
		host_mask: Dictionary,
		occupied: Dictionary,
		along_count: int,
		inland_count: int,
		w: int,
		h: int,
		preferred_i: int,
		preferred_j: int,
		host_j_min: int,
		host_j_max: int,
		use_gap: bool,
) -> Array[Vector2i]:
	var origins: Array[Vector2i] = []
	for j0 in range(host_j_min, host_j_max + 1):
		if j0 + h - 1 > host_j_max:
			continue
		if j0 + h > inland_count:
			continue
		for i0 in range(along_count):
			if i0 + w > along_count:
				continue
			if not _rect_all_host_and_free(
				host_mask, occupied, i0, j0, w, h, along_count, inland_count, use_gap,
			):
				continue
			origins.append(Vector2i(i0, j0))
	if origins.is_empty():
		return origins
	var mid_i: int = along_count >> 1
	origins.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ja: int = absi(a.y - preferred_j)
		var jb: int = absi(b.y - preferred_j)
		if ja != jb:
			return ja < jb
		var da: int = absi(a.x - preferred_i) if preferred_i >= 0 else absi(a.x - mid_i)
		var db: int = absi(b.x - preferred_i) if preferred_i >= 0 else absi(b.x - mid_i)
		if da != db:
			return da < db
		return a.x < b.x
	)
	return origins


static func _rect_all_host_and_free(
		host_mask: Dictionary,
		occupied: Dictionary,
		i0: int,
		j0: int,
		w: int,
		h: int,
		along_count: int,
		inland_count: int,
		use_gap: bool,
) -> bool:
	for j in range(j0, j0 + h):
		for i in range(i0, i0 + w):
			var key := "%d,%d" % [i, j]
			if not host_mask.has(key):
				return false
			if occupied.has(key):
				return false
	if not use_gap:
		return true
	var gap := APRON_PAD_GAP_CELLS
	var i_lo := maxi(i0 - gap, 0)
	var i_hi := mini(i0 + w + gap, along_count)
	var j_lo := maxi(j0 - gap, 0)
	var j_hi := mini(j0 + h + gap, inland_count)
	for j in range(j_lo, j_hi):
		for i in range(i_lo, i_hi):
			if i >= i0 and i < i0 + w and j >= j0 and j < j0 + h:
				continue
			if occupied.has("%d,%d" % [i, j]):
				return false
	return true


static func _occupy_apron_rect_with_gap(
		occupied: Dictionary,
		i0: int,
		j0: int,
		w: int,
		h: int,
		along_count: int,
		inland_count: int,
		use_gap: bool = true,
) -> void:
	var gap := APRON_PAD_GAP_CELLS if use_gap else 0
	var i_lo := maxi(i0 - gap, 0)
	var i_hi := mini(i0 + w + gap, along_count)
	var j_lo := maxi(j0 - gap, 0)
	var j_hi := mini(j0 + h + gap, inland_count)
	for j in range(j_lo, j_hi):
		for i in range(i_lo, i_hi):
			occupied["%d,%d" % [i, j]] = true


static func _make_apron_grid_pad(
		job: Dictionary,
		template_id: String,
		cells: Vector2i,
		i0: int,
		j0: int,
		grid: Dictionary,
		index: int,
) -> Dictionary:
	var cell := float(grid.get("cell_m", PortApronPadCatalog.CELL_M))
	var origin := _xz2(grid.get("origin", [0.0, 0.0]))
	var along := _xz2(grid.get("along_dir", [1.0, 0.0])).normalized()
	var inland := _xz2(grid.get("inland_dir", [0.0, 1.0])).normalized()
	if along.length_squared() < 0.01:
		along = CoastTracer.PORT_LOCAL_ALONGSHORE_DIR
	if inland.length_squared() < 0.01:
		inland = CoastTracer.PORT_LOCAL_INLAND_DIR
	var centre := origin \
			+ along * ((float(i0) + float(cells.x) * 0.5) * cell) \
			+ inland * ((float(j0) + float(cells.y) * 0.5) * cell)
	var yaw_deg := rad_to_deg(atan2(along.y, along.x))
	var size_m := PortApronPadCatalog.size_m(template_id)
	return {
		"id": "pad_%s_%d" % [str(job.get("role", "pad")), index],
		"role": str(job.get("role", "")),
		"pad_template_id": template_id,
		"commodity_id": str(job.get("commodity_id", "")),
		"kind": str(job.get("kind", "universal")),
		"zone": str(job.get("zone", PortApronPadCatalog.ZONE_MID)),
		"cells": [cells.x, cells.y],
		"size_m": [size_m.x, size_m.y],
		"grid_ij": [i0, j0],
		"origin": [centre.x, centre.y],
		"yaw_deg": yaw_deg,
		"along_dir": [along.x, along.y],
		"inland_dir": [inland.x, inland.y],
	}


static func _xz2(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw
	if raw is Array:
		var arr: Array = raw
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO


## Seeded service props on the flat grey apron — inland of the dock face, clear of
## quay roots and asphalt berth arcs. Stamped at foundation crown height, not terrain.
static func _build_apron_decor(
		foundation: Dictionary,
		berth_plan: Dictionary,
		profile: PortTradeProfile,
		size: int,
		site_seed: int,
) -> Dictionary:
	var dock_face := _polyline_from_array(foundation.get("dock_face_polyline", []) as Array)
	if dock_face.size() < 2:
		dock_face = _polyline_from_array(foundation.get("spine", []) as Array)
	if dock_face.size() < 2:
		return {"points": [], "point_count": 0}

	var town_inland := float(foundation.get("town_inland_m", CoastTracer.FOUNDATION_TOWN_INLAND_M))
	var inland_dir := CoastTracer.PORT_LOCAL_INLAND_DIR
	var inland_max := maxf(
		town_inland * APRON_DECOR_INLAND_MAX_FRAC,
		APRON_DECOR_INLAND_MIN_M + 10.0,
	)
	var arc_lengths := CoastTracer.path_arc_lengths(dock_face)
	var total_arc := float(arc_lengths[arc_lengths.size() - 1]) if not arc_lengths.is_empty() else 0.0
	if total_arc < APRON_DECOR_EDGE_PAD_M * 2.0 + APRON_DECOR_STEP_M:
		return {"points": [], "point_count": 0}

	var blocked := _apron_blocked_arcs(dock_face, berth_plan, size)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0xA70A40A1
	var points: Array = []
	var placed_centres: Array[Vector2] = []
	var arc := APRON_DECOR_EDGE_PAD_M + rng.randf_range(0.0, 6.0)
	while arc < total_arc - APRON_DECOR_EDGE_PAD_M:
		if _arc_in_blocked(blocked, arc):
			arc += APRON_DECOR_STEP_M * 0.45
			continue
		var sample := CoastTracer.point_at_arc_s(dock_face, arc_lengths, arc)
		var face_pos: Vector2 = sample.get("position", Vector2.ZERO)
		if _near_quay_station(face_pos, berth_plan):
			arc += APRON_DECOR_STEP_M
			continue
		var tangent_yaw := float(sample.get("tangent_yaw_deg", 0.0))
		var kind := _pick_apron_kind(rng, profile)
		var inland_dist := lerpf(APRON_DECOR_INLAND_MIN_M, inland_max, rng.randf())
		match kind:
			APRON_KIND_LAMP:
				inland_dist = town_inland * 0.30 + rng.randf_range(-3.0, 3.0)
			APRON_KIND_HATCH:
				inland_dist = town_inland * 0.24 + rng.randf_range(-2.0, 2.0)
			APRON_KIND_SIGN:
				inland_dist = town_inland * 0.38 + rng.randf_range(-4.0, 4.0)
		inland_dist = clampf(inland_dist, APRON_DECOR_INLAND_MIN_M, inland_max)
		var local_pos := face_pos + inland_dir * inland_dist
		var too_close := false
		for other in placed_centres:
			if local_pos.distance_to(other) < APRON_DECOR_MIN_SPACING_M:
				too_close = true
				break
		if too_close:
			arc += APRON_DECOR_STEP_M * 0.55
			continue
		var family := _pick_apron_family(rng, profile)
		points.append({
			"kind": kind,
			"local": [local_pos.x, local_pos.y],
			"yaw_deg": tangent_yaw + rng.randf_range(-14.0, 14.0),
			"family": family,
		})
		placed_centres.append(local_pos)
		arc += APRON_DECOR_STEP_M + rng.randf_range(-4.0, 4.0)

	return {"points": points, "point_count": points.size()}


static func _pick_apron_kind(rng: RandomNumberGenerator, profile: PortTradeProfile) -> String:
	var weights := {
		APRON_KIND_LAMP: 22,
		APRON_KIND_CRATES: 18,
		APRON_KIND_PALLETS: 14,
		APRON_KIND_DRUMS: 12,
		APRON_KIND_HOSE: 8,
		APRON_KIND_BOLLARD: 8,
		APRON_KIND_SIGN: 10,
		APRON_KIND_HATCH: 8,
	}
	if profile != null:
		for commodity_id in profile.export_slots:
			_boost_apron_weights(weights, str(commodity_id))
		for commodity_id in profile.import_slots:
			_boost_apron_weights(weights, str(commodity_id))
	var total := 0
	for key in weights:
		total += int(weights[key])
	if total <= 0:
		return APRON_KIND_CRATES
	var roll := rng.randi_range(0, total - 1)
	var cursor := 0
	for key in weights:
		cursor += int(weights[key])
		if roll < cursor:
			return str(key)
	return APRON_KIND_CRATES


static func _boost_apron_weights(weights: Dictionary, commodity_id: String) -> void:
	if commodity_id.is_empty():
		return
	match CommodityCatalog.commodity_terminal_family(commodity_id):
		"bulk":
			weights[APRON_KIND_PALLETS] = int(weights.get(APRON_KIND_PALLETS, 0)) + 6
			weights[APRON_KIND_CRATES] = int(weights.get(APRON_KIND_CRATES, 0)) + 4
		"liquid":
			weights[APRON_KIND_DRUMS] = int(weights.get(APRON_KIND_DRUMS, 0)) + 8
			weights[APRON_KIND_HOSE] = int(weights.get(APRON_KIND_HOSE, 0)) + 6
		"container":
			weights[APRON_KIND_PALLETS] = int(weights.get(APRON_KIND_PALLETS, 0)) + 5
			weights[APRON_KIND_CRATES] = int(weights.get(APRON_KIND_CRATES, 0)) + 3
		"fish":
			weights[APRON_KIND_CRATES] = int(weights.get(APRON_KIND_CRATES, 0)) + 5
			weights[APRON_KIND_HOSE] = int(weights.get(APRON_KIND_HOSE, 0)) + 3
		"timber":
			weights[APRON_KIND_PALLETS] = int(weights.get(APRON_KIND_PALLETS, 0)) + 4
			weights[APRON_KIND_CRATES] = int(weights.get(APRON_KIND_CRATES, 0)) + 4
		"ore":
			weights[APRON_KIND_DRUMS] = int(weights.get(APRON_KIND_DRUMS, 0)) + 3
			weights[APRON_KIND_BOLLARD] = int(weights.get(APRON_KIND_BOLLARD, 0)) + 4
		_:
			weights[APRON_KIND_CRATES] = int(weights.get(APRON_KIND_CRATES, 0)) + 2


static func _pick_apron_family(rng: RandomNumberGenerator, profile: PortTradeProfile) -> String:
	if profile == null:
		return "general"
	var pool: Array[String] = []
	for commodity_id in profile.export_slots:
		var id := str(commodity_id)
		if not id.is_empty():
			pool.append(CommodityCatalog.commodity_terminal_family(id))
	for commodity_id in profile.import_slots:
		var id := str(commodity_id)
		if not id.is_empty():
			pool.append(CommodityCatalog.commodity_terminal_family(id))
	if pool.is_empty():
		return "general"
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _apron_blocked_arcs(
		dock_face: PackedVector2Array,
		berth_plan: Dictionary,
		size: int,
) -> Array:
	var blocked: Array = []
	var loading_clear := PortSizing.asphalt_quay_loading_clearance_m(size)
	for raw in berth_plan.get("quay_stations", []) as Array:
		var station: Dictionary = raw
		var origin := Vector2(
			float((station.get("origin", [0.0, 0.0]) as Array)[0]),
			float((station.get("origin", [0.0, 0.0]) as Array)[1]),
		)
		var root_arc := _nearest_arc_on_polyline(dock_face, origin)
		var half_w := float(station.get("width_m", PortSizing.quay_deck_width_m(size))) * 0.5
		blocked.append({
			"lo": root_arc - half_w - loading_clear,
			"hi": root_arc + half_w + loading_clear,
		})
	for raw in berth_plan.get("asphalt_stations", []) as Array:
		var station: Dictionary = raw
		var arc_m := float(station.get("arc_m", 0.0))
		var half_len := float(station.get("length_m", 0.0)) * 0.5
		blocked.append({
			"lo": arc_m - half_len - APRON_STATION_ARC_CLEAR_M,
			"hi": arc_m + half_len + APRON_STATION_ARC_CLEAR_M,
		})
	return _merge_arc_intervals(blocked)


static func _near_quay_station(face_pos: Vector2, berth_plan: Dictionary) -> bool:
	for raw in berth_plan.get("quay_stations", []) as Array:
		var station: Dictionary = raw
		var origin := Vector2(
			float((station.get("origin", [0.0, 0.0]) as Array)[0]),
			float((station.get("origin", [0.0, 0.0]) as Array)[1]),
		)
		var radius := float(station.get("width_m", 24.0)) * 0.5 + APRON_QUAY_RADIUS_CLEAR_M
		if face_pos.distance_to(origin) < radius:
			return true
	return false


static func _arc_in_blocked(blocked: Array, arc_s: float) -> bool:
	for raw in blocked:
		var interval: Dictionary = raw
		if arc_s >= float(interval.get("lo", 0.0)) - 0.5 \
				and arc_s <= float(interval.get("hi", 0.0)) + 0.5:
			return true
	return false


static func _merge_arc_intervals(intervals: Array) -> Array:
	var sorted: Array = intervals.duplicate(true)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("lo", 0.0)) < float(b.get("lo", 0.0))
	)
	var merged: Array = []
	for raw in sorted:
		var nxt: Dictionary = raw
		if merged.is_empty():
			merged.append(nxt)
			continue
		var cur: Dictionary = merged[merged.size() - 1]
		if float(nxt.get("lo", 0.0)) <= float(cur.get("hi", 0.0)) + 1.0:
			cur["hi"] = maxf(float(cur.get("hi", 0.0)), float(nxt.get("hi", 0.0)))
			merged[merged.size() - 1] = cur
		else:
			merged.append(nxt)
	return merged


static func _nearest_arc_on_polyline(path: PackedVector2Array, point: Vector2) -> float:
	if path.size() < 2:
		return 0.0
	var best_arc := 0.0
	var best_dist := INF
	var arc := 0.0
	for index in range(path.size() - 1):
		var a := path[index]
		var b := path[index + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0 if len_sq < 0.0001 else clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
		var closest := a + ab * t
		var dist := closest.distance_squared_to(point)
		if dist < best_dist:
			best_dist = dist
			best_arc = arc + ab.length() * t
		arc += ab.length()
	return best_arc


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
