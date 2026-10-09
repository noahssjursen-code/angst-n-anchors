class_name CoastalPortPlacer
extends RefCounted

## Pure deterministic conversion from a WorldLayout to coastal PortDefinitions.
## Local -Z is always the seaward direction. The selected site datum is inland;
## PortSizing.COASTAL_GRAPH_ROOT_Z_M moves the graph apron to the shoreline.

const DEFAULT_PORT_COUNT := 35
const PORT_DEFINITION := preload("res://scripts/port/port_definition.gd")

const STRICT_SPACING_M := 800.0
const MIN_SPACING_M := 450.0
const STRICT_WATERWAY_REACH_M := 1800.0
const MAX_WATERWAY_REACH_M := 5000.0
## Public aliases retained for placement tooling and tests.
const PLOT_HALF_DEPTH_M := PortSizing.PLOT_DEPTH_M * 0.5
const DOCK_OVERHANG_M := PortSizing.DOCK_OVERHANG_M
const INLAND_ORIGIN_OFFSET_M := PLOT_HALF_DEPTH_M - DOCK_OVERHANG_M
const FOOTPRINT_HALF_WIDTH_M := PortSizing.SITE_FOOTPRINT_HALF_WIDTH_M
const FOOTPRINT_SEAWARD_M := PortSizing.SITE_FOOTPRINT_SEAWARD_M
const FOOTPRINT_INLAND_M := PortSizing.SITE_FOOTPRINT_INLAND_M
const APPROACH_START_M := 92.0
const APPROACH_END_M := 650.0
const APPROACH_HALF_WIDTH_M := 38.0
const QUAY_HALF_LENGTH_BY_SIZE := PortSizing.QUAY_HALF_LENGTH_BY_SIZE
const QUAY_CLEAR_STEP_M := 8.0
## Samples from the quay face into the berth pocket; land here blocks docking.
const QUAY_BERTH_OFFSETS_M := [0.0, 8.0, 20.0, 38.0, 56.0]
## Require open water (positive SDF) with a small margin so coastline graze fails.
const QUAY_WATER_MARGIN_M := 0.75
## Default backshore grade for explicit checks (~21°). Placement tiers may relax this.
const BACKSHORE_GRADE_MAX := 0.38
const BACKSHORE_GRADE_VALIDATE := 0.52
const BACKSHORE_SAMPLE_DEPTHS_M := [0.0, 24.0, 48.0, 96.0, 160.0, 220.0]

const FALLBACK_NAMES := [
	"Haugsvik", "Alesund", "Bremanger", "Dyrvik", "Eidsund", "Floro",
	"Giske", "Hellesund", "Isfjorden", "Jondal", "Kalvag", "Leirvik",
	"Maloy", "Nordfjordeid", "Oksfjord", "Rorvik", "Selje", "Tingvoll",
	"Ulsteinvik", "Vardo", "Austevoll", "Balestrand", "Dalsfjord",
	"Ervik", "Fedje", "Gulen", "Hitra", "Ibestad", "Kinsarvik", "Luroy",
	"Masfjorden", "Naeroy", "Orsta", "Rognan", "Skjervoy", "Tysnes",
	"Valderoy", "Andalsnes", "Bjugn", "Froya", "Haram", "Kvam",
]


