class_name PassengerOperations
extends Node

## World-owned single-player service; the company manifest is the durable truth.
## Terminal metadata never instantiates a distant port or vessel.
var service := PassengerService.new()
var terminals: Dictionary = {}
var _bound: PlayerData
var _last_phase: Dictionary = {}
var siting_usec := 0

func _ready() -> void:
	add_to_group("passenger_operations")
	_bind(PlayerSession.data)
	PlayerSession.data_loaded.connect(_bind)
	get_tree().node_added.connect(_node_added)

static func current(tree: SceneTree) -> PassengerOperations:
	return tree.get_first_node_in_group("passenger_operations") as PassengerOperations

func _bind(data: PlayerData) -> void:
	_bound = data
	service.bind(data, PlayerSession.company_service)

func register_port(data: PortData, layout: WorldLayout) -> void:
	var started := Time.get_ticks_usec()
	var frame := Transform3D(Basis(Vector3.UP, data.rotation_y), data.world_position)
	var site := PassengerPortSites.plan(data.layout_graph, frame, layout)
	siting_usec += Time.get_ticks_usec() - started
	if site.is_empty(): return
	terminals[data.port_id] = {"name": data.display_name, "position": data.world_position,
		"berth": data.port_id + "/passenger"}

func _node_added(node: Node) -> void:
	if node is ImportedDraftVessel: _attach.call_deferred(weakref(node))

func _attach(reference: WeakRef) -> void:
	var ship := reference.get_ref() as ImportedDraftVessel
	if ship == null or not ship.is_inside_tree() or not ship.is_in_group(PlayerVessel.GROUP): return
	if _bound.find_owned_vessel(str(ship.get_meta("vessel_uid", ""))).is_empty(): return
	if PassengerAccommodation.ramp(ship) == null: return
	if ship.get_node_or_null("PassengerVoyage") != null: return
	var voyage := PassengerVoyage.new()
	voyage.name = "PassengerVoyage"
	voyage.setup(ship, service)
	voyage.changed.connect(_voyage_changed)
	ship.add_child(voyage)

func _voyage_changed(item: Dictionary, _status: String) -> void:
	var id := str(item.id)
	if _last_phase.get(id, "") == item.phase: return
	_last_phase[id] = item.phase
	PlayerSession.save_now()
	if item.phase == "ready": _notify("All passengers aboard. Close the entrance and stow the ramp before casting off.")
	if item.phase == "completed":
		PlayerSession.marks_changed.emit(_bound.marks)
		_notify("Passengers landed · " + PlayerData.format_money(int(item.paid_marks)) + " received.")

func _notify(message: String) -> void:
	var menu := get_node_or_null("/root/GameMenu")
	if menu != null and menu.has_method("notify"): menu.call("notify", message)

func offers(port_id: String, ship: ImportedDraftVessel) -> Array:
	if ship == null or not terminals.has(port_id): return []
	var count := mini(service.capacity(ship), 240)
	if count == 0: return []
	var nearby: Array = terminals.keys()
	nearby.erase(port_id)
	var origin: Vector3 = terminals[port_id].position
	nearby.sort_custom(func(a: String, b: String):
		var da: float = origin.distance_squared_to(terminals[a].position)
		var db: float = origin.distance_squared_to(terminals[b].position)
		return a < b if is_equal_approx(da, db) else da < db)
	var result: Array = []
	for destination: String in nearby.slice(0, 3):
		var distance: float = origin.distance_to(terminals[destination].position)
		var fare := clampi(50 + int(distance / 1000.0 * 4.0), 50, 200)
		var id := "passenger:%s:%s:%d" % [port_id, destination, count]
		service.register_route_ids(id, terminals[port_id].berth, terminals[destination].berth, count, fare)
		result.append({"id": id, "destination": destination, "name": terminals[destination].name,
			"count": count, "fare": fare, "distance_m": distance})
	return result

static func storage_reason(ship: BoatBody) -> String:
	if ship == null: return ""
	var operations := current(ship.get_tree())
	if operations != null and not operations.service.active_for(ship).is_empty():
		return "Finish the passenger sailing, or return to its departure terminal and cancel it, before storing this ferry."
	return ""

## Passage guidance stays attached to the booked vessel and terminal. Berthing
## remains manual; the ordinary autopilot hands over outside the passenger pier.
func navigation_order(ship: BoatBody) -> Dictionary:
	var item := service.active_for(ship)
	if item.is_empty() or item.phase not in ["ready", "underway"]: return {}
	var destination := str(item.destination_berth).trim_suffix("/passenger")
	if not terminals.has(destination): return {}
	return {"destination_port_id": destination, "destination_berth_id": item.destination_berth,
		"origin_port_id": str(item.origin_berth).trim_suffix("/passenger"),
		"berth_id": item.origin_berth, "passenger": true}

func voyage_snapshot(ship: BoatBody) -> Dictionary:
	if ship == null or ship.get_node_or_null("PassengerVoyage") == null: return {}
	var item := service.active_for(ship)
	if item.is_empty():
		return {"objective": "Speak to the passenger terminal agent to book a sailing.", "manifest": {}}
	var destination := str(item.destination_berth).trim_suffix("/passenger")
	var destination_name := str(terminals.get(destination, {}).get("name", destination))
	var objective := ""
	match str(item.phase):
		"boarding": objective = "Boarding for %s: %d / %d aboard. Keep both lines secured, the ramp down and the entrance open." % [destination_name, item.onboard, item.total]
		"ready": objective = "Ready for %s. Cast off, back clear of the pier and turn seaward before engaging passage autopilot." % destination_name
		"underway":
			objective = "Take %d passengers to %s. Moor at its passenger terminal and ask the agent to land them." % [item.onboard, destination_name]
		"alighting": objective = "Landing at %s: %d / %d ashore. Keep the boarding access open." % [destination_name, item.landed, item.total]
		"returning": objective = "Cancelling sailing: %d passengers still aboard. Keep the boarding access open." % item.onboard
	return {"objective": objective, "manifest": item, "destination": destination_name}
