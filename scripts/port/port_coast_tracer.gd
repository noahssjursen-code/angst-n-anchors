class_name PortCoastTracer
extends RefCounted

## Trace the land/water boundary inside a port area. Harbours follow the traced
## shoreline — they are not replaced with synthetic rectangles. Dock pavement
## only merges nearly-straight runs; 90° / 45° snap is optional on long spans.

const FOUNDATION_SURFACE_Y_M := 0.62
const FOUNDATION_EMBED_DEPTH_M := 48.0
const FOUNDATION_SEAWARD_DEPTH_M := 14.0
## Town concrete back from the shore line (+Z local). Fixed — size only lengthens alongshore.
const FOUNDATION_TOWN_INLAND_M := 88.0
## Extra underground mass tying the platform into the island bedrock.
const FOUNDATION_BURIAL_EXTRA_M := 52.0
const FOUNDATION_DOCK_REACH_M := 26.0
const FOUNDATION_BAY_LIP_M := 6.0
## Even spacing along the harbour spine — mesh quads stay uniform on bends.
const FOUNDATION_SPINE_SAMPLE_M := 22.0
## Coast scan must stay near the registered site — not across a whole fjord.
const TRACE_MAX_HALF_DEPTH_M := 280.0
const PORT_LOCAL_INLAND_DIR := Vector2(0.0, 1.0)
const PORT_LOCAL_SEAWARD_DIR := Vector2(0.0, -1.0)
const PORT_LOCAL_ALONGSHORE_DIR := Vector2(1.0, 0.0)
const MAX_SPINE_SEGMENT_M := 72.0
const SPINE_RESAMPLE_STEP_M := 36.0
const STRAIGHT_RUN_ANGLE_DEG := 12.0


static func port_area_half_width_m(size: int) -> float:
	return PortSizing.terrain_pad_width_m(size) * 0.5


static func port_area_half_depth_m(size: int) -> float:
	return PortSizing.terrain_pad_depth_m(size) * 0.5


static func trace_half_depth_m(size: int) -> float:
	return minf(port_area_half_depth_m(size), TRACE_MAX_HALF_DEPTH_M)


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
	var coast := _trace_shoreline_scanline(
		layout,
		port_origin,
		port_yaw,
		half_width_m,
		half_depth_m,
		sample_step_m,
	)
	if coast.size() >= 3:
		return coast
	return synthetic_coast(0, half_width_m, half_depth_m)


## One point per alongshore column where the SDF crosses water → land.
## Left-to-right order — no greedy chaining, no self-intersecting loops.
static func _trace_shoreline_scanline(
		layout: WorldLayout,
		port_origin: Vector3,
		port_yaw: float,
		half_width_m: float,
		half_depth_m: float,
		column_step_m: float = 10.0,
) -> PackedVector2Array:
	var row_step_m := clampf(column_step_m * 0.45, 4.0, 10.0)
	var out := PackedVector2Array()
	var carry := Vector2.ZERO
	var has_carry := false
	var x := -half_width_m
	while x <= half_width_m + 0.01:
		var crossings: Array[Vector2] = []
		var z := -half_depth_m
		var prev_sd := layout.sample_signed_distance(
			_port_local_to_world(Vector2(x, z), port_origin, port_yaw),
		)
		z += row_step_m
		while z <= half_depth_m + 0.01:
			var local := Vector2(x, z)
			var sd := layout.sample_signed_distance(
				_port_local_to_world(local, port_origin, port_yaw),
			)
			if prev_sd > 0.0 and sd <= 0.0:
				var denom := prev_sd - sd
				var t := 0.5 if absf(denom) < 0.0001 else clampf(prev_sd / denom, 0.0, 1.0)
				crossings.append(Vector2(x, z - row_step_m + row_step_m * t))
			prev_sd = sd
			z += row_step_m
		if not crossings.is_empty():
			var pick := _pick_shore_crossing(crossings, carry, has_carry)
			out.append(pick)
			carry = pick
			has_carry = true
		x += column_step_m
	return _dedupe_close_points(out, 3.0)