## names supplies names after the mandatory home port. Empty entries use the
## stable fallback list. The returned array is always ordered with Haugsvik first.
static func place_ports(
		layout: WorldLayout,
		requested_count: int = DEFAULT_PORT_COUNT,
		names: PackedStringArray = PackedStringArray(),
) -> Array[PortDefinition]:
	var result: Array[PortDefinition] = []
	if layout == null or requested_count <= 0:
		return result
	var candidates := _build_candidates(layout)
	if candidates.is_empty():
		return result
	candidates.sort_custom(_candidate_less)

	var selected: Array[Dictionary] = []
	var tiers := [
		{"spacing": STRICT_SPACING_M, "reach": STRICT_WATERWAY_REACH_M, "land_margin": 6.0, "quay_half": 93.0, "backshore_grade": 0.30},
		{"spacing": 680.0, "reach": 2600.0, "land_margin": 2.0, "quay_half": 50.0, "backshore_grade": 0.36},
		{"spacing": 560.0, "reach": 3800.0, "land_margin": 0.25, "quay_half": 50.0, "backshore_grade": 0.42},
		{"spacing": MIN_SPACING_M, "reach": MAX_WATERWAY_REACH_M, "land_margin": 0.0, "quay_half": 20.0, "backshore_grade": 0.52},
	]
	for tier in tiers:
		# Keep the playable network representative of the generated archetype,
		# rather than allowing hash order to select only fjord-facing sites.
		for required_region in [
			WorldLayout.Region.MAINLAND,
			WorldLayout.Region.FJORD,
			WorldLayout.Region.ARCHIPELAGO,
		]:
			if selected.size() >= requested_count:
				break
			if _selected_has_region(selected, required_region):
				continue
			for candidate in candidates:
				if int(candidate["region"]) != required_region:
					continue
				if _candidate_fits_tier(layout, selected, candidate, tier):
					selected.append(candidate)
					break
		for candidate in candidates:
			if selected.size() >= requested_count:
				break
			if _candidate_fits_tier(layout, selected, candidate, tier):
				selected.append(candidate)
		if selected.size() >= requested_count:
			break

	for index in range(selected.size()):
		result.append(_make_definition(layout, selected[index], index, names))
	return result


## Public validation report for tests, tooling, and eventual generation telemetry.
static func validate_site(
		layout: WorldLayout,
		world_xz: Vector2,
		seaward: Vector2,
		land_margin_m: float = 0.0,
) -> Dictionary:
	var connection := nearest_waterway_connection(layout, world_xz)
	var quay_half := quay_clear_half_length_m(layout, world_xz, seaward)
	return {
		"origin_on_land": layout != null and layout.is_land(world_xz),
		"land_footprint": is_land_footprint_valid(layout, world_xz, seaward, land_margin_m),
		"seaward_clearance": has_seaward_clearance(layout, world_xz, seaward),
		"gentle_backshore": has_gentle_backshore(layout, world_xz, seaward, BACKSHORE_GRADE_VALIDATE),
		"quay_clearance": has_quay_clearance(layout, world_xz, seaward, QUAY_HALF_LENGTH_BY_SIZE[1]),
		"quay_half_length_m": quay_half,
		"waterway_connection": connection,
		"waterway_distance_m": float(connection.get("distance_m", INF)),
	}


## Validates the conservative size-0 land footprint used during candidate search.
static func is_land_footprint_valid(
		layout: WorldLayout,
		world_xz: Vector2,
		seaward: Vector2,
		min_inland_distance_m: float = 0.0,
) -> bool:
	return is_size_footprint_valid(layout, world_xz, seaward, 0, min_inland_distance_m)


## Validates the complete land-side width for a selected port tier. Candidate
## discovery uses the size-0 footprint; final tier assignment must call this so
## a long quay cannot authorize a wide settlement across a narrow headland.
static func is_size_footprint_valid(
		layout: WorldLayout,
		world_xz: Vector2,
		seaward: Vector2,
		size: int,
		min_inland_distance_m: float = 0.0,
) -> bool:
	if layout == null or seaward.length_squared() < 0.5:
		return false
	var forward := seaward.normalized()
	var right := Vector2(-forward.y, forward.x)
	var half_width := PortSizing.island_width_m(size) * 0.5
	var depths := PackedFloat32Array([
		-FOOTPRINT_SEAWARD_M,
		(FOOTPRINT_INLAND_M - FOOTPRINT_SEAWARD_M) * 0.5,
		FOOTPRINT_INLAND_M,
	])
	var widths := PackedFloat32Array([
		-half_width,
		-half_width * 0.5,
		0.0,
		half_width * 0.5,
		half_width,
	])
	for depth in depths:
		for width in widths:
			var sample := world_xz - forward * depth + right * width
			if layout.sample_signed_distance(sample) >= -min_inland_distance_m:
				return false
	return true


## Verifies the dock face and a three-lane offshore approach. This invariant is
## retained through every relaxation tier: a port is never allowed to face land.
static func has_seaward_clearance(
		layout: WorldLayout,
		world_xz: Vector2,
		seaward: Vector2,
) -> bool:
	if layout == null or seaward.length_squared() < 0.5:
		return false
	var forward := seaward.normalized()
	var right := Vector2(-forward.y, forward.x)
	for distance in PackedFloat32Array([
		APPROACH_START_M, 150.0, 240.0, 360.0, 500.0, APPROACH_END_M,
	]):
		var center := world_xz + forward * distance
		for lateral in PackedFloat32Array([-APPROACH_HALF_WIDTH_M, 0.0, APPROACH_HALF_WIDTH_M]):
			if layout.sample_signed_distance(center + right * lateral) <= 0.0:
				return false
	return true


