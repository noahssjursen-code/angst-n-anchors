class_name PassengerAccommodation
extends RefCounted

## Capacity comes from supported, distinct passenger sockets, never a hull name
## or helm chair. Keys survive JSON round-trips and placement-array reordering.
static func seats(boat: ImportedDraftVessel) -> Dictionary:
	var found := {}
	var positions: Array[Vector3] = []
	for part in boat.part_roots:
		for socket: Node3D in part.find_children("PassengerSeat*", "Node3D", true, false):
			var point := boat.to_local(socket.global_position)
			var duplicate := false
			for existing in positions:
				if existing.distance_to(point) < .35: duplicate = true
			if duplicate: continue
			# Probe at the passenger's feet, clear of the seat's own base plate.
			# A ray through the chair could mistake its underside for a deck and
			# approve seating suspended in mid-air.
			var foot := socket.global_position - socket.global_basis.z * .4
			var ray := PhysicsRayQueryParameters3D.create(
				foot - boat.global_basis.y * .5,
				foot - boat.global_basis.y * .85, BoatBody.LAYER_BOAT_WALK)
			var hit := boat.get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or hit.collider.get_meta("_boat_owner", null) != boat: continue
			var key := str(part.get_meta("record_key", "")) + "/" + str(socket.name)
			found[key] = socket
			positions.append(point)
	return found

static func ramp(boat: BoatBody) -> FerryBoarding:
	return boat.find_child("FerryBoarding", true, false) as FerryBoarding

static func boarding_door(boat: ImportedDraftVessel) -> ShipPartState:
	var access := ramp(boat)
	if access == null: return null
	var nearest: ShipPartState
	var distance := 10.0
	for part in boat.part_roots:
		if part.find_children("DoorLeafPivot*", "Node3D", true, false).is_empty(): continue
		var candidate := part.get_node_or_null("PartState") as ShipPartState
		var reach := part.global_position.distance_to(access.part.global_position)
		if candidate != null and reach < distance:
			distance = reach
			nearest = candidate
	return nearest
