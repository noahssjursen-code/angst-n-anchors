class_name CoastalSettlements
extends Node3D

## Persistent cheap settlement silhouettes and nearby authored building shells.
## Pure scenery: no NPC simulation, per-house scripts or distant physics.
const LOD_DISTANCE := 480.0
var plan := {}
var _jobs: Array = []
var _groups := {}
var _colliders := {}
var _timer := 0.0
var build_peak_ms := 0.0
var _layout: WorldLayout
var _zones: Array
var _sample_cache := {}
var _zone_cache := {}

func configure(layout: WorldLayout, records: Dictionary, zones: Array) -> void:
	_layout=layout;plan=records;_zones=zones
	for item: Dictionary in plan.buildings:
		var point: Vector3 = item.position
		var coord := Vector2i(floori(point.x/256),floori(point.z/256))
		var chunk: Dictionary = _groups.get_or_add(coord,{"buildings":[],"roads":[],"drives":[]})
		chunk.buildings.append(item)
	for road: PackedVector3Array in plan.roads:
		var mid := (road[0]+road[1])*.5
		var coord := Vector2i(floori(mid.x/256),floori(mid.z/256))
		var chunk: Dictionary = _groups.get_or_add(coord,{"buildings":[],"roads":[],"drives":[]})
		chunk.roads.append(road)
	for drive: PackedVector3Array in plan.get("drives",[]):
		var mid := (drive[0]+drive[1])*.5
		var coord := Vector2i(floori(mid.x/256),floori(mid.z/256))
		var chunk: Dictionary = _groups.get_or_add(coord,{"buildings":[],"roads":[],"drives":[]})
		chunk.drives.append(drive)
	_jobs=_groups.keys()
	var reference := WorldReference.visual_position(get_viewport())
	_jobs.sort_custom(func(a:Vector2i,b:Vector2i): return Vector2(a*256).distance_squared_to(Vector2(reference.x,reference.z))<Vector2(b*256).distance_squared_to(Vector2(reference.x,reference.z)))

func _process(delta: float) -> void:
	if not _jobs.is_empty():
		var started := Time.get_ticks_usec()
		_build_chunk(_jobs.pop_front())
		build_peak_ms=maxf(build_peak_ms,(Time.get_ticks_usec()-started)/1000.0)
	_timer-=delta
	if _timer<=0:
		_timer=.5
		CoastalBuildingLibrary.set_night_factor(1.0-WeatherLighting.daylight_factor())
		_update_collisions(WorldReference.visual_position(get_viewport()))

func _build_chunk(coord: Vector2i) -> void:
	var node := Node3D.new(); node.name="Village_%d_%d"%[coord.x,coord.y]
	var center := Vector3(coord.x*256+128,0,coord.y*256+128)
	add_child(node);node.position=center
	var batches := {}
	for building: Dictionary in _groups[coord].buildings:
		var key := str(building.kind)+":"+str(building.paint)
		var batch: Dictionary = batches.get_or_add(key,{"kind":building.kind,"paint":building.paint,"transforms":[],"occupancy":[]})
		batch.transforms.append(Transform3D(Basis(Vector3.UP,float(building.yaw)),building.position-center))
		batch.occupancy.append(WorldForestStreamer._hash01(int(building.position.x),int(building.position.z),11,29))
	for batch: Dictionary in batches.values():
		for near in [false,true]:
			var instance := MultiMeshInstance3D.new()
			var multi := MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
			multi.use_custom_data=true
			multi.mesh=CoastalBuildingLibrary.mesh(batch.kind,near,int(batch.paint))
			multi.instance_count=batch.transforms.size()
			for i in multi.instance_count:
				multi.set_instance_transform(i,batch.transforms[i])
				multi.set_instance_custom_data(i,Color(batch.occupancy[i],0,0,0))
			instance.multimesh=multi
			instance.visibility_range_begin=0 if near else LOD_DISTANCE
			instance.visibility_range_end=LOD_DISTANCE if near else 0
			instance.visibility_range_begin_margin=35
			instance.visibility_range_end_margin=35
			instance.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if not near: instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(instance)
	_build_roads(node,center,_groups[coord].roads)
	_build_roads(node,center,_groups[coord].drives,true)

func _build_roads(parent: Node3D, center: Vector3, roads: Array, drives := false) -> void:
	if roads.is_empty(): return
	for shoulder in [true,false]:
		if drives and not shoulder: continue
		var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var half := 1.4 if drives else (2.65 if shoulder else 1.9)
		for road: PackedVector3Array in roads:
			var a := Vector2(road[0].x,road[0].z);var b := Vector2(road[1].x,road[1].z)
			var direction := (b-a).normalized();var side := Vector2(-direction.y,direction.x)*half
			var steps := maxi(1,ceili(a.distance_to(b)/1.5))
			for i in steps:
				var p := a.lerp(b,float(i)/steps);var q := a.lerp(b,float(i+1)/steps)
				var vertices: Array[Vector3] = []
				for xz: Vector2 in [p-side,p+side,q-side,q+side]:
					var y := CoastalSettlementPlan.height(_layout,xz,_zones,_zone_cache,_sample_cache)
					vertices.append(Vector3(xz.x,y+(.07 if shoulder else .09),xz.y)-center)
				for index in [0,2,1,1,2,3]: tool.add_vertex(vertices[index])
		tool.generate_normals()
		var mesh := MeshInstance3D.new();mesh.mesh=tool.commit()
		mesh.material_override=SurfaceMaterialLibrary.material("crushed_aggregate" if shoulder else "asphalt",Color(.32,.31,.27) if shoulder else Color(.26,.27,.27))
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_end=3500;mesh.visibility_range_end_margin=250
		mesh.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mesh)

func _update_collisions(reference: Vector3) -> void:
	var required := {}
	for coord: Vector2i in _groups:
		if Vector2(coord*256+Vector2i(128,128)).distance_to(Vector2(reference.x,reference.z))>330: continue
		for item: Dictionary in _groups[coord].buildings:
			if item.position.distance_to(reference)>160: continue
			var key := str(item.position)
			required[key]=true
			if _colliders.has(key): continue
			var body := StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
			add_child(body);body.position=item.position;body.rotation.y=item.yaw
			var shape := BoxShape3D.new();var footprint: Vector2 = CoastalSettlementPlan.FOOTPRINTS[item.kind]
			var height := 5.8 if item.kind=="house" else 3.6
			shape.size=Vector3(footprint.x,height,footprint.y)
			var collider := CollisionShape3D.new();collider.shape=shape;collider.position.y=height*.5
			body.add_child(collider);_colliders[key]=body
	for key in _colliders.keys():
		if not required.has(key): _colliders[key].queue_free();_colliders.erase(key)

func get_debug_stats() -> Dictionary:
	return {"buildings":plan.get("buildings",[]).size(),"road_segments":plan.get("roads",[]).size(),
		"pending":_jobs.size(),"chunks":_groups.size(),"colliders":_colliders.size(),
		"planning_ms":plan.get("build_ms",0),"build_peak_ms":build_peak_ms}
