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
var deployment_fraction:=0.0
var deploy_seconds:=12.0
var recover_seconds:=16.0
var warp_travel_delta:=0.0
var _fold_meshes:Array[MeshInstance3D]=[]
var _last_warp_lengths: Array[float]=[]

func _ready() -> void:
	name="ImportedTrawlRig"
	net=_asset("trawl_net_open")
	for mesh: MeshInstance3D in net.find_children("*","MeshInstance3D",true,false):
		assert(mesh.find_blend_shape_by_name("Stowed")>=0,"Net needs its Blender-authored folded shape")
		mesh.extra_cull_margin=.4 # Folded twine extends slightly forward of the open-net bounds.
		_fold_meshes.append(mesh)
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
	var previous_fraction:=deployment_fraction
	deployment_fraction=move_toward(deployment_fraction,1.0 if active else 0.0,maxf(delta,0)/maxf(deploy_seconds if active else recover_seconds,.01))
	var moving:=not is_equal_approx(previous_fraction,deployment_fraction)
	var stowed:=is_zero_approx(deployment_fraction) and not active
	warp_travel_delta=0
	net.visible=not stowed
	if is_instance_valid(bundle):
		bundle.visible=stowed
		_stow_collision(bundle,stowed)
	for door in doors:_stow_collision(door,stowed and is_instance_valid(gantry))
	for line_ in ropes:line_.hide()
	routes.clear()
	var aft:=boat.global_basis.z;aft.y=0;aft=aft.normalized()
	var right:=Vector3.UP.cross(aft).normalized()
	var basis_:=Basis(right,Vector3.UP,aft)
	var deck_basis:=boat.global_basis.orthonormalized()
	var origin:Vector3=gantry.global_position if is_instance_valid(gantry) else winch.global_position
	var door_centre:=origin+aft*rope_length
	var mouth:=door_centre+aft*3.6
	mouth.y=WaveSurface.get_height_at(mouth.x,mouth.z)-.8
	var net_rest:=bundle.global_transform if is_instance_valid(bundle) else Transform3D(deck_basis,origin+deck_basis*Vector3(0,.34,.95))
	net.global_transform=_travel_pose(net_rest,net_rest.origin+deck_basis.y*1.35,origin+deck_basis*Vector3(0,1.69,4.3),Transform3D(basis_,mouth))
	var unfold:=smoothstep(.48,1.0,deployment_fraction)
	for mesh in _fold_meshes:mesh.set_blend_shape_value(mesh.find_blend_shape_by_name("Stowed"),1.0-unfold)
	var line_index:=0
	for index in 2:
		var side:float=-1.0 if index==0 else 1.0
		var prefix:String="Port" if index==0 else "Starboard"
		var door:=doors[index];door.show()
		var position_:=door_centre+right*side*3.5
		position_.y=WaveSurface.get_height_at(position_.x,position_.z)-1.6
		var rest:Transform3D=(door.get_parent() as Node3D).global_transform if is_instance_valid(gantry) else Transform3D(deck_basis,origin+deck_basis*Vector3(side*1.62,.08,.12))
		door.global_transform=_travel_pose(rest,rest.origin+deck_basis.y*1.28,origin+deck_basis*Vector3(side*1.85,1.36,3.65),Transform3D(basis_*Basis(Vector3.UP,side*deg_to_rad(12)),position_))
		if stowed and is_instance_valid(gantry):door.transform=Transform3D.IDENTITY
		door.visible=not stowed or is_instance_valid(gantry)
		var payout:=winch.find_child("Payout"+prefix,true,false) as Node3D
		assert(payout!=null,"Imported winch needs two payout sockets")
		var points:=PackedVector3Array([payout.global_position])
		if is_instance_valid(blocks[index]):
			for i in 9:points.append(_socket(blocks[index],"WarpLead%d"%i))
		points.append(_socket(door,"TowPoint"))
		routes.append(points)
		var length_:=0.0
		for i in points.size()-1:length_+=points[i].distance_to(points[i+1])
		if _last_warp_lengths.size()<=index:_last_warp_lengths.append(length_)
		var travel:=length_-_last_warp_lengths[index] if moving else 0.0
		_last_warp_lengths[index]=length_
		warp_travel_delta+=travel*.5
		if is_instance_valid(blocks[index]):
			var pivot:=blocks[index].find_child("SheavePivot",true,false) as Node3D
			pivot.rotate_x(-travel/.191)
		for i in points.size()-1:
			if not stowed or is_instance_valid(gantry):_span(ropes[line_index],points[i],points[i+1])
			line_index+=1
		for level in ["Upper","Lower"]:
			var start:=_socket(door,"Bridle"+level)
			var end:=_socket(net,prefix+"Wing"+level+"Stowed").lerp(_socket(net,prefix+"Wing"+level),unfold)
			if not stowed:_span(ropes[line_index],start,end)
			line_index+=1
	assert(line_index<=ropes.size())

func _travel_pose(rest:Transform3D,raised:Vector3,clear:Vector3,water:Transform3D) -> Transform3D:
	# Lift above the bulwark before moving aft. Reverse traverses the same path,
	# so repeated G presses never teleport hardware or restart from an endpoint.
	if deployment_fraction<=.22:
		return Transform3D(rest.basis,rest.origin.lerp(raised,smoothstep(0,.22,deployment_fraction)))
	if deployment_fraction<=.48:
		return Transform3D(rest.basis,raised.lerp(clear,smoothstep(.22,.48,deployment_fraction)))
	var t:=smoothstep(.48,1.0,deployment_fraction)
	return Transform3D(rest.basis.slerp(water.basis,t),clear.lerp(water.origin,t))

func is_transitioning() -> bool:
	return not is_equal_approx(deployment_fraction,1.0 if deployed else 0.0)

func activity_label() -> String:
	if is_transitioning():return "SETTING GEAR" if deployed else "RECOVERING GEAR"
	return "TOWING" if deployed else "STOWED"

func _span(line_:MeshInstance3D,from:Vector3,to:Vector3) -> void:
	var distance:=from.distance_to(to)
	if distance<.001:return
	var y:=(to-from)/distance
	var ref:=Vector3.UP if absf(y.dot(Vector3.UP))<.99 else Vector3.RIGHT
	var x:=y.cross(ref).normalized();var z:=x.cross(y).normalized()
	line_.global_transform=Transform3D(Basis(x,y*distance,z),(from+to)*.5)
	line_.show()
