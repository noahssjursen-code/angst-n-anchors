extends Node
class StreamFixture extends CoastalBridges:
	func _ready() -> void: pass
func _ready() -> void:
	var planner:=CoastalBridgePlan.new()
	planner._mainland=0
	planner._areas={0:100000000,1:5000000}
	assert(not planner._terminal(1),"Large empty islands are not destinations")
	planner._port_components[1]=["Inhabited"]
	assert(planner._terminal(1))
	var camera:=Camera3D.new()
	add_child(camera);camera.current=true
	var stream:=StreamFixture.new()
	add_child(stream)
	var plan:=BridgeStructurePlan.design({"id":1,"a_xz":Vector2.ZERO,"b_xz":Vector2(300,0),"a_ground":10.0,"b_ground":10.0})
	plan["planning_ms"]=0.0
	var crossing:=BridgeStructurePlan.design({"id":2,"a_xz":Vector2(150,-100),"b_xz":Vector2(150,100),"a_ground":10.0,"b_ground":10.0})
	assert(CoastalBridges.conflicts_with(crossing,[plan]),"Crossing spans must be rejected")
	var separate:=BridgeStructurePlan.design({"id":3,"a_xz":Vector2(0,2000),"b_xz":Vector2(300,2000),"a_ground":10.0,"b_ground":10.0})
	assert(not CoastalBridges.conflicts_with(separate,[plan]))
	stream._completed.append(plan)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(stream._nodes.size()==1,"Ready bridges must publish before global planning completes")
	var bridge:Node3D=stream._nodes[1]
	var identity:=bridge.get_instance_id()
	camera.position=Vector3(30000,100,0)
	await get_tree().create_timer(.4).timeout
	assert(not bridge.visible,"Far bridge must stop rendering")
	assert(bridge.get_node("BridgeCollision").collision_layer==0)
	camera.position=Vector3(150,30,0)
	await get_tree().create_timer(.4).timeout
	assert(bridge.visible and bridge.get_instance_id()==identity,"Return must reuse the bridge immediately")
	assert(bridge.get_node("BridgeCollision").collision_layer==1)
	assert(CoastalBridges.distance_to_plan(Vector2(150,0),plan)<.01)
	print("BRIDGE STREAMING PASS: progressive publish, distance cull, cached return, local collision")
	get_tree().quit()
