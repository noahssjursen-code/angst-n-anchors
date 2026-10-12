class_name BridgeRoadConnector
extends RefCounted

## Local road ties use the rendered ground, never the ungraded macro height.
static func connect_road(layout: WorldLayout, landing: Vector3, roads: Array, zones: Array) -> Array:
	var start := Vector2(landing.x,landing.z)
	var targets: Array[Dictionary] = []
	for road: PackedVector3Array in roads:
		for i in range(road.size()-1):
			var a:=Vector2(road[i].x,road[i].z)
			var b:=Vector2(road[i+1].x,road[i+1].z)
			var point:=Geometry2D.get_closest_point_to_segment(start,a,b)
			if start.distance_to(point)>900: continue
			var f:=a.distance_to(point)/maxf(.001,a.distance_to(b))
			targets.append({"point":point,"height":lerpf(road[i].y,road[i+1].y,f)})
	targets.sort_custom(func(a:Dictionary,b:Dictionary):return start.distance_squared_to(a.point)<start.distance_squared_to(b.point))
	var cache:={}
	for item: Dictionary in targets.slice(0,12):
		var target:Vector2=item.point
		if target.distance_to(start)<1: continue
		var sections:=_sections(layout,PackedVector3Array([landing,Vector3(target.x,item.height+.04,target.y)]),zones,cache)
		if not sections.is_empty(): return sections
	if targets.is_empty(): return []
	# Bounded local path search for slopes and small inlets; no global road bake.
	var bounds:=Rect2(start,Vector2.ZERO)
	for item:Dictionary in targets.slice(0,8): bounds=bounds.expand(item.point)
	bounds=bounds.grow(150)
	var origin:Vector2=Vector2(floori(bounds.position.x/25)*25,floori(bounds.position.y/25)*25)
	var size:=Vector2i(ceili(bounds.end.x/25)-floori(origin.x/25)+1,ceili(bounds.end.y/25)-floori(origin.y/25)+1)
	var graph:=AStar3D.new()
	for z in size.y:
		for x in size.x:
			var p:=origin+Vector2(x,z)*25
			var h:=WorldForestStreamer.sample_root_height(layout,p,zones,cache)+.09
			if h<=WaveSurface.WATER_LEVEL+.7: continue
			var dry:=true
			for offset:Vector2 in [Vector2(18,18),Vector2(-18,18),Vector2(18,-18),Vector2(-18,-18)]:
				var edge_height:=WorldForestStreamer.sample_root_height(layout,p+offset,zones,cache)
				if edge_height<=WaveSurface.WATER_LEVEL+.5 or absf(edge_height+.09-h)>3.0: dry=false;break
			if not dry: continue
			graph.add_point(z*size.x+x,Vector3(p.x,h,p.y))
	for z in size.y:
		for x in size.x:
			var id:=z*size.x+x
			if not graph.has_point(id): continue
			for offset:Vector2i in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1)]:
				var q:=Vector2i(x,z)+offset
				if q.x<0 or q.x>=size.x or q.y>=size.y: continue
				var other:=q.y*size.x+q.x
				if not graph.has_point(other): continue
				if absf(graph.get_point_position(id).y-graph.get_point_position(other).y)/(Vector2(offset).length()*25)>.12: continue
				graph.connect_points(id,other)
	var start_id:=size.x*size.y
	_attach(graph,start_id,landing)
	for item:Dictionary in targets.slice(0,8):
		var target:Vector2=item.point
		var end_id:=start_id+1
		_attach(graph,end_id,Vector3(target.x,item.height+.04,target.y))
		var path:=graph.get_point_path(start_id,end_id)
		graph.remove_point(end_id)
		if path.size()<2: continue
		var sections:=_sections(layout,path,zones,cache)
		if not sections.is_empty(): return sections
	return []

static func _attach(graph:AStar3D,id:int,p:Vector3)->void:
	var neighbours:=PackedInt64Array()
	for other in graph.get_point_ids():
		var q:=graph.get_point_position(other)
		var distance:=Vector2(p.x-q.x,p.z-q.z).length()
		if distance>0.01 and distance<40 and absf(p.y-q.y)/distance<=.14: neighbours.append(other)
	graph.add_point(id,p)
	for other in neighbours: graph.connect_points(id,other)

static func _sections(layout:WorldLayout,path:PackedVector3Array,zones:Array,cache:Dictionary)->Array:
	var samples:=PackedVector3Array()
	for segment in range(path.size()-1):
		var count:=maxi(1,ceili(path[segment].distance_to(path[segment+1])/2.0))
		for i in count: samples.append(path[segment].lerp(path[segment+1],float(i)/count))
	samples.append(path[-1])
	var sections:Array=[]
	var previous:=path[0]
	for i in samples.size():
		var p:=Vector2(samples[i].x,samples[i].z)
		var tangent:=samples[mini(i+1,samples.size()-1)]-samples[maxi(0,i-1)]
		var side:=Vector2(tangent.x,tangent.z).normalized().orthogonal()
		var half_width:=lerpf(6.0,1.9,smoothstep(0,1,float(i)/maxi(1,samples.size()-1)))
		var left:=p+side*half_width;var right:=p-side*half_width
		var lh:=WorldForestStreamer.sample_root_height(layout,left,zones,cache)+.09
		var rh:=WorldForestStreamer.sample_root_height(layout,right,zones,cache)+.09
		var h:=WorldForestStreamer.sample_root_height(layout,p,zones,cache)+.09
		if minf(lh,rh)<=WaveSurface.WATER_LEVEL+.5 or absf(lh-rh)>2: return []
		if i==0 or i==samples.size()-1: h=samples[i].y;lh=h;rh=h
		if i>0 and absf(h-previous.y)/maxf(.01,p.distance_to(Vector2(previous.x,previous.z)))>.14: return []
		var surface:=PackedVector3Array()
		for across in 9:
			var at:=left.lerp(right,float(across)/8)
			var ground:=WorldForestStreamer.sample_root_height(layout,at,zones,cache)+.12
			if i==0 or i==samples.size()-1: ground=lerpf(lh,rh,float(across)/8)
			surface.append(Vector3(at.x,ground,at.y))
		sections.append({"left":Vector3(left.x,lh,left.y),"right":Vector3(right.x,rh,right.y),"surface":surface})
		previous=Vector3(p.x,h,p.y)
	return sections



static func port_roads(layout: WorldLayout, ports: Array) -> Array:
	var roads: Array=[]
	for port: PortDefinition in ports:
		var data:=PortExpander.expand(port,layout.seed,layout)
		var attrs:=data.layout_graph.initial_attributes
		var foundation:Dictionary=attrs.get("foundation",{})
		var y:=float(foundation.get("surface_y_m",PortCoastTracer.FOUNDATION_SURFACE_Y_M))+PortCoastTracer.FOUNDATION_TERRAIN_CLEARANCE_M+.032
		var basis:=Basis(Vector3.UP,port.rotation_y)
		for route:Dictionary in attrs.get("land_plan",{}).get("facility_plan",{}).get("routes",[]):
			roads.append(PackedVector3Array([port.world_position+basis*Vector3(route.a[0],y,route.a[1]),port.world_position+basis*Vector3(route.b[0],y,route.b[1])]))
	return roads
