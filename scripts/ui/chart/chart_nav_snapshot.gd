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
var wind_direction_deg := NAN
var wind_speed_knots := 0.0
var fuel_fraction := NAN
var time_label := "--:--"


static func capture(tree: SceneTree):
	var out := ChartNavSnapshot.new()
	var root := tree.root
	var view := root.get_node_or_null("LocalPlayerView")
	if view != null:
		out.ship = view.call("get_active_ship") as Node3D
		out.contracts = view.call("get_active_contracts") as Array
		out.waypoint = _first_contract_waypoint(view, out.contracts)

	if out.ship != null and is_instance_valid(out.ship):
		out.ship_position = out.ship.global_position
		var velocity := Vector3.ZERO
		if out.ship is RigidBody3D:
			velocity = (out.ship as RigidBody3D).linear_velocity
		out._apply_kinematics(
			NavigationAxes.vessel_bow_horizontal(out.ship),
			Vector2(velocity.x, velocity.z),
			out.ship_position,
			out.waypoint
		)
		if out.ship.has_method("get_fuel_fraction"):
			out.fuel_fraction = clampf(float(out.ship.call("get_fuel_fraction")), 0.0, 1.0)

	var wind := _read_local_wind(root)
	out.wind_direction_deg = float(wind["direction_deg"])
	out.wind_speed_knots = float(wind["speed_ms"]) * MPS_TO_KNOTS
	out.time_label = _read_time(root)
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


static func _first_contract_waypoint(view: Node, active_contracts: Array) -> Vector3:
	for contract in active_contracts:
		if contract == null:
			continue
		var destination := str(contract.get("destination_port_id"))
		if destination.is_empty():
			continue
		var pos := view.call("get_port_position", destination) as Vector3
		if pos.is_finite():
			return pos
	return Vector3(INF, INF, INF)


## Isolated compatibility seam: parent weather work can replace this data source
## without changing chart snapshot consumers.
static func _read_local_wind(root: Window) -> Dictionary:
	var world_weather := root.get_node_or_null("WorldWeather")
	if world_weather == null:
		return {"direction_deg": NAN, "speed_ms": 0.0}
	var presentation := world_weather.get("local_presentation") as WeatherState
	var direction := presentation.wind_direction
	var speed_ms := presentation.wind_speed_ms
	if direction.length_squared() < 1.0e-8 or speed_ms < 0.01:
		return {"direction_deg": NAN, "speed_ms": speed_ms}
	# Meteorological wind direction is where the wind comes from.
	var from := -direction
	return {
		"direction_deg": fposmod(
			rad_to_deg(NavigationAxes.bearing_rad_world_delta(from)),
			360.0
		),
		"speed_ms": speed_ms,
	}


static func _read_time(root: Window) -> String:
	var clock := root.get_node_or_null("WorldClock")
	if clock == null:
		return "--:--"
	var day_fraction := float(clock.call("get_time_of_day"))
	var minutes := int(floor(fposmod(day_fraction, 1.0) * 1440.0))
	return "%02d:%02d" % [minutes / 60, minutes % 60]
