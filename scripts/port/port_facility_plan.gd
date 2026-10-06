class_name PortFacilityPlan
extends RefCounted

## JSON-safe initial facility parcels. Never rerun against an evolved saved graph.
const VERSION := 2
const STEP := 4.0
const ROAD_WIDTH := 7.0

static func build(foundation: Dictionary, berths: Dictionary, profile: PortTradeProfile, size: int) -> Dictionary:
	var original := points(foundation.get("spine",[]))
	if original.size()<2: return _build_aligned(foundation,berths,profile,size)
	var angle := (original[-1]-original[0]).angle()
	var aligned := foundation.duplicate(true)
	var aligned_berths := berths.duplicate(true)
	var rotated := PackedVector2Array()
	for p in original: rotated.append(p.rotated(-angle))
	aligned.spine=arrays(rotated)
	for station in aligned_berths.get("quay_stations",[]):
		var p := Vector2(station.origin[0],station.origin[1]).rotated(-angle)
		station.origin=[p.x,p.y]
	var result := _build_aligned(aligned,aligned_berths,profile,size)
	if not result.unmet.is_empty():
		var balanced := _build_aligned(aligned,aligned_berths,profile,size,true)
		if balanced.facilities.size()>result.facilities.size(): result=balanced
	for key in ["boundary","access_spine"]:
		rotated=PackedVector2Array()
		for p in points(result.get(key,[])): rotated.append(p.rotated(angle))
		result[key]=arrays(rotated)
	for facility in result.facilities:
		for key in ["origin","entry","road_connection"]:
			var p := Vector2(facility[key][0],facility[key][1]).rotated(angle)
			facility[key]=[p.x,p.y]
		facility.rotation_y-=angle
	for r in result.routes:
		for key in ["a","b"]:
			var p := Vector2(r[key][0],r[key][1]).rotated(angle)
			r[key]=[p.x,p.y]
	return result

static func parcel_polygon(facility: Dictionary) -> PackedVector2Array:
	var size := Vector2(facility.size_m[0],facility.size_m[1])*.5
	var center := Vector2(facility.origin[0],facility.origin[1])
	var result := PackedVector2Array()
	for p in [Vector2(-size.x,-size.y),Vector2(size.x,-size.y),size,Vector2(-size.x,size.y)]: result.append(center+p.rotated(-float(facility.get("rotation_y",0.0))))
	return result

static func parcel_fits(facility: Dictionary,boundary: PackedVector2Array) -> bool:
	var size := Vector2(facility.size_m[0],facility.size_m[1])
	var center := Vector2(facility.origin[0],facility.origin[1])
	var local_boundary := PackedVector2Array()
	for p in boundary: local_boundary.append((p-center).rotated(float(facility.get("rotation_y",0.0))))
	return rectangle_fits(Rect2(-size*.5,size),local_boundary)

