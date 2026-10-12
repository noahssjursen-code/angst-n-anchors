class_name HarpeRigVisual
extends Node3D

var _hooks:Array[Node3D]=[]
var _fish:Dictionary={}
var _sinker:Node3D
var _branches:MeshInstance3D

func _ready()->void:
	top_level=true;global_transform=Transform3D.IDENTITY
	_sinker=load("res://resources/models/fishing_items/harpe_sinker.glb").instantiate();add_child(_sinker)
	for i in 6:
		var hook:Node3D=load("res://resources/models/fishing_items/harpe_hook.glb").instantiate()
		add_child(hook);_hooks.append(hook)
	_branches=MeshInstance3D.new();_branches.mesh=ImmediateMesh.new()
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(.65,.76,.72);material.cull_mode=BaseMaterial3D.CULL_DISABLED
	_branches.material_override=material;add_child(_branches)

func update_rig(session:HarpeFishingSession,sinker:Vector3,tip:Vector3,time:float)->void:
	visible=session.phase in ["casting","fishing","fighting","landed"]
	if not visible:return
	_sinker.global_position=sinker
	var mesh:=_branches.mesh as ImmediateMesh;mesh.clear_surfaces();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var top:=leader_top(session,sinker,tip)
	var axis:=(top-sinker).normalized()
	var spacing:=top.distance_to(sinker)/6
	_segment(mesh,sinker,top)
	var side:=axis.cross(Vector3.FORWARD).normalized()
	if side.length()<.5:side=Vector3.RIGHT
	var active:Dictionary={}
	for i in 6:
		var junction:=sinker+axis*(i+1)*spacing
		var mouth:=junction+side*(.20 if i%2==0 else -.20)
		_segment(mesh,junction,mouth)
		_hooks[i].global_position=mouth
		var occupied:=false
		for caught in session.catches:
			if int(caught.hook_index)!=i:continue
			occupied=true
			var id:=str(caught.fish_id);active[id]=true
			if not _fish.has(id):
				var model:=FishCatalog.model(str(caught.species_id));add_child(model)
				var socket:=model.find_child("MouthHook",true,false) as Node3D
				_fish[id]={"model":model,"socket":model.to_local(socket.global_position)}
			var entry:Dictionary=_fish[id]
			entry.model.global_transform=FishCatalog.hooked_transform(mouth,junction,entry.socket,float(caught.length_cm)/100,sin(time*7+i)*.15)
		_hooks[i].visible=not occupied
	mesh.surface_end()
	for id in _fish.keys():
		if not active.has(id):_fish[id].model.queue_free();_fish.erase(id)

func _segment(mesh:ImmediateMesh,a:Vector3,b:Vector3)->void:
	var camera:=get_viewport().get_camera_3d()
	var side:=(b-a).cross(camera.global_position-a).normalized()*.002
	for vertex in [a-side,a+side,b+side,a-side,b+side,b-side]:mesh.surface_add_vertex(vertex)


static func leader_top(session:HarpeFishingSession,sinker:Vector3,tip:Vector3)->Vector3:
	if session.phase=="fishing":return sinker+Vector3.UP*HarpeFishingSession.HOOK_SPACING_M*6
	return sinker+(tip-sinker).normalized()*minf(HarpeFishingSession.HOOK_SPACING_M*6,sinker.distance_to(tip)*.85)
