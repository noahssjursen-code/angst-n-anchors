extends "res://tests/live_lighting_review.gd"
## Actual world approach, including the middle tier and port hinterland.
func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(360).timeout.connect(func(): get_tree().quit(1))
	output="C:/Users/noahs/Pictures/machinescreenshots/forest-approach-"+str(Time.get_unix_time_from_system()).replace(".","-")
	DirAccess.make_dir_recursive_absolute(output)
	GameSettings.map_generation_seed=424242
	GameSettings.map_layout_checksum=""
	GameSettings.map_world_size_m=40000
	PlayerSession.data.home_port_id="port-home"
	PlayerSession.data.tutorial_seen["welcome"]=true
	var start:=Time.get_ticks_msec()
	world=preload("res://scenes/world.tscn").instantiate();add_child(world)
	await world.boot_finished
	print("FOREST APPROACH BOOT MS ",Time.get_ticks_msec()-start)
	renderer=world.get_node("WorldRenderer")
	var player:=get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.set_physics_process(false)
	camera=Camera3D.new();camera.far=16000;camera.fov=55;world.add_child(camera);camera.current=true
	weather(.5,.35)
	var layout:=world.get_world_layout() as WorldLayout
	var target:=Vector3(10250,layout.sample_height(Vector2(10250,0)),0)
	# Sea-level approach to the same woodland, rather than only standing inside it.
	for distance in [2800.0,1700.0,900.0]:
		var best_clearance:=-1.0
		for angle in range(-8,9):
			var candidate:Vector3=target+Vector3.RIGHT.rotated(Vector3.UP,float(angle)*.15)*float(distance)
			if layout.sample_signed_distance(Vector2(candidate.x,candidate.z))<60: continue
			var clearance:=INF
			for id in PortCatalog.get_port_ids():
				clearance=minf(clearance,candidate.distance_to(PortCatalog.get_port_position(id)))
			if clearance>best_clearance:
				best_clearance=clearance;camera.position=candidate
		assert(best_clearance>0,"No offshore camera location")
		camera.position.y=8
		assert(layout.sample_signed_distance(Vector2(camera.position.x,camera.position.z))>0)
		camera.look_at(target+Vector3.UP*6)
		await settle()
		await capture("boat-%d"%distance)
		if distance==900: await measure("boat-900")
	camera.position=target+Vector3(120,35,180)
	camera.look_at(target+Vector3.UP*5)
	await settle()
	await capture("woodland-approach")
	await measure("woodland-approach")
	camera.position=target+Vector3(950,550,1400)
	camera.look_at(target+Vector3(0,0,-800))
	await settle()
	await capture("forest-aerial")
	# Review a real port and adjoining land with the normal forest streamer.
	var home:=world.get_node("HomePort") as Node3D
	for height in [65.0,220.0]:
		camera.position=home.global_position+(-home.global_basis.z)*650+Vector3.UP*height
		camera.look_at(home.global_position+home.global_basis.z*100+Vector3.UP*20)
		await settle()
		await capture("harbour-%d"%height)
	print("FOREST APPROACH STATS ",world.get_node("WorldForestStreamer").get_debug_stats())
	await measure("harbour")
	world.queue_free()
	for frame in 5: await get_tree().process_frame
	print("FOREST APPROACH COMPLETE ",output)
	get_tree().quit()

func measure(tag:String) -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	for visible in [true,false]:
		world.get_node("WorldForestStreamer").visible=visible
		var times:Array[float]=[]
		for frame in 120:
			await RenderingServer.frame_post_draw
			if frame>45: times.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		times.sort()
		print("FOREST APPROACH GPU ",tag," visible=",visible," median_ms=",times[times.size()/2]," draws=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)," tris=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	world.get_node("WorldForestStreamer").visible=true

func settle() -> void:
	await get_tree().create_timer(3).timeout
	for attempt in 300:
		var stats:Dictionary=world.get_node("WorldForestStreamer").get_debug_stats()
		if stats.pending==0 and stats.world_canopy_pending==0 and world.get_node("WorldTerrainStreamer").pending_near(camera.position,1800)==0: return
		await get_tree().create_timer(.2).timeout
	assert(false,"Forest approach did not settle")
