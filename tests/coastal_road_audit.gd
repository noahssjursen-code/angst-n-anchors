extends SceneTree

func _initialize() -> void: call_deferred("run")

func root_of(parents: Dictionary, key: String) -> String:
	while parents[key]!=key: key=parents[key]
	return key

func run() -> void:
	var layout := WorldLayoutGenerator.generate(42)
	var ports := CoastalPortPlacer.place_ports(layout)
	var zones := WorldTerrainStreamer.make_flatten_zones(ports,0,42,layout)
	var plan := CoastalSettlementPlan.build(layout,ports,zones)
	var groups := CoastalBridgePlan.new()
	groups._layout=layout; groups._label_land()
	var port_groups := {}
	for port: PortDefinition in ports: port_groups[port.port_id]=groups._component_at(Vector2(port.world_position.x,port.world_position.z))
	var parents := {}
	var max_grade := 0.0
	for road: PackedVector3Array in plan.roads:
		var a := str(road[0]); var b := str(road[1])
		if not parents.has(a): parents[a]=a
		if not parents.has(b): parents[b]=b
		parents[root_of(parents,a)]=root_of(parents,b)
		max_grade=maxf(max_grade,absf(road[0].y-road[1].y)/maxf(.01,Vector2(road[0].x-road[1].x,road[0].z-road[1].z).length()))
	var components := {}
	for key: String in parents:
		var root := root_of(parents,key)
		components[root]=components.get(root,0)+1
	var wrong_land := 0
	var occupied := {}
	for house: Dictionary in plan.buildings:
		var component := groups._component_at(Vector2(house.position.x,house.position.z))
		occupied[component]=true
		if component!=port_groups[house.port_id]: wrong_land+=1
	var largest := 0
	for size: int in components.values(): largest=maxi(largest,size)
	print("ROAD AUDIT seed=42 houses=",plan.buildings.size()," strips=",plan.roads.size()," separate_road_components=",components.size()," largest_component_nodes=",largest," max_endpoint_grade=",max_grade," houses_on_other_landmass=",wrong_land," occupied_landmasses=",occupied.size()," settlement_plan_ms=",plan.build_ms)
	quit()