static func _pick_shore_crossing(
		crossings: Array[Vector2],
		carry: Vector2,
		has_carry: bool,
) -> Vector2:
	if crossings.is_empty():
		return Vector2.ZERO
	var pick: Vector2 = crossings[0]
	var best_score := INF
	for crossing in crossings:
		var score := carry.distance_to(crossing) if has_carry else crossing.distance_to(Vector2.ZERO)
		if score < best_score:
			best_score = score
			pick = crossing
	return pick


## Dense samples along the best traced-coast span for this port size/seed.
static func select_harbour_span(
		coast_path: PackedVector2Array,
		size: int,
		site_seed: int,
		length_options: Dictionary = {},
) -> PackedVector2Array:
	if coast_path.size() < 2:
		return coast_path
	coast_path = orient_alongshore(coast_path)
	var arc_lengths := path_arc_lengths(coast_path)
	var total_length := float(arc_lengths[arc_lengths.size() - 1])
	if total_length <= 1.0:
		return coast_path
	var span_fraction := float(length_options.get("span_fraction", 0.62))
	var min_shore_m := float(length_options.get("min_shore_m", PortSizing.design_hull_loa_m(size) * 1.1))
	## Along-shore quay length only — never terrain pad width (that balloons into open water).
	var quay_run_m := PortSizing.quay_half_length_m(size) * 2.0
	var desired_length := maxf(quay_run_m * lerpf(0.92, 1.06, span_fraction), min_shore_m)
	var span_length := minf(desired_length, total_length)
	## Grow one continuous chain from the site origin toward port +X — not a random mid-coast window.
	var origin_arc := _closest_arc_to_point(coast_path, arc_lengths, Vector2.ZERO)
	var span_start := origin_arc
	var span_end := minf(origin_arc + span_length, total_length)
	if span_end - span_start < span_length * 0.85:
		span_start = maxf(0.0, span_end - span_length)
	var min_links := PortSizing.foundation_min_spine_links(size)
	var actual_length := span_end - span_start
	var sample_step := clampf(actual_length / float(maxi(min_links - 1, 1)), 6.0, 22.0)
	var out := PackedVector2Array()
	var arc_s := span_start
	while arc_s <= span_end + 0.01:
		var sample := point_at_arc_s(coast_path, arc_lengths, arc_s)
		out.append(sample.get("position", Vector2.ZERO) as Vector2)
		arc_s += sample_step
	var end_sample := point_at_arc_s(coast_path, arc_lengths, span_end)
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
	var traced := orient_alongshore(traced_coast)
	var coast_dots := select_harbour_span(traced, size, site_seed, length_options)
	coast_dots = orient_alongshore(coast_dots)
	coast_dots = _prune_spine_jumps(coast_dots)
	coast_dots = resample_spine_even(coast_dots, PortSizing.foundation_spine_spacing_m(size))
	coast_dots = _ensure_min_spine_links(coast_dots, PortSizing.foundation_min_spine_links(size))
	if coast_dots.size() < 2:
		return _empty_shoreline_fit(size, length_options)
	var reach_scale := {"compact": 0.92, "standard": 1.0, "extended": 1.06}
	var profile_name := str(length_options.get("profile", "standard"))
	var dock_reach := FOUNDATION_DOCK_REACH_M * float(reach_scale.get(profile_name, 1.0))
	var foundation := build_foundation_plan(coast_dots, dock_reach)
	foundation["length_profile"] = profile_name
	var dock_face_pts := _polyline_from_array(foundation.get("dock_face_polyline", []) as Array)
	return {
		"harbour_coast": dock_face_pts,
		"natural_shore": coast_dots,
		"span_coast": coast_dots,
		"style": "coast_dots",
		"length_profile": profile_name,
		"shore_length_m": _polyline_length_m(coast_dots),
		"dock_reach_m": dock_reach,
		"design_hull_loa_m": PortSizing.design_hull_loa_m(size),
		"foundation": foundation,
	}


