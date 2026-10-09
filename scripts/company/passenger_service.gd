class_name PassengerService
extends RefCounted

## Single-player passenger operations inside the existing company save/ledger.
## Route configuration is world-authoring input; booking accepts only its ID.
## Scene actors are a projection and never own passenger counts or payment.
const PERSON_WITH_LUGGAGE_KG := 90.0
var _player: PlayerData
var _company: CompanyService
var _routes := {}
var _seat_cache := {}

func bind(player: PlayerData, company: CompanyService) -> void:
	_player = player
	_company = company
	_seat_cache.clear()
	if not _player.company.get("passenger_sailings", []) is Array:
		_player.company["passenger_sailings"] = []
	_player.company.get_or_add("passenger_sailings", [])

func register_route(id: String, origin: QuayBerthSlot, destination: QuayBerthSlot,
		passengers: int, fare_marks: int) -> void:
	assert(not id.is_empty() and origin != destination and passengers > 0 and fare_marks > 0)
	_routes[id] = {"origin":weakref(origin), "destination":weakref(destination),
		"count":passengers, "fare":fare_marks}

func records() -> Array:
	return _player.company.get("passenger_sailings", []).duplicate(true)

func record(id: String) -> Dictionary:
	for item: Dictionary in _player.company.get("passenger_sailings", []):
		if str(item.id) == id: return item.duplicate(true)
	return {}

func active_for(ship: BoatBody) -> Dictionary:
	var uid := str(ship.get_meta("vessel_uid", ""))
	for item: Dictionary in _player.company.get("passenger_sailings", []):
		if item.vessel_uid == uid and item.phase not in ["completed", "cancelled"]:
			return item.duplicate(true)
	return {}

func book(route_id: String, ship: ImportedDraftVessel, request_id: String) -> Dictionary:
	if request_id.is_empty(): return _error("request_required", "Missing booking reference.")
	var prior := record(request_id)
	if not prior.is_empty():
		if prior.route_id != route_id or prior.vessel_uid != str(ship.get_meta("vessel_uid", "")):
			return _error("request_conflict", "That booking reference belongs to another sailing.")
		return CompanyContracts.result_ok(prior)
	var uid := str(ship.get_meta("vessel_uid", ""))
	if uid.is_empty() or _player.find_owned_vessel(uid).is_empty():
		return _error("not_owned", "Deploy a vessel owned by this company.")
	if not active_for(ship).is_empty(): return _error("vessel_busy", "Finish or cancel this vessel's sailing first.")
	if not _routes.has(route_id): return _error("route_missing", "This passenger route is unavailable.")
	var route: Dictionary = _routes[route_id]
	var origin := (route.origin as WeakRef).get_ref() as QuayBerthSlot
	var destination := (route.destination as WeakRef).get_ref() as QuayBerthSlot
	if not is_instance_valid(origin) or not is_instance_valid(destination):
		return _error("terminal_unavailable", "Both passenger terminals must be available.")
	if not _secured(ship, origin.berth_id): return _error("wrong_terminal", "Secure both lines at the departure terminal.")
	if PassengerAccommodation.ramp(ship) == null or PassengerAccommodation.boarding_door(ship) == null:
		return _error("boarding_missing", "Fit a passenger ramp and saloon entrance.")
	var seats := _seats(ship)
	if seats.size() < int(route.count): return _error("capacity", "Not enough supported passenger seats for this sailing.")
	var keys := seats.keys(); keys.sort()
	var selected: Array = keys.slice(0, int(route.count))
	var positions := {}
	var yaws := {}
	for key: String in selected:
		var local := ship.to_local((seats[key] as Node3D).global_position)
		positions[key] = [local.x, local.y, local.z]
		yaws[key] = (ship.global_basis.inverse()*(seats[key] as Node3D).global_basis).get_euler().y
	var item := {"id":request_id, "route_id":route_id, "vessel_uid":uid,
		"origin_berth":origin.berth_id, "destination_berth":destination.berth_id,
		"total":selected.size(), "onboard":0, "landed":0, "returned":0,
		"seat_ids":selected, "seat_positions":positions, "seat_yaws":yaws, "fare_marks":int(route.fare),
		"phase":"boarding", "paid_marks":0}
	_player.company.passenger_sailings.append(item)
	return CompanyContracts.result_ok(item)

func begin_alighting(id: String, ship: ImportedDraftVessel) -> Dictionary:
	var item := record(id)
	var problem := _vessel_error(item, ship)
	if not problem.is_empty(): return problem
	if item.phase in ["alighting", "completed"]: return CompanyContracts.result_ok(item)
	if item.phase != "underway": return _error("not_underway", "Complete boarding and depart before arrival.")
	if not _secured(ship, item.destination_berth): return _error("wrong_terminal", "Secure the ferry at its booked destination.")
	item.phase = "alighting"
	_store(item)
	return CompanyContracts.result_ok(item)

func cancel(id: String, ship: ImportedDraftVessel) -> Dictionary:
	var item := record(id)
	var problem := _vessel_error(item, ship)
	if not problem.is_empty(): return problem
	if item.phase == "cancelled": return CompanyContracts.result_ok(item)
	if item.phase == "completed": return _error("already_completed", "This sailing has already been completed.")
	if not _secured(ship, item.origin_berth): return _error("return_to_origin", "Return to the departure terminal to cancel and land passengers.")
	item.phase = "returning" if int(item.onboard)>0 else "cancelled"
	_store(item)
	return CompanyContracts.result_ok(item)