static func _build_aligned(foundation: Dictionary, berths: Dictionary, profile: PortTradeProfile, size: int, balanced: bool=false) -> Dictionary:
	var spine := points(foundation.get("spine",[]))
	var result := {"version":VERSION,"facilities":[],"routes":[],"unmet":[],"boundary":[]}
	if spine.size()<2: return result
	var reach := float(foundation.get("dock_reach_m",26.0))+float(foundation.get("bay_lip_m",6.0))
	var sea := PortCoastTracer.offset_spine_perpendicular(spine,reach,Vector2.DOWN,false)
	var land := PortCoastTracer.offset_spine_perpendicular(spine,float(foundation.get("town_inland_m",88.0)),Vector2.DOWN,true)
	var boundary := sea.duplicate()
	for i in range(land.size()-1,-1,-1): boundary.append(land[i])
	result.boundary = arrays(boundary)
	var access := PortCoastTracer.offset_spine_perpendicular(spine,maxf(0,reach-10),Vector2.DOWN,false)
	result.access_spine = arrays(access)
	var bounds := Rect2(boundary[0],Vector2.ZERO)
	for p in boundary: bounds=bounds.expand(p)
	var routes: Array = result.routes
	for i in range(access.size()-1): routes.append(route("apron_%d"%i,access[i],access[i+1],ROAD_WIDTH))
	# One inland access stub, kept free before any parcel is selected.
	var gate_a := access[access.size()/2]
	var gate_b := gate_a
	for z in range(8,int(bounds.size.y),4):
		var next := gate_a+Vector2(0,z)
		if not corridor_fits(gate_a,next,ROAD_WIDTH,boundary): break
		gate_b=next
	if gate_a.distance_to(gate_b)>8: routes.append(route("land_access",gate_a,gate_b,ROAD_WIDTH))
	var rear := PortCoastTracer.offset_spine_perpendicular(spine,maxf(16,float(foundation.get("town_inland_m",88.0))-8),Vector2.DOWN,true)
	for i in rear.size()-1:
		if corridor_fits(rear[i],rear[i+1],ROAD_WIDTH,boundary): routes.append(route("rear_%d"%i,rear[i],rear[i+1],ROAD_WIDTH))
	var backbone := routes.duplicate(true)
	var jobs := needs(profile,size,berths)
	var occupied: Array[Rect2] = []
	for job in jobs:
		if balanced and job.kind in ["general","fishing","bulk_ore"]: job.sizes.reverse()
		if job.kind!="office" and job.berth_ids.is_empty():
			result.unmet.append({"kind":job.kind,"reason":"No realized compatible berth","commodity_ids":job.commodity_ids})
			continue
		var chosen := {}
		var best := INF
		for raw_size in job.sizes:
			var extent := Vector2(raw_size[0],raw_size[1])
			var focus := Vector2(job.focus[0],job.focus[1]) if job.has("focus") else gate_a
			# Rank cheap lower bounds first. Once none can beat the best score, stop;
			# polygon/road tests must not scan every lattice cell at every world port.
			var candidates: Array = []
			for xi in range(maxi(0,int(floor((bounds.size.x-extent.x)/STEP))+1)):
				for zi in range(maxi(0,int(floor((bounds.size.y-extent.y)/STEP))+1)):
					var center := bounds.position+Vector2(xi*STEP,zi*STEP)+extent*.5
					var lower := center.distance_to(focus)
					if job.kind=="office": lower+=(bounds.end.y-center.y-extent.y*.5)*.6
					candidates.append({"center":center,"lower":lower,"order":candidates.size()})
			candidates.sort_custom(func(a,b): return a.lower<b.lower if a.lower!=b.lower else a.order<b.order)
			for candidate in candidates:
				if float(candidate.lower)>=best: break
				var center: Vector2=candidate.center
				var rect := Rect2(center-extent*.5,extent)
				var blocked := false
				for other in occupied:
					if rect.grow(2).intersects(other): blocked=true; break
				if blocked: continue
				for r in routes:
					if segment_rect(points([r.a,r.b])[0],points([r.a,r.b])[1],rect.grow(float(r.width)*.5+1)):
						blocked=true; break
				if blocked: continue
				if not rectangle_fits(rect.grow(1.0),boundary): continue
				var entry := Vector2.INF
				var target := Vector2.INF
				var drive_distance := INF
				var yaw := 0.0
				for from_rear in [false,true]:
					if from_rear and job.kind=="office": continue
					var candidate_entry := Vector2(center.x,rect.end.y if from_rear else rect.position.y)
					for r in backbone:
						var q := Geometry2D.get_closest_point_to_segment(candidate_entry,Vector2(r.a[0],r.a[1]),Vector2(r.b[0],r.b[1]))
						if (from_rear and q.y<candidate_entry.y-.01) or (not from_rear and q.y>candidate_entry.y+.01): continue
						var distance := q.distance_to(candidate_entry)
						if distance>=drive_distance or not corridor_fits(candidate_entry,q,ROAD_WIDTH,boundary): continue
						var obstructed := false
						for other in occupied:
							if segment_rect(candidate_entry,q,other.grow(ROAD_WIDTH*.5+1)): obstructed=true; break
						if obstructed: continue
						entry=candidate_entry;target=q;drive_distance=distance;yaw=PI if from_rear else 0.0
				if entry==Vector2.INF: continue
				var score := center.distance_to(focus)+entry.distance_to(target)*.5
				if job.kind=="office": score += (bounds.end.y-rect.end.y)*.6
				if score>=best: continue
				best=score
				chosen={"id":"facility_"+job.kind,"kind":job.kind,"role":job.role,"commodity_ids":job.commodity_ids,
					"rotation_y":yaw,
					"served_berth_ids":job.berth_ids,"origin":[center.x,center.y],"size_m":[extent.x,extent.y],
					"entry":[entry.x,entry.y],"road_connection":[target.x,target.y],"phase":"initial"}
			if not chosen.is_empty(): break
		if chosen.is_empty():
			result.unmet.append({"kind":job.kind,"reason":"No supported parcel with clear road access","commodity_ids":job.commodity_ids})
			continue
		var c := Vector2(chosen.origin[0],chosen.origin[1])
		var e := Vector2(chosen.size_m[0],chosen.size_m[1])
		occupied.append(Rect2(c-e*.5,e))
		result.facilities.append(chosen)
		routes.append(route(chosen.id,Vector2(chosen.entry[0],chosen.entry[1]),Vector2(chosen.road_connection[0],chosen.road_connection[1]),ROAD_WIDTH))
	return result

