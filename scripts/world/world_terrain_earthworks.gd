class_name WorldTerrainEarthworks
extends RefCounted
## Exact local clipping of an existing terrain surface. No resampling or broad
## grading: outside pieces preserve the source triangle's interpolation.

const EPS := 0.00001
const CELL_M := 25.0
const EDGE_EPS := 0.001


static func apply(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array,
		chunk_bounds: Rect2, projections: Array, normals := PackedVector3Array()) -> Dictionary:
	var shapes: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	var shape_index: Dictionary = {}
	var edge_index: Dictionary = {}
	var offset := chunk_bounds.position
	var minimum_height := INF
	for projection: Dictionary in projections:
		if not chunk_bounds.intersects(projection.bounds, true): continue
		var height := float(projection.cut_height_m)
		minimum_height = minf(minimum_height, height)
		for source: PackedVector2Array in projection.footprints:
			var polygon := source.duplicate()
			for i in polygon.size(): polygon[i] -= offset
			var bounds := _bounds(polygon)
			if not Rect2(Vector2.ZERO, chunk_bounds.size).intersects(bounds, true): continue
			_index(shape_index, bounds, shapes.size())
			shapes.append({"polygon": polygon, "bounds": bounds, "height": height})
		for source: Dictionary in projection.edges:
			var edge := source.duplicate()
			edge.start -= offset
			edge.end = edge.start + edge.direction * float(edge.length)
			edge.height = height
			var bounds := Rect2(edge.start, Vector2.ZERO).expand(edge.end).grow(EDGE_EPS)
			if not Rect2(Vector2.ZERO, chunk_bounds.size).intersects(bounds, true): continue
			_index(edge_index, bounds, edges.size())
			edges.append(edge)
	if shapes.is_empty(): return {"changed_triangles": 0, "retaining_triangles": 0}
	var original := indices.duplicate()
	var result := PackedInt32Array()
	var wall_segments: Dictionary = {}
	var changed := 0
	var wall_count := 0
	for i in range(0, original.size(), 3):
		var triangle := PackedVector3Array([vertices[original[i]], vertices[original[i+1]], vertices[original[i+2]]])
		if maxf(triangle[0].y, maxf(triangle[1].y, triangle[2].y)) <= minimum_height + EPS:
			result.append_array(original.slice(i, i+3)); continue
		for j in 3: triangle[j] -= Vector3(offset.x, 0, offset.y)
		var planar := _xz(triangle)
		var area := _area(planar)
		if absf(area) <= EPS:
			result.append_array(original.slice(i, i+3)); continue
		var bounds := _bounds(planar)
		var candidates := _nearby(shape_index, bounds)
		candidates.sort_custom(func(a: int, b: int) -> bool: return float(shapes[a].height) < float(shapes[b].height))
		var remaining: Array[PackedVector3Array] = [triangle]
		var capped: Array[Dictionary] = []
		var altered := false
		for candidate in candidates:
			var shape: Dictionary = shapes[candidate]
			if not bounds.intersects(shape.bounds, true): continue
			var next: Array[PackedVector3Array] = []
			for piece in remaining:
				var partition := _subtract_convex(piece, shape.polygon)
				next.append_array(partition.outside)
				var inside: PackedVector3Array = partition.inside
				if inside.size() < 3: continue
				var split := _split_height(inside, float(shape.height))
				if split.below.size() >= 3: capped.append({"points":split.below,"flat":false})
				if split.above.size() >= 3:
					var lowered: PackedVector3Array = split.above
					for j in lowered.size():
						if lowered[j].y > float(shape.height) + EPS: altered = true
						lowered[j].y = float(shape.height)
					capped.append({"points":lowered,"flat":true})
			remaining = next
			if remaining.is_empty(): break
		var source_colors: Array[Color] = [colors[original[i]], colors[original[i+1]], colors[original[i+2]]]
		var source_normals := PackedVector3Array()
		if not normals.is_empty(): source_normals = PackedVector3Array([normals[original[i]],normals[original[i+1]],normals[original[i+2]]])
		if altered:
			changed += 1
			for piece in remaining: _append_surface(piece, triangle, source_colors, offset, vertices, colors, result, source_normals, normals, false)
			for piece in capped: _append_surface(piece.points, triangle, source_colors, offset, vertices, colors, result, source_normals, normals, bool(piece.flat))
		else: result.append_array(original.slice(i, i+3))
		# Only globally exposed union edges produce retaining faces. A second
		# projection can cover part of an edge, so subtract its outward coverage.
		for edge_id in _nearby(edge_index, bounds):
			var edge: Dictionary = edges[edge_id]
			var interval := _segment_interval(edge.start, edge.end, planar)
			if interval.y - interval.x <= EPS: continue
			var intervals: Array[Vector2] = [interval]
			var shifted_start: Vector2 = edge.start + edge.normal * EDGE_EPS
			var shifted_end: Vector2 = edge.end + edge.normal * EDGE_EPS
			var segment_bounds := Rect2(shifted_start, Vector2.ZERO).expand(shifted_end)
			for other_id in _nearby(shape_index, segment_bounds):
				var cover := _segment_interval(shifted_start, shifted_end, shapes[other_id].polygon)
				if cover.y > cover.x: intervals = _subtract_intervals(intervals, cover)
			for span in intervals:
				var a: Vector2 = edge.start.lerp(edge.end, span.x)
				var b: Vector2 = edge.start.lerp(edge.end, span.y)
				var owner_point: Vector2 = (a+b)*0.5 + offset + edge.normal * EDGE_EPS
				if not chunk_bounds.has_point(owner_point): continue
				var key := "%d:%d:%d" % [edge_id, roundi(span.x * float(edge.length) / EDGE_EPS), roundi(span.y * float(edge.length) / EDGE_EPS)]
				if wall_segments.has(key): continue
				wall_segments[key] = true
				wall_count += _append_wall(a, b, float(edge.height), edge.normal, triangle, source_colors, offset, vertices, colors, result, normals)
	if changed > 0 or wall_count > 0:
		indices.clear()
		indices.append_array(result)
	return {"changed_triangles": changed, "retaining_triangles": wall_count}


