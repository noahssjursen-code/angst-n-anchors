extends Node

const PotWork = preload("res://scripts/ship/crab_pot_work.gd")

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest")
	_timing()
	call_deferred("_boats")


func _timing() -> void:
	var work := PotWork.new()
	work.begin_carry()
	assert(work.hands_bound())
	var steps := 0
	var settled := false
	while not settled and steps < 40:
		settled = work.advance_carry(0.05)
		steps += 1
	assert(settled, "The grab settles into the hands")
	assert(steps > 8 and steps < 30, "Grabbing is a short motion, not a held wait")
	work.begin_throw(20.0)
	assert(work.hands_bound())
	steps = 0
	while work.phase == PotWork.Phase.THROWING and steps < 40:
		work.advance_throw(0.05)
		if work.phase == PotWork.Phase.THROWING and work.progress > PotWork.RELEASE_AT:
			assert(not work.hands_bound(), "Hands let go before the trap hits the water")
		steps += 1
	assert(work.phase == PotWork.Phase.SINKING)
	assert(steps > 8 and steps < 20, "The throw is a short toss")
	assert(not work.hands_bound(), "Hands let go as the trap leaves")
	work.cancel()
	assert(work.phase == PotWork.Phase.STOWED)


func _boats() -> void:
	var line := _boat("res://resources/data/vessels/prebuilt/fishing_hook_line.json")
	add_child(line)
	await get_tree().physics_frame
	assert(line.get_node_or_null("CrabPotStation") == null, "The line boat is not a crabber")
	line.queue_free()
	await get_tree().physics_frame
	var boat := _boat("res://resources/data/vessels/prebuilt/fishing_crab.json")
	add_child(boat)
	boat.freeze = true
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	boat.freeze = true
	PlayerVessel.mark_player_ship(boat)
	for _i in 4:
		await get_tree().physics_frame
	var station = boat.get_node("CrabPotStation")
	station.manual = true
	station.forced_depth = 20.0
	assert(station.slot_count() == 12, "The crabber's twelve creels are the trap capacity")
	var creel := station._slots[0].creel as Node3D
	assert(creel.find_child("LeftHandle", true, false) != null)
	assert(creel.find_child("RightHandle", true, false) != null)
	assert(station.begin_grab(0), station._message)
	station.advance(0.05)
	assert(station.phase_of(0) == PotWork.Phase.CARRYING)
	assert(not station.begin_grab(1), "One trap in the hands at a time")
	var slot: Dictionary = station._slots[0]
	var rest: Transform3D = slot.rest
	station.cancel_carry(0)
	assert(station.phase_of(0) == PotWork.Phase.STOWED)
	assert(not creel.top_level)
	assert(creel.transform.origin.is_equal_approx(rest.origin))
	assert(station.begin_grab(0))
	var steps := 0
	while station.phase_of(0) != PotWork.Phase.SINKING and steps < 80:
		station.advance(0.05)
		steps += 1
	assert(station.phase_of(0) == PotWork.Phase.SINKING, station.hint())
	assert(steps > 10 and steps < 40, "Grab and throw finish without a long hold")
	var thrown: Vector2 = slot.drop_xz
	var marker: Vector3 = station._marker_position(slot.buoy)
	assert(Vector2(marker.x, marker.z).distance_to(thrown) < 1.5, "The buoy floats at the throw while the trap sinks")
	assert(not station.begin_grab(0), "A trap in the water is not still on deck")
	steps = 0
	while station.phase_of(0) == PotWork.Phase.SINKING and steps < 500:
		station.advance(0.05)
		steps += 1
	assert(station.phase_of(0) == PotWork.Phase.DEPLOYED)
	assert(steps > 40, "The trap takes time to sink after it is thrown")
	var field = preload("res://scripts/ship/deployed_crab_pots.gd").ensure(get_tree())
	var gear: Dictionary = field.gear(str(slot.pot_id))
	assert(not gear.is_empty(), "A set trap is recorded outside the hull")
	assert((gear.buoy as Node3D).visible)
	var drop: Vector2 = slot.drop_xz
	var bed := WaveSurface.sample_at(drop.x, drop.y).height - 20.0
	var water_creel := gear.creel as Node3D
	assert(absf(water_creel.global_position.y - bed) < 1.5, "The pot rests on the seabed")
	assert(not creel.visible, "The deck creel stays aboard while its trap is in the water")
	assert(station.phase_of(1) == PotWork.Phase.STOWED)
	assert(not station.begin_haul(0), "A trap soaks until the next day")
	assert(station.hint().to_lower().contains("soaking"))
	var first_id := str(slot.pot_id)
	WorldClock.set_game_hours_elapsed(float(slot.ready_hours) + 0.05)
	assert(station.begin_haul(0))
	assert(not station.begin_grab(2), "The hauler works one pot at a time")
	steps = 0
	while station.phase_of(0) != PotWork.Phase.STOWED and steps < 500:
		station.advance(0.05)
		steps += 1
	assert(station.phase_of(0) == PotWork.Phase.STOWED)
	assert(steps > 40, "Hauling takes time without holding the key")
	assert(not (slot.buoy as Node3D).visible)
	assert(creel.transform.origin.is_equal_approx(rest.origin))
	assert(not bool(field.has_pot(first_id)), "Hauling clears the world record")
	assert(station.begin_grab(0))
	steps = 0
	while station.phase_of(0) != PotWork.Phase.DEPLOYED and steps < 600:
		station.advance(0.05)
		steps += 1
	assert(station.phase_of(0) == PotWork.Phase.DEPLOYED)
	var pot_id := str(slot.pot_id)
	var kept: Vector2 = slot.drop_xz
	assert(bool(field.has_pot(pot_id)))
	boat.free()
	await get_tree().process_frame
	assert(bool(field.has_pot(pot_id)), "Recalling the crabber leaves the trap in the water")
	var still: Dictionary = field.gear(pot_id)
	var stayed := (still.buoy.get_meta("marker") as Node3D).global_position
	assert(Vector2(stayed.x, stayed.z).distance_to(kept) < 1.5, "The buoy stays where it was set")
	var returned := _boat("res://resources/data/vessels/prebuilt/fishing_crab.json")
	var again = returned.get_node("CrabPotStation")
	again.manual = true
	again.forced_depth = 20.0
	add_child(returned)
	returned.freeze = true
	returned.place_at_waterline(WaveSurface.WATER_LEVEL)
	returned.freeze = true
	PlayerVessel.mark_player_ship(returned)
	assert(again.phase_of(0) == PotWork.Phase.DEPLOYED, "The returned crabber picks up its own traps")
	assert(not again.begin_haul(0), "The soak keeps running while the other boat is out")
	WorldClock.set_game_hours_elapsed(float(field.ready_hours(pot_id)) + 0.05)
	assert(again.begin_haul(0))
	steps = 0
	while again.phase_of(0) != PotWork.Phase.STOWED and steps < 500:
		again.advance(0.05)
		steps += 1
	assert(again.phase_of(0) == PotWork.Phase.STOWED)
	assert(not bool(field.has_pot(pot_id)))
	print("CRAB POT PASS: grab, throw, unattended sink, timed haul, twelve creels, line boat excluded")
	get_tree().quit()


func _boat(path: String) -> ImportedDraftVessel:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var boat := ImportedDraftVessel.new()
	boat.configure(data.get("brick_layout", data))
	return boat
