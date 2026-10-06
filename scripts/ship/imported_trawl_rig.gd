class_name ImportedTrawlRig
extends Node3D

## Presentation only. FishingSystem owns requests, catch, drag and authority.
## Fixed assets are Blender exports. Only flexible line spans are generated here.
const DIRECTORY := "res://resources/models/parts/trawl_rig/"
var winch:Node3D
var gantry:Node3D
var boat:BoatBody
var net:Node3D
var bundle:Node3D
var doors:Array[Node3D]=[]
var blocks:Array[Node3D]=[]
var ropes:Array[MeshInstance3D]=[]
var routes:Array[PackedVector3Array]=[]
var deployed:=false
var rope_length:=11.0

func _ready() -> void:
	name="ImportedTrawlRig"
	net=_asset("trawl_net_open")
	for side in ["Port","Starboard"]:
		var stow:=gantry.find_child(side+"DoorStow",true,false) if is_instance_valid(gantry) else null
		var door:Node3D
		if stow!=null:
			door=stow.get_child(0) as Node3D
		else:door=_asset("trawl_door_"+side.to_lower())
		_mark_stowed(door);doors.append(door)
		blocks.append(gantry.find_child(side+"BlockMount",true,false) as Node3D if is_instance_valid(gantry) else null)
	if is_instance_valid(gantry):
		bundle=(gantry.find_child("NetStow",true,false) as Node3D).get_child(0) as Node3D
		_mark_stowed(bundle)
	var line_mesh:=CylinderMesh.new();line_mesh.top_radius=.011;line_mesh.bottom_radius=.011
	line_mesh.height=1;line_mesh.radial_segments=8
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.26,.29,.23);material.roughness=.87
	for i in 24:
		var line_:=MeshInstance3D.new();line_.name="Warp%d"%i;line_.mesh=line_mesh;line_.material_override=material
		line_.set_meta("fishing_rig_visual",true);add_child(line_);ropes.append(line_)
	update_rig(false,0)

func _asset(id:String) -> Node3D:
	var root:Node3D=(load(DIRECTORY+id+".glb") as PackedScene).instantiate()
	add_child(root);_mark_visual(root);return root

func _mark_visual(root:Node3D) -> void:
	for mesh:MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		mesh.set_meta("fishing_rig_visual",true)

func _mark_stowed(root:Node3D) -> void:
	for mesh:MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		mesh.remove_meta("fishing_rig_visual")
		mesh.set_meta("fishing_stow_visual",true)
		mesh.set_meta("fishing_stowed",true)

func _stow_collision(root:Node3D,stowed:bool) -> void:
	for mesh:MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		mesh.set_meta("fishing_stowed",stowed)

func _socket(root:Node3D,id:String) -> Vector3:
	var socket:=root.find_child(id,true,false) as Node3D
	assert(socket!=null,"Missing authored trawl socket "+id)
	return socket.global_position

func update_rig(active:bool,delta:float) -> void:
	deployed=active
	if net==null:return
	net.visible=active
	if is_instance_valid(bundle):
		bundle.visible=not active
		_stow_collision(bundle,not active)
	for door in doors:_stow_collision(door,not active and is_instance_valid(gantry))
	for line_ in ropes:line_.hide()
	routes.clear()
	if not active:
		for door in doors:
			door.visible=is_instance_valid(gantry)
			if is_instance_valid(gantry):door.transform=Transform3D.IDENTITY
		return
	var aft:=boat.global_basis.z;aft.y=0;aft=aft.normalized()
	var right:=Vector3.UP.cross(aft).normalized()
	var basis_:=Basis(right,Vector3.UP,aft)
	var origin:Vector3=gantry.global_position if is_instance_valid(gantry) else winch.global_position
	var door_centre:=origin+aft*rope_length
	var mouth:=door_centre+aft*3.6
	mouth.y=WaveSurface.get_height_at(mouth.x,mouth.z)-.8
	net.global_transform=Transform3D(basis_,mouth)
	var line_index:=0
	for index in 2:
		var side:float=-1.0 if index==0 else 1.0
		var prefix:String="Port" if index==0 else "Starboard"
		var door:=doors[index];door.show()
		var position_:=door_centre+right*side*3.5
		position_.y=WaveSurface.get_height_at(position_.x,position_.z)-1.6
		door.global_transform=Transform3D(basis_*Basis(Vector3.UP,side*deg_to_rad(12)),position_)
		var payout:=winch.find_child("Payout"+prefix,true,false) as Node3D
		assert(payout!=null,"Imported winch needs two payout sockets")
		var points:=PackedVector3Array([payout.global_position])
		if is_instance_valid(blocks[index]):
			for i in 9:points.append(_socket(blocks[index],"WarpLead%d"%i))
			var pivot:=blocks[index].find_child("SheavePivot",true,false) as Node3D
			pivot.rotate_x(delta*2.5)
		points.append(_socket(door,"TowPoint"))
		routes.append(points)
		for i in points.size()-1:
			_span(ropes[line_index],points[i],points[i+1]);line_index+=1
		for level in ["Upper","Lower"]:
			var start:=_socket(door,"Bridle"+level);var end:=_socket(net,prefix+"Wing"+level)
			_span(ropes[line_index],start,end);line_index+=1
	assert(line_index<=ropes.size())

func _span(line_:MeshInstance3D,from:Vector3,to:Vector3) -> void:
	var distance:=from.distance_to(to)
	if distance<.001:return
	var y:=(to-from)/distance
	var ref:=Vector3.UP if absf(y.dot(Vector3.UP))<.99 else Vector3.RIGHT
	var x:=y.cross(ref).normalized();var z:=x.cross(y).normalized()
	line_.global_transform=Transform3D(Basis(x,y*distance,z),(from+to)*.5)
	line_.show()