static func needs(profile: PortTradeProfile, size: int, berths: Dictionary) -> Array[Dictionary]:
	var jobs: Array[Dictionary] = [{"kind":"office","role":"harbour_office","commodity_ids":[],"berth_ids":[],"sizes":[[48,48],[40,44]]}]
	if profile==null: return jobs
	var groups := {}
	for cid in profile.export_slots+profile.import_slots:
		var family := CommodityCatalog.commodity_terminal_family(cid)
		# Keep incompatible liquid products in separate facilities.
		var kind := cid if family=="liquid" else family
		if not groups.has(kind): groups[kind]=[]
		if not groups[kind].has(cid): groups[kind].append(cid)
	# Reserve large contiguous compounds before smaller sheds consume their frontage.
	var order := ["container","lng","crude_oil","diesel","bulk_grain","general","fishing","bulk_ore"]
	for kind in order:
		if not groups.has(kind): continue
		var extent := Vector2(64,56) if size>=2 else Vector2(48,44)
		var fallback := Vector2(40,40)
		if kind=="container": extent=Vector2(64,56); fallback=Vector2(40,40)
		if kind in ["lng","diesel","crude_oil"]: extent=Vector2(88,64); fallback=Vector2(64,56)
		if kind=="bulk_grain": extent=Vector2(72,56); fallback=Vector2(56,48)
		var job := {"kind":kind,"role":"general_warehouse" if kind=="general" else kind,
			"commodity_ids":groups[kind],"berth_ids":[],"sizes":[[extent.x,extent.y],[fallback.x,fallback.y]]}
		var sum := Vector2.ZERO
		for s in berths.get("quay_stations",[]):
			var compatible := false
			for cid in groups[kind]:
				if s.get("commodities",[]).has(cid): compatible=true
			if compatible:
				job.berth_ids.append(str(s.get("id","")))
				var o: Array = s.get("origin",[0,0]); sum+=Vector2(o[0],o[1])
		if not job.berth_ids.is_empty():
			sum/=job.berth_ids.size(); job.focus=[sum.x,sum.y]
		jobs.append(job)
	return jobs

static func route(id: String,a: Vector2,b: Vector2,width: float) -> Dictionary:
	return {"id":id,"a":[a.x,a.y],"b":[b.x,b.y],"width":width}

static func closest(p: Vector2,line: PackedVector2Array) -> Vector2:
	var best := line[0]
	for i in range(line.size()-1):
		var q := Geometry2D.get_closest_point_to_segment(p,line[i],line[i+1])
		if p.distance_squared_to(q)<p.distance_squared_to(best): best=q
	return best

static func rectangle_fits(rect: Rect2,polygon: PackedVector2Array) -> bool:
	var corners := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	for i in 4:
		var n := maxi(1,int(ceil(corners[i].distance_to(corners[(i+1)%4])/3.0)))
		for j in range(n+1):
			if not Geometry2D.is_point_in_polygon(corners[i].lerp(corners[(i+1)%4],float(j)/n),polygon): return false
	return true

static func corridor_fits(a: Vector2,b: Vector2,width: float,polygon: PackedVector2Array) -> bool:
	var side := (b-a).normalized().orthogonal()*width*.5
	var n := maxi(1,int(ceil(a.distance_to(b)/3.0)))
	for i in range(n+1):
		for offset in [-side,Vector2.ZERO,side]:
			if not Geometry2D.is_point_in_polygon(a.lerp(b,float(i)/n)+offset,polygon): return false
	return true

static func segment_rect(a: Vector2,b: Vector2,r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b): return true
	var c := [r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a,b,c[i],c[(i+1)%4])!=null: return true
	return false

static func points(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in raw: out.append(Vector2(float(p[0]),float(p[1])))
	return out

static func arrays(raw: PackedVector2Array) -> Array:
	var out: Array = []
	for p in raw: out.append([p.x,p.y])
	return out
