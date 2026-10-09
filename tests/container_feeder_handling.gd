extends Node3D
## Six-degree-of-freedom Jolt, flat water, actual installed engine and controller.
## The 800 t loaded case uses 40 ContainerUnits, not an arbitrary rigid-body mass.
var boat: ImportedDraftVessel
var helm: BoatController
var rows: Array[Dictionary]=[]
var failed:=false

func run_for(seconds: float) -> void:
	var elapsed:=0.0
	while elapsed<seconds:
		await get_tree().physics_frame
		elapsed+=get_physics_process_delta_time()

func speed() -> float:
	return boat.linear_velocity.dot(-boat.global_basis.z)*1.943844

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	Engine.time_scale=8
	Engine.physics_ticks_per_second=480
	Engine.max_physics_steps_per_frame=64
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.wind_speed_ms=0
	var p:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/container_feeder_40.json"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--engine="):
			p.brick_layout.engine_preset = arg.trim_prefix("--engine=")
	for laden in [false,true]:
		boat=VesselSpawn.instantiate_from_record(VesselSpawn.normalize_record({"uid":"feeder-handling","name":p.name,"hull_id":p.hull_id,"brick_layout":p.brick_layout}))
		add_child(boat)
		boat.position=Vector3(0,-3.3,0)
		helm=boat.get_node("BoatController")
		helm._active=true
		if laden:
			for i in boat.get_cargo_pads().size():boat.get_cargo_pads()[i].add_container(ContainerUnit.create("handling-%d"%i,"provisions",20000))
		await run_for(30)
		var row:Dictionary={"engine_preset":p.brick_layout.engine_preset,"power_kw":boat.physics_profile.shaft_power_kw,"laden":laden,"mass_t":boat.mass/1000,"static_keel_y":boat.position.y,"static_roll_deg":boat.rotation_degrees.z,"static_pitch_deg":boat.rotation_degrees.x}
		helm.set_throttle_stage_idx(4)
		await run_for(240)
		row.cruise_kn=speed()
		row.cruise_roll_deg=boat.rotation_degrees.z
		row.cruise_pitch_deg=boat.rotation_degrees.x
		var propulsion := boat.get_node("PropulsionComponent") as PropulsionComponent
		var hydro := boat.get_node("HydrodynamicsComponent") as HydrodynamicsComponent
		row.cruise_thrust_n = propulsion.delivered_thrust_n
		row.cruise_drag_n = hydro.forward_drag_n
		row.cruise_throttle = propulsion.throttle
		helm.set_throttle_stage_idx(1)
		await run_for(30)
		row.coast_30s_kn=speed()
		boat.linear_velocity = -boat.global_basis.z * float(row.cruise_kn) / 1.943844
		helm.set_throttle_stage_idx(0)
		var full_stop_seconds := 0.0
		var stop_start := boat.position
		while speed() > .5 and full_stop_seconds < 120:
			await get_tree().physics_frame
			full_stop_seconds += get_physics_process_delta_time()
		row.stop_from_cruise_s = full_stop_seconds
		row.stop_from_cruise_m = Vector2(boat.position.x-stop_start.x, boat.position.z-stop_start.z).length()
		boat.linear_velocity=-boat.global_basis.z*4
		helm.set_throttle_stage_idx(0)
		var seconds:=0.0
		while speed()>.5 and seconds<120:
			await get_tree().physics_frame
			seconds+=get_physics_process_delta_time()
		row.stop_from_7_8kn_s=seconds
		boat.linear_velocity=Vector3.ZERO
		await run_for(60)
		row.astern_60s_kn=speed()
		boat.linear_velocity=-boat.global_basis.z*4
		boat.angular_velocity=Vector3.ZERO
		var heading:=boat.rotation.y
		helm.set_throttle_stage_idx(3)
		Input.action_press("move_right")
		await run_for(90)
		Input.action_release("move_right")
		row.turn_90s_degrees=absf(rad_to_deg(angle_difference(heading,boat.rotation.y)))
		row.turn_speed_kn=speed()
		row.turn_roll_deg=boat.rotation_degrees.z
		var high_output := is_equal_approx(boat.physics_profile.shaft_power_kw, 5600)
		var cruise_ok: bool = row.cruise_kn >= 15.0 and row.cruise_kn <= 16.0 if high_output else row.cruise_kn > 12.0 and row.cruise_kn < 14.0
		row.passed=cruise_ok and row.coast_30s_kn<row.cruise_kn*.9 and seconds<60 and full_stop_seconds<90 and row.astern_60s_kn<-.5 and row.astern_60s_kn> -8.0 and row.turn_90s_degrees>8 and absf(row.turn_roll_deg)<15
		failed=failed or not row.passed
		rows.append(row)
		print("FEEDER HANDLING ",JSON.stringify(row))
		boat.queue_free()
		for i in 5:await get_tree().process_frame
	var path:="C:/Users/noahs/Pictures/machinescreenshots/feeder-handling-%s.json"%str(Time.get_unix_time_from_system()).replace(".","-")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Flat-water free-floating Jolt; installed engine/controller; 40 real 20 t cargo units; no wave/wind forcing","passed":not failed,"cases":rows},"  "))
	print("FEEDER HANDLING REPORT ",path)
	get_tree().quit(1 if failed else 0)
