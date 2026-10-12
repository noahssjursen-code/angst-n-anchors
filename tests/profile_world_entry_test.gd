extends Node

## Exercises the real Sail handler against an explicitly supplied COPY of saves.
## The runner survives the normal menu -> world scene replacement.
var started := 0
var entered := 0

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--captain-fixture")
	assert(index >= 0 and index + 1 < args.size())
	LocalCaptainStore.root_override = args[index + 1]
	assert(LocalCaptainStore.root_override.contains("profile-load-fixture"))
	get_tree().current_scene = null
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().create_timer(1.0).timeout
	var entries := LocalCaptainStore.list_captains()
	assert(not entries.is_empty())
	get_tree().node_added.connect(on_node)
	if args.has("--uncached-generation"):
		WorldGenerationCache.enabled=false
		WorldLayoutGenerator.clear_cache()
	started = Time.get_ticks_msec()
	menu._on_sp_sail(str(entries[0].id))
	print("ENTRY Sail handler returned ms=", Time.get_ticks_msec()-started)

func on_node(node: Node) -> void:
	if not node.has_signal("boot_finished"): return
	print("ENTRY world node added ms=", Time.get_ticks_msec()-started)
	node.connect("boot_finished", on_boot.bind(node), CONNECT_ONE_SHOT)

func on_boot(world: Node) -> void:
	entered = Time.get_ticks_msec()
	print("ENTRY playable ms=", entered-started)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var terrain := world.get_node("WorldTerrainStreamer")
	assert(terrain.is_ready_around(player.global_position),"Boot returned without local terrain")
	print("ENTRY spawn=",player.global_position," terrain_focus=",terrain.boot_focus())
	var forest := world.get_node("WorldForestStreamer")
	var canopy := forest._distant as Node
	var canopy_id := canopy.get_instance_id()
	var bridges := world.get_node("CoastalBridges")
	bridges.structures_ready.connect(func(_structures):
		assert(is_instance_valid(canopy) and forest._distant.get_instance_id()==canopy_id,"Bridge reset the forest")
		print("ENTRY bridge forest preserved"))
	for event in Telemetry.load_events: print("ENTRY_STAGE ",JSON.stringify(event))
	for sample in 4:
		print("ENTRY_STREAM after_ms=",Time.get_ticks_msec()-entered)
		for name in ["WorldTerrainStreamer", "WorldForestStreamer", "CoastalSettlements", "ProximityLoader"]:
			var node := world.get_node_or_null(NodePath(name))
			if node != null: print(name," ",JSON.stringify(node.get_debug_stats()))
		await get_tree().create_timer(5.0).timeout
	if OS.get_cmdline_user_args().has("--wait-bridges"):
		var deadline := Time.get_ticks_msec()+90000
		while not bridges.planning_complete and Time.get_ticks_msec()<deadline:
			await get_tree().create_timer(.25).timeout
		assert(bridges.planning_complete)
		assert(is_instance_valid(canopy) and forest._distant.get_instance_id()==canopy_id)
		assert(canopy.trees>0,"Distant forest failed to publish trees")
		await RenderingServer.frame_post_draw
		var archive := "C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(archive)
		var path := archive.path_join("world-entry-forest-%d.png" % Time.get_ticks_msec())
		get_viewport().get_texture().get_image().save_png(path)
		print("ENTRY capture=",path)
	if OS.get_cmdline_user_args().has("--capture-port-clearance"):
		var port: Node3D = get_tree().get_first_node_in_group("port_plot")
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.far = 20000
		camera.global_position = port.to_global(Vector3(140,110,-180))
		camera.look_at(port.to_global(Vector3(0,0,65)))
		camera.make_current()
		await get_tree().create_timer(2).timeout
		await RenderingServer.frame_post_draw
		var archive := "C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(archive)
		var path := archive.path_join("port-terrain-clearance-%d.png" % Time.get_unix_time_from_system())
		get_viewport().get_texture().get_image().save_png(path)
		print("PORT CLEARANCE capture=",path)
	if OS.get_cmdline_user_args().has("--capture-bridge-landings"):
		var deadline:=Time.get_ticks_msec()+180000
		while not bridges.planning_complete and Time.get_ticks_msec()<deadline:
			await get_tree().create_timer(.25).timeout
		assert(bridges.planning_complete)
		var structures:Array=bridges.report.structures.duplicate()
		structures.sort_custom(func(a:Dictionary,b:Dictionary):return a.approaches[0].distance_squared_to(player.global_position)<b.approaches[0].distance_squared_to(player.global_position))
		var connected:Array=[]
		for candidate:Dictionary in structures:
			for link:Array in candidate.road_links:
				if not link.is_empty(): connected.append(candidate);break
		if not connected.is_empty(): structures=connected
		var camera:=Camera3D.new();world.add_child(camera);camera.far=20000;camera.make_current()
		var links:=0
		for structure:Dictionary in structures:
			for link:Array in structure.road_links:
				if not link.is_empty(): links+=1
		print("BRIDGE REVIEW built=",bridges.report.structures.size()," road_links=",links," rejected=",bridges.report.rejected)
		for i in mini(2,structures.size()):
			var structure:Dictionary=structures[i]
			for end in 2:
				var at:Vector3=structure.approaches[end]
				var bank:Vector2=structure.a if end==0 else structure.b
				var direction:=(at-Vector3(bank.x,at.y,bank.y)).normalized()
				camera.global_position=at+Vector3.UP*65+direction.cross(Vector3.UP)*120-direction*50
				camera.look_at(at+direction*25)
				await get_tree().create_timer(5).timeout
				await RenderingServer.frame_post_draw
				var directory:="C:/Users/noahs/Pictures/machinescreenshots"
				DirAccess.make_dir_recursive_absolute(directory)
				var path:=directory.path_join("bridge-landfall-%d-%d-%d.png"%[Time.get_unix_time_from_system(),i,end])
				get_viewport().get_texture().get_image().save_png(path);print("BRIDGE CAPTURE ",path)
	print("PROFILE WORLD ENTRY PASS")
	get_tree().quit()
