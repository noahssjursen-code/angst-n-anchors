extends "res://scripts/port/port_showcase.gd"

var failures: Array[String] = []

func _ready() -> void:
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
	check(facilities.facilities.size()==4,"Office, shared general cargo, fish and ore facilities fit")
	check(facilities.unmet.is_empty(),"Reference site fits its required facilities")
	check(terminals.size()==3,"Three original quay terminals preserved")
	check(visual.find_children("arch_fender_batch","MultiMeshInstance3D",true,false).size()==3,"Fenders batched per quay")
	check(not _meta_panel.visible,"Details collapsed on entry")
	print("HARBOUR shells=",warehouses.size()," terminals=",terminals.size())
	_frame_port()
	get_node("HudLayer").hide()
	await capture("daylight-overview")
	if not warehouses.is_empty():
		var building := warehouses[0]
		_camera.global_position = building.to_global(Vector3(12,7,18))
		_camera.look_at(building.to_global(Vector3(0,3,0)))
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
			check(local.z>4.25 and local.z<4.7,"Office wall physically blocks entry")
			check(_review_player.is_on_floor(),"Player supported outside office")
			print("OFFICE COLLISION local=",local)
	_toggle_walk_review()
	check(not is_instance_valid(_review_player) and _camera.current,"Fly mode restored")
	get_node("GeneratedPort").queue_free()
	await get_tree().process_frame
	LandDecorCache.clear()
	BuildingCache.clear()
	ModelCache.clear()
	if failures.is_empty(): print("HARBOUR ENVIRONMENT PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