static func _subtract_convex(subject: PackedVector3Array, clip: PackedVector2Array) -> Dictionary:
	var inside := subject
	var outside: Array[PackedVector3Array] = []
	var winding := 1.0 if _area(clip) > 0 else -1.0
	for i in clip.size():
		if inside.size() < 3: break
		var a := clip[i]
		var direction := clip[(i+1)%clip.size()] - a
		var split := _split(inside, func(p: Vector3) -> float: return direction.cross(Vector2(p.x,p.z)-a)*winding)
		if split.negative.size() >= 3: outside.append(split.negative)
		inside = split.positive
	return {"inside": inside, "outside": outside}


## Skirts are not physical terrain, but their old top edge must not run across
## an excavation at a chunk boundary. Split just the intersecting spans; keep
## the remainder at its original height so neighbouring LOD gaps stay covered.
static func skirt_spans(a: Vector3, b: Vector3, projections: Array) -> Array[Dictionary]:
	var origin := Vector2(a.x,a.z)
	var end := Vector2(b.x,b.z)-origin
	var bounds := Rect2(origin,Vector2.ZERO).expand(origin+end)
	var covered: Array[Dictionary] = []
	var divisions: Array[float] = [0.0,1.0]
	for projection: Dictionary in projections:
		if maxf(a.y,b.y)<=float(projection.cut_height_m)+EPS or not projection.bounds.intersects(bounds,true): continue
		for footprint: PackedVector2Array in projection.footprints:
			var local := footprint.duplicate()
			for i in local.size(): local[i]-=origin
			var interval := _segment_interval(Vector2.ZERO,end,local)
			if interval.y-interval.x<=EPS: continue
			covered.append({"span":interval,"height":float(projection.cut_height_m)})
			divisions.append(interval.x);divisions.append(interval.y)
			if absf(b.y-a.y)>EPS:
				var crossing: float=(float(projection.cut_height_m)-a.y)/(b.y-a.y)
				if crossing>interval.x and crossing<interval.y:divisions.append(crossing)
	if covered.is_empty():return []
	divisions.sort()
	var result: Array[Dictionary]=[]
	for i in range(divisions.size()-1):
		var first:=divisions[i]
		var last:=divisions[i+1]
		if last-first<=EPS:continue
		var middle:=(first+last)*.5
		var height:=INF
		for cover in covered:
			if middle>=cover.span.x and middle<=cover.span.y:height=minf(height,float(cover.height))
		var top_a:=a.lerp(b,first)
		var top_b:=a.lerp(b,last)
		var lowered:=maxf(top_a.y,top_b.y)>height+EPS
		top_a.y=minf(top_a.y,height);top_b.y=minf(top_b.y,height)
		result.append({"a":top_a,"b":top_b,"first":first,"last":last,"lowered":lowered})
	return result