## Rejects quay sites where the backshore climbs faster than a walkable grade.
static func has_gentle_backshore(
		layout: WorldLayout,
		world_xz: Vector2,
		seaward: Vector2,
		max_grade: float = BACKSHORE_GRADE_MAX,
) -> bool:
	if layout == null or seaward.length_squared() < 0.5:
		return false
	var inland := -seaward.normalized()
	var heights: Array[float] = []
	for depth in BACKSHORE_SAMPLE_DEPTHS_M:
		heights.append(layout.sample_port_site_height(world_xz + inland * float(depth)))
	for i in range(1, heights.size()):
		var run := float(BACKSHORE_SAMPLE_DEPTHS_M[i] - BACKSHORE_SAMPLE_DEPTHS_M[i - 1])
		if run <= 0.001:
			continue
		var rise := heights[i] - heights[i - 1]
		if rise / run > max_grade:
			return false
	return true


## How far seaward from `origin_xz` stays open water before hitting land.
## Used to cap pier finger length in tight bays / inner fjords.
## Origin may sit on the dock apron (coast / slight land); we skip inland until
## water, then measure the continuous water run to the opposite shore.
static func seaward_water_clearance_m(
		layout: WorldLayout,
		origin_xz: Vector2,
		seaward: Vector2,
		max_m: float = 480.0,
		step_m: float = 8.0,
		water_margin_m: float = QUAY_WATER_MARGIN_M,
) -> float:
	if layout == null or seaward.length_squared() < 0.5:
		return 0.0
	var forward := seaward.normalized()
	var step := maxf(step_m, 1.0)
	var travelled := 0.0
	var found_water := false
	## Reach open water first (dock face often sits on the SDF zero contour).
	while travelled + step <= max_m + 0.01:
		var reach := origin_xz + forward * (travelled + step)
		if layout.sample_signed_distance(reach) > water_margin_m:
			found_water = true
			break
		travelled += step
	if not found_water:
		return 0.0
	var clear := 0.0
	while travelled + clear + step <= max_m + 0.01:
		var probe := origin_xz + forward * (travelled + clear + step)
		if layout.sample_signed_distance(probe) <= water_margin_m:
			return clear
		clear += step
	return clear


## Across-bay water half-width from `origin_xz` along ±`along` (shore-parallel).
## Low values mean a narrow pocket that cannot host a wide pier comb.
static func across_water_clearance_m(
		layout: WorldLayout,
		origin_xz: Vector2,
		along: Vector2,
		max_m: float = 320.0,
		step_m: float = 8.0,
		water_margin_m: float = QUAY_WATER_MARGIN_M,
) -> float:
	if layout == null or along.length_squared() < 0.5:
		return 0.0
	var axis := along.normalized()
	var left := 0.0
	var right := 0.0
	var step := maxf(step_m, 1.0)
	while left + step <= max_m + 0.01:
		if layout.sample_signed_distance(origin_xz - axis * (left + step)) <= water_margin_m:
			break
		left += step
	while right + step <= max_m + 0.01:
		if layout.sample_signed_distance(origin_xz + axis * (right + step)) <= water_margin_m:
			break
		right += step
	return minf(left, right)


## True when a straight quay of the given half-length has open water along the
## full berth pocket. Rejects convex coastline corners that wedge land through
## the dock face (the "can't berth at a bend" case).
static func has_quay_clearance(
		layout: WorldLayout,
		world_xz: Vector2,
		seaward: Vector2,
		half_length_m: float,
) -> bool:
	if half_length_m <= 0.0:
		return false
	# Measure with the full search range, then compare. Passing half_length_m as
	# the search cap used to miss non-multiple-of-step thresholds (e.g. 93 m).
	return quay_clear_half_length_m(layout, world_xz, seaward) + 0.01 >= half_length_m


