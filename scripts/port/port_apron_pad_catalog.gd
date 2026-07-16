class_name PortApronPadCatalog
extends RefCounted

## Apron pad templates: N×M cells on the foundation yellow grid.
## One cell = CELL_M metres = CELL_M brick cells (BuildingGrid.CELL_M = 1).

const CoastTracer := preload("res://scripts/port/port_coast_tracer.gd")

const CELL_M := 22.0
const BRICK_HEIGHT_CELLS := 16
## Quay working strip: host cells whose centre is closer than this to the dock face are omitted.
const DOCK_SETBACK_ROWS := 1
## Extra lattice padding beyond the apron AABB (cells).
const GRID_AABB_PAD_CELLS := 1

## Template id → apron cell footprint [along, inland].
const TEMPLATES := {
	"pad_1x1": {"id": "pad_1x1", "cells": Vector2i(1, 1), "label": "1×1 (22×22 m)"},
	"pad_1x2": {"id": "pad_1x2", "cells": Vector2i(1, 2), "label": "1×2 (22×44 m)"},
	"pad_2x1": {"id": "pad_2x1", "cells": Vector2i(2, 1), "label": "2×1 (44×22 m)"},
	"pad_2x2": {"id": "pad_2x2", "cells": Vector2i(2, 2), "label": "2×2 (44×44 m)"},
	"pad_2x3": {"id": "pad_2x3", "cells": Vector2i(2, 3), "label": "2×3 (44×66 m)"},
}

## Apron depth bands on the uniform host lattice (j = inland index):
##   waterside — cold chain / trade handling (lowest host j)
##   mid       — warehouse, fuel, parking
##   townside  — harbour office facing the settlement
const ZONE_WATERSIDE := "waterside"
const ZONE_MID := "mid"
const ZONE_TOWNSIDE := "townside"

## role_id → placement defaults. kind: universal | trade.
const ROLES := {
	"harbour_office": {
		"id": "harbour_office",
		"label": "Harbour office",
		## 2×2 + one inland row → 2×3 (44×66 m); shrinks if the apron is tight.
		"pad_template_id": "pad_2x3",
		"kind": "universal",
		"zone": ZONE_TOWNSIDE,
		"precinct": "admin",
		"commodity_ids": [],
	},
	"customs_shed": {
		"id": "customs_shed",
		"label": "Customs shed",
		"pad_template_id": "pad_1x2",
		"kind": "universal",
		"zone": ZONE_TOWNSIDE,
		"precinct": "admin",
		"commodity_ids": [],
	},
	"general_warehouse": {
		"id": "general_warehouse",
		"label": "General warehouse",
		"pad_template_id": "pad_2x2",
		"kind": "universal",
		"zone": ZONE_MID,
		"precinct": "storage",
		"commodity_ids": [],
	},
	"fuel_bunker": {
		"id": "fuel_bunker",
		"label": "Fuel bunker",
		"pad_template_id": "pad_1x1",
		"kind": "universal",
		"zone": ZONE_MID,
		"precinct": "storage",
		"commodity_ids": [],
	},
	"crew_welfare": {
		"id": "crew_welfare",
		"label": "Crew welfare",
		"pad_template_id": "pad_1x1",
		"kind": "universal",
		"zone": ZONE_TOWNSIDE,
		"precinct": "admin",
		"commodity_ids": [],
	},
	"chandlery": {
		"id": "chandlery",
		"label": "Chandlery",
		"pad_template_id": "pad_1x1",
		"kind": "universal",
		"zone": ZONE_TOWNSIDE,
		"precinct": "marine_services",
		"commodity_ids": [],
	},
	"workshop": {
		"id": "workshop",
		"label": "Workshop",
		"pad_template_id": "pad_1x2",
		"kind": "universal",
		"zone": ZONE_TOWNSIDE,
		"precinct": "marine_services",
		"commodity_ids": [],
	},
	"parking_apron": {
		"id": "parking_apron",
		"label": "Parking apron",
		"pad_template_id": "pad_2x1",
		"kind": "universal",
		## Mid band — never on the dock-lip setback row.
		"zone": ZONE_MID,
		"precinct": "parking",
		"commodity_ids": [],
	},
	"container_yard": {
		"id": "container_yard",
		"label": "Container yard",
		"pad_template_id": "pad_2x2",
		"kind": "trade",
		"zone": ZONE_WATERSIDE,
		"precinct": "trade_containers",
		"commodity_ids": ["containers"],
	},
	"container_stack": {
		"id": "container_stack",
		"label": "Container stack",
		"pad_template_id": "pad_1x2",
		"kind": "trade",
		"zone": ZONE_WATERSIDE,
		"precinct": "trade_containers",
		"commodity_ids": ["containers"],
	},
}

