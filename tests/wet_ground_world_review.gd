extends "res://tests/compact_world_review.gd"
## Same-view dry baseline and damp finish in the actual harbour/woodland.
func capture(label: String, _eye: Vector3, _target: Vector3) -> void:
	if OS.get_cmdline_user_args().has("--coast-only") and label!="coast":return
	var home:=world.get_node("HomePort") as Node3D
	var renderer:=world.get_node("WorldRenderer") as WorldRenderer
	var eye:Vector3=home.get_spawn_position()+Vector3.UP*1.65
	var target:Vector3=eye+home.global_basis*Vector3(30,-1,-100)
	if label=="coast":
		var scenery:=world.get_node("CoastalSettlements") as CoastalSettlements
		check(await wait_until(func():return scenery.get_debug_stats().pending==0,90),"all settlements ready")
		var houses:Array=scenery.plan.buildings.filter(func(item):return item.port_id=="port-2" and item.kind!="boathouse")
		var house:Dictionary=houses[houses.size()/2]
		target=house.position+Vector3.UP*1.5
		var direction:=CoastalSettlementPlan.gradient(LandField.get_layout(),Vector2(target.x,target.z))
		eye=target+Vector3(direction.x,0,direction.y)*18+Vector3(5,4,0)
	var tod:=.04 if label=="channel" else .44
	WorldClock.snap_time_of_day(tod);WeatherLighting.time_of_day=tod
	var state:=WeatherState.new();state.cloud_cover=.94;state.precipitation=.8;state.visibility=.90
	state.wind_speed_ms=8;state.wind_force=.36;state.wind_direction=Vector3(.8,0,.6)
	WeatherLighting.apply_weather_state(state)
	renderer.set_process(false)
	player.global_position=eye;camera.position=eye;camera.look_at(target)
	var forest:=world.get_node("WorldForestStreamer") as WorldForestStreamer
	for frame in 12:await get_tree().process_frame
	check(await wait_until(func():var s:=forest.get_debug_stats();return s.pending==0 and s.world_canopy_pending==0,120),label+" full woodland ready")
	for value in [0.0,1.0]:
		SurfaceWetness.set_amount(value)
		await super.capture(label+("-dry" if value==0 else "-wet"),eye,target)
	report.get_or_add("wetness",{})[label]=SurfaceWetness.amount
	if label=="coast":
		# Repeated settled frames distinguish material cost from streaming/startup.
		var rid:=get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(rid,true)
		for value in [0.0,1.0,0.0,1.0]:
			SurfaceWetness.set_amount(value)
			var gpu:Array[float]=[];var wall:Array[float]=[];var previous:=Time.get_ticks_usec()
			for frame in 180:
				await get_tree().process_frame
				var now:=Time.get_ticks_usec()
				if frame>=60:
					gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
					wall.append((now-previous)/1000.0)
				previous=now
			gpu.sort();wall.sort()
			report.get_or_add("settled_cost",[]).append({"wet":value,"gpu_median_ms":gpu[60],"frame_p95_ms":wall[114],"frame_max_ms":wall[-1]})
		RenderingServer.viewport_set_measure_render_time(rid,false)
