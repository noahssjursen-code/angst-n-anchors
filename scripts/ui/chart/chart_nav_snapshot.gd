class_name ChartNavSnapshot
extends RefCounted

const MPS_TO_KNOTS := 1.943844492

var ship: Node3D = null
var ship_position := Vector3(INF, INF, INF)
var bow_horizontal := Vector2(0.0, -1.0)
var velocity_horizontal := Vector2.ZERO
var heading_deg := 0.0
var course_deg := NAN
var speed_knots := 0.0
var bearing_deg := NAN
var leeway_deg := NAN
var waypoint := Vector3(INF, INF, INF)
var contracts: Array = []
var moored_port_id := ""
var moored_berth_id := ""
var wind_direction_deg := NAN
var wind_speed_knots := 0.0
var fuel_fraction := NAN
var time_label := "--:--"


static func capture(tree: SceneTree):
	var out := ChartNavSnapshot.new()
	var root := tree.root
	var view := root.get_node_or_null("LocalPlayerView")
	if view != null:
		var projection := view.call("get_navigation_snapshot") as Dictionary
		out.contracts = projection.get("contracts", []) as Array
		out.waypoint = projection.get("waypoint", Vector3(INF, INF, INF)) as Vector3
		out.moored_port_id = str(projection.get("moored_port_id", ""))
		out.moored_berth_id = str(projection.get("moored_berth_id", ""))
		out.ship_position = projection.get("position", Vector3(INF, INF, INF)) as Vector3
		var velocity := projection.get("velocity", Vector3.ZERO) as Vector3
		if out.ship_position.is_finite():
			out._apply_kinematics(
				projection.get("bow", Vector2(0.0, -1.0)) as Vector2,
				Vector2(velocity.x, velocity.z),
				out.ship_position,
				out.waypoint
			)
		out.fuel_fraction = float(projection.get("fuel_fraction", NAN))
		var wind_direction := projection.get("wind_direction", Vector3.ZERO) as Vector3
		var wind_speed_ms := float(projection.get("wind_speed_ms", 0.0))
		if wind_direction.length_squared() >= 1.0e-8 and wind_speed_ms >= 0.01:
			out.wind_direction_deg = fposmod(
				rad_to_deg(NavigationAxes.bearing_rad_world_delta(-wind_direction)),
				360.0
			)
		out.wind_speed_knots = wind_speed_ms * MPS_TO_KNOTS
		out.time_label = BrandFormat.time_24h(float(projection.get("time_hours", 0.0)))
	return out


static func from_kinematics(
	bow: Vector2,
	velocity: Vector2,
	position: Vector3,
	next_waypoint: Vector3,
):
	var out := ChartNavSnapshot.new()
	out.ship_position = position
	out.waypoint = next_waypoint
	out._apply_kinematics(bow, velocity, position, next_waypoint)
	return out


func has_ship() -> bool:
	return ship_position.is_finite()


func has_course() -> bool:
	return is_finite(course_deg)


func has_waypoint() -> bool:
	return waypoint.is_finite()


func set_waypoint(next_waypoint: Vector3) -> void:
	waypoint = next_waypoint
	if ship_position.is_finite() and waypoint.is_finite():
		bearing_deg = fposmod(
			rad_to_deg(NavigationAxes.bearing_rad_world_delta(waypoint - ship_position)),
			360.0
		)
	else:
		bearing_deg = NAN


func _apply_kinematics(
	bow: Vector2,
	velocity: Vector2,
	position: Vector3,
	next_waypoint: Vector3,
) -> void:
	bow_horizontal = bow.normalized() if bow.length_squared() > 1.0e-10 else Vector2(0.0, -1.0)
	velocity_horizontal = velocity
	heading_deg = NavigationAxes.heading_deg_horizontal(bow_horizontal)
	speed_knots = velocity.length() * MPS_TO_KNOTS
	if velocity.length_squared() > 0.01:
		course_deg = NavigationAxes.heading_deg_horizontal(velocity)
		leeway_deg = signed_angle_difference_deg(heading_deg, course_deg)
	else:
		course_deg = NAN
		leeway_deg = NAN
	if position.is_finite() and next_waypoint.is_finite():
		bearing_deg = fposmod(
			rad_to_deg(NavigationAxes.bearing_rad_world_delta(next_waypoint - position)),
			360.0
		)
	else:
		bearing_deg = NAN


static func signed_angle_difference_deg(from_deg: float, to_deg: float) -> float:
	return fposmod(to_deg - from_deg + 180.0, 360.0) - 180.0