## Always placed — harbourmaster / shipwright live here later.
const UNIVERSAL_REQUIRED_V1 := [
	"harbour_office",
]

## Soft decorative pads — placed when space allows; never steal the harbour office.
const UNIVERSAL_DECORATIVE_V1 := [
	"general_warehouse",
	"fuel_bunker",
]

## Required + decorative (parking / customs / chandlery etc. stay in ROLES only).
const UNIVERSAL_V1 := [
	"harbour_office",
	"general_warehouse",
	"fuel_bunker",
]

## V1 trade roles — only when commodity is unlocked.
const TRADE_V1 := [
	"container_yard",
	"container_stack",
]


static func template_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id in ["pad_1x1", "pad_1x2", "pad_2x1", "pad_2x2", "pad_2x3"]:
		out.append(id)
	return out


static func template(template_id: String) -> Dictionary:
	return TEMPLATES.get(template_id, {}) as Dictionary


static func template_cells(template_id: String) -> Vector2i:
	var entry: Dictionary = template(template_id)
	if entry.is_empty():
		return Vector2i(1, 1)
	return entry.get("cells", Vector2i(1, 1)) as Vector2i


## Shrink ladder when apron space is tight — always ends at 1×1.
static func template_fallbacks(template_id: String) -> PackedStringArray:
	match template_id:
		"pad_2x3":
			return PackedStringArray(["pad_2x3", "pad_2x2", "pad_2x1", "pad_1x2", "pad_1x1"])
		"pad_2x2":
			return PackedStringArray(["pad_2x2", "pad_2x1", "pad_1x2", "pad_1x1"])
		"pad_2x1":
			return PackedStringArray(["pad_2x1", "pad_1x1"])
		"pad_1x2":
			return PackedStringArray(["pad_1x2", "pad_1x1"])
		"pad_1x1":
			return PackedStringArray(["pad_1x1"])
		_:
			return PackedStringArray([template_id, "pad_1x1"]) if not template_id.is_empty() \
					else PackedStringArray(["pad_1x1"])


static func size_m(template_id: String) -> Vector2:
	var cells := template_cells(template_id)
	return Vector2(float(cells.x) * CELL_M, float(cells.y) * CELL_M)


## Brick authoring volume: X = along cells, Z = inland cells, Y = height.
static func brick_volume(template_id: String) -> Vector3i:
	var cells := template_cells(template_id)
	return Vector3i(
		maxi(cells.x * int(CELL_M), 1),
		BRICK_HEIGHT_CELLS,
		maxi(cells.y * int(CELL_M), 1),
	)


static func role(role_id: String) -> Dictionary:
	return ROLES.get(role_id, {}) as Dictionary


static func role_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id in ROLES.keys():
		out.append(str(id))
	out.sort()
	return out


static func role_label(role_id: String) -> String:
	var entry := role(role_id)
	if entry.is_empty():
		return role_id
	return str(entry.get("label", role_id))


static func default_template_for_role(role_id: String) -> String:
	var entry := role(role_id)
	return str(entry.get("pad_template_id", "pad_1x1"))


static func zone_for_role(role_id: String) -> String:
	var entry := role(role_id)
	return str(entry.get("zone", ZONE_MID))


## Preferred inland origin j for a zone given host j range + footprint height.
static func preferred_j_for_zone(zone: String, host_j_min: int, host_j_max: int, height_cells: int) -> int:
	var h := maxi(height_cells, 1)
	var max_j0 := maxi(host_j_max - h + 1, host_j_min)
	match zone:
		ZONE_WATERSIDE:
			return host_j_min
		ZONE_TOWNSIDE:
			return max_j0
		_:
			return clampi((host_j_min + max_j0) / 2, host_j_min, max_j0)