static func _split_height(polygon: PackedVector3Array, height: float) -> Dictionary:
	var minimum := INF
	var maximum := -INF
	for point in polygon:
		minimum = minf(minimum,point.y)
		maximum = maxf(maximum,point.y)
	if maximum <= height: return {"above":PackedVector3Array(),"below":polygon}
	if minimum >= height: return {"above":polygon,"below":PackedVector3Array()}
	var split := _split(polygon, func(p: Vector3) -> float: return p.y-height)
	return {"above": split.positive, "below": split.negative}


static func _split(polygon: PackedVector3Array, distance: Callable) -> Dictionary:
	var positive := PackedVector3Array()
	var negative := PackedVector3Array()
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		var da: float = distance.call(a)
		var db: float = distance.call(b)
		if da >= 0: positive.append(a)
		if da <= 0: negative.append(a)
		if (da > 0 and db < 0) or (da < 0 and db > 0):
			var intersection := a.lerp(b, da/(da-db))
			positive.append(intersection)
			negative.append(intersection)
	return {"positive": positive, "negative": negative}


static func _segment_interval(a: Vector2, b: Vector2, polygon: PackedVector2Array) -> Vector2:
	var first := 0.0
	var last := 1.0
	var winding := 1.0 if _area(polygon) > 0 else -1.0
	for i in polygon.size():
		var edge := polygon[(i+1)%polygon.size()]-polygon[i]
		var da := edge.cross(a-polygon[i])*winding
		var db := edge.cross(b-polygon[i])*winding
		if da < 0 and db < 0: return Vector2.ZERO
		if da < 0: first = maxf(first, da/(da-db))
		elif db < 0: last = minf(last, da/(da-db))
		if last <= first: return Vector2.ZERO
	return Vector2(first,last)