## Called by the local vessel component at a bounded passenger-transfer cadence.
## Every increment rechecks the physical berth/ramp/door; interruptions pause.
func advance(id: String, ship: ImportedDraftVessel) -> String:
	var item := record(id)
	var problem := _vessel_error(item, ship)
	if not problem.is_empty(): return str(problem.message)
	if item.phase in ["completed", "cancelled"]: return str(item.phase).capitalize()
	if item.phase == "ready" and ship.get_moored_berth() == null:
		if not ship.departure_block_reason().is_empty(): return "Secure boarding equipment before departure"
		item.phase = "underway"; _store(item)
		return "Underway"
	if item.phase in ["ready", "underway"]: return str(item.phase).capitalize()
	var berth: String = item.destination_berth if item.phase == "alighting" else item.origin_berth
	if not _secured(ship, berth): return "Secure both lines at the booked terminal"
	var ramp := PassengerAccommodation.ramp(ship)
	if ramp == null or not ramp.deployed: return "Waiting for a safe boarding ramp"
	var door := PassengerAccommodation.boarding_door(ship)
	if door == null or door.current_door < .95: return "Open the passenger entrance"
	if item.phase == "boarding":
		var seats := _seats(ship)
		for key: String in item.seat_ids:
			if not seats.has(key): return "Passenger seating changed; restore it or cancel this sailing"
		item.onboard = int(item.onboard)+1
		if int(item.onboard) == int(item.total): item.phase = "ready"
	elif int(item.onboard) > 0:
		item.onboard = int(item.onboard)-1
		if item.phase == "returning": item.returned = int(item.returned)+1
		else: item.landed = int(item.landed)+1
	if int(item.onboard) == 0 and item.phase == "returning": item.phase = "cancelled"
	# Store before payment, then settle in the same synchronous mutation. A
	# restored zero-onboard/alighting record retries the stable ledger reference.
	_store(item)
	if int(item.onboard) == 0 and item.phase == "alighting":
		if int(item.landed) != int(item.total): return "Passenger manifest is incomplete"
		var amount := int(item.total)*int(item.fare_marks)
		# The generic request cache is bounded. The ledger remains the durable
		# receipt even after many other company commands evict that cache entry.
		var paid := {}
		for entry: Dictionary in _player.company.account.get("ledger", []):
			if entry.get("request_id", "") == "passenger-fare:"+id:
				paid = CompanyContracts.result_ok(entry)
				break
		if paid.is_empty():
			paid = _company.post_transaction({"request_id":"passenger-fare:"+id,
				"amount_marks":amount, "category":"passenger_fares", "related_entity_id":id,
				"description":"Passenger sailing: "+str(item.route_id), "count_as_earned":true})
		if not bool(paid.get("ok",false)): return str(paid.get("message","Fare settlement failed"))
		item.phase = "completed"; item.paid_marks = amount; _store(item)
	return str(item.phase).capitalize()

func departure_reason(ship: ImportedDraftVessel) -> String:
	var item := active_for(ship)
	if item.is_empty(): return ""
	if item.phase not in ["ready", "underway"]: return "Finish passenger boarding or disembarkation before departure."
	var seats := _seats(ship)
	for key: String in item.seat_ids:
		if not seats.has(key): return "Restore the booked passenger seats before departure."
	var door := PassengerAccommodation.boarding_door(ship)
	if door == null or door.current_door > .01: return "Close the passenger entrance before departure."
	return ""

func restore_mass(ship: ImportedDraftVessel) -> void:
	var item := active_for(ship)
	if item.is_empty() or int(item.onboard) == 0:
		ship.remove_mass_entry("passenger_manifest")
		return
	var center := Vector3.ZERO
	# Boarding fills a deterministic seat allocation. Alighting empties it from
	# the back; positions remain in the manifest if a later refit removes a seat.
	for key: String in (item.seat_ids as Array).slice(0,int(item.onboard)):
		var point: Array = item.seat_positions[key]
		center += Vector3(point[0],point[1],point[2])
	center /= int(item.onboard)
	ship.set_mass_entry("passenger_manifest",int(item.onboard)*PERSON_WITH_LUGGAGE_KG,center,"passengers")

func _secured(ship: BoatBody, berth_id: String) -> bool:
	var slot := ship.get_moored_berth() as QuayBerthSlot
	var lines := ship.get_node_or_null("ShipGameplay/MooringComponent") as MooringComponent
	return slot != null and slot.berth_id == berth_id and lines != null and lines.bow_line_tied and lines.stern_line_tied and ship.linear_velocity.length()<.4

func _seats(ship: ImportedDraftVessel) -> Dictionary:
	var id := ship.get_instance_id()
	var cached: Dictionary = _seat_cache.get(id, {})
	if cached.get("revision", -1) != ship.fitout_revision:
		cached = {"revision":ship.fitout_revision, "seats":PassengerAccommodation.seats(ship)}
		_seat_cache[id] = cached
	return cached.seats

func _vessel_error(item: Dictionary, ship: ImportedDraftVessel) -> Dictionary:
	if item.is_empty(): return _error("sailing_missing", "Passenger sailing not found.")
	var uid := str(ship.get_meta("vessel_uid", ""))
	if item.vessel_uid != uid or _player.find_owned_vessel(uid).is_empty():
		return _error("wrong_vessel", "This sailing belongs to another vessel.")
	return {}

func _store(item: Dictionary) -> void:
	var sailings: Array = _player.company.passenger_sailings
	for i in sailings.size():
		if sailings[i].id == item.id:
			sailings[i] = item
			return

func _error(code: String, message: String) -> Dictionary:
	return CompanyContracts.result_error(code,message)
