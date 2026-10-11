extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for size in [30000.0,40000.0]:
		var layout := WorldLayoutGenerator.generate(424242, WorldConfig.ARCHETYPE_PATH,size)
		var defs := CoastalPortPlacer.place_ports(layout,35)
		var zones := WorldTerrainStreamer.make_flatten_zones(defs,0,424242,layout)
		var plan := CoastalSettlementPlan.build(layout,defs,zones)
		assert(plan.buildings.size()>100, "Too few inhabited coastal plots")
		var second := CoastalSettlementPlan.build(layout,defs,zones)
		assert(plan.buildings==second.buildings and plan.roads==second.roads,"Settlement placement is not deterministic")
		var local_zones := {};var cache := {};var ports := {}
		for item: Dictionary in plan.buildings:
			var point := Vector2(item.position.x,item.position.z)
			assert(item.position.y>.2 and item.relief<=.8,"Building is submerged or on a cliff")
			assert(not CoastalSettlementPlan.excluded(point,zones,local_zones),"Building occupies a port or quay")
			assert(ForestField.inside_flatten_zones(point,plan.exclusions),"Building does not exclude trees")
			ports[item.port_id]=true
		for road: PackedVector3Array in plan.roads:
			for step in 8:
				var point := road[0].lerp(road[1],float(step)/7)
				assert(layout.sample_signed_distance(Vector2(point.x,point.z))<0,"Road crosses the sea")
		print("SETTLEMENT PASS size=",size," houses=",plan.buildings.size()," roads=",plan.roads.size()," towns=",ports.size()," planning_ms=",plan.build_ms)
	quit()
