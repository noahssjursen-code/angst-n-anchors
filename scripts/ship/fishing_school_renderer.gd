class_name FishingSchoolRenderer
extends Node3D
## Local presentation only. Habitat owns every fish, including those not drawn.
const LIMIT:=192
const RANGE_M:=180.0
var _batches:Dictionary={}
var _timer:=0.0
var _tracks:Array=[]
var _elapsed:=0.0

func _ready()->void:
	top_level=true;global_transform=Transform3D.IDENTITY
	physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF

func _process(delta:float)->void:
	if LocalPlayerView.get_active_ship()!=get_parent().get_parent():
		visible=false;return
	visible=true
	if FishingField.habitat==null:return
	var camera:=get_viewport().get_camera_3d()
	if camera==null:return
	_timer-=delta;_elapsed+=delta
	if _timer<=0:
		_timer=.25;_elapsed=0
		_refresh(camera.global_position)
	for track:Dictionary in _tracks:
		var target:Transform3D=track.target
		var pose:Transform3D=track.from.interpolate_with(target,clampf(_elapsed/.25,0,1))
		(_batches[track.species] as MultiMeshInstance3D).multimesh.set_instance_transform(track.slot,pose)

func _batch(species:String)->MultiMeshInstance3D:
	if _batches.has(species):return _batches[species]
	var model:=FishCatalog.model(species)
	var meshes:=model.find_children("*","MeshInstance3D",true,false)
	assert(not meshes.is_empty())
	var batch:=MultiMeshInstance3D.new()
	batch.multimesh=MultiMesh.new();batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh=(meshes[0] as MeshInstance3D).mesh
	batch.multimesh.instance_count=LIMIT;batch.multimesh.visible_instance_count=0
	batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch);_batches[species]=batch;model.free()
	return batch

func _refresh(at:Vector3)->void:
	var previous:Dictionary={}
	for track:Dictionary in _tracks:
		previous[track.id]=(_batches[track.species] as MultiMeshInstance3D).multimesh.get_instance_transform(track.slot)
	_tracks.clear()
	var schools:=FishingField.habitat.schools_near(Vector2(at.x,at.z),WorldClock.get_game_hours_elapsed(),RANGE_M)
	schools.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.position.distance_squared_to(Vector2(at.x,at.z))<b.position.distance_squared_to(Vector2(at.x,at.z)))
	var counts:Dictionary={}
	for school:Dictionary in schools:
		for fish:Dictionary in FishingField.habitat.members(school,WorldClock.get_game_hours_elapsed()):
			if _tracks.size()>=LIMIT:break
			if at.distance_to(fish.position)>RANGE_M:continue
			var batch:=_batch(fish.species)
			var slot:=int(counts.get(fish.species,0));counts[fish.species]=slot+1
			var x:Vector3=fish.heading
			var pose:=Transform3D(Basis(x,Vector3.UP,x.cross(Vector3.UP)).scaled(Vector3.ONE*float(fish.specimen.length_cm)/100),fish.position)
			_tracks.append({"id":fish.fish_id,"species":fish.species,"slot":slot,"from":previous.get(fish.fish_id,pose),"target":pose})
			batch.multimesh.set_instance_transform(slot,previous.get(fish.fish_id,pose))
	for species:String in _batches:
		(_batches[species] as MultiMeshInstance3D).multimesh.visible_instance_count=int(counts.get(species,0))
