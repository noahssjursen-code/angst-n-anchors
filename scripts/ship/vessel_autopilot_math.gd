extends RefCounted

## Dependency-free control math, isolated for deterministic headless tests.


static func rudder_for_heading(
	bow: Vector2,
	desired: Vector2,
	full_error_deg: float = 32.0,
) -> float:
	if bow.length_squared() <= 0.0001 or desired.length_squared() <= 0.0001:
		return 0.0
	var heading_error := bow.normalized().angle_to(desired.normalized())
	return clampf(heading_error / deg_to_rad(maxf(full_error_deg, 1.0)), -1.0, 1.0)


static func adaptive_lookahead_m(
		base_m: float,
		cross_track_error_m: float,
		upcoming_turn_deg: float,
		minimum_m: float = 32.0,
) -> float:
	## Long look-ahead is stable at sea but cuts across harbour corners. Pull the
	## target back toward the centreline as either curvature or route error rises.
	var turn_severity := clampf(absf(upcoming_turn_deg) / 75.0, 0.0, 1.0)
	var error_severity := clampf(maxf(cross_track_error_m, 0.0) / 180.0, 0.0, 1.0)
	var base := maxf(base_m, minimum_m)
	## A turn still needs forward preview: collapsing all the way to the minimum
	## made ships wait until the bow reached the bend. Curvature may shorten the
	## preview modestly; only genuine cross-track recovery pulls it close.
	var turn_lookahead := lerpf(base, maxf(minimum_m, base * 0.72), turn_severity)
	var recovery_lookahead := lerpf(base, minimum_m, error_severity * 0.88)
	return minf(turn_lookahead, recovery_lookahead)


static func throttle_for_course(
		cruise: float,
		heading_error_deg: float,
		cross_track_error_m: float,
		upcoming_turn_deg: float,
) -> float:
	## Give the hull time to rotate instead of carrying cruise momentum through a
	## bend. Straight, on-track passages remain completely unaffected.
	var heading_severity := clampf((absf(heading_error_deg) - 8.0) / 62.0, 0.0, 1.0)
	var turn_severity := clampf((absf(upcoming_turn_deg) - 8.0) / 67.0, 0.0, 1.0)
	var error_severity := clampf((maxf(cross_track_error_m, 0.0) - 20.0) / 160.0, 0.0, 1.0)
	var correction := maxf(heading_severity, maxf(turn_severity, error_severity))
	return minf(cruise, lerpf(cruise, 0.30, correction))


static func centreline_guidance(
		position: Vector2,
		route_point: Vector2,
		current_tangent: Vector2,
		preview_tangent: Vector2,
		speed_ms: float,
		anticipation: float = 0.62,
		cross_track_gain: float = 0.11,
		max_correction_deg: float = 62.0,
) -> Vector2:
	if current_tangent.length_squared() <= 0.0001:
		return (route_point - position).normalized()
	var current := current_tangent.normalized()
	var preview := preview_tangent.normalized() \
		if preview_tangent.length_squared() > 0.0001 else current
	var base_angle := lerp_angle(current.angle(), preview.angle(), clampf(anticipation, 0.0, 1.0))
	var base_course := Vector2.from_angle(base_angle)
	## Positive cross product means the vessel lies left of route direction, so
	## steer right (negative angle), and vice versa. atan2 keeps recovery smooth
	## while still providing strong authority when well outside the lane.
	var signed_error := current.cross(position - route_point)
	var correction := atan2(-signed_error * cross_track_gain, maxf(speed_ms, 2.0))
	correction = clampf(correction, -deg_to_rad(max_correction_deg), deg_to_rad(max_correction_deg))
	return base_course.rotated(correction).normalized()
