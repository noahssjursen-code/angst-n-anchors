class_name PortCoastTracer
extends RefCounted

## Trace the land/water boundary inside a port area. Harbours follow the traced
## shoreline — they are not replaced with synthetic rectangles. Dock pavement
## only merges nearly-straight runs; 90° / 45° snap is optional on long spans.

const FOUNDATION_SURFACE_Y_M := 0.62
const FOUNDATION_THICKNESS_M := 3.6
const FOUNDATION_LAND_DEPTH_M := 40.0
const FOUNDATION_BAY_LIP_M := 6.0
const MAX_SPINE_SEGMENT_M := 72.0
const SPINE_RESAMPLE_STEP_M := 36.0


static func port_area_half_width_m(size: int) -> float:
	return PortSizing.terrain_pad_width_m(size) * 0.5


static func port_area_half_depth_m(size: int) -> float:
	return PortSizing.terrain_pad_depth_m(size) * 0.5


static func port_area_half_extent_m(size: int) -> float:
	return maxf(port_area_half_width_m(size), port_area_half_depth_m(size))


static func normalized_min_segment_m(size: int) -> float:
	return lerpf(48.0, 120.0, float(PortSizing.normalized_size(size)) / float(PortSizing.MAX_SIZE))


static func trace_in_port_area(
		layout: WorldLayout,
		port_origin: Vector3,
		port_yaw: float,
		half_width_m: float,
		half_depth_m: float,
		sample_step_m: float = 10.0,
) -> PackedVector2Array:
	if layout == null:
		return PackedVector2Array()
	var span_x := half_width_m * 2.0
	var span_z := half_depth_m * 2.0
	var grid_n := clampi(int(ceil(maxf(span_x, span_z) / sample_step_m)), 12, 96)
	var land_grid: Array = []
	for _z in range(grid_n + 1):
		var row: Array = []
		for _x in range(grid_n + 1):
			row.append(false)
		land_grid.append(row)

	for iz in range(grid_n + 1):
		for ix in range(grid_n + 1):
			var local := Vector2(
				- half_width_m + float(ix) / float(grid_n) * span_x,
				- half_depth_m + float(iz) / float(grid_n) * span_z,
			)
			var world := _port_local_to_world(local, port_origin, port_yaw)
			land_grid[iz][ix] = layout.is_land(world)

	var edge_points: Array[Vector2] = []
	for iz in range(grid_n):
		for ix in range(grid_n):
			var bl := bool(land_grid[iz][ix])
			var br := bool(land_grid[iz][ix + 1])
			var tl := bool(land_grid[iz + 1][ix])
			var tr := bool(land_grid[iz + 1][ix + 1])
			var x0 := -half_width_m + float(ix) / float(grid_n) * span_x
			var x1 := -half_width_m + float(ix + 1) / float(grid_n) * span_x
			var z0 := -half_depth_m + float(iz) / float(grid_n) * span_z
			var z1 := -half_depth_m + float(iz + 1) / float(grid_n) * span_z
			_collect_edge(edge_points, bl, br, Vector2(lerpf(x0, x1, 0.5), z0))
			_collect_edge(edge_points, tl, tr, Vector2(lerpf(x0, x1, 0.5), z1))
			_collect_edge(edge_points, bl, tl, Vector2(x0, lerpf(z0, z1, 0.5)))
			_collect_edge(edge_points, br, tr, Vector2(x1, lerpf(z0, z1, 0.5)))

	if edge_points.is_empty():
		return synthetic_coast(0, half_width_m, half_depth_m)
	var chain := _chain_edge_points(edge_points, maxf(48.0, half_width_m * 0.05))
	return simplify_coast_path(chain, 5.0, 18.0)