## Largest quay half-length (metres from midships toward either end) that stays
## clear of land. Steps outward so size can be clamped to what the coast allows.
static func quay_clear_half_length_m(
		layout: WorldLayout,
		world_xz: Vector2,
		seaward: Vector2,
		max_half_m: float = QUAY_HALF_LENGTH_BY_SIZE[PortSizing.MAX_SIZE],
) -> float:
	if layout == null or seaward.length_squared() < 0.5:
		return 0.0
	var forward := seaward.normalized()
	var right := Vector2(-forward.y, forward.x)
	var dock_face := world_xz + forward * PLOT_HALF_DEPTH_M
	if not _quay_column_clear(layout, dock_face, forward, right, 0.0):
		return 0.0
	var clear := 0.0
	var lateral := QUAY_CLEAR_STEP_M
	while lateral <= max_half_m + 0.01:
		if not _quay_column_clear(layout, dock_face, forward, right, lateral):
			return clear
		if not _quay_column_clear(layout, dock_face, forward, right, -lateral):
			return clear
		clear = lateral
		lateral += QUAY_CLEAR_STEP_M
	# Exact threshold (size table values are not all step-aligned).
	if clear + 0.01 < max_half_m:
		if _quay_column_clear(layout, dock_face, forward, right, max_half_m) \
				and _quay_column_clear(layout, dock_face, forward, right, -max_half_m):
			clear = max_half_m
	return clear


static func max_size_for_quay_half(half_length_m: float) -> int:
	for size in range(QUAY_HALF_LENGTH_BY_SIZE.size() - 1, -1, -1):
		if half_length_m + 0.01 >= float(QUAY_HALF_LENGTH_BY_SIZE[size]):
			return size
	return -1


static func _quay_column_clear(
		layout: WorldLayout,
		dock_face: Vector2,
		forward: Vector2,
		right: Vector2,
		lateral_m: float,
) -> bool:
	var along := dock_face + right * lateral_m
	for offset in QUAY_BERTH_OFFSETS_M:
		if layout.sample_signed_distance(along + forward * float(offset)) <= QUAY_WATER_MARGIN_M:
			return false
	return true


## Checks generated records without relying on scene nodes.
static func validate_ports(
		layout: WorldLayout,
		ports: Array[PortDefinition],
		min_spacing_m: float = MIN_SPACING_M,
) -> PackedStringArray:
	var errors := PackedStringArray()
	for i in range(ports.size()):
		var port := ports[i]
		var point := Vector2(port.world_position.x, port.world_position.z)
		var seaward := seaward_from_yaw(port.rotation_y)
		var report := validate_site(layout, point, seaward)
		if not bool(report["land_footprint"]):
			errors.append("%s has invalid land footprint" % port.port_id)
		if not is_size_footprint_valid(layout, point, seaward, port.size):
			errors.append("%s size footprint crosses the coastline" % port.port_id)
		if not bool(report["seaward_clearance"]):
			errors.append("%s has blocked seaward approach" % port.port_id)
		if not bool(report.get("gentle_backshore", true)):
			errors.append("%s backshore is too steep" % port.port_id)
		var needed_half := float(QUAY_HALF_LENGTH_BY_SIZE[PortSizing.normalized_size(port.size)])
		if not has_quay_clearance(layout, point, seaward, needed_half):
			errors.append("%s quay is cut by a coastline corner" % port.port_id)
		if float(report["waterway_distance_m"]) > MAX_WATERWAY_REACH_M:
			errors.append("%s is disconnected from waterways" % port.port_id)
		for j in range(i):
			var other := ports[j]
			var other_point := Vector2(other.world_position.x, other.world_position.z)
			if point.distance_to(other_point) < min_spacing_m:
				errors.append("%s is too close to %s" % [port.port_id, other.port_id])
	return errors


## Returns the closest point on the navigable centerline graph and enough
## metadata for chart routing or snapping a port approach to that graph.
static func nearest_waterway_connection(layout: WorldLayout, world_xz: Vector2) -> Dictionary:
	var best := {
		"waterway_id": "",
		"segment_index": -1,
		"point": Vector2.ZERO,
		"distance_m": INF,
		"distance_along_m": 0.0,
	}
	if layout == null:
		return best
	for waterway in layout.waterway_centerlines:
		var points: PackedVector2Array = waterway["points"]
		var along := 0.0
		for segment_index in range(points.size() - 1):
			var projection := _project_to_segment(world_xz, points[segment_index], points[segment_index + 1])
			var point: Vector2 = projection["point"]
			var distance := world_xz.distance_to(point)
			if distance < float(best["distance_m"]):
				best = {
					"waterway_id": String(waterway["id"]),
					"segment_index": segment_index,
					"point": point,
					"distance_m": distance,
					"distance_along_m": along + float(projection["along_m"]),
				}
			along += points[segment_index].distance_to(points[segment_index + 1])
	return best


