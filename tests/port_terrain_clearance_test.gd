extends SceneTree

class Hillside extends RefCounted:
	func sample_signed_distance(_p: Vector2) -> float: return -100.0
	func sample_height(p: Vector2) -> float: return 95.0 + p.y * 0.04

func _initialize() -> void:
	var graph := PortLayoutGraph.new()
	graph.initial_attributes = {"foundation": {"spine": [[-160,0],[0,12],[160,0]], "town_inland_m":88.0,"surface_y_m":2.0}}
	var hillside := Hillside.new()
	for yaw in [0.0, 0.7, 2.1]:
		var zones := graph.flatten_zone_records(Vector3(490,3,480),yaw)
		var zone: Dictionary = zones[0]
		assert(zone.cut_only)
		var polygon: PackedVector2Array = zone.polygon
		assert(is_equal_approx(zone.height,4.88))
		var center := Vector2.ZERO
		for p in polygon: center += p
		center /= polygon.size()
		assert(WorldTerrainStreamer.sample_render_terrain_height(hillside,center,zones)<=4.881)
		var outside := Vector2(50,50)
		assert(is_equal_approx(WorldTerrainStreamer.sample_render_terrain_height(hillside,outside,zones),hillside.sample_height(outside)-WorldTerrainStreamer.TERRAIN_SINK_M))
		for step in [25.0,50.0,100.0,200.0]:
			var data := WorldTerrainStreamer.build_chunk_mesh_data(hillside,Vector2i.ZERO,step,zones,0.0)
			var vertices: PackedVector3Array=data.vertices
			var indices: PackedInt32Array=data.indices
			for v in vertices:
				assert(absf(v.y-WorldTerrainStreamer.sample_render_terrain_height(hillside,Vector2(v.x,v.z),zones))<0.001,"Mesh changed after shared height sampling")
			var checked:=0
			for i in range(0,indices.size(),3):
				var tri:=PackedVector2Array()
				for j in 3:
					var v:=vertices[indices[i+j]]
					tri.append(Vector2(v.x,v.z))
				var a:=vertices[indices[i]]
				var b:=vertices[indices[i+1]]
				var c:=vertices[indices[i+2]]
				var p:=(a+b+c)/3.0
				var root_height:=WorldForestStreamer.sample_root_height(hillside,Vector2(p.x,p.z),zones,{})
				assert(absf(root_height-p.y)<0.01,"Scenery height disagrees with port mesh")
				if Geometry2D.intersect_polygons(tri,polygon).is_empty(): continue
				for j in 3: assert(vertices[indices[i+j]].y<=4.881,"Terrain crosses foundation")
				checked+=1
			assert(checked>0)
			print("CLEARANCE yaw=",yaw," step=",step," triangles=",checked)
	var edge_zones := graph.flatten_zone_records(Vector3(1000,3,480),0.7)
	var west := WorldTerrainStreamer.sample_chunk_border(hillside,Vector2i.ZERO,25,&"east",edge_zones)
	var east := WorldTerrainStreamer.sample_chunk_border(hillside,Vector2i(1,0),200,&"west",edge_zones)
	for p in east:
		assert(west.has(p),"Port grading differs across chunk/LOD boundary")
	# Excavation must not fill water underneath piers.
	assert(WorldTerrainStreamer._apply_flatten_zones(-30,10,Vector2(490,480),graph.flatten_zone_records(Vector3(490,3,480),0)) == -30)
	print("PORT TERRAIN CLEARANCE PASS")
	quit()
