extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for seed_value in [42,1850239324,1212599375]:
		if OS.get_cmdline_user_args().has("--single-seed") and seed_value!=42: continue
		if OS.get_cmdline_user_args().has("--reported-seed") and seed_value!=1850239324: continue
		var layout := WorldLayoutGenerator.generate(seed_value)
		var ports := CoastalPortPlacer.place_ports(layout)
		var settlements: Array = []
		if seed_value==1850239324:
			var zones := WorldTerrainStreamer.make_flatten_zones(ports,0.0,seed_value,layout)
			settlements=CoastalSettlementPlan.build(layout,ports,zones).buildings
		var plan := CoastalBridgePlan.build(layout,ports,settlements)
		assert(not plan.bridges.is_empty(),"Reference worlds should offer usable crossing candidates")
		assert(plan.bridges.size()<=CoastalBridgePlan.MAX_BRIDGES)
		if seed_value==1850239324:
			assert(plan.bridges.size()>7,"Expand useful network beyond former seven previews")
			assert(plan.bridges.any(func(b: Dictionary) -> bool: return b.kind=="Island connection"),"Budget must retain mainland island links")
		for bridge: Dictionary in plan.bridges:
			assert(layout.is_land(bridge.a_xz) and layout.is_land(bridge.b_xz))
			assert(bridge.span_m<=CoastalBridgePlan.MAX_SPAN+2*CoastalBridgePlan.LANDING_INSET)
			assert(bridge.deck_y>=WaveSurface.WATER_LEVEL+35)
			assert(bridge.component_a>=0 and bridge.component_b>=0)
			if seed_value==1850239324:
				# User screenshots: these were tiny bay shortcuts, including a
				# false island classification across a visibly joined beach.
				for rejected in [Vector2(7064,-8160),Vector2(9743,-14611),Vector2(10124,-11183)]:
					assert(bridge.center.distance_to(rejected)>180,"Rejected bay bridge must not recur")
			for port: PortDefinition in ports:
				var p := Vector2(port.world_position.x,port.world_position.z)
				assert(p.distance_to(Geometry2D.get_closest_point_to_segment(p,bridge.a_xz,bridge.b_xz))>=120)

		print("BRIDGES seed=%d selected=%d candidates=%d ms=%.0f" % [seed_value,plan.bridges.size(),plan.candidate_count,plan.build_ms])
		print("GROUPING ms=",plan.grouping_ms)
		for b: Dictionary in plan.bridges: print("  ",b.kind," span=",roundi(b.span_m)," from=",b.a_xz," to=",b.b_xz)
		if seed_value==42:
			var preview := CoastalBridgePreview.new()
			preview.configure(layout,ports,settlements)
			add_child(preview)
			assert(not preview.visible and preview.get_child_count()==0)
			DebugHud.set_gizmo_layer_enabled(WorldGizmos.LAYER_BRIDGES,true)
			var deadline := Time.get_ticks_msec()+120000
			while preview.report.is_empty() and Time.get_ticks_msec()<deadline:
				await get_tree().create_timer(.05).timeout
			assert(not preview.report.is_empty(),"Lazy worker finishes")
			assert(preview.report.bridges.size()==plan.bridges.size(),"Worker selection count is deterministic")
			for i in plan.bridges.size():
				var expected: Dictionary=plan.bridges[i]
				var actual: Dictionary=preview.report.bridges[i]
				assert(actual.a_xz==expected.a_xz and actual.b_xz==expected.b_xz,"Worker endpoints are deterministic")
				# Worker/main-thread floating-point rounding may differ below 1e-12.
				assert(actual.kind==expected.kind and absf(actual.score-expected.score)<.001,"Worker ranking is deterministic within 1 mm cost")
			assert(preview.visible and preview.get_child_count()>0)
			DebugHud.set_gizmo_layer_enabled(WorldGizmos.LAYER_BRIDGES,false)
			assert(not preview.visible)
			preview.queue_free()
			await get_tree().process_frame
	print("COASTAL BRIDGE PLAN PASS")
	get_tree().quit()
