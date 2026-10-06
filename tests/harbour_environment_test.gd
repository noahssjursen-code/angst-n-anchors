extends "res://scripts/port/port_showcase.gd"

var failures: Array[String] = []

func _ready() -> void:
	_configuring=true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port-size="): port_size=int(arg.get_slice("=",1))
		if arg.begins_with("--region="): region_index=int(arg.get_slice("=",1))
	_configuring=false
	super._ready()
	call_deferred("verify")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"): return
	for i in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/noahs/Pictures/machinescreenshots/2026-10-06_harbour-rebuild"
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(str(Time.get_unix_time_from_system()).replace(".","-")+"-"+label+".png")
	check(get_viewport().get_texture().get_image().save_png(path)==OK,"Capture saved")
	print("CAPTURE ",path)

func verify() -> void:
	assert(ShipyardPlaytestMode.active())
	for i in 180:
		await get_tree().process_frame
		if i>60 and _terrain.pending_near(_terrain_boot_focus,2200)==0: break
	var plot := get_node("GeneratedPort/PortPlot")
	var visual := plot.get_node("PortLayoutGraph")
	var warehouses: Array[Node3D] = []
	var terminals: Array[Node3D] = []
	for raw in visual.find_children("*","Node3D",true,false):
		var node := raw as Node3D
		if node.has_meta("office_shell"): warehouses.append(node)
		if node.has_meta("review_walk_spawn"): terminals.append(node)
	check(warehouses.size()==1,"Exactly one imported harbour office")
	var facilities: Dictionary = _last_data.layout_graph.initial_attributes.land_plan.facility_plan
	print("FACILITY PLAN count=",facilities.facilities.size()," unmet=",facilities.unmet.size())
	if not facilities.unmet.is_empty(): print("UNMET ",facilities.unmet)
	if OS.get_cmdline_user_args().has("--dump-plan"): print("PLAN_JSON ",JSON.stringify(facilities))
	if port_size==2 and region_index==0:
		check(facilities.facilities.size()==4,"Office, shared general cargo, fish and ore facilities fit")
		check(facilities.unmet.is_empty(),"Reference site fits its required facilities")
		check(terminals.size()==3,"Three original quay terminals preserved")
		check(visual.find_children("arch_fender_batch","MultiMeshInstance3D",true,false).size()==3,"Fenders batched per quay")
	for record in facilities.facilities:
		var extent := Vector2(record.size_m[0],record.size_m[1])
		check(PortFacilityPlan.parcel_fits(record,PortFacilityPlan.points(facilities.boundary)),"Actual coastal facility supported")
	check(not _meta_panel.visible,"Details collapsed on entry")
	print("HARBOUR shells=",warehouses.size()," terminals=",terminals.size())

	var yards := get_tree().get_nodes_in_group("container_yard_pad")
	for raw in yards:
		var yard := raw as CargoSlotPadComponent
		check(not yard.show_pad_visual and yard.get_node_or_null("PadVisual")==null,"Quay has no pad or orange grid")
	if not yards.is_empty():
		var yard := yards[0] as CargoSlotPadComponent
		var slot := yard.add_container(ContainerUnit.create("asphalt_review"))
		check(slot>=0,"Invisible yard retains freight placement")
		var containers := yard.iter_container_nodes()
		if not containers.is_empty():
			var container := containers[0]
			check(absf(container.global_position.y-yard.global_position.y)<.001,"Container base rests at asphalt height")
			_camera.global_position=container.to_global(Vector3(10,6,12))
			_camera.look_at(container.to_global(Vector3(0,1,0)))
			await capture("container-on-asphalt")
		yard.remove_container_at(slot)
	_frame_port()
	get_node("HudLayer").hide()
	await capture("daylight-overview")
	if not warehouses.is_empty():
		var building := warehouses[0]
		_camera.global_position = building.to_global(Vector3(28,16,34))
		_camera.look_at(building.to_global(Vector3(0,7,0)))
		await capture("office-parking")
		_camera.global_position = building.to_global(Vector3(35,35,48))
		_camera.look_at(building.to_global(Vector3(0,0,12)))
		await capture("facility-precinct")
	if not terminals.is_empty():
		var terminal := terminals[0]
		var width: float = terminal.get_meta("deck_half_w",22.0)
		_camera.global_position = terminal.to_global(Vector3(width+12,4,-12))
		_camera.look_at(terminal.to_global(Vector3(width,-.4,0)))
		await capture("quay-edge-fenders")
	_toggle_walk_review()
	check(is_instance_valid(_review_player),"Walk mode creates production player")
	if is_instance_valid(_review_player):
		for i in 25: await get_tree().physics_frame
		check(_review_player.is_on_floor(),"Player stands on quay lane")
		var start := _review_player.global_position
		# Travel landward, crossing the actual pier/apron join rather than only standing.
		var terminal := terminals[0]
		var lane: Vector3 = terminal.get_meta("review_walk_spawn")
		var length: float = (_last_data.layout_graph.initial_attributes.berth_plan.quay_stations[0] as Dictionary).get("length_m",150.0)
		_review_player.global_position = terminal.to_global(Vector3(lane.x,.09,-length*.5+2))
		_review_player.velocity = Vector3.ZERO
		_review_player.rotation.y = terminal.global_rotation.y
		for i in 15: await get_tree().physics_frame
		start = _review_player.global_position
		Input.action_press("move_forward")
		for i in 100: await get_tree().physics_frame
		Input.action_release("move_forward")
		check(_review_player.global_position.distance_to(start)>4.0,"Player walks across quay/apron join")
		check(_review_player.is_on_floor(),"Player remains supported across join")
		print("WALK moved=",_review_player.global_position.distance_to(start)," floor=",_review_player.is_on_floor())
		await capture("player-walking-apron")
		if not warehouses.is_empty():
			var shell := warehouses[0]
			_review_player.global_position = shell.to_global(Vector3(3,.1,8))
			_review_player.velocity = Vector3.ZERO
			_review_player.rotation.y = shell.global_rotation.y
			for i in 20: await get_tree().physics_frame
			Input.action_press("move_forward")
			for i in 100: await get_tree().physics_frame
			Input.action_release("move_forward")
			var local := shell.to_local(_review_player.global_position)
			var front: float=shell.get_meta("front_wall",4.0)
			check(local.z>front+.25 and local.z<front+.7,"Office wall physically blocks entry")
			check(_review_player.is_on_floor(),"Player supported outside office")
			print("OFFICE COLLISION local=",local)
			var precinct := shell.get_parent() as Node3D
			var record: Dictionary=precinct.get_meta("facility_record")
			var half := Vector2(record.size_m[0],record.size_m[1])*.5
			_review_player.global_position=precinct.to_global(Vector3(-half.x+1.5,.1,-half.y-1))
			_review_player.velocity=Vector3.ZERO
			_review_player.rotation.y=precinct.global_rotation.y+PI
			for i in 20: await get_tree().physics_frame
			var footway_start := _review_player.global_position
			Input.action_press("move_forward")
			for i in 100: await get_tree().physics_frame
			Input.action_release("move_forward")
			check(_review_player.global_position.distance_to(footway_start)>5,"Office pedestrian entrance remains clear of parking and kerbs")
			check(_review_player.is_on_floor(),"Player walks onto raised footway")
			await capture("office-footway-walking")
	_toggle_walk_review()
	check(not is_instance_valid(_review_player) and _camera.current,"Fly mode restored")
	get_node("GeneratedPort").queue_free()
	await get_tree().process_frame
	LandDecorCache.clear()
	BuildingCache.clear()
	ModelCache.clear()
	if failures.is_empty(): print("HARBOUR ENVIRONMENT PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
