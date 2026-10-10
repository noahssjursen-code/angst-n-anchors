extends "res://tests/compact_world_review.gd"

func capture(label: String, _eye: Vector3, _target: Vector3) -> void:
	var scenery := world.get_node("CoastalSettlements") as CoastalSettlements
	check(await wait_until(func():return scenery.get_debug_stats().pending==0,90), "settlements finish uploading")
	var town := "port-2"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--town="): town=arg.trim_prefix("--town=")
	var houses: Array = scenery.plan.buildings.filter(func(item):return item.port_id==town and item.kind!="boathouse")
	if not check(houses.size()>3,"mainland port has inhabited settlement"): return
	var item: Dictionary = houses[houses.size()/2]
	var target: Vector3 = item.position
	var direction := CoastalSettlementPlan.gradient(LandField.get_layout(),Vector2(target.x,target.z))
	var sea := Vector3(direction.x,0,direction.y)
	var eye := target+sea*650+Vector3(0,45,0)
	if label=="harbour": eye=target+sea*120+Vector3(30,55,0)
	elif label=="coast": eye=target+sea*18+Vector3(5,5,0)
	player.global_position=eye
	camera.position=eye;camera.look_at(target+Vector3(0,3,0))
	var tod := .06 if OS.get_cmdline_user_args().has("--night") else .46
	WorldClock.snap_time_of_day(tod);WeatherLighting.time_of_day=tod
	WeatherLighting.cloud_cover=.3;WeatherLighting.precipitation=0;WeatherLighting.visibility=1
	var forest := world.get_node("WorldForestStreamer") as WorldForestStreamer
	for tick in 10:await get_tree().process_frame
	check(await wait_until(func():var stats:=forest.get_debug_stats();return stats.pending==0 and stats.world_canopy_pending==0,120),"complete settlement woodland")
	await super.capture(label,eye,target+Vector3(0,3,0))
	if label=="coast":
		var start := target+sea*12+Vector3.UP*1.8
		var ray := PhysicsRayQueryParameters3D.create(start,target+Vector3.UP*1.8,1)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty() and scenery._colliders.values().has(hit.collider),"nearby house has physical walls")
	# Same view and forest with settlement draws off: isolates scenery GPU cost.
	scenery.visible=false
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid,true)
	var samples: Array[float] = []
	for tick in 90:
		await get_tree().process_frame
		if tick>=30:samples.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	samples.sort()
	report.get_or_add("without_settlement",{})[label]={"gpu_median_ms":samples[30],
		"draw_calls":get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	RenderingServer.viewport_set_measure_render_time(rid,false)
	scenery.visible=true
	report["settlements"]=scenery.get_debug_stats()
	report["forest"]=forest.get_debug_stats()
