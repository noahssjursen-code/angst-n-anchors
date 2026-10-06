class_name HarbourRoadSurface
extends RefCounted

## Union the complete road footprint before drawing its perimeter. Shared bends
## and T-junctions have one surface and no internal crossing edge stripes.
static func build(parent: Node3D, routes: Array) -> void:
	var polygons: Array[PackedVector2Array] = []
	if routes.is_empty(): return
	for r in routes:
		var a := Vector2(r.a.x,r.a.z)
		var b := Vector2(r.b.x,r.b.z)
		if a.distance_to(b)<.05: continue
		var side := (b-a).normalized().orthogonal()*float(r.width)*.5
		var polygon := PackedVector2Array([a-side,b-side,b+side,a+side])
		var changed := true
		while changed:
			changed=false
			for i in polygons.size():
				var merged := Geometry2D.merge_polygons(polygon,polygons[i])
				if merged.size()==1:
					polygon=merged[0]; polygons.remove_at(i); changed=true; break
		polygons.append(polygon)
	var y: float=routes[0].a.y
	for polygon in polygons:
		var mesh := ArrayMesh.new()
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		for p in polygon: vertices.append(Vector3(p.x,y-.004,p.y)); normals.append(Vector3.UP)
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_INDEX]=Geometry2D.triangulate_polygon(polygon)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var surface := MeshInstance3D.new()
		surface.name="JoinedRoadSurface"
		surface.mesh=mesh
		surface.material_override=HarbourEnvironmentKit.paving()
		parent.add_child(surface)
		for i in polygon.size():
			var a := polygon[i]; var b := polygon[(i+1)%polygon.size()]
			var end_cap := false
			for r in routes:
				var direction := Vector2(r.b.x-r.a.x,r.b.z-r.a.z).normalized()
				if absf((b-a).normalized().dot(direction))>.01: continue
				for end in [r.a,r.b]:
					var point := Vector2(end.x,end.z)
					if absf((a-point).dot(direction))<.01 and absf((b-point).dot(direction))<.01 and (a+b).distance_to(point*2)<.05: end_cap=true
			if end_cap: continue
			HarbourEnvironmentKit.line(parent,Vector3(a.x,y,a.y),Vector3(b.x,y,b.y),.16)
	for r in routes:
		var a: Vector3=r.a; var b: Vector3=r.b
		var direction := (b-a).normalized()
		var distance := a.distance_to(b)
		# Fixed metre repeat aligned by the route's projected position, not its length.
		var phase := fposmod(a.dot(direction),6.0)
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
				for p in [pa,(pa+pb)*.5,pb]:
					var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x,p.z),Vector2(other.a.x,other.a.z),Vector2(other.b.x,other.b.z))
					if q.distance_to(Vector2(p.x,p.z))<float(other.width)*.5+.5: blocked=true
			if not blocked: HarbourEnvironmentKit.line(parent,pa,pb,.16)