static func _empty_shoreline_fit(size: int, length_options: Dictionary) -> Dictionary:
	var profile_name := str(length_options.get("profile", "standard"))
	return {
		"harbour_coast": PackedVector2Array(),
		"natural_shore": PackedVector2Array(),
		"span_coast": PackedVector2Array(),
		"style": "coast_dots",
		"length_profile": profile_name,
		"shore_length_m": 0.0,
		"dock_reach_m": FOUNDATION_DOCK_REACH_M,
		"design_hull_loa_m": PortSizing.design_hull_loa_m(size),
		"foundation": {"spine": [], "segments": []},
	}


## Drop hairpin jumps that only happen when a coast polyline self-crosses.
static func _prune_spine_jumps(
		path: PackedVector2Array,
		max_segment_m: float = 56.0,
) -> PackedVector2Array:
	if path.size() < 2:
		return path
	var out := PackedVector2Array([path[0]])
	for index in range(1, path.size()):
		var step := path[index] - out[out.size() - 1]
		var length := step.length()
		if length > max_segment_m or length < 0.5:
			continue
		if out.size() >= 2:
			var prev := (out[out.size() - 1] - out[out.size() - 2]).normalized()
			var dir := step / length
			if prev.dot(dir) < -0.12:
				continue
		out.append(path[index])
	return out if out.size() >= 2 else path


static func _ensure_min_spine_links(
		path: PackedVector2Array,
		min_points: int,
) -> PackedVector2Array:
	if path.size() >= min_points or path.size() < 2:
		return path
	var length_m := _polyline_length_m(path)
	if length_m <= 1.0:
		return path
	return resample_spine_even(path, length_m / float(maxi(min_points - 1, 1)))


