class_name ShipSurfaceKit
extends RefCounted
const POINTS := [Vector2(0,0),Vector2(.25,0),Vector2(.5,0),Vector2(.5,.25),Vector2(.5,.5),Vector2(.25,.5),Vector2(0,.5),Vector2(0,.25)]
static func is_surface(id: String) -> bool:
	return id == "floor_tile" or id == "roof_tile"
static func polygon(record: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in record.get("outline", []):
		result.append(Vector2(p[0],p[1]))
	return result
static func area(poly: PackedVector2Array) -> float:
	var result := 0.0
	for i in poly.size():
		result += poly[i].cross(poly[(i+1)%poly.size()])
	return absf(result)*.5
static func valid(poly: PackedVector2Array) -> bool:
	if poly.size() < 3 or poly.size() > 64 or area(poly) < .1:
		return false
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i+1)%poly.size()]
		if not is_finite(a.x) or not is_finite(a.y) or absf(a.x)>20 or absf(a.y)>20 or a.distance_to(a.snapped(Vector2(.5,.5)))>.001:
			return false
		var d := (b-a).abs()
		if d.length()<.49 or not (is_zero_approx(d.x) or is_zero_approx(d.y) or is_equal_approx(d.x,d.y) or is_equal_approx(d.x*2,d.y) or is_equal_approx(d.x,d.y*2)):
			return false
		# Reject duplicate vertices, non-adjacent intersections and backtracking.
		var before := a-poly[(i+poly.size()-1)%poly.size()]
		if absf(before.cross(b-a))<.001 and before.dot(b-a)<0:
			return false
		for j in range(i+1,poly.size()):
			if a.distance_to(poly[j])<.001:
				return false
			if j==i+1 or (i==0 and j==poly.size()-1):
				continue
			if Geometry2D.segment_intersects_segment(a,b,poly[j],poly[(j+1)%poly.size()])!=null:
				return false
	return not Geometry2D.triangulate_polygon(poly).is_empty()
static func tiles(poly: PackedVector2Array, style: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not valid(poly):
		return result
	var bounds := Rect2(poly[0],Vector2.ZERO)
	for p in poly: bounds=bounds.expand(p)
	for xi in range(floori(bounds.position.x*2),ceili(bounds.end.x*2)):
		for zi in range(floori(bounds.position.y*2),ceili(bounds.end.y*2)):
			var origin := Vector2(xi*.5,zi*.5)
			var square := PackedVector2Array([origin,origin+Vector2(.5,0),origin+Vector2(.5,.5),origin+Vector2(0,.5)])
			for clipped in Geometry2D.intersect_polygons(poly,square):
				if area(clipped)<.00001: continue
				if is_equal_approx(area(clipped),.25):
					result.append({"id":style+"_tile","origin":origin,"area":.25})
					continue
				var indices := Geometry2D.triangulate_polygon(clipped)
				for k in range(0,indices.size(),3):
					var ids: Array[int] = []
					var triangle := PackedVector2Array()
					for j in 3:
						var v: Vector2 = clipped[indices[k+j]]-origin
						var found := -1
						for index in POINTS.size():
							if v.distance_to(POINTS[index])<.001: found=index
						if found<0: return []
						ids.append(found)
						triangle.append(v)
					ids.sort()
					result.append({"id":"%s_tri_%d_%d_%d" % [style,ids[0],ids[1],ids[2]],"origin":origin,"area":area(triangle)})
	return result
static func create(record: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Roof" if record["asset_id"]=="roof_tile" else "Floor"
	var poly := polygon(record)
	var style := "roof" if record["asset_id"]=="roof_tile" else "floor"
	var min_x := INF
	var max_x := -INF
	for p in poly:
		min_x=minf(min_x,p.x)
		max_x=maxf(max_x,p.x)
	var center := (min_x+max_x)*.5
	var half_width := maxf((max_x-min_x)*.5,.25)
	var rise := minf(.12,half_width*.08) if record.get("crown",false) and style=="roof" else 0.0
	for tile in tiles(poly,style):
		var model := BrickCatalog.create_visual(tile["id"])
		model.position=Vector3(tile["origin"].x,0,tile["origin"].y)
		root.add_child(model)
		_crown(model,"Crown",tile["origin"].x,1.0,center,half_width,rise)
	if style=="roof":
		# Normalize winding: outside of a CCW XZ polygon is to the right.
		if Geometry2D.is_polygon_clockwise(poly): poly.reverse()
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i+1)%poly.size()]
			var e := (b-a).normalized()
			var previous := (a-poly[(i+poly.size()-1)%poly.size()]).normalized()
			var following := (poly[(i+2)%poly.size()]-b).normalized()
			var d := (b-a).abs()
			var code := "straight" if is_zero_approx(d.x) or is_zero_approx(d.y) else ("45" if is_equal_approx(d.x,d.y) else "26")
			var length: float = {"straight":.5,"45":sqrt(.5),"26":sqrt(1.25)}[code]
			var count := roundi(a.distance_to(b)/length)
			var width := _eave_width(e,int(record.get("visor_direction",0)))
			var start_shear := _offset_shear(previous,e,e,_eave_width(previous,int(record.get("visor_direction",0))),width)/width
			var end_shear := _offset_shear(e,following,e,width,_eave_width(following,int(record.get("visor_direction",0))))/width
			for j in count:
				var model := BrickCatalog.create_visual("roof_edge_"+code)
				model.set_meta("edge_asset","roof_edge_"+code)
				var p := a+e*length*j
				model.position=Vector3(p.x,0,p.y)
				model.rotation.y=atan2(e.x,e.y)
				model.scale.x=width/.15
				root.add_child(model)
				var start := start_shear if j==0 else 0.0
				var end := end_shear if j==count-1 else 0.0
				for mesh in model.find_children("*","MeshInstance3D",true,false):
					mesh.custom_aabb=mesh.mesh.get_aabb().grow(.5)
					for key in mesh.mesh.get_blend_shape_count():
						var name: String=mesh.mesh.get_blend_shape_name(key)
						if name in ["MiterStart","MiterEnd"]:
							mesh.set_blend_shape_value(key,(start if name=="MiterStart" else end)*model.scale.x/4.0)
				_crown_edge(model,p.x-center,(e.y+e.x*start)*model.scale.x,e.x,e.x*(end-start)*model.scale.x/length,half_width,rise)
	return root
