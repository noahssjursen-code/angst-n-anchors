class_name ShipSurfaceKit
extends RefCounted
const POINTS := [Vector2(0,0),Vector2(.25,0),Vector2(.5,0),Vector2(.5,.25),Vector2(.5,.5),Vector2(.25,.5),Vector2(0,.5),Vector2(0,.25)]
static var _infill_meshes: Dictionary = {}
static var _infill_cache_bytes := 0
const INFILL_CACHE_BYTES := 32 * 1024 * 1024
const INFILL_BATCH_TRIANGLES := 4096
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
	# Large hulls put perfectly small cabins far from the vessel origin. Limit
	# tessellation by surface span, not by an obsolete +/-20 m hull coordinate.
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for point in poly: bounds = bounds.expand(point)
	if bounds.size.x > 40 or bounds.size.y > 40: return false
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i+1)%poly.size()]
		if not is_finite(a.x) or not is_finite(a.y) or absf(a.x)>128 or absf(a.y)>128 or a.distance_to(a.snapped(Vector2(.5,.5)))>.001:
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
static func create(record: Dictionary, finish := true, combine_infill := true) -> Node3D:
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
	var mesh_key := var_to_str([style,poly,rise])
	var combined: Array = _infill_meshes.get(mesh_key,[])
	if not combine_infill or combined.is_empty():
		for tile in tiles(poly,style):
			# Finish once after assembly, retaining the original authored materials.
			var model := BrickCatalog.create_visual(tile["id"], {"skip_finish":true})
			model.position=Vector3(tile["origin"].x,0,tile["origin"].y)
			root.add_child(model)
			_crown(model,"Crown",tile["origin"].x,1.0,center,half_width,rise)
		if combine_infill:
			combined=_combine_infill(root)
			var bytes := 0
			for mesh: ArrayMesh in combined:
				for surface in mesh.get_surface_count():
					bytes+=mesh.surface_get_array_len(surface)*64+mesh.surface_get_array_index_len(surface)*4
			if _infill_meshes.size()>=16 or _infill_cache_bytes+bytes>INFILL_CACHE_BYTES:
				_infill_meshes.clear();_infill_cache_bytes=0
			if bytes<=INFILL_CACHE_BYTES:
				_infill_meshes[mesh_key]=combined;_infill_cache_bytes+=bytes
	if combine_infill:
		for mesh: ArrayMesh in combined:
			var infill := MeshInstance3D.new()
			infill.name="AuthoredInfill" if root.get_child_count()==0 else "AuthoredInfill%d"%root.get_child_count()
			infill.mesh=mesh
			root.add_child(infill)
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
				var model := BrickCatalog.create_visual("roof_edge_"+code, {"skip_finish":not finish})
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
	if finish: SurfaceMaterialLibrary.apply(root, style)
	return root

static func _combine_infill(root: Node3D) -> Array[ArrayMesh]:
	# Adjacent half-metre meshes accumulate independent world-matrix rounding
	# at harbour coordinates. One local render frame closes those visible cracks.
	# This copies Blender triangles; it does not replace the authored part library.
	var surfaces: Dictionary = {}
	var poses: Dictionary = {}
	for node in SurfaceMaterialLibrary.meshes(root):
		var source := node as MeshInstance3D
		var pose := source.transform
		var parent := source.get_parent()
		while parent != root:
			if parent is Node3D: pose=parent.transform*pose
			parent=parent.get_parent()
		# Crown is constant down a column: bake an imported shape once per pose,
		# not once per tile (which would repeatedly upload/read back GPU meshes).
		var weights := PackedFloat32Array()
		for index in source.get_blend_shape_count(): weights.append(source.get_blend_shape_value(index))
		var pose_key := str(source.mesh.get_instance_id())+var_to_str(weights)
		if not poses.has(pose_key): poses[pose_key]=_posed_infill(source)
		var baked := poses[pose_key] as Mesh
		for surface in baked.get_surface_count():
			var original := source.mesh.surface_get_material(surface)
			var key := original.resource_name.get_slice(".",0)
			var groups: Array = surfaces.get_or_add(key,[])
			var array_mesh := baked as ArrayMesh
			var triangles := array_mesh.surface_get_array_index_len(surface)/3
			if triangles==0: triangles=array_mesh.surface_get_array_len(surface)/3
			# Each draw remains a bounded collision subshape in the existing ship
			# walk body. A whole subdivided roof can exceed Jolt's subshape-ID bits.
			# All batches have the SAME local frame, so no tile-world rounding gap.
			if groups.is_empty() or int(groups[-1].triangles)+triangles>INFILL_BATCH_TRIANGLES:
				var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.set_material(original);groups.append({"tool":tool,"triangles":0})
			(groups[-1].tool as SurfaceTool).append_from(baked,surface,pose)
			groups[-1].triangles+=triangles
	var result: Array[ArrayMesh] = []
	for groups: Array in surfaces.values():
		for group: Dictionary in groups:
			var tool := group.tool as SurfaceTool
			tool.generate_tangents()
			result.append(tool.commit())
	for child in root.get_children(): child.free()
	return result

static func _posed_infill(source: MeshInstance3D) -> Mesh:
	var weights: Dictionary = {}
	for index in source.get_blend_shape_count():
		var weight := source.get_blend_shape_value(index)
		if not is_zero_approx(weight): weights[index]=weight
	if weights.is_empty(): return source.mesh
	var result := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var shapes := source.mesh.surface_get_blend_shape_arrays(surface)
		for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL]:
			var base: PackedVector3Array=arrays[channel]
			var values := base.duplicate()
			for index: int in weights:
				var shape: PackedVector3Array=shapes[index][channel]
				if shape.size()!=base.size(): continue
				for i in values.size():
					values[i]+=(shape[i]-base[i] if source.mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED else shape[i])*float(weights[index])
			if channel==Mesh.ARRAY_NORMAL:
				for i in values.size(): values[i]=values[i].normalized()
			arrays[channel]=values
		# Recreate the UV tangent basis after the static crown has been applied.
		arrays[Mesh.ARRAY_TANGENT]=null
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
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
