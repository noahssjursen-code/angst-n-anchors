extends Node
class Plateau extends WorldLayout:
	func sample_height(_p:Vector2)->float:return 90.0
	func sample_signed_distance(_p:Vector2)->float:return -100.0
class Inlet extends WorldLayout:
	func sample_height(p:Vector2)->float:return (-10.0 if absf(p.x)<45 and p.y<105 else 10.0)+WorldTerrainStreamer.TERRAIN_SINK_M
	func sample_signed_distance(p:Vector2)->float:return 100.0 if absf(p.x)<45 and p.y<105 else -100.0
func _ready()->void:
	var layout:=Plateau.new()
	var zones:=[{"polygon":PackedVector2Array([Vector2(-1500,-1500),Vector2(1500,-1500),Vector2(1500,1500),Vector2(-1500,1500)]),"cut_only":true,"height":2.0,"falloff":240.0,"clearance_margin":36.0}]
	var roads:=[PackedVector3Array([Vector3(-650,2.2,-100),Vector3(-650,2.2,100)]),PackedVector3Array([Vector3(650,2.2,-100),Vector3(650,2.2,100)])]
	var plan:=BridgeStructurePlan.design({"a_xz":Vector2(-150,0),"b_xz":Vector2(150,0),"a_ground":87.5,"b_ground":87.5},layout,"",zones,roads)
	assert(plan.accepted)
	assert(plan.deck_y<40,"Old bank height controls bridge instead of graded terrain")
	assert(plan.road_links.size()==2)
	for i in 2:
		var p:Vector3=plan.approaches[i]
		assert(absf(p.y-2.08)<.001,"Landing floats above graded ground")
		var road:Array=plan.road_links[i]
		assert(road.size()>1,"No road connected")
		assert(absf(road[0].left.y-p.y)<.001)
		assert(absf(road[-1].left.y-2.24)<.001,"Connector misses existing road elevation")
		assert(plan.landing_bases[i]<2.0-4.9)
	var bridge:=BridgeAssembler.build(plan);add_child(bridge)
	assert(bridge.get_node("BridgeCollision").get_child_count()>10)
	var road_end:Vector3=bridge.to_local(plan.road_links[0][-1].left)
	var visible_end:=false
	for mesh:MeshInstance3D in bridge.find_children("*","MeshInstance3D",true,false):
		for vertex:Vector3 in mesh.mesh.get_faces():
			if vertex.distance_to(road_end)<.01: visible_end=true;break
	assert(visible_end,"Road connector has collision but no rendered faces")
	var inlet:=Inlet.new()
	var detour:=preload("res://scripts/world/bridge_road_connector.gd").connect_road(inlet,Vector3(-200,10.09,0),[PackedVector3Array([Vector3(200,10.09,-20),Vector3(200,10.09,20)])],[])
	assert(detour.size()>2,"Road search failed to route around inlet")
	var goes_around:=false
	for section:Dictionary in detour:
		if section.left.z>105: goes_around=true
	assert(goes_around,"Connector crossed inlet instead of routing around it")
	print("GRADED BRIDGE LANDINGS AND ROAD CONNECTIONS PASS")
	get_tree().quit()