static func _eave_width(direction: Vector2, visor_direction: int) -> float:
	var outward := Vector2(direction.y,-direction.x)
	var facing: Vector2 = [Vector2.ZERO,Vector2(0,-1),Vector2(0,1),Vector2(-1,0),Vector2(1,0)][clampi(visor_direction,0,4)]
	return .15 + .30*maxf(outward.dot(facing),0.0)


static func _offset_shear(a: Vector2,b: Vector2,along: Vector2,wa: float,wb: float) -> float:
	var na := Vector2(a.y,-a.x)
	var nb := Vector2(b.y,-b.x)
	var corner: Variant=Geometry2D.line_intersects_line(na*wa,a,nb*wb,b)
	return 0.0 if corner==null else (corner as Vector2).dot(along)

static func _crown(model: Node3D,prefix: String,origin: float,axis: float,center: float,half_width: float,rise: float) -> void:
	var offset := origin-center
	var factor := rise/(half_width*half_width)
	var weights := {prefix+"0":rise-factor*offset*offset,prefix+"X":-2.0*factor*offset*axis,prefix+"XX":-factor*axis*axis}
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for key in mesh.mesh.get_blend_shape_count():
			var name: String=mesh.mesh.get_blend_shape_name(key)
			if weights.has(name): mesh.set_blend_shape_value(key,weights[name])
		mesh.custom_aabb=mesh.mesh.get_aabb().grow(.5)


static func _crown_edge(model: Node3D,a: float,b: float,c: float,d: float,half_width: float,rise: float) -> void:
	# World X after the two miter deformations is a+b*x+c*z+d*x*z.
	# Squaring that polynomial gives the exact same crown on every joined piece.
	var coefficients := {Vector2i(0,0):a,Vector2i(1,0):b,Vector2i(0,1):c,Vector2i(1,1):d}
	var weights := {}
	for left in coefficients:
		for right in coefficients:
			var power: Vector2i=left+right
			var key := "Crown%d%d" % [power.x,power.y]
			weights[key]=weights.get(key,0.0)-rise*coefficients[left]*coefficients[right]/(half_width*half_width)
	weights["Crown00"]+=rise
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for key in mesh.mesh.get_blend_shape_count():
			var name: String=mesh.mesh.get_blend_shape_name(key)
			if weights.has(name): mesh.set_blend_shape_value(key,weights[name])
