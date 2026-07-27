extends Node

## Central read model. Systems write here on change; UI and tools read from here.
## Never poll this every frame — connect to the signals on each sub-state instead.

var player:   PlayerState   = PlayerState.new()
var ship:     ShipState     = ShipState.new()
var contract: ContractState = ContractState.new()
var world:    WorldState    = WorldState.new()

var _wired_controllers: Array = []
var _active_controller: BoatController
var _active_boat: BoatBody
var _instrument_elapsed := 0.0
const INSTRUMENT_REFRESH_S := 0.05


func _ready() -> void:
	_wire_player_session()
	_wire_weather()
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "BoatController", true, false):
		_wire_boat_controller(n as BoatController)


func _process(delta: float) -> void:
	if _active_controller == null or _active_boat == null:
		return
	if not is_instance_valid(_active_controller) or not is_instance_valid(_active_boat):
		_on_helm_off()
		return
	_instrument_elapsed += delta
	if _instrument_elapsed < INSTRUMENT_REFRESH_S:
		return
	_instrument_elapsed = 0.0
	ship.publish_instruments(_capture_instruments())


# ── PlayerSession ─────────────────────────────────────────────────────────────

func _wire_player_session() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return
	player.marks        = session.get_marks()
	player.display_name = session.data.display_name
	session.marks_changed.connect(func(bal: int) -> void:
		player.marks = bal
	)
	session.data_loaded.connect(func(d: PlayerData) -> void:
		player.marks        = d.marks
		player.display_name = d.display_name
	)
	contract.active = []


# ── WeatherLighting ───────────────────────────────────────────────────────────

func _wire_weather() -> void:
	var wl := get_node_or_null("/root/WeatherLighting")
	if wl == null:
		return
	wl.state_changed.connect(_refresh_weather)
	_refresh_weather()


func _refresh_weather() -> void:
	var wl := get_node_or_null("/root/WeatherLighting") as WeatherLightingState
	if wl == null:
		return
	var wind := wl.wind_force
	var rain := wl.precipitation
	if wind >= 0.7 and rain >= 0.7:
		world.weather_label = "Full Gale"
	elif wind >= 0.5:
		world.weather_label = "Strong Wind"
	elif rain >= 0.5:
		world.weather_label = "Heavy Rain"
	elif wind >= 0.2 or rain >= 0.2:
		world.weather_label = "Overcast"
	elif wind < 0.1 and rain < 0.1:
		world.weather_label = "Clear / Calm"
	else:
		world.weather_label = "Light Breeze"


# ── BoatController ────────────────────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if node is BoatController:
		_wire_boat_controller(node as BoatController)


func _wire_boat_controller(bc: BoatController) -> void:
	if _wired_controllers.has(bc):
		return
	_wired_controllers.append(bc)
	bc.helm_activated.connect(func() -> void: _on_helm_on(bc))
	bc.helm_deactivated.connect(_on_helm_off)
	_wire_mooring.call_deferred(bc)


func _on_helm_on(bc: BoatController) -> void:
	var sd          := ShipData.new()
	sd.ship_id      = bc.get_parent().name
	sd.display_name = bc.ship_name
	sd.hull_health  = 1.0
	sd.fuel         = 1.0
	ship.data       = sd
	_active_controller = bc
	_active_boat = bc.get_parent() as BoatBody
	_instrument_elapsed = INSTRUMENT_REFRESH_S
	if _active_boat != null:
		ship.publish_instruments(_capture_instruments())


func _on_helm_off() -> void:
	ship.data = null
	ship.clear_instruments()
	_active_controller = null
	_active_boat = null


func _wire_mooring(controller: BoatController) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var boat := controller.get_parent() as BoatBody
	if boat == null:
		return
	var mooring := boat.get_node_or_null("ShipGameplay/MooringComponent") as MooringComponent
	if mooring != null and not mooring.mooring_rejected.is_connected(_on_ship_notice):
		mooring.mooring_rejected.connect(_on_ship_notice)


func _on_ship_notice(message: String) -> void:
	ship.push_notice(message)


