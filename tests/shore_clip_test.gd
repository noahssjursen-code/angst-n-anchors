extends SceneTree
class Coast extends RefCounted:
	func sample_signed_distance(p:Vector2) -> float: return p.x-100
	func sample_height(p:Vector2) -> float:
		return (100-p.x)*(100-p.x)*.1 if p.x<100 else -(p.x-100)*.2
func _initialize() -> void:
	var coast:=Coast.new()
	for step:float in [25.0,50.0,100.0,200.0]:
		var x:=floorf(128.0/step)*step
		var points:=PackedVector3Array([Vector3(x,400,0),Vector3(x+step,-10,0)])
		var forward:=points.duplicate();var reverse:=points.duplicate()
		var a:=WorldTerrainStreamer._shore_edge_vertex(forward,PackedColorArray(),0,1,x-128,x+step-128,coast,[])
		var b:=WorldTerrainStreamer._shore_edge_vertex(reverse,PackedColorArray(),1,0,x+step-128,x-128,coast,[])
		assert(forward[a]==reverse[b],"Opposite shared edge winding changes shoreline")
		assert(absf(forward[a].x-128)<.001 and absf(forward[a].y+8.1)<.001,"Clipped shore inherits hill height")
	var layout:=WorldLayoutGenerator.generate(424242)
	var bad:=0;var total:=0;var worst:=0.0
	for z in range(-20,20):
		for x in range(-20,20):
			var data:=WorldTerrainStreamer.build_chunk_mesh_data(layout,Vector2i(x,z),200,[],0)
			var vertices:PackedVector3Array=data.vertices
			var used:Dictionary={}
			for index in data.indices: used[index]=true
			for i in used:
				if i<data.surface_side*data.surface_side: continue
				total+=1
				var p:=Vector2(vertices[i].x,vertices[i].z)
				var expected:=WorldTerrainStreamer.sample_render_terrain_height(layout,p)
				worst=maxf(worst,absf(vertices[i].y-expected))
				if vertices[i].y>0 and expected<0: bad+=1
	assert(bad==0 and worst<.001,"Clipped shelf differs from terrain height field")
	assert(total>1000,"Regression missed the real coastline")
	print("SHORE CLIP sample_count=",total," erroneous_above_water=",bad," maximum_height_error=",worst)
	quit()