static func _subtract_intervals(intervals: Array[Vector2], cut: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for span in intervals:
		if cut.y <= span.x or cut.x >= span.y: result.append(span); continue
		if cut.x > span.x: result.append(Vector2(span.x,cut.x))
		if cut.y < span.y: result.append(Vector2(cut.y,span.y))
	return result


static func _append_surface(polygon: PackedVector3Array, source: PackedVector3Array, source_colors: Array[Color], offset: Vector2,
		vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array,
		source_normals: PackedVector3Array, normals: PackedVector3Array, flat: bool) -> void:
	if polygon.size() < 3 or absf(_area(_xz(polygon))) <= EPS: return
	var first := vertices.size()
	for point in polygon:
		vertices.append(point + Vector3(offset.x,0,offset.y))
		colors.append(_color_at(Vector2(point.x,point.z),source,source_colors))
		if not source_normals.is_empty():
			var w := _weights(Vector2(point.x,point.z),source)
			# Keep the source surface's smooth normal interpolation unchanged.
			# Retaining walls use their own duplicated vertices and sharp normals.
			normals.append(Vector3.UP if flat else source_normals[0]*w.x+source_normals[1]*w.y+source_normals[2]*w.z)
	for i in range(1,polygon.size()-1):
		if absf((polygon[i]-polygon[0]).cross(polygon[i+1]-polygon[0]).y) > EPS:
			indices.append_array(PackedInt32Array([first,first+i,first+i+1]))


static func _append_wall(a: Vector2, b: Vector2, height: float, outward: Vector2, source: PackedVector3Array,
		source_colors: Array[Color], offset: Vector2, vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array,
		normals: PackedVector3Array) -> int:
	var top_a := _height_at(a,source)
	var top_b := _height_at(b,source)
	if maxf(top_a,top_b) <= height+EPS: return 0
	if top_a < height:
		a = a.lerp(b,(height-top_a)/(top_b-top_a)); top_a = height
	elif top_b < height:
		b = b.lerp(a,(height-top_b)/(top_a-top_b)); top_b = height
	var points := PackedVector3Array([Vector3(a.x,top_a,a.y), Vector3(b.x,top_b,b.y), Vector3(b.x,height,b.y), Vector3(a.x,height,a.y)])
	var first := vertices.size()
	var desired := Vector3(-outward.x,0,-outward.y)
	var has_normals := not normals.is_empty()
	for point in points:
		vertices.append(point+Vector3(offset.x,0,offset.y))
		colors.append(_color_at(Vector2(point.x,point.z),source,source_colors))
		if has_normals: normals.append(desired)
	var facing := Vector3(b.x-a.x,0,b.y-a.y).cross(Vector3.DOWN).dot(desired)
	var count := 0
	for tri in [[0,1,2],[0,2,3]]:
		if (points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]]).length_squared() <= EPS*EPS: continue
		# Godot's front face uses clockwise vertex order.
		if facing > 0: indices.append_array(PackedInt32Array([first+tri[0],first+tri[2],first+tri[1]]))
		else: indices.append_array(PackedInt32Array([first+tri[0],first+tri[1],first+tri[2]]))
		count += 1
	return count


static func _weights(point: Vector2, source: PackedVector3Array) -> Vector3:
	var a := Vector2(source[0].x,source[0].z)
	var ab := Vector2(source[1].x,source[1].z)-a
	var ac := Vector2(source[2].x,source[2].z)-a
	var relative := point-a
	var denominator := ab.cross(ac)
	var u := relative.cross(ac)/denominator
	var v := ab.cross(relative)/denominator
	return Vector3(1-u-v,u,v)


static func _height_at(point: Vector2, source: PackedVector3Array) -> float:
	var w := _weights(point,source)
	return source[0].y*w.x+source[1].y*w.y+source[2].y*w.z


static func _color_at(point: Vector2, source: PackedVector3Array, colors: Array[Color]) -> Color:
	var w := _weights(point,source)
	return colors[0]*w.x+colors[1]*w.y+colors[2]*w.z


static func _xz(points: PackedVector3Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points: result.append(Vector2(point.x,point.z))
	return result


static func _area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon.size(): area += polygon[i].cross(polygon[(i+1)%polygon.size()])
	return area*0.5


static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0],Vector2.ZERO)
	for point in polygon: result=result.expand(point)
	return result


static func _index(index: Dictionary, bounds: Rect2, id: int) -> void:
	for x in range(floori(bounds.position.x/CELL_M),floori(bounds.end.x/CELL_M)+1):
		for z in range(floori(bounds.position.y/CELL_M),floori(bounds.end.y/CELL_M)+1):
			var cell := Vector2i(x,z)
			if not index.has(cell): index[cell]=[]
			index[cell].append(id)


static func _nearby(index: Dictionary, bounds: Rect2) -> Array[int]:
	var unique := {}
	for x in range(floori(bounds.position.x/CELL_M),floori(bounds.end.x/CELL_M)+1):
		for z in range(floori(bounds.position.y/CELL_M),floori(bounds.end.y/CELL_M)+1):
			for id in index.get(Vector2i(x,z),[]): unique[id]=true
	var result: Array[int] = []
	for id in unique: result.append(id)
	return result