## Dense samples along the best traced-coast span for this port size/seed.
static func select_harbour_span(
		coast_path: PackedVector2Array,
		size: int,
		site_seed: int,
		length_options: Dictionary = {},
) -> PackedVector2Array:
	if coast_path.size() < 2:
		return coast_path
	var arc_lengths := path_arc_lengths(coast_path)
	var total_length := float(arc_lengths[arc_lengths.size() - 1])
	if total_length <= 1.0:
		return coast_path
	var pad_width := PortSizing.terrain_pad_width_m(size)
	var span_fraction := float(length_options.get("span_fraction", 0.62))
	var min_shore_m := float(length_options.get("min_shore_m", PortSizing.design_hull_loa_m(size) * 1.15))
	var desired_length := maxf(pad_width * span_fraction, min_shore_m)
	var span_length := minf(desired_length, total_length)
	var candidate_count := clampi(int(total_length / maxf(48.0, pad_width * 0.08)), 3, 18)
	var best_center := total_length * 0.5
	var best_score := INF
	for index in range(candidate_count):
		var fraction := (float(index) + 0.5) / float(candidate_count)
		var center := lerpf(span_length * 0.5, total_length - span_length * 0.5, fraction)
		var score := _span_turn_score(coast_path, arc_lengths, center, span_length)
		score += float(abs((site_seed ^ (index * 92821)) % 997)) * 0.0001
		if score < best_score:
			best_score = score
			best_center = center
	var span_start := best_center - span_length * 0.5
	var sample_step := clampf(span_length / 28.0, 10.0, 22.0)
	var out := PackedVector2Array()
	var arc_s := span_start
	while arc_s <= span_start + span_length + 0.01:
		var sample := point_at_arc_s(coast_path, arc_lengths, arc_s)
		out.append(sample.get("position", Vector2.ZERO) as Vector2)
		arc_s += sample_step
	var end_sample := point_at_arc_s(coast_path, arc_lengths, span_start + span_length)
	out.append(end_sample.get("position", Vector2.ZERO) as Vector2)
	return _dedupe_close_points(out, 4.0)


## Grows the mainland edge seaward to meet the dock. Bay water stays outside;
## terrain is reclaimed (not carved) along the pavement footprint.
static func fit_port_shoreline(
		layout: WorldLayout,
		port_origin: Vector3,
		port_yaw: float,
		traced_coast: PackedVector2Array,
		size: int,
		site_seed: int,
		_half_extent_m: float = 0.0,
		profile_override: String = "",
) -> Dictionary:
	var length_options := harbour_length_options(size, site_seed, profile_override)
	var raw_span := select_harbour_span(traced_coast, size, site_seed, length_options)
	var natural := simplify_coast_path(raw_span, 14.0, 26.0)
	natural = merge_long_runs(natural, _target_segment_m(size, length_options) * 1.15, 20.0)
	natural = _conform_spine_to_arc(natural, raw_span, MAX_SPINE_SEGMENT_M, SPINE_RESAMPLE_STEP_M)
	natural = _ensure_ribbon_spine(natural, raw_span)
	natural = orient_seaward(layout, port_origin, port_yaw, natural)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x504F5254 ^ (size * 31337)
	var size_t := float(size) / float(PortSizing.MAX_SIZE)
	var reach_scale := {"compact": 0.88, "standard": 1.0, "extended": 1.14}
	var profile_name := str(length_options.get("profile", "standard"))
	var dock_reach := lerpf(22.0, 52.0, size_t) \
			* float(reach_scale.get(profile_name, 1.0)) \
			* rng.randf_range(0.92, 1.08)
	var dock_face := offset_polyline(natural, dock_reach, true)
	var foundation := foundation_ribbon_grown(natural, dock_face, dock_reach)
	foundation["footprint_quads"] = _footprint_quads(
		foundation.get("land_edge", []) as Array,
		foundation.get("water_edge", []) as Array,
	)
	foundation["inland_blend_quads"] = _inland_blend_quads(
		foundation.get("land_edge", []) as Array,
		_inland_blend_depth_m(size),
	)
	foundation["length_profile"] = profile_name
	return {
		"harbour_coast": dock_face,
		"natural_shore": natural,
		"span_coast": raw_span,
		"style": "grown_dock",
		"length_profile": profile_name,
		"shore_length_m": _polyline_length_m(natural),
		"dock_reach_m": dock_reach,
		"design_hull_loa_m": PortSizing.design_hull_loa_m(size),
		"foundation": foundation,
	}


