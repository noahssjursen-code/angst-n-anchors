extends Node3D
## Narrow first-construction acceptance: actual imported collision, mass,
## two lift strips, shaft presentation and free Jolt handling. No captain saves.
var failures: Array[String]=[]
var report: Dictionary={}
var access_player: CharacterBody3D

func check(ok: bool, description: String) -> void:
	if not ok: failures.append(description)
	print("PASS " if ok else "FAIL ",description)

func run_for(seconds: float) -> void:
	var elapsed:=0.0
	while elapsed<seconds:
		await get_tree().physics_frame
		elapsed+=get_physics_process_delta_time()

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	Engine.time_scale=8
	Engine.physics_ticks_per_second=480
	Engine.max_physics_steps_per_frame=64
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.wind_speed_ms=0
	var recipe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/coastal_express_recipe.json"))
	check(ImportedShipPartsEditor.valid_draft(recipe),"editable ferry recipe valid")
	if OS.get_cmdline_user_args().has("--editor-roundtrip"):
		var editor:=preload("res://scenes/apps/shipyard_brick_editor.tscn").instantiate() as ShipyardBrickEditor
		add_child(editor);await get_tree().process_frame
		var builder:ImportedShipPartsEditor=editor.get("_imported_parts_editor")
		builder._load_draft_data(recipe)
		builder.save_draft("user://coastal_express_review.json")
		var restored:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://coastal_express_review.json"))
		builder._load_draft_data(restored,"user://coastal_express_review.json")
		check(builder.records.size()==recipe.parts.size() and restored.hull==recipe.hull and restored.engine_preset==recipe.engine_preset,"actual Shipyard save/reload retains ferry parts and machinery")
		editor.free()
	var boat:=ImportedDraftVessel.new();boat.configure(recipe);add_child(boat)
	boat.position.y=WaveSurface.WATER_LEVEL-1.55
	var port:=boat.get_node("StripBuoyancyComponent") as StripBuoyancyComponent
	var starboard:=boat.get_node("StripBuoyancyStarboard") as StripBuoyancyComponent
	var profile:=boat.physics_profile
	check(absf(port.hull_center_x_m+4.3)<.001 and absf(starboard.hull_center_x_m-4.3)<.001,"lift acts at both demihulls")
	for draft in [.4,1.0,1.55,2.5,3.1]:
		check(absf(boat.hull_stations.volume_below(draft)-port.hull_stations.volume_below(draft)*2)<.01,"spawn and buoyancy volume agree at draft %.2f"%draft)
	check(absf(boat.hull_stations.volume_below(1.55)*1.025-160)<.1,"design draft supports actual 160 t package")
	check(boat.find_children("PassengerSeat*","Node3D",true,false).size()==240,"240 authored seat positions")
	var drive:=boat.get_node("HullVisual/DriveGear") as ShipDriveVisual
	check(drive.propellers.size()==2 and drive.rudders.size()==2,"two animated shaft/rudder assemblies")
	var helm:=boat.get_node("BoatController") as BoatController;helm._active=true
	await run_for(25)
	report.static_keel_y=boat.position.y;report.static_roll_deg=boat.rotation_degrees.z;report.static_pitch_deg=boat.rotation_degrees.x
	check(absf(boat.position.y-WaveSurface.WATER_LEVEL+1.55)<.18 and absf(boat.rotation_degrees.z)<2 and absf(boat.rotation_degrees.x)<2,"stable free-floating design waterline")
	var ray:=PhysicsRayQueryParameters3D.create(boat.to_global(Vector3(0,1.8,-22)),boat.to_global(Vector3(0,1.8,22)),BoatBody.LAYER_BOAT_HULL)
	check(get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"open tunnel has no invisible hull collision")
	for x in [-4.3,4.3]:
		ray=PhysicsRayQueryParameters3D.create(boat.to_global(Vector3(x,1.8,-22)),boat.to_global(Vector3(x,1.8,22)),BoatBody.LAYER_BOAT_HULL)
		check(not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"demihull collision at %.1f"%x)
	helm.set_throttle_stage_idx(4)
	await run_for(180)
	report.cruise_kn=boat.linear_velocity.dot(-boat.global_basis.z)*1.943844
	report.cruise_pitch_deg=boat.rotation_degrees.x
	check(report.cruise_kn>28 and report.cruise_kn<40,"credible high-speed cruise without speed clamp")
	check(absf(boat.rotation_degrees.z)<8 and absf(boat.rotation_degrees.x)<8,"stable powered attitude")
	helm.set_throttle_stage_idx(1);await run_for(30)
	report.coast_30s_kn=boat.linear_velocity.dot(-boat.global_basis.z)*1.943844
	check(report.coast_30s_kn<report.cruise_kn*.9,"cuts power and loses momentum")
	helm.set_throttle_stage_idx(0)
	var stopping:=0.0
	while boat.linear_velocity.dot(-boat.global_basis.z)>.25 and stopping<90:
		await get_tree().physics_frame;stopping+=get_physics_process_delta_time()
	report.reverse_stop_s=stopping
	check(stopping<90,"astern brakes the ferry")
	if OS.get_cmdline_user_args().has("--access"):
		await verify_access(boat)
	# Preserve the shared monohull station path and shaft aliases.
	var old:=ImportedDraftVessel.new()
	old.configure({"hull":"trawler_hull_14m","parts":[]})
	var old_drive:=old.get_node("HullVisual/DriveGear") as ShipDriveVisual
	check(old.get_node_or_null("StripBuoyancyStarboard")==null and old_drive.propellers.size()==1 and old_drive.propeller==old_drive.propellers[0],"existing monohull retains single lift/shaft contract")
	old.free()
	report.failures=failures;report.passed=failures.is_empty()
	var path:="C:/Users/noahs/Pictures/machinescreenshots/ferry-construction-test-%s.json"%str(Time.get_unix_time_from_system()).replace(".","-")
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "))
	print("FERRY TEST REPORT ",path," ",JSON.stringify(report))
	boat.queue_free()
	for frame in 5: await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_access(boat: ImportedDraftVessel) -> void:
	assert(DisplayServer.get_name()!="headless", "Real-player input requires rendering")
	Engine.time_scale=4;Engine.physics_ticks_per_second=240
	boat.freeze=true;boat.transform=Transform3D.IDENTITY
	for child in boat.get_children():child.set_physics_process(false)
	boat._sync_walk_deck_transform()
	access_player=preload("res://scenes/shared/player.tscn").instantiate()
	var terminal:=preload("res://scenes/port/passenger_terminal.tscn").instantiate() as Node3D
	terminal.position.y=3.2;add_child(terminal)
	add_child(access_player);access_player.position=Vector3(0,3.28,-24.0)
	for frame in 20:await get_tree().physics_frame
	await walk_to(Vector3(0,3.2,-16.0))
	check(access_player.position.z> -16.2 and absf(access_player.position.y-3.2)<.15,"player crosses fixed passenger pier and bow ramp")
	access_player.position=Vector3(0,3.28,10.8);access_player.velocity=Vector3.ZERO
	for frame in 20:await get_tree().physics_frame
	await walk_to(Vector3(0,3.2,-5.5))
	check(access_player.position.z< -5.2 and absf(access_player.position.y-3.2)<.15,"real player traverses saloon centre aisle")
	await walk_to(Vector3(0,5.9,-10.3))
	check(access_player.position.z< -10.0 and absf(access_player.position.y-5.9)<.15,"real player climbs to bridge with clear headroom")
	await walk_to(Vector3(0,3.2,-5.5))
	check(absf(access_player.position.y-3.2)<.15,"real player descends to saloon")
	access_player.position=Vector3(0,3.3,-16);access_player.velocity=Vector3.ZERO
	for part in boat.part_roots:
		if part.get_meta("asset_id")=="cabin_door_straight" and part.position.z< -13:
			part.get_node("PartState").request_door_from(access_player.global_position)
	for frame in 60:await get_tree().physics_frame
	await walk_to(Vector3(0,3.2,-11.7))
	check(access_player.position.z> -12 and absf(access_player.position.y-3.2)<.15,"bow door admits player from boarding deck")
	await walk_to(Vector3(3.0,3.2,-11.7))
	await walk_to(Vector3(3.0,3.2,12.0))
	check(access_player.position.z>11.7 and absf(access_player.position.y-3.2)<.15,"passenger aisle bypasses bridge stairs and reaches aft seating")
	access_player.queue_free()
	terminal.queue_free()
	for frame in 5:await get_tree().process_frame

func walk_to(target: Vector3) -> void:
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var cam:Node=access_player.get("_player_camera")
	for frame in 2000:
		var offset:=target-access_player.global_position;offset.y=0
		if offset.length()<.10:break
		var yaw:=atan2(-offset.x,-offset.z)
		cam.shift_look_yaw(wrapf(yaw-cam.get_look_yaw(),-PI,PI))
		Input.action_press("move_forward",clampf(offset.length()*2,.65,1))
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for frame in 15:await get_tree().physics_frame
	print("FERRY ACCESS target=",target," actual=",access_player.position)