## Uniform port-local lattice clipped to the apron pavement polygon.
## Cells are perfect squares; anything outside the apron (or on the dock lip) is omitted.
static func build_host_grid(foundation: Dictionary, berth_plan: Dictionary = {}) -> Dictionary:
	var empty := {
		"polygon": [],
		"origin": [0.0, 0.0],
		"along_dir": [1.0, 0.0],
		"inland_dir": [0.0, 1.0],
		"cell_m": CELL_M,
		"along_count": 0,
		"inland_count": 0,
		"host_count": 0,
		"host_j_min": 0,
		"host_j_max": 0,
		"cells": [],
		"mask": {},
	}
	var dock_face := _polyline_from_array(foundation.get("dock_face_polyline", []) as Array)
	if dock_face.size() < 2:
		dock_face = _polyline_from_array(foundation.get("spine", []) as Array)
	if dock_face.size() < 2:
		return empty

	var town_inland := float(foundation.get("town_inland_m", CoastTracer.FOUNDATION_TOWN_INLAND_M))
	if town_inland < CELL_M * 0.5:
		return empty

	var inland_dir := CoastTracer.PORT_LOCAL_INLAND_DIR.normalized()
	var sea_a := dock_face[0]
	var sea_b := dock_face[dock_face.size() - 1]
	var along_raw := sea_b - sea_a
	var along_dir := along_raw.normalized() if along_raw.length_squared() > 0.01 \
			else CoastTracer.PORT_LOCAL_ALONGSHORE_DIR
	## Keep along roughly +X so i increases left→right with port convention.
	if along_dir.dot(CoastTracer.PORT_LOCAL_ALONGSHORE_DIR) < 0.0:
		along_dir = -along_dir

	var polygon := _apron_pavement_polygon(dock_face, inland_dir, town_inland)
	if polygon.size() < 3:
		return empty

	var frame_origin := (sea_a + sea_b) * 0.5
	var u_min := INF
	var u_max := -INF
	var v_min := INF
	var v_max := -INF
	for p in polygon:
		var rel := p - frame_origin
		var u := rel.dot(along_dir)
		var v := rel.dot(inland_dir)
		u_min = minf(u_min, u)
		u_max = maxf(u_max, u)
		v_min = minf(v_min, v)
		v_max = maxf(v_max, v)

	var pad_m := float(GRID_AABB_PAD_CELLS) * CELL_M
	u_min -= pad_m
	u_max += pad_m
	v_min -= pad_m
	v_max += pad_m

	var i0_world := int(floor(u_min / CELL_M))
	var j0_world := int(floor(v_min / CELL_M))
	var i1_world := int(ceil(u_max / CELL_M))
	var j1_world := int(ceil(v_max / CELL_M))
	var along_count := maxi(i1_world - i0_world, 0)
	var inland_count := maxi(j1_world - j0_world, 0)
	if along_count < 1 or inland_count < 1:
		return empty

	var lattice_origin := frame_origin \
			+ along_dir * (float(i0_world) * CELL_M) \
			+ inland_dir * (float(j0_world) * CELL_M)
	var setback_m := float(DOCK_SETBACK_ROWS) * CELL_M
	var quay_keepout := _quay_keepout_points(berth_plan)

	var cells: Array = []
	var mask: Dictionary = {}
	var host_j_min := 999999
	var host_j_max := -999999
	for j in range(inland_count):
		for i in range(along_count):
			var corners := uniform_cell_corners(lattice_origin, along_dir, inland_dir, i, j, CELL_M)
			if not _corners_inside_polygon(corners, polygon):
				continue
			var centre := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
			if _dist_to_polyline(centre, dock_face) < setback_m:
				continue
			if _near_quay_keepout(centre, quay_keepout):
				continue
			var key := "%d,%d" % [i, j]
			mask[key] = true
			host_j_min = mini(host_j_min, j)
			host_j_max = maxi(host_j_max, j)
			cells.append({
				"i": i,
				"j": j,
				"origin": [corners[0].x, corners[0].y],
				"centre": [centre.x, centre.y],
				"corners": [
					[corners[0].x, corners[0].y],
					[corners[1].x, corners[1].y],
					[corners[2].x, corners[2].y],
					[corners[3].x, corners[3].y],
				],
			})

	if cells.is_empty():
		host_j_min = 0
		host_j_max = 0

	return {
		"polygon": _polyline_to_array(polygon),
		"origin": [lattice_origin.x, lattice_origin.y],
		"along_dir": [along_dir.x, along_dir.y],
		"inland_dir": [inland_dir.x, inland_dir.y],
		"cell_m": CELL_M,
		"along_count": along_count,
		"inland_count": inland_count,
		"host_count": cells.size(),
		"host_j_min": host_j_min,
		"host_j_max": host_j_max,
		"cells": cells,
		"mask": mask,
	}


static func uniform_cell_corners(
		lattice_origin: Vector2,
		along_dir: Vector2,
		inland_dir: Vector2,
		i: int,
		j: int,
		cell_m: float = CELL_M,
) -> PackedVector2Array:
	var along := along_dir.normalized()
	var inland := inland_dir.normalized()
	var c00 := lattice_origin + along * (float(i) * cell_m) + inland * (float(j) * cell_m)
	var c10 := lattice_origin + along * (float(i + 1) * cell_m) + inland * (float(j) * cell_m)
	var c11 := lattice_origin + along * (float(i + 1) * cell_m) + inland * (float(j + 1) * cell_m)
	var c01 := lattice_origin + along * (float(i) * cell_m) + inland * (float(j + 1) * cell_m)
	return PackedVector2Array([c00, c10, c11, c01])


