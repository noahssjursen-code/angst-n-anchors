extends RefCounted

## Conservative data-only candidates for a walking capsule at the shared deck.
## The host can refine these against current colliders (cargo, open doors, NPCs).
const RULES = preload("res://scripts/port/state/custom_port_placement_rules.gd")
const FOOT_LIFT := 0.15

static func prepare(snapshot: Dictionary, catalog: Dictionary, radius:=0.35, height:=1.8) -> Dictionary:
	var result: Dictionary={"platforms":[],"platform_index":{},"blockers":[],"blocker_index":{},"half_width":radius+0.05}
	for placement in snapshot.get("placements",[]):
		var spec: Dictionary=RULES.definition(placement,catalog)
		if str(spec.get("kind",""))=="platform":
			for polygon in RULES.polygons(placement,spec):_add_shape(result,"platform",polygon)
			continue
		if spec.has("door"):
			# Moving-node colliders are expressed in their authored hinge frame.
			# Home can conservatively avoid the doorway; the live player safety
			# check uses its actual open/closed collider, not this footprint.
			for polygon in RULES.polygons(placement,spec):_add_shape(result,"blocker",polygon)
		elif spec.has("colliders"):
			for collider in spec.colliders:
				var at: Array=collider.get("position_m",[0,0,0])
				var size: Array=collider.get("size_m",[0,0,0])
				if float(at[1])+float(size[1])*.5<=FOOT_LIFT or float(at[1])-float(size[1])*.5>=FOOT_LIFT+height:continue
				var footprint: Dictionary={"occupied_rects_m":[[float(at[0])-float(size[0])*.5,float(at[2])-float(size[2])*.5,float(size[0]),float(size[2])]]}
				for polygon in RULES.polygons(placement,footprint):_add_shape(result,"blocker",polygon)
		else:
			var bounds: Dictionary=spec.get("bounds_m",{})
			var low: float=float(bounds.get("min",[0,0,0])[1])
			var high: float=float(bounds.get("max",[0,spec.get("height_m",3),0])[1])
			if high<=FOOT_LIFT or low>=FOOT_LIFT+height:continue
			for polygon in RULES.polygons(placement,spec):_add_shape(result,"blocker",polygon)
	return result

static func _add_shape(context: Dictionary, kind: String, polygon: PackedVector2Array) -> void:
	var shapes: Array=context[kind+"s"]
	RULES._index_add(context[kind+"_index"],RULES.polygon_bounds(polygon),shapes.size())
	shapes.append(polygon)

static func supported(context: Dictionary, point: Vector2) -> bool:
	var probe:=_probe(context,point)
	var nearby: Array[PackedVector2Array]=[]
	for index in RULES._nearby(context.platform_index,RULES.polygon_bounds(probe)):nearby.append(context.platforms[index])
	return RULES.polygon_covered(probe,nearby)

static func clear(context: Dictionary, point: Vector2) -> bool:
	var probe:=_probe(context,point)
	for index in RULES._nearby(context.blocker_index,RULES.polygon_bounds(probe)):
		if RULES.intersection_area(probe,context.blockers[index])>RULES.EPS:return false
	return true

static func find(context: Dictionary, runtime_clear:=Callable()) -> Dictionary:
	for polygon in context.platforms:
		var center:=Vector2.ZERO
		for point in polygon:center+=point
		center/=float(polygon.size())
		var candidates: Array[Vector2]=[center]
		var bounds:=RULES.polygon_bounds(polygon)
		# Search the interior on a 1m walking lattice, nearest to this tile's
		# centre first. Exact union coverage rejects holes and diagonal cutouts.
		var inset: float=context.half_width
		for z in range(ceili(bounds.position.y+inset),floori(bounds.end.y-inset)+1):
			for x in range(ceili(bounds.position.x+inset),floori(bounds.end.x-inset)+1):candidates.append(Vector2(x,z))
		candidates.sort_custom(func(a: Vector2,b: Vector2)->bool:
			var da:=a.distance_squared_to(center)
			var db:=b.distance_squared_to(center)
			if not is_equal_approx(da,db):return da<db
			return a.x<b.x if not is_equal_approx(a.x,b.x) else a.y<b.y)
		for point in candidates:
			if not supported(context,point) or not clear(context,point):continue
			var local:=Vector3(point.x,FOOT_LIFT,point.y)
			if runtime_clear.is_valid() and not runtime_clear.call(local):continue
			return {"ok":true,"local":local}
	return {"ok":false,"local":Vector3.ZERO}

static func _probe(context: Dictionary, point: Vector2) -> PackedVector2Array:
	var half: float=context.half_width
	return RULES.rect_polygon(Rect2(point-Vector2.ONE*half,Vector2.ONE*half*2.0))
