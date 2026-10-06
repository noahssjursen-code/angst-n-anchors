extends Node3D
## Real vessel physics in deterministic calm water. Run --fixed-fps 60, isolated.
var boats: Array[ImportedDraftVessel] = []
var ticks := 0
var samples: Array[Dictionary] = []

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	WaveSurface.wave_intensity = 0
	WeatherLighting.wind_speed_ms = 0
	WorldWeather.set_blend_to_lighting_paused(true)
	for option in CompanyContracts.starter_options():
		var record := CompanyService.build_starter_vessel_record(option.id)
		if OS.get_cmdline_user_args().has("--upgraded"):
			record.brick_layout.engine_preset = MarineEngineCatalog.options(record.hull_id).back().id
		var boat := VesselSpawn.instantiate_from_record(record) as ImportedDraftVessel
		if OS.get_cmdline_user_args().has("--no-linear-damping"):
			boat.linear_damp_coeff = 0
			boat.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		boat.position.x = boats.size() * 80
		add_child(boat)
		if OS.get_cmdline_user_args().has("--loaded"):
			for pad in boat.get_cargo_pads(): pad.add_container(ContainerUnit.create("","provisions",24000))
		boat.place_at_waterline(WaveSurface.WATER_LEVEL)
		boat.get_node("BoatController").set_physics_process(false)
		boat.get_node("PropulsionComponent").throttle = -1
		boats.append(boat)
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if boats.size() != 4: return
	ticks += 1
	if ticks in [1200,3600,7200]:
		for index in boats.size():
			var boat := boats[index]
			var prop := boat.get_node("PropulsionComponent") as PropulsionComponent
			var hydro := boat.get_node("HydrodynamicsComponent") as HydrodynamicsComponent
			var forward := -(boat.global_basis.inverse() * boat.linear_velocity).z
			var sample := {"ship":CompanyContracts.starter_options()[index].id,"seconds":ticks/60.,"knots":forward*1.943844,"shaft_kw":prop.shaft_power_kw,"thrust_n":prop.delivered_thrust_n,"drag_n":hydro.forward_drag_n,"mass_kg":boat.mass,"pitch_deg":boat.rotation_degrees.x,"fuel_l":boat.fuel_l,"damping":boat.linear_damp,"damping_mode":boat.linear_damp_mode}
			samples.append(sample)
			print("PERFORMANCE ",JSON.stringify(sample))
			if ticks == 7200: assert(forward*1.943844>10 and forward*1.943844<19,"Calm-water service speed outside tuned envelope")
	if ticks>=7200:
		set_physics_process(false)
		finish.call_deferred()

func finish() -> void:
	# Dry tanks stop thrust and shaft presentation; astern uses the same engine.
	for boat in boats: boat.fuel_l = 0
	for frame in 8: await get_tree().physics_frame
	for boat in boats:
		assert(is_zero_approx(boat.get_node("PropulsionComponent").delivered_thrust_n))
		boat.get_node("HullVisual/DriveGear")._process(.1)
		assert(is_zero_approx(boat.get_node("HullVisual/DriveGear").signed_rpm))
		boat.fuel_l = 10
		boat.get_node("PropulsionComponent").throttle = 1
	for frame in 8: await get_tree().physics_frame
	for boat in boats:
		assert(boat.get_node("PropulsionComponent").delivered_thrust_n > 0)
		boat.get_node("HullVisual/DriveGear")._process(.1)
		assert(boat.get_node("HullVisual/DriveGear").signed_rpm < 0)
	var args := OS.get_cmdline_user_args()
	var output := args.find("--output")
	if output>=0:
		var file := FileAccess.open(args[output+1],FileAccess.WRITE)
		file.store_string(JSON.stringify(samples,"\t"))
	for boat in boats: boat.queue_free()
	for i in 4: await get_tree().process_frame
	print("VESSEL PERFORMANCE COMPLETE: 120 seconds full ahead, real propulsion/buoyancy/drag")
	get_tree().quit()
