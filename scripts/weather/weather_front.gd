class_name WeatherFront
extends Resource

## Deterministic, analytically advected synoptic feature. Fronts are data, not
## scene nodes: every client reconstructs the same center from seed + clock.

enum Kind { WARM_FRONT, COLD_FRONT, SQUALL_LINE }

@export var id: int = 0
@export var kind: Kind = Kind.COLD_FRONT
@export var origin_xz: Vector2 = Vector2.ZERO
@export var velocity_m_per_game_hour: Vector2 = Vector2.ZERO
@export var radius_m: float = 6000.0
@export_range(0.0, 1.0, 0.01) var intensity: float = 0.5
@export var phase_offset: float = 0.0


func center_at(game_hours: float, world_half_extent: float) -> Vector2:
	var span := world_half_extent * 2.0
	var moved := origin_xz + velocity_m_per_game_hour * game_hours
	return Vector2(
		fposmod(moved.x + world_half_extent, span) - world_half_extent,
		fposmod(moved.y + world_half_extent, span) - world_half_extent
	)


func activity_at(game_hours: float) -> float:
	# Multi-day lifecycle with no day-boundary discontinuity.
	var cycle := sin(game_hours * TAU / 96.0 + phase_offset) * 0.5 + 0.5
	return intensity * smoothstep(0.18, 0.82, cycle)


func kind_label() -> String:
	match kind:
		Kind.WARM_FRONT:
			return "Warm front"
		Kind.SQUALL_LINE:
			return "Squall line"
		_:
			return "Cold front"
