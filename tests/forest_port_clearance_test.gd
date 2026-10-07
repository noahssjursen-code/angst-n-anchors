extends Node
var failures := 0
class FlatLayout extends RefCounted:
	var half_extent_m := 20000.0
	func sample_signed_distance(_p:Vector2) -> float: return -500.0
	func sample_height(_p:Vector2) -> float: return 30.0

func check(ok:bool,message:String) -> void:
	if not ok: failures+=1;push_error(message)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var graph:=PortLayoutGraph.new()
	var foundation:Dictionary={"spine":[[-360,0],[-160,5],[0,20],[160,0],[360,-10]],"town_inland_m":160,"dock_reach_m":26,"bay_lip_m":6}
	var profile:=PortTradeProfile.new()
	var plan:=PortFacilityPlan.build(foundation,{},profile,3)
	graph.initial_attributes={"foundation":foundation,"land_plan":{"facility_plan":plan}}
	var serialized:=var_to_bytes(graph.to_dict())
	var position:=Vector3(8000,0,-6200)
	var layout:=FlatLayout.new()
	for yaw in [0.0,.7,PI,-1.4]:
		var zones:=graph.flatten_zone_records(position,yaw)
		var basis:=Basis(Vector3.UP,yaw)
		for route in plan.routes:
			var a:=Vector2(route.a[0],route.a[1])
			var b:=Vector2(route.b[0],route.b[1])
			for step in 11:
				var p:=a.lerp(b,float(step)/10)
				var world:=position+basis*Vector3(p.x,0,p.y)
				check(ForestField.inside_flatten_zones(Vector2(world.x,world.z),zones),"Road must remain clear of trees")
		for facility in plan.facilities:
			for p in PortFacilityPlan.parcel_polygon(facility):
				var world:=position+basis*Vector3(p.x,0,p.y)
				check(ForestField.inside_flatten_zones(Vector2(world.x,world.z),zones),"Occupied parcel must remain clear")
		var back:=position+basis*Vector3(0,0,230)
		check(not ForestField.inside_flatten_zones(Vector2(back.x,back.z),zones),"Unused hinterland must not be cleared")
		for x in range(-450,451,25):
			for z in range(-50,501,25):
				var p3:=position+basis*Vector3(x,0,z)
				var p:=Vector2(p3.x,p3.z)
				check(is_equal_approx(WorldTerrainStreamer.sample_render_terrain_height(layout,p,zones),WorldTerrainStreamer.sample_render_terrain_height(layout,p,[])),"Forest mask must not change terrain height")
	check(serialized==var_to_bytes(graph.to_dict()),"Vegetation mask must not mutate saved port graph")
	# Legacy house plots still keep clearance without deleting the whole town.
	graph.initial_attributes.land_plan={"terrain_grid":{"points":[{"local":[0,230],"radius_m":4}]}}
	var legacy:=graph.flatten_zone_records(position,0)
	check(ForestField.inside_flatten_zones(Vector2(8000,-5970),legacy),"Legacy occupied plot remains clear")
	check(not ForestField.inside_flatten_zones(Vector2(8040,-5970),legacy),"Legacy plot does not clear unused neighbouring land")
	# Queue prioritization retains partial work while following the actual camera.
	var streamer:=WorldForestStreamer.new()
	streamer._layout=layout
	streamer._refresh_requests(Vector3.ZERO)
	streamer._refresh_requests(Vector3(1800,0,0))
	check(Vector2(streamer._jobs[0].coord).distance_to(Vector2(7,0))<=1.5,"Approaching trees must not wait behind old distant requests")
	streamer.free()
	print("FOREST PORT CLEARANCE ","PASS" if failures==0 else "FAIL")
	get_tree().quit(0 if failures==0 else 1)
