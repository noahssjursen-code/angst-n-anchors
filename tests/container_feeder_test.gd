extends "res://tests/coaster_access_test.gd"
## Stock spawn + real cargo components, moving stern gear and actual player stairs.
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	if DisplayServer.get_name() == "headless":
		push_error("Run container_feeder_test with rendering: the real player requires captured mouse input.")
		get_tree().quit(2)
		return
	Engine.time_scale=4
	Engine.physics_ticks_per_second=240
	Engine.max_physics_steps_per_frame=32
	var preset: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/container_feeder_40.json"))
	var record := VesselSpawn.normalize_record({"uid":"feeder-test","name":preset.name,"hull_id":preset.hull_id,"brick_layout":preset.brick_layout})
	check(ImportedVesselLayout.valid(preset.brick_layout,preset.hull_id,true),"Valid editable stock layout")
	var data := PlayerData.new()
	data.upsert_owned_vessel(record)
	data.set_active_vessel(record)
	var restored := PlayerData.from_dict(JSON.parse_string(JSON.stringify(data.to_dict())))
	check(PlayerData.json_equivalent(restored.active_vessel.brick_layout,record.brick_layout),"Full fitout survives captain save roundtrip")
	boat = VesselSpawn.instantiate_from_record(restored.active_vessel)
	boat.freeze = true
	add_child(boat)
	for component in ["StripBuoyancyComponent","HydrodynamicsComponent","PropulsionComponent","RudderComponent","BowThrusterComponent"]:
		boat.get_node(component).set_physics_process(false)
	for i in 4: await get_tree().physics_frame
	check(boat.part_roots.size()==preset.brick_layout.parts.size(),"All placements spawn")
	var pads := boat.get_cargo_pads()
	check(pads.size()==40,"Forty actual deck pads")
	var empty_mass := boat.mass
	for i in pads.size():
		var pad := pads[i]
		check(pad.get_max_slots()==1,"One ISO unit per foundation")
		check(pad.add_container(ContainerUnit.create("feeder-load-%d" % i,"provisions",20000))>=0,"Load cargo bed %d" % i)
		check(pad.global_position.y>=5.6,"Cargo above deck")
		check(pad.find_free_slot()<0,"Full bed excluded by crane API")
		check(pad.iter_container_nodes().size()==1,"Crane discovers the real unit")
	check(absf(boat.mass-empty_mass-800000)<10,"Forty 20-tonne units add 800 tonnes")
	for pad in pads:
		var node := pad.iter_container_nodes()[0]
		var detached := pad.take_container_node(node)
		check(detached!=null and pad.find_free_slot()>=0,"Crane can lift and free pad")
		node.queue_free()
	check(absf(boat.mass-empty_mass)<10,"Unloading removes all cargo mass")
	var drive := boat.get_node("HullVisual/DriveGear") as ShipDriveVisual
	drive.local_boat = null
	drive.apply_snapshot({"throttle":.7,"steering":.6,"powered":true},100)
	var angle := drive.propeller.rotation.z
	drive._process(.1)
	check(not is_equal_approx(angle,drive.propeller.rotation.z) and absf(drive.rudder.rotation.y)>.1,"Propeller and rudder move about their authored pivots")
	check(boat.get_bridge_stations().size()>0,"Usable helm interaction")
	check(boat.gangway!=null,"Boarding gangway installed")
	print("FEEDER CARGO/SAVE PASS mass_empty=",empty_mass," loaded=",empty_mass+800000)
	# Headroom, landings and door must work with the real capsule/controller.
	player=preload("res://scenes/shared/player.tscn").instantiate()
	add_child(player)
	player.walk_speed=2.0
	player.position=Vector3(4.5,5.68,32.7)
	for i in 20: await get_tree().physics_frame
	await walk_to(Vector3(4.5,7.805,42.5),700)
	check(player.position.z>42.1 and absf(player.position.y-7.805)<.16,"Ascend deck-to-gallery stairs and reach aft landing")
	print("FEEDER STAIR 1 ",player.position)
	await walk_to(Vector3(-4.5,7.805,42.5),360)
	await walk_to(Vector3(-4.5,10.005,38.5),700)
	check(player.position.z<38.8 and player.position.y>9.5,"Ascend gallery-to-bridge stairs with clear headroom")
	print("FEEDER STAIR 2 ",player.position)
	for part in boat.part_roots:
		if part.get_meta("asset_id")=="cabin_door_straight" and part.position.y>9:
			part.get_node("PartState").request_door_from(player.global_position)
	for i in 60: await get_tree().physics_frame
	await walk_to(Vector3(-4.5,10.005,36.6),240)
	check(player.position.z<37.2 and absf(player.position.y-10.005)<.16,"Open wing door and enter T bridge")
	print("FEEDER BRIDGE ENTRY ",player.position)
	player.queue_free();boat.queue_free()
	for i in 4: await get_tree().process_frame
	var unsafe: Dictionary=preset.brick_layout.duplicate(true)
	unsafe.parts[0].position[1]+=1.0
	boat=VesselSpawn.instantiate(preset.hull_id,unsafe)
	boat.freeze=true;add_child(boat)
	check(boat.get_cargo_pads().size()==39,"Raised unsupported bed cannot create capacity")
	boat.queue_free()
	for i in 4: await get_tree().process_frame
	print("CONTAINER FEEDER ","FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)

func walk_to(local_target: Vector3, frames: int) -> void:
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var cam: Node=player.get("_player_camera")
	# Slow uphill walking needs its real traversal time. Headless display cannot
	# capture the mouse, so this actual-input access check runs with rendering.
	for i in maxi(frames, 700):
		var delta:=boat.to_global(local_target)-player.global_position
		delta.y=0
		if delta.length()<.09:break
		# Walking is now look-relative. Turn the actual look rig, not the body
		# transform that the accepted character controller deliberately owns.
		var yaw:=atan2(-delta.x,-delta.z)
		cam.shift_look_yaw(wrapf(yaw-cam.get_look_yaw(),-PI,PI))
		Input.action_press("move_forward",clampf(delta.length()*2,.65,1))
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for i in 15:await get_tree().physics_frame
	print("FEEDER WAYPOINT ",local_target," reached ",player.position)
