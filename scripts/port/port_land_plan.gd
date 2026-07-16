class_name PortLandPlan
extends RefCounted

## Inland buildable land for port decoration / settlement.
## v1: trapezoid volume (narrow apron → wide hills) plus a terrain-sampled
## stake grid. Stakes only land inland of the beach band and above sea level.

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
const BEACH_SETBACK_M := 32.0
## Terrain surface must clear the ocean by at least this much (no beach shelves).
const MIN_HEIGHT_ABOVE_WATER_M := 4.0


static func build(
		_profile: PortTradeProfile,
		size: int,
		foundation: Dictionary,
		_berth_plan: Dictionary,
		_site_seed: int,
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

	var terrain_grid := _build_terrain_grid(
		corners,
		along_span_sea,
		along_span_in,
		inland_depth,
		world_layout,
		world_position,
		rotation_y,
	)

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
	var notes: PackedStringArray = PackedStringArray([
		"buildable land trapezoid  %.0f→%.0f m wide × %.0f m inland · height %.0f→%.0f m" % [
			along_span_sea,
			along_span_in,
			inland_depth,
			ZONE_HEIGHT_SEAWARD_M,
			ZONE_HEIGHT_INLAND_M,
		],
		"terrain grid  %d stakes kept · %d rejected (ocean/beach) @ %.0f m" % [
			(terrain_grid.get("points", []) as Array).size(),
			int(terrain_grid.get("rejected_count", 0)),
			float(terrain_grid.get("step_m", GRID_STEP_M)),
		],
	])
	return {
		"buildable_zone": zone,
		"terrain_grid": terrain_grid,
		"structures": [],
		"structure_count": 0,
		"notes": notes,
	}


## UV grid over the trapezoid. Each kept corner is a stake on buildable land.
## Ocean, beach shelves, and too-low rock are dropped — no houses in the wet.
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
	var points: Array = []
	var rejected := 0
	var min_surface_y := WaveSurface.WATER_LEVEL + MIN_HEIGHT_ABOVE_WATER_M
	for vi in range(v_count):
		var v := float(vi) / float(v_count - 1)
		for ui in range(u_count):
			var u := float(ui) / float(u_count - 1)
			var local_xz := _trapezoid_point(corners, u, v)
			if not _is_buildable_stake(
					world_layout,
					world_position,
					port_basis,
					local_xz,
					min_surface_y,
			):
				rejected += 1
				continue
			var terrain_y := _sample_terrain_y(
				world_layout,
				world_position,
				port_basis,
				local_xz,
			)
			points.append({
				"u": u,
				"v": v,
				"local": [local_xz.x, local_xz.y],
				"y": terrain_y,
			})
	return {
		"step_m": step,
		"u_count": u_count,
		"v_count": v_count,
		"points": points,
		"rejected_count": rejected,
		"beach_setback_m": BEACH_SETBACK_M,
		"min_height_above_water_m": MIN_HEIGHT_ABOVE_WATER_M,
	}


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
		min_surface_y: float,
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
	var terrain_y := TerrainStreamer.sample_terrain_height(world_layout, world_xz, []) \
			- world_position.y
	if terrain_y < min_surface_y:
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
	## Match streamed terrain (natural hills; harbour pads do not flatten).
	## Stored as port-local Y (plot sits at world_position).
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
