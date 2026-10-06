class_name BlenderBulkCraneRig
extends Node3D

## Presentation adapter only. BulkCrane owns every control and cargo operation.
const DIRECTORY := "res://resources/models/parts/crane_kit/"
var parts: Dictionary = {}
var grab_visual: Node3D
var luff_barrel: Node3D
var luff_rod: Node3D
var feed_wire: Node3D
var grab_actuators: Array[Dictionary] = []

func _ready() -> void:
	var base := _part_node("base", self, Vector3.ZERO)
	_asset(base, "crane_pedestal")
	_box_collision(base, Vector3(3.6,.26,3.6), Vector3(0,.13,0))
	_box_collision(base, Vector3(2.24,2.03,2.24), Vector3(0,1.275,0))
	var cabin := _part_node("cabin", base, Vector3(0,2.29,0))
	_asset(cabin, "crane_cabin")
	# Same solid cab/machinery obstacle contract as the former convex meshes.
	_box_collision(cabin, Vector3(1.65,1.78,1.7), Vector3(0,.83,-.13))
	_box_collision(cabin, Vector3(1.9,1.55,2.7), Vector3(-1.9,.78,1))
	var seat := Node3D.new();seat.name="OperatorSeat";cabin.add_child(seat)
	var boom := _part_node("boom", cabin, Vector3(-1.75,3.7,-.25))
	_asset(boom, "crane_boom_30m")
	luff_barrel=_part_node("luff_barrel",cabin,Vector3(-1.75,1.2,-2))
	_asset(luff_barrel,"crane_luff_barrel")
	luff_rod=_part_node("luff_rod",cabin,Vector3.ZERO)
	_asset(luff_rod,"crane_luff_rod")
	feed_wire = _part_node("feed_wire", cabin, Vector3.ZERO)
	_asset(feed_wire,"crane_wire_10m")
	var wire := _part_node("wire", boom, Vector3(0,0,-30))
	_asset(wire, "crane_wire_10m")
	var bucket := _part_node("bucket", boom, Vector3.ZERO)
	grab_visual=Node3D.new();grab_visual.name="GrabScale";bucket.add_child(grab_visual)
	_asset(grab_visual,"grab_head")
	for side in ["left","right"]:
		var jaw := _part_node("shell_"+side,grab_visual,Vector3(0,-1,0))
		_asset(jaw,"grab_jaw_"+side)
		var barrel := _part_node("grab_barrel_"+side,grab_visual,Vector3.ZERO)
		_asset(barrel,"grab_actuator_barrel")
		var rod := _part_node("grab_rod_"+side,grab_visual,Vector3.ZERO)
		_asset(rod,"grab_actuator_rod")
		grab_actuators.append({"barrel":barrel,"rod":rod,"base":grab_visual.find_child("ActuatorBase"+side.capitalize(),true,false),"end":jaw.find_child("ActuatorEnd",true,false)})


func get_part(part_name: String) -> Node3D:
	return parts.get(part_name) as Node3D

func set_grab_scale(value: float) -> void:
	grab_visual.scale=Vector3.ONE*value

func update_luff_cylinder() -> void:
	var boom:=get_part("boom")
	var end:=boom.transform*Vector3(0,-.58,-6)
	var delta:=end-luff_barrel.position
	var direction:=delta.normalized()
	var rotation_basis:=Basis(Quaternion(Vector3.UP,direction))
	luff_barrel.basis=rotation_basis
	luff_rod.position=luff_barrel.position+direction*3.5
	luff_rod.basis=rotation_basis.scaled_local(Vector3(1,(delta.length()-3.5)/4,1))
	# Two tensioned feed lines connect the authored drum to the boom heel.
	var start := Vector3(-1.75,2.49,1)
	var heel := boom.transform * Vector3(0,.75,0)
	var feed := heel-start
	feed_wire.position=start
	feed_wire.basis=Basis(Quaternion(Vector3.DOWN,feed.normalized())).scaled_local(Vector3(1,feed.length()/10,1))

func update_grab_actuators() -> void:
	for item in grab_actuators:
		var start := grab_visual.to_local((item.base as Node3D).global_position)
		var end := grab_visual.to_local((item.end as Node3D).global_position)
		var direction := (end-start).normalized()
		var rotation_basis := Basis(Quaternion(Vector3.UP,direction))
		item.barrel.position=start
		item.barrel.basis=rotation_basis
		item.rod.position=start+direction*.50
		item.rod.basis=rotation_basis.scaled_local(Vector3(1,(end-start).length()*2-1,1))


func _part_node(part_name: String, parent: Node3D, offset: Vector3) -> Node3D:
	var node:=Node3D.new();node.name="ModelPart_"+part_name;node.position=offset
	parent.add_child(node);parts[part_name]=node
	return node

func _asset(parent: Node3D, asset_name: String) -> void:
	var scene:=load(DIRECTORY+asset_name+".glb") as PackedScene
	assert(scene != null, "Missing authored crane part: "+asset_name)
	parent.add_child(scene.instantiate())

func _box_collision(parent: Node3D, size_m: Vector3, center: Vector3) -> void:
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size_m
	shape.shape=box;shape.position=center;body.add_child(shape);parent.add_child(body)
