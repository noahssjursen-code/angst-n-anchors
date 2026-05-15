extends Node

## Central read model. Systems write here on change; UI and tools read from here.
## Never poll this every frame — connect to the signals on each sub-state instead.

var player:   PlayerState   = PlayerState.new()
var ship:     ShipState     = ShipState.new()
var contract: ContractState = ContractState.new()
var world:    WorldState    = WorldState.new()

var _wired_controllers: Array = []


func _ready() -> void:
	_wire_player_session()
	_wire_contract_registry()
	_wire_weather()
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "BoatController", true, false):
		_wire_boat_controller(n as BoatController)


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


# ── ContractRegistry ──────────────────────────────────────────────────────────

func _wire_contract_registry() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	registry.contract_accepted.connect(func(_c: Contract) -> void: _refresh_contracts())
	registry.contract_completed.connect(func(_c: Contract) -> void: _refresh_contracts())


func _refresh_contracts() -> void:
	var registry := get_node_or_null("/root/ContractRegistry")
	if registry == null:
		return
	contract.active = registry.get_accepted_contracts()


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


func _on_helm_on(bc: BoatController) -> void:
	var sd          := ShipData.new()
	sd.ship_id      = bc.get_parent().name
	sd.display_name = bc.ship_name
	sd.hull_health  = 1.0
	sd.fuel         = 1.0
	sd.cargo        = CargoManifest.new()
	ship.data       = sd


func _on_helm_off() -> void:
	ship.data = null
