class_name HarbourRoadSurface
extends RefCounted

## Union the complete road footprint before drawing its perimeter. Shared bends
## and T-junctions have one surface and no internal crossing edge stripes.
static func footprint(routes: Array) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for r in routes:
		var a := Vector2(r.a.x,r.a.z)
		var b := Vector2(r.b.x,r.b.z)
		if a.distance_to(b)<.05: continue
		# A buffered centreline has proper overlap at every bend, unlike rectangles
		# whose end faces only touch and leave slivers after floating point union.
		var extension := (b-a).normalized()*.02
		var polygon: PackedVector2Array = Geometry2D.offset_polyline(PackedVector2Array([a-extension,b+extension]),float(r.width)*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_BUTT)[0]
		var changed := true
		while changed:
			changed=false
			for i in polygons.size():
				var merged := Geometry2D.merge_polygons(polygon,polygons[i])
				if merged.size()==1:
					polygon=merged[0]; polygons.remove_at(i); changed=true; break
		polygons.append(polygon)
	# Morphological closing adds a 3m inner turning fillet while retaining the
	# outside extent of each lane. The road is one connected paved envelope.
	var finished: Array[PackedVector2Array] = []
	for polygon in polygons:
		for expanded in Geometry2D.offset_polygon(polygon,3.0,Geometry2D.JOIN_ROUND):
			for closed in Geometry2D.offset_polygon(expanded,-3.0,Geometry2D.JOIN_ROUND):
				var clean := PackedVector2Array()
				for p in closed:
					if clean.is_empty() or clean[-1].distance_to(p)>.04: clean.append(p)
				if clean.size()>2 and clean[-1].distance_to(clean[0])<.04: clean.remove_at(clean.size()-1)
				if clean.size()>2: finished.append(simplify_boundary(clean))
	return finished

static func build(parent: Node3D, routes: Array) -> void:
	if routes.is_empty(): return
	var polygons := footprint(routes)
	var y: float=routes[0].a.y
	for polygon in polygons:
		var mesh := ArrayMesh.new()
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for p in polygon: vertices.append(Vector3(p.x,y-.004,p.y)); normals.append(Vector3.UP)
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_INDEX]=Geometry2D.triangulate_polygon(polygon)
		assert(not arrays[Mesh.ARRAY_INDEX].is_empty(),"Road boundary must triangulate")
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var surface := MeshInstance3D.new()
		surface.name="JoinedRoadSurface"
		surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface.mesh=mesh
		var material := HarbourEnvironmentKit.paving().duplicate() as ShaderMaterial
		material.set_shader_parameter("pavement_color",Vector3(.025,.028,.031))
		surface.material_override=material
		parent.add_child(surface)
		for i in polygon.size():
			var a := polygon[i]; var b := polygon[(i+1)%polygon.size()]
			var end_cap := false
			for r in routes:
				var direction := Vector2(r.b.x-r.a.x,r.b.z-r.a.z).normalized()
				for end in [r.a,r.b]:
					var point := Vector2(end.x,end.z)
					var connected := false
					for other in routes:
						if other==r: continue
						var closest := Geometry2D.get_closest_point_to_segment(point,Vector2(other.a.x,other.a.z),Vector2(other.b.x,other.b.z))
						if closest.distance_to(point)<.2: connected=true; break
					if connected: continue
					var midpoint := (a+b)*.5
					if midpoint.distance_to(point)>float(r.width)*.5+.15: continue
					# End caps are not road-edge paint, including fragmented/curved caps.
					var inward := direction if end==r.a else -direction
					if (midpoint-point).dot(inward)<.1: end_cap=true
			if end_cap: continue
			HarbourEnvironmentKit.line(parent,Vector3(a.x,y,a.y),Vector3(b.x,y,b.y),.16)
	for r in marking_routes(routes):
		var a: Vector3=r.a; var b: Vector3=r.b
		var direction := (b-a).normalized()
		var distance := a.distance_to(b)
		# Fixed metre repeat aligned by the route's projected position, not its length.
		var phase := fposmod(float(r.phase),6.0)
		for i in range(int(ceil((distance+phase)/6.0))):
			var start := maxf(0,i*6.0-phase)
			var finish := minf(distance,i*6.0-phase+2.5)
			if finish<=start: continue
			var pa := a+direction*start; var pb := a+direction*finish
			var blocked := false
			for other in routes:
				if other==r: continue
				var od: Vector3=(other.b-other.a).normalized()
				if absf(direction.dot(od))>.98: continue
				var shared_end: bool=a.distance_to(other.a)<.1 or a.distance_to(other.b)<.1 or b.distance_to(other.a)<.1 or b.distance_to(other.b)<.1
				if shared_end and absf(direction.dot(od))>.7: continue
				for p in [pa,(pa+pb)*.5,pb]:
					var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),Vector2(other.a.x,other.a.z),Vector2(other.b.x,other.b.z))
					if q.distance_to(Vector2(p.x,p.z))<float(other.width)*.5+.5: blocked=true
			if not blocked: HarbourEnvironmentKit.line(parent,pa,pb,.16)

static func marking_routes(routes: Array) -> Array:
	var remaining := routes.duplicate(true)
	var result := []
	while not remaining.is_empty():
		var first: Dictionary=remaining.pop_front()
		var points: Array[Vector3]=[first.a,first.b]
		var growing := true
		while growing:
			growing=false
			for i in remaining.size():
				var r: Dictionary=remaining[i]
				if absf(float(r.width)-float(first.width))>.01: continue
				for reverse in [false,true]:
					var a: Vector3=r.b if reverse else r.a
					var b: Vector3=r.a if reverse else r.b
					if a.distance_to(points[-1])<.1 and (b-a).normalized().dot((points[-1]-points[-2]).normalized())>.7:
						points.append(b); remaining.remove_at(i); growing=true; break
					if b.distance_to(points[0])<.1 and (b-a).normalized().dot((points[1]-points[0]).normalized())>.7:
						points.push_front(a); remaining.remove_at(i); growing=true; break
				if growing: break
		var phase := 0.0
		for i in points.size()-1:
			result.append({"a":points[i],"b":points[i+1],"width":first.width,"phase":phase})
			phase+=points[i].distance_to(points[i+1])
	return result

static func simplify_boundary(polygon: PackedVector2Array) -> PackedVector2Array:
	# Offsetting round joins can leave narrow out-and-back spikes. Collapse the
	# nearly coincident return before triangulation, without rounding metre corners.
	var result := polygon.duplicate()
	var changed := true
	while changed and result.size()>3:
		changed=false
		for i in result.size():
			var a := result[posmod(i-1,result.size())]
			var b := result[i]
			var c := result[(i+1)%result.size()]
			if a.distance_to(c)<.05 or b.distance_to(Geometry2D.get_closest_point_to_segment(b,a,c))<.015:
				result.remove_at(i)
				changed=true
				break
	return result
