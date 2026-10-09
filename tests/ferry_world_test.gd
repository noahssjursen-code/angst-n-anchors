extends Node3D
## Actual generated-world placement, harbour deployment, access and frame cost.
## Isolated player data; does not touch captain saves or change geography.
var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var ship: ImportedDraftVessel
var terminal: PassengerTerminal
var output: String
var report := {"checks":[],"sites":[],"performance":{}}
var failures: Array[String]=[]
var next_berth := ""

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func check(ok: bool, text: String) -> bool:
	report.checks.append({"ok":ok,"check":text})
	print("FERRY WORLD ","PASS " if ok else "FAIL ",text)
	if not ok: failures.append(text)
	return ok

func wait_until(predicate: Callable, seconds: float) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call(): return true
		await get_tree().process_frame
	return bool(predicate.call())

func run() -> void:
	output="C:/Users/noahs/Pictures/machinescreenshots/ferry-world-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	PlayerSaveStore.storage_root_override=output.path_join("scratch-save")
	var backend:=LocalWorldBackend.new()
	WorldGateway.add_child(backend);WorldGateway._backend=backend
	backend.session_started.connect(WorldGateway._on_session_started)
	backend.session_ended.connect(WorldGateway._on_session_ended)
	backend.event_received.connect(WorldGateway._on_world_event)
	backend.command_finished.connect(WorldGateway._on_command_finished)
	backend.projections_received.connect(WorldGateway._on_projections_received)
	backend.start_session("ferry-test","Ferry captain","")
	GameSettings.map_generation_seed=424242;GameSettings.map_layout_checksum="";GameSettings.map_world_size_m=40000
	PlayerSession.data.home_port_id="port-home"
	world=preload("res://scenes/world.tscn").instantiate()
	var booted:=[false];world.boot_finished.connect(func():booted[0]=true);add_child(world)
	if not check(await wait_until(func():return booted[0],90),"world boots with isolated captain"): finish();return
	player=get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(false)
	camera=Camera3D.new();camera.far=12000;add_child(camera);camera.make_current()
	GameMenu.set_gameplay_hud_visible(false)
	WorldWeather.set_blend_to_lighting_paused(true);WorldClock.set_process(false);WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day=.5;WeatherLighting.precipitation=0
	var layout:=LandField.get_layout()
	var definitions:Array=world._generate_definitions()
	var candidates:Array[PortData]=[]
	for definition: PortDefinition in definitions:
		var data:=PortExpander.expand(definition,424242,layout)
		var frame:=Transform3D(Basis(Vector3.UP,data.rotation_y),data.world_position)
		var before:=JSON.stringify(data.layout_graph.to_dict())
		var plan:=PassengerPortSites.plan(data.layout_graph,frame,layout)
		check(before==JSON.stringify(data.layout_graph.to_dict()),"siting preserves layout "+data.port_id)
		if not plan.is_empty():
			report.sites.append({"id":data.port_id,"site":plan})
			candidates.append(data)
	if not check(candidates.size()>=2,"at least two existing harbours have a clear passenger site"):finish();return
	var origin:=player.global_position
	candidates.sort_custom(func(a:PortData,b:PortData):return a.world_position.distance_squared_to(origin)<b.world_position.distance_squared_to(origin))
	var selected:=candidates.slice(0,2)
	for data in candidates:
		if data.port_id=="port-8" and data not in selected:selected.append(data)
	for data in selected:
		next_berth=candidates[1 if data==candidates[0] else 0].port_id+"/passenger"
		player.global_position=data.world_position+Vector3(0,5,0)
		camera.global_position=data.world_position+Vector3(0,40,-100)
		camera.look_at(data.world_position)
		await wait_until(func():return HarbourRegistry.controller(data.port_id)!=null,30)
		var harbour:=HarbourRegistry.controller(data.port_id)
		if not check(harbour!=null,"selected harbour streams "+data.port_id):continue
		var plot:=harbour.get_parent() as PortPlot
		var terrain:=world.get_node("WorldTerrainStreamer") as WorldTerrainStreamer
		check(await wait_until(func():return terrain.is_ready_around(player.global_position),45),"near terrain finishes streaming")
		report.get_or_add("terrain",{})[data.port_id]=terrain.get_debug_stats()
		print("FERRY WORLD TERRAIN ",terrain.get_debug_stats())
		var before:=JSON.stringify(plot.port_data().layout_graph.to_dict())
		terminal=plot.find_child("PassengerTerminal",true,false) as PassengerTerminal
		check(terminal!=null,"passenger terminal installs "+data.port_id)
		if terminal==null:continue
		check(before==JSON.stringify(plot.port_data().layout_graph.to_dict()),"installation leaves cargo layout unchanged")
		await review(plot)
		if is_instance_valid(ship):
			var ramp:=PassengerAccommodation.ramp(ship)
			ramp.request_stow()
			await wait_until(func():return ramp.departure_block_reason().is_empty(),8)
			(ship.get_node("ShipGameplay/MooringComponent") as MooringComponent).release_mooring()
			ship.queue_free();ship=null
		await get_tree().process_frame
	finish()

