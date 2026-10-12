extends Node

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	assert(ShipyardPlaytestMode.active())
	var terrain := WorldTerrainStreamer.new()
	assert(terrain._boot_ready_radius_m()==1000.0)
	terrain.free()
	var routes := [
		{"a":Vector3.ZERO,"b":Vector3(100,0,0),"width":8.0},
		{"a":Vector3(50,0,0),"b":Vector3(50,0,80),"width":8.0},
		{"a":Vector3(100,0,0),"b":Vector3(150,0,30),"width":6.0},
		{"a":Vector3(240,0,0),"b":Vector3(240,0,50),"width":6.0},
	]
	var caps := HarbourRoadSurface.exposed_end_caps(routes)
	for polygon in HarbourRoadSurface.footprint(routes):
		for i in polygon.size():
			var mid := (polygon[i]+polygon[(i+1)%polygon.size()])*.5
			assert(HarbourRoadSurface.is_end_cap(mid,caps)==old_end_cap(mid,routes),"Road edge paint changed")
	var zone := {"center":Vector2(10,10),"half_size":Vector2(3,3)}
	var near := WorldForestStreamer.new()
	var a := Transform3D(Basis.IDENTITY,Vector3(10,0,10))
	var b := Transform3D(Basis.IDENTITY,Vector3(2600,0,10))
	near._chunks[Vector2i.ZERO]={"node":null,"transforms":[a]}
	near._chunks[Vector2i(10,0)]={"node":null,"transforms":[b]}
	near.add_exclusions([zone])
	assert(not near._chunks.has(Vector2i.ZERO))
	assert(near._chunks.has(Vector2i(10,0)),"Bridge erased unrelated near forest")
	near.free()
	var far := DistantForest.new()
	var mm := MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	mm.mesh=BoxMesh.new()
	mm.instance_count=2
	mm.set_instance_transform(0,a)
	mm.set_instance_transform(1,b)
	var node := MultiMeshInstance3D.new()
	node.multimesh=mm
	node.set_meta("forest_bounds",Rect2(0,0,3000,100))
	far.add_child(node)
	far.trees=2
	far.add_exclusions([zone])
	while not far.exclusion_jobs.is_empty(): far._process_exclusions()
	assert(node.multimesh.instance_count==1 and node.multimesh.get_instance_transform(0)==b)
	assert(far.trees==1)
	var records := PackedFloat32Array([10,0,10,1,2600,0,10,1])
	assert(DistantForest.filter_placements(records,[zone])==PackedFloat32Array([2600,0,10,1]))
	far.free()
	print("LOADING PRIORITY PASS: 1 km ring, identical road markings, local forest exclusions")
	get_tree().quit()

func old_end_cap(midpoint: Vector2,routes: Array) -> bool:
	for r in routes:
		var direction := Vector2(r.b.x-r.a.x,r.b.z-r.a.z).normalized()
		for end in [r.a,r.b]:
			var point := Vector2(end.x,end.z)
			var connected := false
			for other in routes:
				if other==r: continue
				var closest := Geometry2D.get_closest_point_to_segment(point,Vector2(other.a.x,other.a.z),Vector2(other.b.x,other.b.z))
				if closest.distance_to(point)<.2: connected=true;break
			if connected or midpoint.distance_to(point)>float(r.width)*.5+.15: continue
			var inward := direction if end==r.a else -direction
			if (midpoint-point).dot(inward)<.1:return true
	return false
