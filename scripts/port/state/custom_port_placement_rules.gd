class_name CustomPortPlacementRules
extends RefCounted

## Geometry validation independent of render nodes and physics. Metres throughout.
const EPS := .001
const SPATIAL_CELL_M := 8.0

static func validate(record: Dictionary, catalog: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	var shapes: Array[Dictionary] = []
	var platforms: Array[PackedVector2Array] = []
	var platform_index: Dictionary = {}
	for placement in record.get("placements",[]):
		if not placement is Dictionary: continue
		var values: Array = placement.get("position_m",[])
		if values.size()!=3: continue
		var yaw := float(placement.get("yaw_degrees",0))
		if not is_finite(yaw): continue
		if absf(float(values[1]))>EPS:
			errors.append("%s: placement must use the shared deck datum" % placement.get("id",""))
		var metadata := definition(placement,catalog)
		var kind := str(metadata.get("kind","decoration"))
		var rotation_step:=90.0 if kind=="platform" else 45.0
		if not is_equal_approx(fposmod(yaw,rotation_step),0):
			errors.append("%s: construction rotation must follow its %.0f degree grid" % [placement.get("id",""),rotation_step])
			continue
		var outlines := polygons(placement,metadata)
		var bounds: Array[Rect2] = []
		var total_bounds := Rect2()
		for outline in outlines:
			var box := polygon_bounds(outline)
			total_bounds = box if bounds.is_empty() else total_bounds.merge(box)
			bounds.append(box)
		var row := {"id":str(placement.get("id","")),"kind":kind,"meta":metadata,
			"position":Vector2(float(values[0]),float(values[2])),"yaw":yaw,
			"layer":str(metadata.get("placement_layer","platform" if kind=="platform" else "surface")),
			"polygons":outlines,"rects":bounds,"bounds":total_bounds}
		shapes.append(row)
		if kind=="platform":
			for polygon_index in outlines.size():
				_index_add(platform_index,bounds[polygon_index],platforms.size())
				platforms.append(outlines[polygon_index])
	var layers: Dictionary = {}
	for i in shapes.size():
		var row: Dictionary = shapes[i]
		if not layers.has(row.layer): layers[row.layer] = {}
		var layer_index: Dictionary = layers[row.layer]
		# Only nearby earlier shapes can overlap. Exact polygon intersection and
		# the existing corner-joint rule remain the final decisions.
		for j in _nearby(layer_index,row.bounds):
			var other: Dictionary = shapes[j]
			var collision := false
			for a_index in row.polygons.size():
				for b_index in other.polygons.size():
					var overlap: Rect2 = row.rects[a_index].intersection(other.rects[b_index])
					if overlap.size.x<=EPS or overlap.size.y<=EPS: continue
					if intersection_area(row.polygons[a_index],other.polygons[b_index])<=EPS: continue
					# Perpendicular 4m wall ends meet at the same corner socket.
					var wall_corner: bool = row.meta.get("placement_kind","")=="building" and other.meta.get("placement_kind","")=="building" \
						and not is_equal_approx(fposmod(row.yaw-other.yaw,180),0) and maxf(overlap.size.x,overlap.size.y)<=.5
					if not wall_corner: collision=true
			if collision: errors.append("%s overlaps %s" % [row.id,other.id])
		_index_add(layer_index,row.bounds,i)
		if row.kind=="platform" or not bool(row.meta.get("requires_support",false)): continue
		if str(row.meta.get("placement_kind",""))=="edge":
			var angle := deg_to_rad(float(row.yaw))
			var back: Vector2 = row.position+Vector2(sin(angle),cos(angle))*.25
			var support := rect_polygon(Rect2(back-Vector2.ONE*.05,Vector2.ONE*.1))
			if not polygon_covered(support,_nearby_platforms(support,platforms,platform_index)):
				errors.append("%s needs a supporting quay edge" % row.id)
		else:
			for polygon in row.polygons:
				if not polygon_covered(polygon,_nearby_platforms(polygon,platforms,platform_index)):
					errors.append("%s needs foundations beneath it" % row.id)
					break
	return errors

static func _index_add(index: Dictionary,bounds: Rect2,id: int) -> void:
	for cell in _cells(bounds):
		if not index.has(cell): index[cell] = []
		index[cell].append(id)

static func _nearby(index: Dictionary,bounds: Rect2) -> Array[int]:
	var unique: Dictionary = {}
	for cell in _cells(bounds):
		for id in index.get(cell,[]): unique[id] = true
	var result: Array[int] = []
	for id in unique: result.append(id)
	result.sort()
	return result

static func _cells(bounds: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(floori(bounds.position.x/SPATIAL_CELL_M),floori(bounds.end.x/SPATIAL_CELL_M)+1):
		for z in range(floori(bounds.position.y/SPATIAL_CELL_M),floori(bounds.end.y/SPATIAL_CELL_M)+1): result.append(Vector2i(x,z))
	return result

static func _nearby_platforms(polygon: PackedVector2Array,platforms: Array[PackedVector2Array],index: Dictionary) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for id in _nearby(index,polygon_bounds(polygon)): result.append(platforms[id])
	return result

static func definition(placement: Dictionary, catalog: Dictionary) -> Dictionary:
	var id := str(placement.get("asset_id",""))
	var result: Dictionary = (catalog.get(id,{}) as Dictionary).duplicate(true)
	if catalog.has("assets"):
		for entry in catalog.assets:
			if str(entry.get("id",""))==id: result=entry.duplicate(true); break
	result.merge(placement.get("attributes",{}),true)
	return result

static func rectangles(placement: Dictionary, metadata: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for polygon in polygons(placement,metadata): result.append(polygon_bounds(polygon))
	return result

static func polygons(placement: Dictionary, metadata: Dictionary) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var fp: Array = metadata.get("footprint_m",[1.0,1.0])
	if fp.size()!=2: return result
	var areas: Array = metadata.get("occupied_rects_m",[[-float(fp[0])*.5,-float(fp[1])*.5,float(fp[0]),float(fp[1])]])
	var at: Array = placement.get("position_m",[0,0,0])
	var angle := deg_to_rad(float(placement.get("yaw_degrees",0)))
	var source: Array[PackedVector2Array]=[]
	if metadata.has("footprint_polygon_m"):
		var outline:=PackedVector2Array()
		for point in metadata.footprint_polygon_m:
			if point is Array and point.size()==2: outline.append(Vector2(float(point[0]),float(point[1])))
		if outline.size()>=3: source.append(outline)
	else:
		for values in areas:
			if values is Array and values.size()==4: source.append(rect_polygon(Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))))
	for polygon in source:
		var transformed:=PackedVector2Array()
		for corner in polygon:
			transformed.append(Vector2(corner.x*cos(angle)+corner.y*sin(angle),-corner.x*sin(angle)+corner.y*cos(angle))+Vector2(float(at[0]),float(at[2])))
		result.append(transformed)
	return result

static func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

static func polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty(): return Rect2()
	var result:=Rect2(polygon[0],Vector2.ZERO)
	for point in polygon: result=result.expand(point)
	return result

static func polygon_area(polygon: PackedVector2Array) -> float:
	var twice:=0.0
	for i in polygon.size(): twice+=polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(twice)*.5

static func intersection_area(a: PackedVector2Array,b: PackedVector2Array) -> float:
	if not polygon_bounds(a).intersects(polygon_bounds(b)): return 0
	var area:=0.0
	for part in Geometry2D.intersect_polygons(a,b): area+=polygon_area(part)
	return area

## Platforms and plots cannot overlap, so summing clipped intersection area
## proves coverage without treating a triangular corner as a filled square.
static func polygon_covered(polygon: PackedVector2Array,surfaces: Array[PackedVector2Array]) -> bool:
	var needed:=polygon_area(polygon)
	if needed<=EPS: return false
	var covered_area:=0.0
	var bounds:=polygon_bounds(polygon)
	for surface in surfaces:
		if not bounds.intersects(polygon_bounds(surface)): continue
		covered_area+=intersection_area(polygon,surface)
	return covered_area>=needed-maxf(EPS,needed*.00001)

static func placement_within_plots(placement: Dictionary,catalog: Dictionary,plots: Array) -> bool:
	var surfaces: Array[PackedVector2Array]=[]
	for plot in plots:
		var r: Array=plot.get("rect_m",[])
		if r.size()==4: surfaces.append(rect_polygon(Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))))
	for polygon in polygons(placement,definition(placement,catalog)):
		if not polygon_covered(polygon,surfaces): return false
	return true

## Exact rectangle union coverage, including holes. No terrain or scene queries.
static func covered(area: Rect2, surfaces: Array[Rect2]) -> bool:
	var xs: Array[float] = [area.position.x,area.end.x]
	var clipped: Array[Rect2] = []
	for surface in surfaces:
		var intersection := surface.intersection(area)
		if not intersection.has_area(): continue
		clipped.append(intersection)
		xs.append(intersection.position.x); xs.append(intersection.end.x)
	xs.sort()
	for i in range(xs.size()-1):
		if xs[i+1]-xs[i]<EPS: continue
		var middle := (xs[i]+xs[i+1])*.5
		var intervals: Array[Vector2] = []
		for rect in clipped:
			if middle>=rect.position.x-EPS and middle<=rect.end.x+EPS:
				intervals.append(Vector2(rect.position.y,rect.end.y))
		intervals.sort_custom(func(a: Vector2,b: Vector2)->bool:return a.x<b.x)
		var end := area.position.y
		for interval in intervals:
			if interval.x>end+EPS: return false
			end=maxf(end,interval.y)
		if end<area.end.y-EPS: return false
	return true
