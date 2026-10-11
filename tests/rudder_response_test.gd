extends Node3D

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func run() -> void:
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.wind_speed_ms = 0
	WaveSurface.wave_intensity = 0
	var boats: Array[BoatBody] = []
	for entry in PrebuiltVesselCatalog.for_sale_entries():
		var boat := VesselSpawn.instantiate_from_record(VesselSpawn.normalize_record({"uid":"rudder-"+str(entry.prebuilt_id),"name":entry.display,"hull_id":entry.hull_id,"brick_layout":entry.prebuilt_layout.duplicate(true)}))
		boat.position = Vector3(boats.size()*400, -boat.draft_m, 0)
		add_child(boat)
		boat.set_meta("test_name", entry.prebuilt_id)
		if OS.get_cmdline_user_args().has("--laden"):
			for pad in boat.get_cargo_pads(): pad.add_container(ContainerUnit.create("rudder-load", "provisions", 20000))
		var floating := OS.get_cmdline_user_args().has("--floating")
		boat.axis_lock_linear_y = not floating
		boat.axis_lock_angular_x = not floating
		boat.axis_lock_angular_z = not floating
		if floating: boat.place_at_waterline(WaveSurface.WATER_LEVEL)
		else: boat.gravity_scale = 0
		boat.get_node("BoatController").set_physics_process(false)
		if not floating: boat.get_node("StripBuoyancyComponent").set_physics_process(false)
		var rudder := boat.get_node("RudderComponent") as RudderComponent
		rudder.rudder_input = 1
		boat.get_node("PropulsionComponent").throttle = -0.15
		rudder._physics_process(1.0/60.0)
		assert(is_zero_approx(rudder.lateral_force_n), "Stopped engine cannot produce propeller wash")
		boat.get_node("PropulsionComponent").set_engine_running(true)
		rudder._physics_process(1.0/60.0)
		assert(rudder.lateral_force_n > 0, "Slow ahead must give rudder flow before vessel gathers speed")
		boat.get_node("PropulsionComponent").throttle = -0.15 if OS.get_cmdline_user_args().has("--slow") else -0.5
		boat.get_node("RudderComponent").rudder_input = 1
		boat.linear_velocity = Vector3.ZERO if OS.get_cmdline_user_args().has("--slow") else Vector3(0,0,-4)
		boats.append(boat)
	for tick in 1800: await get_tree().physics_frame
	var failed := false
	for boat in boats:
		if boat.get_meta("test_name") in ["28_10_m", "bulk_small", "coastal_coaster", "container_feeder_40"]:
			var minimum := 3.0 if OS.get_cmdline_user_args().has("--slow") else 30.0
			if -rad_to_deg(boat.rotation.y) < minimum or absf(boat.rotation_degrees.z) > 20:
				failed = true
		print("RUDDER RESPONSE ", boat.get_meta("test_name"), " heading_deg=", rad_to_deg(boat.rotation.y), " yaw_deg_s=", rad_to_deg(boat.angular_velocity.y), " speed=", boat.linear_velocity.length(), " area=",boat.get_node("RudderComponent").rudder_area_m2)
		boat.queue_free()
	for tick in 3: await get_tree().process_frame
	print("RUDDER RESPONSE PASS" if not failed else "RUDDER RESPONSE FAIL")
	get_tree().quit(1 if failed else 0)
