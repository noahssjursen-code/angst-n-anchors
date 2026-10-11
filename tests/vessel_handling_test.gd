extends Node3D

## Actual stock vessels, controller, thrust and hydrodynamics in isolated Jolt.
## Lock heave/rotation for repeatable longitudinal measurements in flat water.
var boats: Array[BoatBody] = []
var rows: Array[Dictionary] = []
var phase := -1
var elapsed := 0.0
var baseline := false
var output := ""
var floating := false
var laden := false
const STAGES := ["cruise", "coast_cruise", "coast_harbour", "crash_stop", "astern", "brake_astern"]
const DURATIONS := [180.0, 30.0, 30.0, 90.0, 60.0, 45.0]

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	baseline = OS.get_cmdline_user_args().has("--baseline")
	floating = OS.get_cmdline_user_args().has("--floating")
	laden = OS.get_cmdline_user_args().has("--laden")
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 64
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.wind_speed_ms = 0.0
	process_physics_priority = 100
	output = "C:/Users/noahs/Pictures/machinescreenshots/handling-%s.json" % str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	for entry in PrebuiltVesselCatalog.for_sale_entries():
		var boat := VesselSpawn.instantiate_from_record(VesselSpawn.normalize_record({"uid":"handling-"+str(entry.prebuilt_id),"name":entry.display,"hull_id":entry.hull_id,"brick_layout":entry.prebuilt_layout.duplicate(true)}))
		boat.position = Vector3(boats.size()*300.0,-boat.draft_m,0)
		add_child(boat)
		boat.axis_lock_linear_y = not floating
		boat.axis_lock_angular_x = not floating
		boat.axis_lock_angular_y = true
		boat.axis_lock_angular_z = not floating
		if not floating:
			boat.gravity_scale = 0
			boat.get_node("StripBuoyancyComponent").set_physics_process(false)
		if laden:
			# Controlled mass fixture, independent of cargo booking/packing tests.
			boat.set_mass_entry("handling_load",boat.mass*.25,boat.center_of_mass,"cargo")
		var helm := boat.get_node("BoatController") as BoatController
		helm._active = true
		boats.append(boat)
		rows.append({"vessel":entry.prebuilt_id,"length_m":boat.length_m,"mass_kg":boat.mass,"crash_stop_s":-1.0,"brake_astern_s":-1.0})
	await get_tree().physics_frame
	next_phase()

func next_phase() -> void:
	if phase >= 0:
		for i in boats.size():
			rows[i][STAGES[phase]+"_end_kn"] = -boats[i].linear_velocity.z * 1.943844
	phase += 1
	elapsed = 0.0
	if phase == STAGES.size():
		finish()
		return
	for i in boats.size():
		var boat := boats[i]
		var helm := boat.get_node("BoatController") as BoatController
		if phase == 0: helm.set_throttle_stage_idx(4)
		if phase in [1,2]: helm.set_throttle_stage_idx(1)
		if phase == 2: boat.linear_velocity = Vector3(0,0,-2.0)
		if phase == 3:
			boat.linear_velocity = Vector3(0,0,-4.0)
			helm.set_throttle_stage_idx(0)
		if phase == 4:
			boat.linear_velocity = Vector3.ZERO
			helm.set_throttle_stage_idx(0)
		if phase == 5: helm.set_throttle_stage_idx(4)
	print("HANDLING STAGE ",STAGES[phase])

func _physics_process(delta: float) -> void:
	if phase < 0 or phase >= STAGES.size(): return
	elapsed += delta
	for i in boats.size():
		var speed := -boats[i].linear_velocity.z
		if phase == 3 and speed <= 0.25 and float(rows[i].crash_stop_s) < 0:
			rows[i].crash_stop_s = elapsed
		if phase == 5 and speed >= -0.25 and float(rows[i].brake_astern_s) < 0:
			rows[i].brake_astern_s = elapsed
	if elapsed >= float(DURATIONS[phase]): next_phase()

func finish() -> void:
	var passed := true
	for row in rows:
		# A loaded 88 m feeder must retain more momentum than a 14 m trawler.
		# Still require measurable unpowered decay and finite stopping both ways.
		var feeder := float(row.length_m) >= 60.0
		var ok := float(row.crash_stop_s) > 0 and float(row.crash_stop_s) < (90 if feeder else 35) \
			and float(row.brake_astern_s) > 0 and float(row.brake_astern_s) < (45 if feeder else 25) \
			and absf(float(row.coast_harbour_end_kn)) < (3.5 if feeder else 1.0) \
			and float(row.coast_cruise_end_kn) < float(row.cruise_end_kn)*(.95 if feeder else .8)
		row["passed"] = ok
		passed = passed and ok
		print("HANDLING RESULT ",JSON.stringify(row))
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"flat-water longitudinal Jolt; stock controller; yaw locked","floating":floating,"extra_mass_fraction":0.25 if laden else 0.0,"baseline":baseline,"passed":passed,"vessels":rows},"\t"))
	print("HANDLING REPORT ",output)
	for boat in boats: boat.queue_free()
	boats.clear()
	for frame in 4: await get_tree().process_frame
	get_tree().quit(0 if passed or baseline else 1)