static func harbour_length_options(
		size: int,
		site_seed: int,
		profile_override: String = "",
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x4C454E47 ^ (size * 7717)
	var profiles: Array[String] = ["compact", "standard", "extended"]
	var profile: String
	if profile_override in profiles:
		profile = profile_override
	else:
		profile = profiles[rng.randi_range(0, profiles.size() - 1)]
	var fractions := {
		"compact": 0.40,
		"standard": 0.62,
		"extended": 0.84,
	}
	var min_shore := PortSizing.design_hull_loa_m(size) * 1.2
	return {
		"profile": profile,
		"span_fraction": float(fractions.get(profile, 0.62)),
		"min_shore_m": min_shore,
	}


static func _target_segment_m(size: int, length_options: Dictionary) -> float:
	var profile := str(length_options.get("profile", "standard"))
	var scale := {"compact": 0.85, "standard": 1.0, "extended": 1.15}
	return normalized_min_segment_m(size) * float(scale.get(profile, 1.0))


## Drop points closer than min_point_dist_m; merge corners gentler than merge_angle_deg.
static func simplify_coast_path(
		points: PackedVector2Array,
		min_point_dist_m: float = 6.0,
		merge_angle_deg: float = 14.0,
) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var deduped := _dedupe_close_points(points, min_point_dist_m)
	if deduped.size() < 3:
		return deduped
	var out := PackedVector2Array([deduped[0]])
	for index in range(1, deduped.size() - 1):
		var prev := out[out.size() - 1]
		var current := deduped[index]
		var next := deduped[index + 1]
		var dir_a := (current - prev).normalized()
		var dir_b := (next - current).normalized()
		if dir_a.length_squared() < 0.001 or dir_b.length_squared() < 0.001:
			continue
		var turn := absf(wrapf(
			rad_to_deg(atan2(dir_b.y, dir_b.x)) - rad_to_deg(atan2(dir_a.y, dir_a.x)),
			-180.0,
			180.0,
		))
		if turn < merge_angle_deg and prev.distance_to(next) > min_point_dist_m * 1.5:
			continue
		out.append(current)
	out.append(deduped[deduped.size() - 1])
	if out.size() < 2:
		return deduped
	return out


## Merge only nearly-collinear runs that are already long enough for dock pavement.
static func merge_long_runs(
		points: PackedVector2Array,
		min_run_m: float,
		merge_angle_deg: float = 12.0,
) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array([points[0]])
	var index := 0
	while index < points.size() - 1:
		var anchor: Vector2 = out[out.size() - 1]
		var direction := (points[index + 1] - anchor).normalized()
		if direction.length_squared() < 0.001:
			index += 1
			continue
		var end_index := index + 1
		while end_index < points.size() - 1:
			var next_direction := (points[end_index + 1] - points[end_index]).normalized()
			if next_direction.length_squared() < 0.001:
				end_index += 1
				continue
			var delta := absf(wrapf(
				rad_to_deg(atan2(next_direction.y, next_direction.x))
				- rad_to_deg(atan2(direction.y, direction.x)),
				-180.0,
				180.0,
			))
			if delta > merge_angle_deg:
				break
			end_index += 1
		var end_point := points[end_index]
		if anchor.distance_to(end_point) < min_run_m and end_index < points.size() - 1:
			index = end_index
			continue
		out.append(end_point)
		index = end_index
	if out.size() < 2:
		return points
	return out


## Optional: straighten only long runs that are already close to 90° / 45°.
static func soften_cardinal_runs(
		points: PackedVector2Array,
		min_run_m: float,
		tolerance_deg: float = 12.0,
) -> PackedVector2Array:
	if points.size() < 2:
		return points
	var out := PackedVector2Array([points[0]])
	for index in range(1, points.size()):
		var anchor: Vector2 = out[out.size() - 1]
		var delta := points[index] - anchor
		if delta.length() < min_run_m * 0.5:
			out.append(points[index])
			continue
		var dir := delta.normalized()
		var ang := rad_to_deg(atan2(dir.y, dir.x))
		var snapped_ang := roundf(ang / 45.0) * 45.0
		if absf(wrapf(snapped_ang - ang, -180.0, 180.0)) <= tolerance_deg:
			var snapped_dir := Vector2(cos(deg_to_rad(snapped_ang)), sin(deg_to_rad(snapped_ang)))
			out.append(anchor + snapped_dir * delta.dot(snapped_dir))
		else:
			out.append(points[index])
	if out.size() < 2:
		return points
	return out


## Extend the traced mainland edge seaward to form the dock lip. Bay stays beyond.
static func grow_coast_seaward(path: PackedVector2Array, reach_m: float) -> PackedVector2Array:
	if path.size() < 2 or reach_m <= 0.0:
		return path
	var out := PackedVector2Array()
	for index in range(path.size()):
		var previous := path[maxi(index - 1, 0)]
		var next := path[mini(index + 1, path.size() - 1)]
		var tangent := (next - previous).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector2(1.0, 0.0)
		var water_normal := Vector2(tangent.y, -tangent.x)
		var weight := _growth_weight(index, path.size())
		out.append(path[index] + water_normal * reach_m * weight)
	return out


## Offset a polyline along its local seaward normal. Negative offset drives inland.
static func offset_polyline(
		path: PackedVector2Array,
		offset_m: float,
		use_end_weights: bool = false,
) -> PackedVector2Array:
	if path.size() < 2 or is_equal_approx(offset_m, 0.0):
		return path
	var out := PackedVector2Array()
	for index in range(path.size()):
		var previous := path[maxi(index - 1, 0)]
		var next := path[mini(index + 1, path.size() - 1)]
		var tangent := (next - previous).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector2(1.0, 0.0)
		var water_normal := Vector2(tangent.y, -tangent.x)
		var weight := _growth_weight(index, path.size()) if use_end_weights and offset_m > 0.0 else 1.0
		out.append(path[index] + water_normal * offset_m * weight)
	return out


static func foundation_ribbon_grown(
		natural_shore: PackedVector2Array,
		dock_face: PackedVector2Array,
		dock_reach_m: float,
		land_depth_m: float = FOUNDATION_LAND_DEPTH_M,
		bay_lip_m: float = FOUNDATION_BAY_LIP_M,
) -> Dictionary:
	var land_edge: Array = []
	var water_edge: Array = []
	var visual_water_edge: Array = []
	var segments: Array = []
	if natural_shore.size() < 2 or natural_shore.size() != dock_face.size():
		return {"land_edge": land_edge, "water_edge": water_edge, "segments": segments}
	var inland := offset_polyline(natural_shore, -land_depth_m, false)
	var seaward := offset_polyline(dock_face, 0.0, false)
	var visual := offset_polyline(dock_face, bay_lip_m, true)
	for index in range(natural_shore.size()):
		land_edge.append([inland[index].x, inland[index].y])
		water_edge.append([seaward[index].x, seaward[index].y])
		visual_water_edge.append([visual[index].x, visual[index].y])
	for index in range(dock_face.size() - 1):
		var a := dock_face[index]
		var b := dock_face[index + 1]
		if a.distance_to(b) < 0.5:
			continue
		segments.append(_make_segment_record(a, b, land_depth_m + dock_reach_m))
	return {
		"land_edge": land_edge,
		"water_edge": water_edge,
		"visual_water_edge": visual_water_edge,
		"segments": segments,
		"land_depth_m": land_depth_m,
		"dock_reach_m": dock_reach_m,
		"bay_lip_m": bay_lip_m,
		"thickness_m": FOUNDATION_THICKNESS_M,
		"surface_y_m": FOUNDATION_SURFACE_Y_M,
		"natural_shore_polyline": _polyline_to_array(natural_shore),
		"dock_face_polyline": _polyline_to_array(dock_face),
		"coast_polyline": _polyline_to_array(dock_face),
	}


static func foundation_ribbon(
		coast_path: PackedVector2Array,
		land_depth_m: float = FOUNDATION_LAND_DEPTH_M,
		water_depth_m: float = FOUNDATION_BAY_LIP_M,
) -> Dictionary:
	var land_edge: Array = []
	var water_edge: Array = []
	var segments: Array = []
	if coast_path.size() < 2:
		return {"land_edge": land_edge, "water_edge": water_edge, "segments": segments}
	for index in range(coast_path.size()):
		var previous := coast_path[maxi(index - 1, 0)]
		var next := coast_path[mini(index + 1, coast_path.size() - 1)]
		var tangent := (next - previous).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector2(1.0, 0.0)
		var water_normal := Vector2(tangent.y, -tangent.x)
		var coast := coast_path[index]
		land_edge.append([coast.x - water_normal.x * land_depth_m, coast.y - water_normal.y * land_depth_m])
		water_edge.append([coast.x + water_normal.x * water_depth_m, coast.y + water_normal.y * water_depth_m])
	for index in range(coast_path.size() - 1):
		var a := coast_path[index]
		var b := coast_path[index + 1]
		var direction := b - a
		if direction.length() < 0.5:
			continue
		segments.append(_make_segment_record(a, b, land_depth_m + water_depth_m))
	return {
		"land_edge": land_edge,
		"water_edge": water_edge,
		"segments": segments,
		"land_depth_m": land_depth_m,
		"water_depth_m": water_depth_m,
		"surface_y_m": FOUNDATION_SURFACE_Y_M,
		"coast_polyline": _polyline_to_array(coast_path),
	}


static func orient_seaward(
		layout: WorldLayout,
		port_origin: Vector3,
		port_yaw: float,
		path: PackedVector2Array,
) -> PackedVector2Array:
	if layout == null or path.size() < 2:
		return path
	var center_index := maxi(int(float(path.size() - 1) * 0.5), 0)
	var a := path[center_index]
	var b := path[mini(center_index + 1, path.size() - 1)]
	var tangent := (b - a).normalized()
	if tangent.length_squared() < 0.01:
		return path
	var right_normal := Vector2(tangent.y, -tangent.x)
	var midpoint := (a + b) * 0.5
	var sample := _port_local_to_world(midpoint + right_normal * 18.0, port_origin, port_yaw)
	if not layout.is_land(sample):
		return path
	var reversed := PackedVector2Array()
	for index in range(path.size() - 1, -1, -1):
		reversed.append(path[index])
	return reversed


static func synthetic_coast(site_seed: int, half_width_m: float, half_depth_m: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x434F4154
	var span := half_width_m * 0.72
	var inland_z := half_depth_m * 0.20
	match rng.randi_range(0, 2):
		0:
			return PackedVector2Array([
				Vector2(-span, inland_z),
				Vector2(span * 0.5, inland_z * 0.92),
				Vector2(span, inland_z * 0.75),
			])
		1:
			return PackedVector2Array([
				Vector2(-span, inland_z * 1.05),
				Vector2(-span * 0.2, inland_z * 0.85),
				Vector2(span * 0.35, inland_z * 0.55),
				Vector2(span * 0.7, -half_depth_m * 0.08),
			])
		_:
			return PackedVector2Array([
				Vector2(-span, inland_z * 1.1),
				Vector2(-span * 0.35, inland_z * 0.45),
				Vector2(span * 0.2, inland_z * 0.2),
				Vector2(span, -half_depth_m * 0.05),
			])


static func path_arc_lengths(points: PackedVector2Array) -> Array[float]:
	var lengths: Array[float] = [0.0]
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
		lengths.append(total)
	return lengths


static func point_at_arc_s(points: PackedVector2Array, arc_lengths: Array[float], arc_s: float) -> Dictionary:
	if points.is_empty():
		return {"position": Vector2.ZERO, "tangent_yaw_deg": 0.0, "segment_index": 0}
	var total := arc_lengths[arc_lengths.size() - 1] if not arc_lengths.is_empty() else 0.0
	var target := clampf(arc_s, 0.0, total)
	for i in range(1, points.size()):
		var a0 := float(arc_lengths[i - 1])
		var a1 := float(arc_lengths[i])
		if target > a1 + 0.001:
			continue
		var seg := points[i] - points[i - 1]
		var t := 0.0 if is_equal_approx(a1, a0) else (target - a0) / (a1 - a0)
		var pos := points[i - 1].lerp(points[i], clampf(t, 0.0, 1.0))
		var yaw := rad_to_deg(atan2(seg.y, seg.x))
		return {"position": pos, "tangent_yaw_deg": yaw, "segment_index": i - 1}
	var last := points[points.size() - 1]
	var prev := points[points.size() - 2]
	var seg := last - prev
	return {
		"position": last,
		"tangent_yaw_deg": rad_to_deg(atan2(seg.y, seg.x)),
		"segment_index": maxi(points.size() - 2, 0),
	}


static func _collect_edge(
		edge_points: Array[Vector2],
		land_a: bool,
		land_b: bool,
		midpoint: Vector2,
) -> void:
	if land_a == land_b:
		return
	edge_points.append(midpoint)


static func _chain_edge_points(points: Array[Vector2], max_link_m: float = 48.0) -> PackedVector2Array:
	if points.is_empty():
		return PackedVector2Array()
	var remaining := points.duplicate()
	var start_idx := 0
	var best_z := INF
	for i in range(remaining.size()):
		var p: Vector2 = remaining[i]
		if p.y < best_z:
			best_z = p.y
			start_idx = i
	var chain := PackedVector2Array([remaining[start_idx]])
	remaining.remove_at(start_idx)
	while not remaining.is_empty():
		var tail: Vector2 = chain[chain.size() - 1]
		var nearest := 0
		var nearest_dist := INF
		for i in range(remaining.size()):
			var dist: float = tail.distance_to(remaining[i])
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = i
		if nearest_dist > max_link_m:
			break
		chain.append(remaining[nearest])
		remaining.remove_at(nearest)
	return chain


static func _dedupe_close_points(points: PackedVector2Array, min_dist: float) -> PackedVector2Array:
	if points.is_empty():
		return points
	var out := PackedVector2Array([points[0]])
	for index in range(1, points.size()):
		if out[out.size() - 1].distance_to(points[index]) >= min_dist:
			out.append(points[index])
	if out.size() < 2 and points.size() >= 2:
		return PackedVector2Array([points[0], points[points.size() - 1]])
	return out


static func _polyline_to_array(path: PackedVector2Array) -> Array:
	var out: Array = []
	for point in path:
		out.append([point.x, point.y])
	return out


static func _polyline_length_m(path: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += path[index].distance_to(path[index - 1])
	return total


static func _growth_weight(index: int, count: int) -> float:
	if count <= 1:
		return 1.0
	var t := float(index) / float(count - 1)
	return 0.55 + 0.45 * sin(t * PI)


static func _closest_arc_s(
		arc: PackedVector2Array,
		arc_lengths: Array[float],
		point: Vector2,
) -> float:
	var best_s := 0.0
	var best_dist := INF
	for index in range(arc.size() - 1):
		var a := arc[index]
		var b := arc[index + 1]
		var ab := b - a
		var length_sq := ab.length_squared()
		if length_sq < 0.000001:
			continue
		var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
		var closest := a + ab * t
		var dist := point.distance_to(closest)
		if dist < best_dist:
			best_dist = dist
			best_s = lerpf(float(arc_lengths[index]), float(arc_lengths[index + 1]), t)
	return best_s


static func _conform_spine_to_arc(
		spine: PackedVector2Array,
		arc: PackedVector2Array,
		max_segment_m: float,
		sample_step_m: float,
) -> PackedVector2Array:
	if spine.size() < 2 or arc.size() < 2:
		return spine
	var arc_lengths := path_arc_lengths(arc)
	var out := PackedVector2Array([spine[0]])
	for index in range(spine.size() - 1):
		var a := spine[index]
		var b := spine[index + 1]
		if a.distance_to(b) <= max_segment_m:
			if out[out.size() - 1].distance_to(b) > 4.0:
				out.append(b)
			continue
		var start_s := minf(_closest_arc_s(arc, arc_lengths, a), _closest_arc_s(arc, arc_lengths, b))
		var end_s := maxf(_closest_arc_s(arc, arc_lengths, a), _closest_arc_s(arc, arc_lengths, b))
		var arc_s := start_s + sample_step_m
		while arc_s < end_s - 0.5:
			var sample := point_at_arc_s(arc, arc_lengths, arc_s).get("position", Vector2.ZERO) as Vector2
			if out[out.size() - 1].distance_to(sample) > 4.0:
				out.append(sample)
			arc_s += sample_step_m
		if out[out.size() - 1].distance_to(b) > 4.0:
			out.append(b)
	return _dedupe_close_points(out, 4.0)


static func _resample_arc_uniform(arc: PackedVector2Array, count: int) -> PackedVector2Array:
	if arc.size() < 2 or count < 2:
		return arc
	var arc_lengths := path_arc_lengths(arc)
	var total := float(arc_lengths[arc_lengths.size() - 1])
	var out := PackedVector2Array()
	for index in range(count):
		var arc_s := total * float(index) / float(count - 1)
		out.append(point_at_arc_s(arc, arc_lengths, arc_s).get("position", Vector2.ZERO) as Vector2)
	return out


static func _ensure_ribbon_spine(spine: PackedVector2Array, arc: PackedVector2Array) -> PackedVector2Array:
	var length_m := _polyline_length_m(spine)
	var min_points := clampi(int(ceil(length_m / MAX_SPINE_SEGMENT_M)) + 1, 3, 12)
	if spine.size() >= min_points:
		return spine
	return _resample_arc_uniform(arc, min_points)


static func _inland_blend_depth_m(size: int) -> float:
	var size_t := float(size) / float(PortSizing.MAX_SIZE)
	return lerpf(72.0, 160.0, size_t)


static func _footprint_quads(land_edge: Array, water_edge: Array) -> Array:
	var quads: Array = []
	if land_edge.size() < 2 or land_edge.size() != water_edge.size():
		return quads
	for index in range(land_edge.size() - 1):
		quads.append({
			"corners": [
				land_edge[index],
				land_edge[index + 1],
				water_edge[index + 1],
				water_edge[index],
			],
		})
	return quads


static func _inland_blend_quads(land_edge: Array, blend_depth_m: float) -> Array:
	var quads: Array = []
	if land_edge.size() < 2 or blend_depth_m <= 0.0:
		return quads
	for index in range(land_edge.size() - 1):
		var near_a := land_edge[index] as Array
		var near_b := land_edge[index + 1] as Array
		if near_a.size() < 2 or near_b.size() < 2:
			continue
		var a := Vector2(float(near_a[0]), float(near_a[1]))
		var b := Vector2(float(near_b[0]), float(near_b[1]))
		var tangent := (b - a).normalized()
		if tangent.length_squared() < 0.001:
			continue
		var inland_normal := Vector2(-tangent.y, tangent.x)
		var far_a := a + inland_normal * blend_depth_m
		var far_b := b + inland_normal * blend_depth_m
		quads.append({
			"corners": [
				[far_a.x, far_a.y],
				[far_b.x, far_b.y],
				near_b,
				near_a,
			],
			"blend_depth_m": blend_depth_m,
		})
	return quads


static func _make_segment_record(a: Vector2, b: Vector2, width_m: float) -> Dictionary:
	var direction := b - a
	var length := direction.length()
	if length < 0.5:
		return {}
	var tangent := direction / length
	return {
		"center": [(a.x + b.x) * 0.5, (a.y + b.y) * 0.5],
		"yaw_degrees": rad_to_deg(atan2(-tangent.y, tangent.x)),
		"direction_local": [tangent.x, tangent.y],
		"length_m": length,
		"width_m": width_m,
	}


static func _span_turn_score(
		path: PackedVector2Array,
		arc_lengths: Array[float],
		center: float,
		span_length: float,
) -> float:
	var start := center - span_length * 0.5
	var first_sample := point_at_arc_s(path, arc_lengths, start)
	var previous := float(first_sample.get("tangent_yaw_deg", 0.0))
	var score := 0.0
	for index in range(1, 5):
		var sample := point_at_arc_s(
			path,
			arc_lengths,
			start + span_length * float(index) / 4.0,
		)
		var current := float(sample.get("tangent_yaw_deg", 0.0))
		score += absf(wrapf(current - previous, -180.0, 180.0))
		previous = current
	return score


static func _port_local_to_world(local: Vector2, origin: Vector3, yaw: float) -> Vector2:
	var local3 := Vector3(local.x, 0.0, local.y)
	var world := origin + Basis(Vector3.UP, yaw) * local3
	return Vector2(world.x, world.z)