## Harbour spine always grows port-local -X → +X (one continuous A→B chain).
static func orient_alongshore(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() < 2:
		return path
	if (path[path.size() - 1] - path[0]).dot(PORT_LOCAL_ALONGSHORE_DIR) < 0.0:
		var reversed := PackedVector2Array()
		for index in range(path.size() - 1, -1, -1):
			reversed.append(path[index])
		return reversed
	return path


static func _closest_arc_to_point(
		path: PackedVector2Array,
		arc_lengths: Array[float],
		point: Vector2,
) -> float:
	if path.is_empty():
		return 0.0
	var best_arc := 0.0
	var best_dist := INF
	for index in range(path.size()):
		var dist := path[index].distance_to(point)
		if dist < best_dist:
			best_dist = dist
			best_arc = float(arc_lengths[index])
	return best_arc


static func harbour_length_options(
		size: int,
		site_seed: int,
		profile_override: String = "",
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x4C454E47
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
	if PortSizing.normalized_size(size) == 0:
		min_shore = maxf(min_shore, PortSizing.quay_half_length_m(size) * 1.5)
	return {
		"profile": profile,
		"span_fraction": float(fractions.get(profile, 0.62)),
		"min_shore_m": min_shore,
	}


static func _target_segment_m(size: int, length_options: Dictionary) -> float:
	var profile := str(length_options.get("profile", "standard"))
	var scale := {"compact": 0.85, "standard": 1.0, "extended": 1.15}
	return normalized_min_segment_m(size) * float(scale.get(profile, 1.0))


## Merge consecutive segments that agree with the run's average bearing. Corners
## survive only where the chain actually turns — interior wiggle becomes one plank.
static func straighten_spine_runs(
		points: PackedVector2Array,
		min_run_m: float,
		angle_tolerance_deg: float = STRAIGHT_RUN_ANGLE_DEG,
) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var run_starts: Array[int] = [0]
	var run_dirs: Array[Vector2] = []
	for index in range(1, points.size()):
		var seg := points[index] - points[index - 1]
		if seg.length_squared() < 0.25:
			continue
		var seg_dir := seg.normalized()
		if run_dirs.is_empty():
			run_dirs.append(seg_dir)
			continue
		var mean_dir := _average_direction(run_dirs)
		if _angle_delta_deg(mean_dir, seg_dir) > angle_tolerance_deg:
			run_starts.append(index - 1)
			run_dirs = [seg_dir]
		else:
			run_dirs.append(seg_dir)
	if run_starts.is_empty():
		return points
	var merged_starts: Array[int] = [int(run_starts[0])]
	for run_index in range(1, run_starts.size()):
		var start_i: int = int(run_starts[run_index - 1])
		var end_i: int = int(run_starts[run_index])
		var run_len := points[end_i].distance_to(points[start_i])
		if run_len < min_run_m and merged_starts.size() > 1:
			continue
		merged_starts.append(int(run_starts[run_index]))
	var corners := PackedVector2Array()
	for start_i in merged_starts:
		corners.append(points[start_i])
	corners.append(points[points.size() - 1])
	return _dedupe_close_points(corners, 4.0)


## Split long straight edges without re-bending them back onto the traced coast.
static func subdivide_straight_runs(
		points: PackedVector2Array,
		max_segment_m: float,
) -> PackedVector2Array:
	if points.size() < 2 or max_segment_m <= 0.0:
		return points
	var out := PackedVector2Array([points[0]])
	for index in range(1, points.size()):
		var start := points[index - 1]
		var end := points[index]
		var span := end - start
		var length := span.length()
		if length <= max_segment_m:
			if out[out.size() - 1].distance_to(end) > 0.5:
				out.append(end)
			continue
		var direction := span / length
		var dist := max_segment_m
		while dist < length - 0.5:
			var sample := start + direction * dist
			if out[out.size() - 1].distance_to(sample) > 0.5:
				out.append(sample)
			dist += max_segment_m
		if out[out.size() - 1].distance_to(end) > 0.5:
			out.append(end)
	return out


static func _average_direction(directions: Array[Vector2]) -> Vector2:
	var sum := Vector2.ZERO
	for dir in directions:
		sum += dir
	return sum.normalized() if sum.length_squared() > 0.001 else Vector2.RIGHT


static func _angle_delta_deg(a: Vector2, b: Vector2) -> float:
	if a.length_squared() < 0.001 or b.length_squared() < 0.001:
		return 0.0
	return absf(wrapf(
		rad_to_deg(atan2(b.y, b.x)) - rad_to_deg(atan2(a.y, a.x)),
		-180.0,
		180.0,
	))


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


## Spine-only harbour plan. Mesh rows are derived at stamp time from spine + constants.
static func build_foundation_plan(
		spine: PackedVector2Array,
		dock_reach_m: float,
		bay_lip_m: float = FOUNDATION_BAY_LIP_M,
		town_inland_m: float = FOUNDATION_TOWN_INLAND_M,
		burial_extra_m: float = FOUNDATION_BURIAL_EXTRA_M,
) -> Dictionary:
	var segments: Array = []
	if spine.size() < 2:
		return {"spine": [], "segments": segments}
	var dock_face := offset_spine_perpendicular(spine, dock_reach_m, PORT_LOCAL_INLAND_DIR, false)
	for index in range(dock_face.size() - 1):
		var a := dock_face[index]
		var b := dock_face[index + 1]
		if a.distance_to(b) < 0.5:
			continue
		segments.append(_make_segment_record(a, b, dock_reach_m + bay_lip_m))
	return {
		"spine": _polyline_to_array(spine),
		"town_inland_m": town_inland_m,
		"burial_extra_m": burial_extra_m,
		"dock_reach_m": dock_reach_m,
		"bay_lip_m": bay_lip_m,
		"embed_depth_m": FOUNDATION_EMBED_DEPTH_M,
		"seaward_depth_m": FOUNDATION_SEAWARD_DEPTH_M,
		"surface_y_m": FOUNDATION_SURFACE_Y_M,
		"natural_shore_polyline": _polyline_to_array(spine),
		"dock_face_polyline": _polyline_to_array(dock_face),
		"coast_polyline": _polyline_to_array(dock_face),
		"segments": segments,
	}


## Push spine samples onto land when they sit in open water. Never drops points.
static func nudge_spine_onto_land(
		layout: WorldLayout,
		port_origin: Vector3,
		port_yaw: float,
		path: PackedVector2Array,
) -> PackedVector2Array:
	if layout == null or path.is_empty():
		return path
	var out := PackedVector2Array()
	for index in range(path.size()):
		var local := path[index]
		var inland := spine_inland_normal(path, index, PORT_LOCAL_INLAND_DIR)
		for _step in range(32):
			var world := _port_local_to_world(local, port_origin, port_yaw)
			if layout.sample_signed_distance(world) <= 0.0:
				break
			local += inland * 5.0
		out.append(local)
	return out


## Unit normal perpendicular to the spine, pointing toward port inland (+Z local).
static func spine_inland_normal(
		path: PackedVector2Array,
		index: int,
		reference_inland: Vector2 = PORT_LOCAL_INLAND_DIR,
) -> Vector2:
	if path.size() < 2:
		return reference_inland.normalized()
	var previous := path[maxi(index - 1, 0)]
	var next := path[mini(index + 1, path.size() - 1)]
	var tangent := (next - previous).normalized()
	if tangent.length_squared() < 0.001:
		return reference_inland.normalized()
	var left := Vector2(-tangent.y, tangent.x)
	var right := Vector2(tangent.y, -tangent.x)
	var ref := reference_inland.normalized()
	if left.dot(ref) >= right.dot(ref):
		return left.normalized() if left.length_squared() > 0.001 else ref
	return right.normalized() if right.length_squared() > 0.001 else ref


## Offset each spine sample perpendicular to the traced coast.
static func offset_spine_perpendicular(
		path: PackedVector2Array,
		distance_m: float,
		reference_inland: Vector2 = PORT_LOCAL_INLAND_DIR,
		toward_inland: bool = true,
) -> PackedVector2Array:
	if path.is_empty() or is_equal_approx(distance_m, 0.0):
		return path
	var sign := 1.0 if toward_inland else -1.0
	var out := PackedVector2Array()
	for index in range(path.size()):
		var normal := spine_inland_normal(path, index, reference_inland)
		out.append(path[index] + normal * distance_m * sign)
	return out


## Even arc-length resample so ruled quads stay consistent on curves.
static func resample_spine_even(path: PackedVector2Array, spacing_m: float) -> PackedVector2Array:
	if path.size() < 2 or spacing_m <= 0.5:
		return path
	var arcs := path_arc_lengths(path)
	var total := float(arcs[arcs.size() - 1])
	if total <= spacing_m:
		return path
	var out := PackedVector2Array()
	var arc_s := 0.0
	while arc_s <= total + 0.01:
		out.append(point_at_arc_s(path, arcs, arc_s).get("position", Vector2.ZERO) as Vector2)
		arc_s += spacing_m
	var end_pt := point_at_arc_s(path, arcs, total).get("position", Vector2.ZERO) as Vector2
	if out.is_empty() or out[out.size() - 1].distance_to(end_pt) > 1.0:
		out.append(end_pt)
	return out if out.size() >= 2 else path


static func _polyline_from_array(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for raw in points:
		var pt := raw as Array
		if pt.size() >= 2:
			out.append(Vector2(float(pt[0]), float(pt[1])))
	return out


## Uniform translation — stable inland burial without curve-normal blowout into the sea.
static func offset_polyline_along(
		path: PackedVector2Array,
		direction_local: Vector2,
		distance_m: float,
) -> PackedVector2Array:
	if path.is_empty() or is_equal_approx(distance_m, 0.0):
		return path
	var dir := direction_local.normalized()
	if dir.length_squared() < 0.001:
		dir = Vector2(0.0, 1.0)
	var out := PackedVector2Array()
	for point in path:
		out.append(point + dir * distance_m)
	return out


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