static func project_to_cell_i(
		world_xz: Vector2,
		lattice_origin: Vector2,
		along_dir: Vector2,
		cell_m: float = CELL_M,
) -> int:
	var along := along_dir.normalized()
	var u := (world_xz - lattice_origin).dot(along)
	return int(floor(u / cell_m))


static func _apron_pavement_polygon(
		dock_face: PackedVector2Array,
		inland_dir: Vector2,
		town_inland_m: float,
) -> PackedVector2Array:
	var inland := inland_dir.normalized()
	var poly := PackedVector2Array()
	for p in dock_face:
		poly.append(p)
	for index in range(dock_face.size() - 1, -1, -1):
		poly.append(dock_face[index] + inland * town_inland_m)
	return poly


static func _corners_inside_polygon(corners: PackedVector2Array, polygon: PackedVector2Array) -> bool:
	if corners.size() < 4 or polygon.size() < 3:
		return false
	for c in corners:
		if not Geometry2D.is_point_in_polygon(c, polygon):
			return false
	return true


static func _dist_to_polyline(point: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 2:
		return INF
	var best := INF
	for index in range(poly.size() - 1):
		var a := poly[index]
		var b := poly[index + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0 if len_sq < 0.0001 else clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
		best = minf(best, point.distance_to(a + ab * t))
	return best


static func _quay_keepout_points(berth_plan: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if berth_plan.is_empty():
		return out
	for raw in berth_plan.get("quay_stations", []) as Array:
		var station: Dictionary = raw
		var origin_arr: Array = station.get("origin", []) as Array
		if origin_arr.size() < 2:
			continue
		out.append(Vector2(float(origin_arr[0]), float(origin_arr[1])))
	return out


static func _near_quay_keepout(centre: Vector2, quay_points: Array[Vector2], radius_m: float = 28.0) -> bool:
	for q in quay_points:
		if centre.distance_to(q) <= radius_m:
			return true
	return false


static func _polyline_from_array(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for item in raw:
		if item is Vector2:
			out.append(item)
		elif item is Array and (item as Array).size() >= 2:
			var arr: Array = item
			out.append(Vector2(float(arr[0]), float(arr[1])))
	return out


static func _polyline_to_array(path: PackedVector2Array) -> Array:
	var out: Array = []
	for p in path:
		out.append([p.x, p.y])
	return out


## Jobs to place for a live trade profile (universal + asphalt trade roles).
static func placement_jobs(profile: PortTradeProfile) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for role_id in UNIVERSAL_REQUIRED_V1:
		var entry := role(role_id)
		if entry.is_empty():
			continue
		jobs.append({
			"role": role_id,
			"pad_template_id": str(entry.get("pad_template_id", "pad_1x1")),
			"kind": "universal",
			"required": true,
			"commodity_id": "",
			"zone": str(entry.get("zone", ZONE_TOWNSIDE)),
			"precinct": str(entry.get("precinct", role_id)),
		})
	for role_id in UNIVERSAL_DECORATIVE_V1:
		var entry := role(role_id)
		if entry.is_empty():
			continue
		jobs.append({
			"role": role_id,
			"pad_template_id": str(entry.get("pad_template_id", "pad_1x1")),
			"kind": "universal",
			"required": false,
			"commodity_id": "",
			"zone": str(entry.get("zone", ZONE_MID)),
			"precinct": str(entry.get("precinct", role_id)),
		})
	if profile == null:
		return jobs
	var unlocked: Dictionary = {}
	for commodity_id in profile.export_slots:
		unlocked[str(commodity_id)] = true
	for commodity_id in profile.import_slots:
		unlocked[str(commodity_id)] = true
	for role_id in TRADE_V1:
		var entry := role(role_id)
		if entry.is_empty():
			continue
		var commodity_ids: Array = entry.get("commodity_ids", []) as Array
		var matched := ""
		for cid in commodity_ids:
			if unlocked.has(str(cid)):
				matched = str(cid)
				break
		if matched.is_empty():
			continue
		## Trade pads sit on apron waterside, snapped near their asphalt berth arc.
		jobs.append({
			"role": role_id,
			"pad_template_id": str(entry.get("pad_template_id", "pad_1x1")),
			"kind": "trade",
			"commodity_id": matched,
			"zone": str(entry.get("zone", ZONE_WATERSIDE)),
			"precinct": str(entry.get("precinct", "trade_%s" % matched)),
			"prefer_berth": CommodityCatalog.uses_asphalt_dock(matched),
		})
	return jobs
