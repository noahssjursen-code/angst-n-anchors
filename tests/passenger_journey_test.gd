extends "res://tests/coastal_express_test.gd"
## Rendered two-terminal local service slice. Real ferry equipment and save I/O;
## owned vessel and inter-port teleport are fixtures. Crowds are static seated poses.
var boat: ImportedDraftVessel
var origin: PassengerTerminal
var destination: PassengerTerminal
var company: CompanyService
var data: PlayerData
var service: PassengerService
var voyage: PassengerVoyage
var camera: Camera3D
var label: Label
var output: String
var recipe: Dictionary
var sailing := "outbound"
var stage := "Preparing passenger service"

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	assert(DisplayServer.get_name() != "headless")
	Engine.time_scale=6; Engine.physics_ticks_per_second=360; Engine.max_physics_steps_per_frame=64
	WorldClock.set_process(false); WorldClock.snap_time_of_day(.5)
	WorldWeather.set_blend_to_lighting_paused(true)
	WeatherLighting.time_of_day=.5; WeatherLighting.precipitation=0; WeatherLighting.wind_speed_ms=0
	add_child(preload("res://scripts/world/world_renderer.gd").new())
	GameMenu.set_gameplay_hud_visible(false)
	output="C:/Users/noahs/Pictures/machinescreenshots/passenger-journey-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	PlayerSaveStore.storage_root_override=output.path_join("scratch-save")
	data=PlayerData.new(); data.account_id="passenger-test"; data.display_name="Ferry test captain"
	company=CompanyService.new(); company.bind(data)
	recipe=JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/coastal_express_recipe.json"))
	recipe.format="imported_models"; recipe.hull_id=recipe.hull
	var owned:=VesselSpawn.normalize_record({"uid":"ferry-journey","name":"Coastal Express","hull_id":recipe.hull,"brick_layout":recipe})
	data.upsert_owned_vessel(owned); data.set_active_vessel(owned)
	origin=terminal("passenger-origin",Vector3(0,WaveSurface.WATER_LEVEL+1.65,0),0)
	destination=terminal("passenger-destination",Vector3(250,WaveSurface.WATER_LEVEL+1.65,-420),.8)
	boat=VesselSpawn.instantiate_from_record(owned) as ImportedDraftVessel
	boat.freeze=true; add_child(boat)
	service=PassengerService.new(); service.bind(data,company); routes()
	attach_voyage()
	camera=Camera3D.new(); camera.near=.06; camera.fov=60; add_child(camera); camera.make_current()
	var ui:=CanvasLayer.new(); add_child(ui)
	label=Label.new(); label.position=Vector2(18,18); label.add_theme_font_size_override("font_size",20); ui.add_child(label)
	await moor(origin)
	check(PassengerAccommodation.seats(boat).size()==240,"physical supported sockets provide 240 places without counting helm chair")
	var denied:=service.book("too-many",boat,"too-many")
	check(not denied.ok and denied.code=="capacity","241-passenger booking rejected")
	var booking:=service.book("out",boat,sailing)
	check(booking.ok,"company books full-capacity sailing at origin: "+str(booking.get("message","accepted")))
	if not booking.ok:
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":false,"failures":failures},"  "))
		get_tree().quit(1)
		return
	check(service.book("out",boat,sailing).ok and service.records().size()==1,"booking retry preserves a single manifest")
	check(not service.book("back",boat,sailing).ok,"reused booking reference cannot select another route")
	await run_for(1)
	check(service.record(sailing).onboard==0,"closed entrance prevents boarding")
	PassengerAccommodation.boarding_door(boat).request("door_open",true)
	stage="Boarding 240 passengers"
	await run_for(4)
	var count:=int(service.record(sailing).onboard)
	check(count>0 and count<240,"boarding advances gradually at the real ramp")
	var lines:=boat.get_node("ShipGameplay/MooringComponent") as MooringComponent
	lines.release_mooring()
	check(lines.is_moored and not service.departure_reason(boat).is_empty(),"unfinished boarding holds departure")
	PassengerAccommodation.ramp(boat).request_boarding()
	await run_for(3)
	PassengerAccommodation.boarding_door(boat).request("door_open",false)
	await run_for(1)
	count=int(service.record(sailing).onboard); await run_for(2)
	check(service.record(sailing).onboard==count,"closed door pauses rather than losing boarded passengers")
	await save_reload()
	check(service.record(sailing).onboard==count and absf(float(boat.get_mass_breakdown().categories.get("passengers",0))-count*90)<.1,"scratch reload restores partial manifest and passenger mass")
	PassengerAccommodation.ramp(boat).request_boarding()
	PassengerAccommodation.boarding_door(boat).request("door_open",true)
	await reach_phase("ready",90)
	check(service.record(sailing).onboard==240 and absf(float(boat.get_mass_breakdown().categories.get("passengers",0))-21600)<.1,"full manifest adds actual 21.6 tonnes of passengers and luggage")
	var altered:=recipe.duplicate(true)
	for part: Dictionary in altered.parts:
		if part.asset_id=="ferry_seating_row_10":
			part.position[1]+=2.0
			break
	boat.apply_brick_layout(altered); await run_for(3)
	check(PassengerAccommodation.seats(boat).size()==230 and not service.departure_reason(boat).is_empty(),"unsupported row loses capacity and missing booked seats block departure")
	altered=recipe.duplicate(true); altered.parts.reverse()
	boat.apply_brick_layout(altered); await run_for(3)
	PassengerAccommodation.boarding_door(boat).request("door_open",false); await run_for(1)
	check(service.departure_reason(boat).is_empty(),"restored seats keep stable manifest identities after placement reordering")
	await capture("fully-boarded")
	check(voyage.cabin_visual.rendered_count==240,"batched seated crowd represents every boarded passenger")
	await capture("saloon-full",true)
	await sample_performance()
	await cast_off()
	await reach_phase("underway",3)
	check(service.record(sailing).phase=="underway","stowed ramp and closed door permit departure")
	check(not service.begin_alighting(sailing,boat).ok,"cannot unload or earn fares at sea")
	check(not service.cancel(sailing,boat).ok,"cannot erase passengers by cancelling at sea")
	await save_reload(true)
	check(service.record(sailing).phase=="underway" and service.record(sailing).onboard==240,"underway save retains every passenger")
	# Teleport only the journey. The berth, mooring, ramp and transfer stay real.
	await moor(origin)
	check(not service.begin_alighting(sailing,boat).ok,"wrong arrival terminal cannot unload")
	await cast_off()
	await moor(destination)
	PassengerAccommodation.boarding_door(boat).request("door_open",true)
	check(service.begin_alighting(sailing,boat).ok,"booked destination accepts alighting")
	stage="Landing passengers at destination"
	await run_for(5)
	count=int(service.record(sailing).onboard)
	check(count>0 and count<240 and data.marks==0,"partial alighting does not pay prematurely")
	await save_reload()
	check(service.record(sailing).onboard==count,"partial destination transfer survives scratch save")
	await reach_phase("completed",90)
	check(data.marks==240*75 and data.total_marks_earned==240*75,"completed trip pays once through company ledger")
	check(service.record(sailing).landed==240 and service.record(sailing).onboard==0 and not boat.get_mass_breakdown().categories.has("passengers"),"all passengers land and their mass is removed")
	await capture("arrival-paid")
	await save_reload()
	service.begin_alighting(sailing,boat); service.advance(sailing,boat)
	check(data.marks==18000 and fare_entries()==1,"repeated arrival after save cannot duplicate fares")
	# Exercise durable ledger receipt after the short generic request cache clears.
	data.company.processed_requests={}
	var completed:Dictionary=data.company.passenger_sailings[0]
	completed.phase="alighting"; completed.paid_marks=0
	service.advance(sailing,boat)
	check(data.marks==18000 and fare_entries()==1,"durable fare receipt also prevents payment after request-cache eviction")
	sailing="return-cancelled"
	check(service.book("back",boat,sailing).ok,"return sailing books at opposite terminal")
	stage="Cancellation returns boarded passengers"
	await run_for(4)
	count=int(service.record(sailing).onboard)
	check(count>0,"return trip begins boarding")
	check(service.cancel(sailing,boat).ok,"cancellation accepted at its origin")
	await reach_phase("cancelled",15)
	check(service.record(sailing).returned==count and service.record(sailing).onboard==0 and data.marks==18000,"cancellation lands its boarded passengers without a fare")
	await save_reload()
	check(service.record(sailing).phase=="cancelled" and service.active_for(boat).is_empty(),"cancelled trip restores without reserving the vessel")
	stage="Passenger service checks complete"
	await capture("cancelled-return")
	report.failures=failures; report.passed=failures.is_empty(); report.sailings=service.records(); report.marks=data.marks
	report.scope={"passengers":"logical manifest and static seated crowd; walking/queue animation not implemented", "journey":"teleported", "equipment":"actual ramp, doors, lines and collision", "saves":"isolated real PlayerSaveStore I/O; vessel pose retained by fixture on rebuild"}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PASSENGER REPORT ",output," failures=",failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func routes() -> void:
	# Explicit authored development-route demand/fares, not copied operator tariffs.
	service.register_route("out",origin.berth,destination.berth,240,75)
	service.register_route("back",destination.berth,origin.berth,48,75)
	service.register_route("too-many",origin.berth,destination.berth,241,75)