## Shortest route over the waterway graph, including straight snap distances
## from each supplied point. Returns INF only when no waterway graph exists.
static func navigable_route_distance(layout: WorldLayout, from_xz: Vector2, to_xz: Vector2) -> float:
	if layout == null or layout.waterway_centerlines.is_empty():
		return INF
	var from_connection := nearest_waterway_connection(layout, from_xz)
	var to_connection := nearest_waterway_connection(layout, to_xz)
	var graph := _build_route_graph(layout, from_connection, to_connection)
	var distances: PackedFloat32Array = graph["distances"]
	var adjacency: Array = graph["adjacency"]
	var start := int(graph["start"])
	var target := int(graph["target"])
	var visited := PackedByteArray()
	visited.resize(distances.size())
	distances.fill(INF)
	distances[start] = 0.0
	for _iteration in range(distances.size()):
		var current := -1
		var current_distance := INF
		for node_index in range(distances.size()):
			if visited[node_index] == 0 and distances[node_index] < current_distance:
				current = node_index
				current_distance = distances[node_index]
		if current < 0 or current == target:
			break
		visited[current] = 1
		for edge in adjacency[current]:
			var next := int(edge["to"])
			var proposed := current_distance + float(edge["distance"])
			if proposed < distances[next]:
				distances[next] = proposed
	return (
		float(from_connection["distance_m"])
		+ distances[target]
		+ float(to_connection["distance_m"])
	)


static func seaward_from_yaw(rotation_y: float) -> Vector2:
	return Vector2(-sin(rotation_y), -cos(rotation_y)).normalized()


static func yaw_for_seaward(seaward: Vector2) -> float:
	var direction := seaward.normalized()
	return atan2(-direction.x, -direction.y)


static func _build_candidates(layout: WorldLayout) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for contour_index in range(layout.coastline_contours.size()):
		var contour := layout.coastline_contours[contour_index]
		if contour.size() < 2:
			continue
		var a := contour[0]
		var b := contour[1]
		var tangent := b - a
		if tangent.length_squared() < 1.0:
			continue
		tangent = tangent.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var midpoint := (a + b) * 0.5
		var probe := maxf(140.0, layout.cell_size_m * 1.1)
		var distance_plus := layout.sample_signed_distance(midpoint + normal * probe)
		var distance_minus := layout.sample_signed_distance(midpoint - normal * probe)
		var inland := normal if distance_plus < distance_minus else -normal
		var seaward := -inland
		var position := midpoint + inland * INLAND_ORIGIN_OFFSET_M
		if not layout.is_land(position):
			continue
		var connection := nearest_waterway_connection(layout, position + seaward * APPROACH_END_M)
		var quay_half := quay_clear_half_length_m(layout, position, seaward)
		if quay_half < float(QUAY_HALF_LENGTH_BY_SIZE[0]):
			continue
		candidates.append({
			"position": position,
			"seaward": seaward,
			"waterway_distance_m": float(connection["distance_m"]),
			"quay_half_length_m": quay_half,
			"region": int(layout.classify_region(position)),
			"score": _stable_score(layout.seed, midpoint, contour_index),
			"contour_index": contour_index,
		})
	return candidates


static func _candidate_less(a: Dictionary, b: Dictionary) -> bool:
	var score_a := int(a["score"])
	var score_b := int(b["score"])
	if score_a != score_b:
		return score_a < score_b
	return int(a["contour_index"]) < int(b["contour_index"])


static func _stable_score(seed: int, point: Vector2, index: int) -> int:
	var value := seed ^ (int(round(point.x)) * 73856093)
	value ^= int(round(point.y)) * 19349663
	value ^= index * 83492791
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0x7fffffff
	value = ((value ^ (value >> 16)) * 0x45d9f3b) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff


static func _already_selected(selected: Array[Dictionary], candidate: Dictionary) -> bool:
	var index := int(candidate["contour_index"])
	for existing in selected:
		if int(existing["contour_index"]) == index:
			return true
	return false


