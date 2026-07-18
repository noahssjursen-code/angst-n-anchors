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
