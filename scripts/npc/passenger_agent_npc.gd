class_name PassengerAgentNpc
extends NpcInteractable

var port_id := ""

func _ready() -> void:
	appearance = CharacterCatalog.appearance_preset("shipping_manager")
	prompt_text = "Press F — Passenger terminal"
	super._ready()

func _on_interact() -> void:
	PassengerTerminalPanel.open(self)

func snapshot() -> Dictionary:
	var result := {"port": PortCatalog.get_port_display_name(port_id), "offers": [],
		"manifest": {}, "status": "Deploy a passenger ferry at this terminal.", "can_arrive": false,
		"can_cancel": false, "can_board": false}
	var operations := PassengerOperations.current(get_tree())
	var ship := PlayerVessel.find_active_ship(get_tree()) as ImportedDraftVessel
	if operations == null or ship == null: return result
	var item := operations.service.active_for(ship)
	var berth_id := port_id + "/passenger"
	var secured := operations.service.secured_at(ship, berth_id)
	result.manifest = item
	if item.is_empty():
		if secured:
			result.offers = operations.offers(port_id, ship)
			result.status = "Choose a destination. Boarding requires both mooring lines, the bow ramp and an open passenger entrance."
		return result
	result.destination = PortCatalog.get_port_display_name(str(item.destination_berth).trim_suffix("/passenger"))
	var voyage := ship.get_node_or_null("PassengerVoyage") as PassengerVoyage
	result.status = voyage.status if voyage != null else str(item.phase).capitalize()
	result.can_arrive = secured and item.destination_berth == berth_id and item.phase == "underway"
	result.can_cancel = secured and item.origin_berth == berth_id and item.phase != "returning"
	result.can_board = secured and ((item.origin_berth == berth_id and item.phase in ["boarding", "returning"])
		or (item.destination_berth == berth_id and item.phase == "alighting"))
	if result.can_board:
		var ramp := PassengerAccommodation.ramp(ship)
		var door := PassengerAccommodation.boarding_door(ship)
		result.can_board = ramp == null or not ramp.deployed or door == null or door.current_door < .95
	return result

func request(action: String, id: String = "", request_id: String = "") -> Dictionary:
	if _nearest_player() == null:
		return CompanyContracts.result_error("out_of_reach", "Return to the passenger terminal agent.")
	var operations := PassengerOperations.current(get_tree())
	var ship := PlayerVessel.find_active_ship(get_tree()) as ImportedDraftVessel
	if operations == null or ship == null:
		return CompanyContracts.result_error("no_ferry", "Deploy a passenger ferry here first.")
	var state := snapshot()
	var result: Dictionary
	match action:
		"book":
			var offered := false
			for offer: Dictionary in state.offers:
				if offer.id == id: offered = true
			# A duplicate request is safe, but another terminal cannot create it.
			var previous := operations.service.record(request_id)
			if not offered and not (previous.get("route_id", "") == id and previous.get("origin_berth", "") == port_id + "/passenger"):
				return CompanyContracts.result_error("offer_expired", "This sailing is no longer offered here.")
			result = operations.service.book(id, ship, request_id)
		"arrive":
			if not state.can_arrive: return _not_ready()
			result = operations.service.begin_alighting(state.manifest.id, ship)
		"cancel":
			if not state.can_cancel: return _not_ready()
			result = operations.service.cancel(state.manifest.id, ship)
		"boarding_access":
			if not state.can_board: return _not_ready()
			result = CompanyContracts.result_ok({})
		_:
			return _not_ready()
	if result.get("ok", false):
		# Equipment still performs its own berth, alignment and motion checks.
		var ramp := PassengerAccommodation.ramp(ship)
		var door := PassengerAccommodation.boarding_door(ship)
		if ramp != null: ramp.request_boarding()
		if door != null: door.request("door_open", true)
		PlayerSession.save_now()
	return result

func _not_ready() -> Dictionary:
	return CompanyContracts.result_error("not_ready", "Secure the ferry with both lines at the correct passenger terminal.")