func review(plot: PortPlot) -> void:
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/models/examples/coastal_express_recipe.json"))
	recipe.format="imported_models";recipe.hull_id=recipe.hull
	var owned:=VesselSpawn.normalize_record({"uid":"world-ferry-"+plot.port_id,"name":"Coastal Express","hull_id":recipe.hull,"brick_layout":recipe})
	PlayerSession.data.upsert_owned_vessel(owned);PlayerSession.data.set_active_vessel(owned)
	var slot:=HarbourDeploy.pick_slot(plot.harbour_controller(),owned)
	if not check(slot==terminal.berth,"ferry chooses passenger berth ahead of cargo quays"):return
	ship=HarbourDeploy.deploy(plot,owned) as ImportedDraftVessel
	if not check(ship!=null,"harbour deploys ferry"):return
	await wait_until(func():return PassengerAccommodation.ramp(ship).deployed,12)
	var ramp:=PassengerAccommodation.ramp(ship)
	check(ramp.deployed,"world landing accepts bow ramp: "+ramp.status)
	await capture(plot.port_id+"-overview",Vector3(70,50,65),Vector3(0,0,-10))
	await capture(plot.port_id+"-shore",Vector3(10,6,-51),Vector3(0,1,-38))
	ship.freeze=true
	Engine.time_scale=4;Engine.physics_ticks_per_second=240;Engine.max_physics_steps_per_frame=64
	player.global_position=terminal.to_global(Vector3(1.5,terminal.shore_rise+.15,-51))
	player.velocity=Vector3.ZERO;player.set_physics_process(true)
	for frame in 20:await get_tree().physics_frame
	await walk_to(terminal.to_global(Vector3(1.5,0,-37)))
	check(terminal.to_local(player.global_position).z > -37.3,"real player crosses shore ramp into waiting room")
	await walk_to(terminal.to_global(Vector3(1.5,0,-22)))
	check(terminal.to_local(player.global_position).z > -22.3,"real player exits waiting room to boarding apron")
	await walk_to(terminal.to_global(Vector3(0,0,-22)))
	PassengerAccommodation.boarding_door(ship).request("door_open",true)
	await walk_to(ship.to_global(Vector3(0,3.2,-16)))
	check(ship.to_local(player.global_position).z > -16.3,"real player boards from live port")
	player.set_physics_process(false)
	player.global_position=terminal.to_global(Vector3(8,1,-25))
	var service:=PassengerService.new();var company:=CompanyService.new();company.bind(PlayerSession.data)
	service.bind(PlayerSession.data,company)
	service.register_route_ids("review",terminal.berth.berth_id,next_berth,240,75)
	var booking:=service.book("review",ship,"world-"+plot.port_id)
	check(booking.ok,"route books by terminal ID without loading distant terminal")
	if booking.ok:
		for passenger in 240: service.advance("world-"+plot.port_id,ship)
		service.restore_mass(ship)
		var crowd:=PassengerCabinVisual.new();ship.add_child(crowd);crowd.sync(service.active_for(ship))
		check(crowd.rendered_count==240,"full seated crowd in live port")
		await capture(plot.port_id+"-occupied",Vector3(65,22,48),Vector3(0,2,-5))
		await performance(plot.port_id,crowd)
		service.cancel("world-"+plot.port_id,ship)
		for passenger in 240:service.advance("world-"+plot.port_id,ship)
	Engine.time_scale=1;Engine.physics_ticks_per_second=60

func walk_to(target:Vector3) -> void:
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var cam:Node=player.get("_player_camera")
	for frame in 1800:
		var offset:=target-player.global_position;offset.y=0
		if offset.length()<.12:break
		var yaw:=atan2(-offset.x,-offset.z)
		cam.shift_look_yaw(wrapf(yaw-cam.get_look_yaw(),-PI,PI))
		Input.action_press("move_forward",clampf(offset.length()*2,.65,1))
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for frame in 10:await get_tree().physics_frame
	print("FERRY WORLD WALK ",terminal.to_local(player.global_position)," target ",terminal.to_local(target))

func performance(id:String,crowd:PassengerCabinVisual) -> void:
	Engine.time_scale=1;Engine.physics_ticks_per_second=60
	var rid:=get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	var timings:Dictionary={"resolution":str(get_viewport().get_visible_rect().size)}
	for visible_crowd in [false,true]:
		crowd.visible=visible_crowd
		for frame in 90:await get_tree().process_frame
		var gpu:Array[float]=[];var frame_ms:Array[float]=[];var last:=Time.get_ticks_usec()
		for frame in 180:
			await get_tree().process_frame
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			var now:=Time.get_ticks_usec();frame_ms.append((now-last)/1000.0);last=now
		gpu.sort();frame_ms.sort()
		timings["occupied" if visible_crowd else "empty"]={"gpu_median_ms":gpu[90],"gpu_p95_ms":gpu[171],"frame_median_ms":frame_ms[90],"frame_p95_ms":frame_ms[171],"draw_calls":get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	report.performance[id]=timings
	RenderingServer.viewport_set_measure_render_time(rid,false)

func capture(tag:String,eye:Vector3,target:Vector3) -> void:
	camera.global_position=terminal.to_global(eye);camera.look_at(terminal.to_global(target));camera.make_current()
	for i in 15:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(tag+".png"))

func finish() -> void:
	report.failures=failures;report.passed=failures.is_empty()
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("FERRY WORLD REPORT ",output," ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
