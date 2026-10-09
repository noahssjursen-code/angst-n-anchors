extends "res://tests/coastal_express_test.gd"
## Actual ferry/terminal line commands and real player traversal. Synthetic
## bounded roll/heave is only a repeatable moving-support fixture, not sea physics.
var boat: ImportedDraftVessel
var ramp: FerryBoarding
var terminal: PassengerTerminal
var camera: Camera3D
var output: String
var docked: Transform3D
var motion := false
var phase := 0.0
var label: Label

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	assert(DisplayServer.get_name()!="headless")
	process_physics_priority = -30
	WorldClock.set_process(false);WorldClock.snap_time_of_day(.5)
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.time_of_day=.5;WeatherLighting.precipitation=0
	WeatherLighting.wind_speed_ms=2;WeatherLighting.sea_state=.08
	add_child(preload("res://scripts/world/world_renderer.gd").new())
	GameMenu.set_gameplay_hud_visible(false)
	output="C:/Users/noahs/Pictures/machinescreenshots/ferry-boarding-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/coastal_express_recipe.json"))
	boat=ImportedDraftVessel.new();boat.configure(recipe);boat.freeze=true;add_child(boat)
	ramp=boat.find_child("FerryBoarding",true,false)
	terminal=make_terminal("boarding-a",Vector3(100,WaveSurface.WATER_LEVEL+1.65,80),.6)
	boat.dock_at_berth(terminal.berth)
	boat.freeze=true
	docked=boat.global_transform
	camera=Camera3D.new();camera.near=.05;camera.fov=58;add_child(camera);camera.make_current()
	var ui:=CanvasLayer.new();add_child(ui);label=Label.new();label.position=Vector2(18,16);label.add_theme_font_size_override("font_size",20);ui.add_child(label)
	await run_for(.3)
	check(ramp.angle>1.56 and not ramp.deployed,"ramp starts physically stowed")
	var expected:=terminal.to_global(Vector3(0,0,0))
	check(Vector2(boat.position.x-expected.x,boat.position.z-expected.z).length()<.01 and boat.global_basis.z.dot(terminal.global_basis.z)>.999,"bow-in dock pose uses actual vessel length and terminal heading")
	var mooring:=boat.get_node("ShipGameplay/MooringComponent") as MooringComponent
	var reply:=order_lines(mooring,terminal.berth)
	check(mooring.bow_line_tied and mooring.stern_line_tied,"lines secure passenger berth: "+reply)
	await run_for(3)
	check(ramp.deployed,"secured ramp reaches real pier: "+ramp.status)
	check_cylinders("deployed")
	look_at_ramp();await capture("deployed")
	access_player=preload("res://scenes/shared/player.tscn").instantiate();add_child(access_player)
	access_player.get_node("BodyMesh").visual.set_local_first_person(false)
	access_player.global_position=terminal.to_global(Vector3(0,.08,-22))
	await run_for(.4)
	motion=true
	await walk_to(boat.to_global(Vector3(0,3.2,-16)))
	check(boat.to_local(access_player.global_position).z> -16.3 and access_player.is_on_floor(),"player boards while hull heaves, pitches and rolls")
	look_at_ramp();await capture("aboard-moving")
	await walk_to(terminal.to_global(Vector3(0,0,-22)))
	check(terminal.to_local(access_player.global_position).z< -21.6 and access_player.is_on_floor(),"player walks ashore on moving ramp")
	motion=false;boat.global_transform=docked
	await run_for(.3)
	access_player.global_position=boat.to_global(Vector3(0,3.28,-18.5));access_player.velocity=Vector3.ZERO
	await run_for(.4)
	check(ramp.occupied(),"ramp detects a person crossing")
	var previous:=ramp.angle
	reply=order_lines(mooring,terminal.berth)
	await run_for(.3)
	check(mooring.is_moored and absf(ramp.angle-previous)<.01 and "clear" in reply,"cast-off keeps lines and ramp still while occupied")
	mooring.set_line_tied(true,false)
	check(mooring.bow_line_tied,"single-line release cannot bypass ramp interlock")
	var drive:=boat.get_node("PropulsionComponent") as PropulsionComponent
	var thruster:=boat.get_node("BowThrusterComponent") as BowThrusterComponent
	var fuel:=boat.fuel_l
	drive.throttle=-1;thruster.lateral_input=1
	await run_for(.1)
	check(drive.delivered_thrust_n==0 and thruster.lateral_input==0 and is_equal_approx(fuel,boat.fuel_l),"ramp interlock blocks direct propulsion, thruster and fuel burn")
	await walk_to(terminal.to_global(Vector3(0,0,-22)))
	await run_for(3)
	check(ramp.angle>1.56 and boat.departure_block_reason().is_empty(),"clear ramp folds up before departure")
	check_cylinders("stowed")
	look_at_ramp();await capture("stowed")
	order_lines(mooring,terminal.berth)
	check(not mooring.is_moored and boat.get_moored_berth()==null,"second line order releases lines and harbour occupancy")
	var ray:=PhysicsRayQueryParameters3D.create(boat.to_global(Vector3(0,4,-18.7)),boat.to_global(Vector3(0,2.5,-18.7)),BoatBody.LAYER_BOAT_WALK)
	check(get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"stowing removes the old horizontal ramp collision")
	var destination:=make_terminal("boarding-b",Vector3(420,WaveSurface.WATER_LEVEL+1.65,-300),-1.0)
	boat.dock_at_berth(destination.berth);boat.freeze=true;docked=boat.global_transform
	await run_for(.2)
	order_lines(mooring,destination.berth)
	await run_for(3)
	check(ramp.deployed and boat.get_moored_berth()==destination.berth,"arrival resolves destination posts and redeploys at rotated second terminal")
	terminal=destination
	# No phantom bridge in air, through a wall, at the wrong heading, or to sea.
	boat.position.y+=1.2;await run_for(3)
	check(not ramp.deployed and ramp.angle>1.56,"excessive boarding slope rejected")
	boat.global_transform=docked;boat.position+=terminal.global_basis.x*4;await run_for(.3)
	check(not ramp.deployed and ramp._landing_solution().is_empty(),"sideways misalignment rejected")
	boat.global_transform=docked;boat.rotate_y(PI);await run_for(.3)
	check(ramp._landing_solution().is_empty(),"wrong bow direction rejected")
	boat.global_transform=docked;boat.position+=terminal.global_basis.z*6;await run_for(.3)
	check(ramp._landing_solution().is_empty(),"water gap beyond rigid ramp reach rejected")
	boat.global_transform=docked;await run_for(3)
	check(ramp.deployed,"ramp recovers when the valid landing returns")
	# Let Jolt and the real two-hull buoyancy solve run at this secured berth.
	boat.linear_velocity=Vector3.ZERO;boat.angular_velocity=Vector3.ZERO
	boat.freeze=false;await run_for(8)
	report.moored_shift_m=boat.global_position.distance_to(docked.origin)
	check(report.moored_shift_m<.65 and ramp.deployed,"free-floating ferry remains aligned with boarding landing")
	look_at_ramp();await capture("destination-afloat")
	boat.freeze=true
	var updated:=boat.draft.duplicate(true);updated.name="Ferry boarding refit"
	boat.apply_brick_layout(updated)
	await run_for(3)
	ramp=boat.find_child("FerryBoarding",true,false)
	check(ramp.deployed and boat.departure_checks.size()==1,"fit-out rebuild restores boarding with exactly one live departure check")
	report.failures=failures;report.passed=failures.is_empty()
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
	print("FERRY BOARDING REPORT ",output," ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func check_cylinders(stage: String) -> void:
	var valid:=true
	for i in 2:
		var side:float=-1 if i==0 else 1
		var expected:=ramp.part.to_global(Vector3(side*1.18,0,-.6))
		var rod:Node3D=ramp._rods[i]
		valid=valid and rod.to_global(Vector3(0,0,-1.35)).distance_to(expected)<.002
		valid=valid and rod.scale.is_equal_approx(Vector3.ONE) and rod.position.z>= -1.42 and rod.position.z<=0
	check(valid,"hydraulic pins stay attached within real unscaled stroke: "+stage)

func order_lines(mooring: MooringComponent, slot: QuayBerthSlot) -> String:
	# Exercise the gameplay command endpoints without requiring a particular HUD.
	if mooring.is_moored:
		mooring.release_mooring()
		return mooring.last_mooring_reject
	mooring.moor_to_nearest_of(slot.bollards())
	return "Both lines fast" if mooring.bow_line_tied and mooring.stern_line_tied else mooring.last_mooring_reject

func make_terminal(id: String, at: Vector3, yaw: float) -> PassengerTerminal:
	var instance:=PassengerTerminal.new();instance.position=at;instance.rotation.y=yaw;add_child(instance)
	var harbour:=HarbourController.new();harbour.setup(id);add_child(harbour);HarbourRegistry.register(harbour)
	instance.register_berth(harbour)
	return instance

func _physics_process(delta: float) -> void:
	if not motion: return
	phase+=delta
	boat.global_transform=docked*Transform3D(Basis.from_euler(Vector3(deg_to_rad(.25)*sin(phase*1.1),0,deg_to_rad(1.25)*sin(phase*.8))),Vector3(0,.18*sin(phase*1.3),0))

func look_at_ramp() -> void:
	camera.global_position=boat.to_global(Vector3(6,7,-23))
	camera.look_at(boat.to_global(Vector3(0,3.6,-18)))
	camera.make_current()
	label.text="FERRY BOARDING  |  "+ramp.status

func capture(tag: String) -> void:
	for frame in 10:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(tag+".png"))