func attach_voyage() -> void:
	voyage=PassengerVoyage.new(); voyage.setup(boat,service); boat.add_child(voyage)

func save_reload(rebuild_vessel: bool = false) -> void:
	voyage.free()
	check(PlayerSaveStore.save_player(data),"scratch company/manifest save succeeds")
	data=PlayerSaveStore.load_player()
	company=CompanyService.new(); company.bind(data)
	service=PassengerService.new(); service.bind(data,company); routes()
	if rebuild_vessel:
		var pose:=boat.global_transform
		boat.free()
		boat=VesselSpawn.instantiate_from_record(data.active_vessel) as ImportedDraftVessel
		boat.freeze=true; add_child(boat); boat.global_transform=pose
		await run_for(.25)
	attach_voyage()

func terminal(id: String, at: Vector3, yaw: float) -> PassengerTerminal:
	var instance:=PassengerTerminal.new(); instance.position=at; instance.rotation.y=yaw; add_child(instance)
	var harbour:=HarbourController.new(); harbour.setup(id); add_child(harbour); HarbourRegistry.register(harbour)
	instance.register_berth(harbour)
	return instance

func moor(target: PassengerTerminal) -> void:
	boat.dock_at_berth(target.berth); boat.freeze=true
	(boat.get_node("ShipGameplay/MooringComponent") as MooringComponent).moor_to_nearest_of(target.berth.bollards())
	await run_for(3)