static func _selected_has_region(selected: Array[Dictionary], region: int) -> bool:
	for candidate in selected:
		if int(candidate.get("region", -1)) == region:
			return true
	return false


static func _candidate_fits_tier(
		layout: WorldLayout,
		selected: Array[Dictionary],
		candidate: Dictionary,
		tier: Dictionary,
) -> bool:
	if _already_selected(selected, candidate):
		return false
	if float(candidate["waterway_distance_m"]) > float(tier["reach"]):
		return false
	if not is_land_footprint_valid(
			layout,
			candidate["position"],
			candidate["seaward"],
			float(tier["land_margin"]),
	):
		return false
	if not has_seaward_clearance(layout, candidate["position"], candidate["seaward"]):
		return false
	if not has_gentle_backshore(
			layout,
			candidate["position"],
			candidate["seaward"],
			float(tier.get("backshore_grade", BACKSHORE_GRADE_MAX)),
	):
		return false
	if float(candidate.get("quay_half_length_m", 0.0)) + 0.01 < float(tier["quay_half"]):
		return false
	return _has_spacing(selected, candidate["position"], float(tier["spacing"]))


static func _has_spacing(selected: Array[Dictionary], point: Vector2, spacing_m: float) -> bool:
	for existing in selected:
		if point.distance_to(existing["position"]) < spacing_m:
			return false
	return true


static func _make_definition(
		layout: WorldLayout,
		candidate: Dictionary,
		index: int,
		names: PackedStringArray,
) -> PortDefinition:
	var point: Vector2 = candidate["position"]
	var port := PORT_DEFINITION.new() as PortDefinition
	# Preserve the established IDs so economy/contracts do not need a port rewrite.
	port.port_id = "port-home" if index == 0 else "port-%d" % index
	port.display_name = _name_for_index(index, names)
	# PortLayoutGraph uses this inland datum and offsets its root seaward.
	port.world_position = Vector3(point.x, 0.0, point.y)
	var value := _stable_score(layout.seed ^ 0x706f7274, point, index)
	var quay_half := float(candidate.get("quay_half_length_m", quay_clear_half_length_m(
		layout, point, candidate["seaward"]
	)))
	var max_size := maxi(max_size_for_quay_half(quay_half), 0)
	var requested_size := clampi(
		mini(int(value % (PortSizing.MAX_SIZE + 1)), max_size),
		PortSizing.MIN_SIZE,
		PortSizing.MAX_SIZE,
	)
	if index == 0:
		# Home port prefers a useful berth count, but never a corner-cut quay.
		requested_size = maxi(requested_size, mini(2, max_size))
	while requested_size > 0 and not is_size_footprint_valid(
			layout, point, candidate["seaward"], requested_size
	):
		requested_size -= 1
	port.size = requested_size
	## Geography ceiling — player upgrades cannot grow past this site.
	port.site_max_size = clampi(max_size, PortSizing.MIN_SIZE, PortSizing.MAX_SIZE)
	port.site_quay_half_m = quay_half
	port.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	port.site_id = "coast-segment-%05d" % int(candidate["contour_index"])
	port.site_seed = _stable_score(layout.seed ^ 0x73697465, point, int(candidate["contour_index"]))
	port.has_lighthouse = index == 0 or value % 5 == 0
	port.has_fog_horn = index == 0 or value % 7 == 0
	port.rotation_y = yaw_for_seaward(candidate["seaward"])
	port.has_explicit_rotation = true
	port.region_kind = _port_region(layout.classify_region(point))
	port.ground_mode = PortDefinition.GroundMode.WORLD_TERRAIN
	return port


static func _name_for_index(index: int, supplied: PackedStringArray) -> String:
	if index == 0:
		return "Haugsvik"
	var supplied_index := index - 1
	if supplied_index < supplied.size() and not supplied[supplied_index].strip_edges().is_empty():
		return supplied[supplied_index].strip_edges()
	return FALLBACK_NAMES[index % FALLBACK_NAMES.size()]


static func _port_region(region: WorldLayout.Region) -> PortDefinition.RegionKind:
	match region:
		WorldLayout.Region.FJORD:
			return PortDefinition.RegionKind.FJORD
		WorldLayout.Region.ARCHIPELAGO:
			return PortDefinition.RegionKind.ARCHIPELAGO
		_:
			return PortDefinition.RegionKind.MAINLAND


