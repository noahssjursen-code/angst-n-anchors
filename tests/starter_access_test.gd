extends "res://tests/coaster_access_test.gd"

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	boat = VesselSpawn.instantiate_from_record(CompanyService.build_starter_vessel_record("general_cargo"))
	boat.freeze = true
	add_child(boat)
	for component in ["StripBuoyancyComponent","HydrodynamicsComponent","PropulsionComponent","RudderComponent","BowThrusterComponent"]:
		boat.get_node(component).set_physics_process(false)
	player = preload("res://scenes/shared/player.tscn").instantiate()
	add_child(player)
	player.walk_speed = 2.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for i in 4: await get_tree().physics_frame
	for tilt in [Vector3.ZERO, Vector3(3,0,4), Vector3(-3,0,-4)]:
		boat.rotation_degrees = tilt
		boat._sync_walk_deck_transform()
		player.global_position = boat.to_global(Vector3(2.75,3.66,4.9))
		player.velocity = Vector3.ZERO
		player.rotation = Vector3.ZERO
		for i in 20: await get_tree().physics_frame
		check(player.is_on_floor(),"Cargo stair foot is reachable")
		await walk_to(Vector3(2.75,5.8,9.1),200)
		var local := boat.to_local(player.global_position)
		print("CARGO ASCENT ",tilt," ",local)
		check(local.z>8.8 and absf(local.y-5.805)<.15,"Climb cargo bridge stairs")
		await walk_to(Vector3(2.75,3.6,4.9),200)
		local = boat.to_local(player.global_position)
		print("CARGO DESCENT ",tilt," ",local)
		check(local.z<5.2 and absf(local.y-3.6)<.15,"Descend cargo stairs")
	boat.rotation = Vector3.ZERO
	boat._sync_walk_deck_transform()
	player.position = Vector3(2.75,5.86,9.1)
	player.velocity = Vector3.ZERO
	for i in 20: await get_tree().physics_frame
	await walk_to(Vector3(2.75,5.805,10.5),160)
	for i in 12: await get_tree().physics_frame
	await walk_to(Vector3(0,5.805,10.5),160)
	print("CARGO REAR ", player.position)
	check(player.position.distance_to(Vector3(0,5.805,10.5))<.3,"Walk around rear balcony to bridge door")
	for part in boat.part_roots:
		if part.get_meta("asset_id")=="cabin_door_straight" and part.position.y>5:
			part.get_node("PartState").request_door_from(player.global_position)
	for i in 60: await get_tree().physics_frame
	await walk_to(Vector3(0,5.805,8.6),160)
	print("CARGO INSIDE ", player.position)
	check(player.position.distance_to(Vector3(0,5.805,8.6))<.3,"Enter furnished bridge and approach helm")
	player.walk_speed = 4.5
	player.position = Vector3(2.75,3.66,4.9)
	player.velocity = Vector3.ZERO
	for i in 20: await get_tree().physics_frame
	await walk_to(Vector3(2.75,5.8,9.1),160)
	check(player.position.z>8.8 and absf(player.position.y-5.805)<.15,"Normal walking speed also climbs the cargo stairs")
	player.queue_free()
	boat.queue_free()
	for i in 4: await get_tree().process_frame
	if not failed: print("STARTER ACCESS PASS: actual player, tilted cargo stair ascent/descent, balcony, door and furnished helm approach")
	get_tree().quit(1 if failed else 0)