func cast_off() -> void:
	var lines:=boat.get_node("ShipGameplay/MooringComponent") as MooringComponent
	lines.release_mooring(); await run_for(3); lines.release_mooring(); await run_for(.5)
	check(not lines.is_moored,"cast-off completes after closing door and securing ramp")

func reach_phase(phase: String, timeout: float) -> void:
	var elapsed:=0.0
	while service.record(sailing).get("phase","")!=phase and elapsed<timeout:
		await run_for(.25); elapsed+=.25
	check(service.record(sailing).get("phase","")==phase,"sailing reaches "+phase+": "+voyage.status)

func fare_entries() -> int:
	var count:=0
	for entry:Dictionary in data.company.account.ledger:
		if entry.category=="passenger_fares":count+=1
	return count

func _process(_delta: float) -> void:
	if not is_instance_valid(label):return
	var item:=service.record(sailing)
	label.text="PASSENGER JOURNEY  |  "+stage+"\n%s   On board %d / %d   Landed %d   Account %d\n%s" % [item.get("phase","Preparing"),item.get("onboard",0),item.get("total",0),item.get("landed",0),data.marks,voyage.status]

func capture(tag: String, interior: bool = false) -> void:
	camera.global_position=boat.to_global(Vector3(0,4.65,-6.4) if interior else Vector3(25,15,-30))
	camera.look_at(boat.to_global(Vector3(0,4.1,7) if interior else Vector3(0,3,-8)))
	for frame in 10: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(tag+".png"))

func sample_performance() -> void:
	Engine.time_scale=1; Engine.physics_ticks_per_second=60
	var old_vsync:=DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var viewport_rid:=get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid,true)
	report.performance={"resolution":str(get_viewport().get_visible_rect().size),"vsync":"disabled", "views":{}}
	for view in ["saloon", "outside_120m"]:
		if view=="outside_120m":
			camera.global_position=boat.to_global(Vector3(90,32,-74))
			camera.look_at(boat.to_global(Vector3(0,3,0)))
		var samples:Dictionary={}
		for occupied in [false,true]:
			voyage.cabin_visual.visible=occupied
			for frame in 60: await get_tree().process_frame
			var times:Array[float]=[]; var gpu:Array[float]=[]; var cpu:Array[float]=[]
			var last:=Time.get_ticks_usec()
			for frame in 180:
				await get_tree().process_frame
				var now:=Time.get_ticks_usec(); times.append((now-last)/1000.0); last=now
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid))
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid))
			times.sort(); gpu.sort(); cpu.sort()
			samples["full" if occupied else "empty"]={"median_ms":times[90],"p95_ms":times[171],
				"gpu_median_ms":gpu[90],"gpu_p95_ms":gpu[171],"render_cpu_median_ms":cpu[90],
				"draw_calls":get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
		report.performance.views[view]=samples
	DisplayServer.window_set_vsync_mode(old_vsync)
	RenderingServer.viewport_set_measure_render_time(viewport_rid,false)
	Engine.time_scale=6; Engine.physics_ticks_per_second=360