static func _region_name(region: WorldLayout.Region) -> String:
	match region:
		WorldLayout.Region.FJORD:
			return "fjord"
		WorldLayout.Region.ARCHIPELAGO:
			return "archipelago"
		_:
			return "mainland"


static func _project_to_segment(point: Vector2, a: Vector2, b: Vector2) -> Dictionary:
	var segment := b - a
	var length := segment.length()
	if length <= 0.0001:
		return {"point": a, "along_m": 0.0, "t": 0.0}
	var t := clampf((point - a).dot(segment) / (length * length), 0.0, 1.0)
	return {"point": a + segment * t, "along_m": length * t, "t": t}


static func _build_route_graph(
		layout: WorldLayout,
		from_connection: Dictionary,
		to_connection: Dictionary,
) -> Dictionary:
	var nodes: Array[Vector2] = []
	var adjacency: Array = []
	var waterway_nodes := {}
	var ocean_mouth_nodes := PackedInt32Array()
	for waterway in layout.waterway_centerlines:
		var indices := PackedInt32Array()
		for point in waterway["points"]:
			indices.append(_graph_node(nodes, adjacency, point))
		waterway_nodes[String(waterway["id"])] = indices
		if (waterway["connects_to"] as PackedStringArray).has("open_ocean"):
			ocean_mouth_nodes.append(indices[0])
		for i in range(indices.size() - 1):
			_add_graph_edge(adjacency, indices[i], indices[i + 1], nodes[indices[i]].distance_to(nodes[indices[i + 1]]))
	# Trunk mouths all open into the same navigable ocean. Direct mouth-to-mouth
	# edges model that open-water leg without inventing a geographic hub point.
	for i in range(ocean_mouth_nodes.size()):
		for j in range(i):
			var a := ocean_mouth_nodes[i]
			var b := ocean_mouth_nodes[j]
			_add_graph_edge(adjacency, a, b, nodes[a].distance_to(nodes[b]))
	for waterway in layout.waterway_centerlines:
		var connections: PackedStringArray = waterway["connects_to"]
		for parent_id in connections:
			if parent_id == "open_ocean" or not waterway_nodes.has(parent_id):
				continue
			var child_indices: PackedInt32Array = waterway_nodes[String(waterway["id"])]
			var parent_indices: PackedInt32Array = waterway_nodes[parent_id]
			var child_node := child_indices[0]
			var parent_node := _nearest_graph_node(nodes[child_node], parent_indices, nodes)
			_add_graph_edge(adjacency, child_node, parent_node, nodes[child_node].distance_to(nodes[parent_node]))
	var start := _attach_connection(nodes, adjacency, waterway_nodes, from_connection)
	var target := _attach_connection(nodes, adjacency, waterway_nodes, to_connection)
	var distances := PackedFloat32Array()
	distances.resize(nodes.size())
	return {"adjacency": adjacency, "distances": distances, "start": start, "target": target}


static func _graph_node(nodes: Array[Vector2], adjacency: Array, point: Vector2) -> int:
	for i in range(nodes.size()):
		if nodes[i].distance_squared_to(point) < 0.01:
			return i
	nodes.append(point)
	adjacency.append([])
	return nodes.size() - 1


static func _add_graph_edge(adjacency: Array, a: int, b: int, distance: float) -> void:
	adjacency[a].append({"to": b, "distance": distance})
	adjacency[b].append({"to": a, "distance": distance})


static func _nearest_graph_node(point: Vector2, indices: PackedInt32Array, nodes: Array[Vector2]) -> int:
	var best := indices[0]
	var best_distance := INF
	for index in indices:
		var distance := point.distance_squared_to(nodes[index])
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


static func _attach_connection(
		nodes: Array[Vector2],
		adjacency: Array,
		waterway_nodes: Dictionary,
		connection: Dictionary,
) -> int:
	var point: Vector2 = connection["point"]
	var node := _graph_node(nodes, adjacency, point)
	var indices: PackedInt32Array = waterway_nodes[String(connection["waterway_id"])]
	var segment_index := clampi(int(connection["segment_index"]), 0, indices.size() - 2)
	var a := indices[segment_index]
	var b := indices[segment_index + 1]
	_add_graph_edge(adjacency, node, a, point.distance_to(nodes[a]))
	_add_graph_edge(adjacency, node, b, point.distance_to(nodes[b]))
	return node