func _capture_instruments() -> Dictionary:
	if _active_boat == null or _active_controller == null:
		return {}
	var boat := _active_boat
	var controller := _active_controller
	var bow := NavigationAxes.vessel_bow_horizontal(boat)
	var velocity := boat.linear_velocity
	var heading_deg := NavigationAxes.heading_deg_horizontal(bow)
	var throttle_values := controller.throttle_stage_values
	var throttle_index := controller.get_throttle_stage_idx()
	var throttle_value := (
		float(throttle_values[clampi(throttle_index, 0, throttle_values.size() - 1)])
		if not throttle_values.is_empty()
		else 0.0
	)
	var autopilot := controller.get_autopilot()
	var autopilot_active := autopilot != null and autopilot.is_engaged()
	if autopilot_active:
		throttle_value = autopilot.cruise_throttle
	var target_bearing := NAN
	var destination_name := ""
	var remaining_distance_m := 0.0
	if autopilot_active and autopilot.target_point.is_finite():
		var target_delta := Vector3(
			autopilot.target_point.x - boat.global_position.x,
			0.0,
			autopilot.target_point.y - boat.global_position.z
		)
		target_bearing = fposmod(
			rad_to_deg(NavigationAxes.bearing_rad_world_delta(target_delta)),
			360.0
		)
	if autopilot != null and autopilot.route != null:
		var destination_id := autopilot.route.destination_port_id
		var catalog := get_node_or_null("/root/PortCatalog")
		destination_name = (
			str(catalog.get_port_display_name(destination_id))
			if catalog != null
			else destination_id
		)
		remaining_distance_m = autopilot.remaining_distance_m()
	var lighting := boat.get_node_or_null("ShipLighting")
	var lights := (
		str(lighting.get_preset_name())
		if lighting != null and lighting.has_method("get_preset_name")
		else "OFF"
	)
	var watch_snapshot: Dictionary = {}
	var watch := boat.get_node_or_null("BridgeWatchAlarm") as BridgeWatchAlarm
	if watch != null:
		watch_snapshot = watch.snapshot()
	var fishing_snapshot: Dictionary = {}
	var fishing_systems := boat.get_fishing_systems()
	if not fishing_systems.is_empty():
		var fishing: FishingSystem = fishing_systems[0]
		fishing_snapshot["status"] = fishing.get_activity_status()
		var catch_hold := fishing.get_catch_hold()
		if catch_hold != null:
			var catch_state := catch_hold.get_state()
			fishing_snapshot["mass_t"] = catch_state.total_mass_kg() / 1000.0
			fishing_snapshot["capacity_t"] = catch_state.capacity_kg / 1000.0
	var weather := get_node_or_null("/root/WorldWeather")
	var wind_direction := Vector3.ZERO
	var wind_speed_ms := 0.0
	if weather != null:
		var presentation := weather.get("local_presentation") as WeatherState
		if presentation != null:
			wind_direction = presentation.wind_direction
			wind_speed_ms = presentation.wind_speed_ms
	var clock := get_node_or_null("/root/WorldClock")
	var time_hours := float(clock.get_time_of_day()) * 24.0 if clock != null else 0.0
	return {
		"position": boat.global_position,
		"bow": bow,
		"velocity": velocity,
		"heading_deg": heading_deg,
		"speed_knots": velocity.length() * 1.943844,
		"fuel_fraction": boat.get_fuel_fraction(),
		"throttle_values": Array(throttle_values),
		"throttle_index": throttle_index,
		"throttle_value": throttle_value,
		"thruster_mode": controller.get_thruster_mode(),
		"lights": lights,
		"autopilot_active": autopilot_active,
		"target_bearing_deg": target_bearing,
		"destination_name": destination_name,
		"remaining_distance_m": remaining_distance_m,
		"bridge_watch": watch_snapshot,
		"fishing": fishing_snapshot,
		"wind_direction": wind_direction,
		"wind_speed_ms": wind_speed_ms,
		"time_hours": time_hours,
	}
