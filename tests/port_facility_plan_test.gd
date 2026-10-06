extends Node

var failed := false

func check(ok: bool,message: String) -> void:
	if not ok: failed=true; push_error(message)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var start := Time.get_ticks_msec()
	var profile := PortTradeProfile.new()
	profile.export_slots.assign(["provisions","containers","iron_ore","coal","grain","diesel","crude_oil","lng"])
	profile.import_slots.assign(["provisions","containers","fresh_groundfish","diesel"])
	var berths := {"quay_stations":[]}
	var seen := {}
	for cid in profile.export_slots+profile.import_slots:
		if seen.has(cid): continue
		seen[cid]=true
		berths.quay_stations.append({"id":"berth_"+cid,"family":CommodityCatalog.commodity_terminal_family(cid),"commodities":[cid],"origin":[seen.size()*24-120,-32]})
	var foundation := {"spine":[[-180,0],[-80,5],[0,20],[80,0],[180,-10]],"town_inland_m":110,"dock_reach_m":26,"bay_lip_m":6}
	var plan := PortFacilityPlan.build(foundation,berths,profile,5)
	check(plan.facilities.size()==9,"Office and all eight cargo facility families fit broad test site")
	print("UNMET ",plan.unmet)
	check(plan.unmet.is_empty(),"Broad site has no unmet facilities")
	check(JSON.stringify(plan)==JSON.stringify(PortFacilityPlan.build(foundation,berths,profile,5)),"Plan is deterministic")
	validate(plan)
	var kinds := {}
	for f in plan.facilities:
		check(not kinds.has(f.kind),"One shared facility per compatible group")
		kinds[f.kind]=true
		if f.kind=="general": check(f.commodity_ids.size()==1,"Import/export general cargo deduplicated")
		if f.kind=="bulk_ore": check(f.commodity_ids.size()==2,"Ore and coal share precinct with separate commodity IDs")
		if f.kind in ["diesel","crude_oil","lng"]:
			check(f.served_berth_ids==["berth_"+f.kind],"Liquid facility links only its product berth")
	var graph := PortLayoutGraph.new()
	graph.initial_attributes={"land_plan":{"facility_plan":plan},"foundation":foundation,"berth_plan":berths}
	var restored := PortLayoutGraph.from_dict(graph.to_dict())
	check(JSON.stringify(restored.initial_attributes)==JSON.stringify(graph.initial_attributes),"Graph round-trip retains exact facility record")
	var small := {"spine":[[-24,0],[24,0]],"town_inland_m":30,"dock_reach_m":12,"bay_lip_m":0}
	var constrained := PortFacilityPlan.build(small,berths,profile,0)
	validate(constrained)
	check(not constrained.unmet.is_empty(),"Constrained site reports unmet needs instead of overlap")
	var no_berth := PortFacilityPlan.build(foundation,{"quay_stations":[]},profile,0)
	check(no_berth.facilities.size()==1,"Missing berths cannot invent operational cargo facilities")
	verify_road_union()
	print("FACILITY PLAN fixtures=3 families=",plan.facilities.size()," constrained_unmet=",constrained.unmet.size()," elapsed_ms=",Time.get_ticks_msec()-start)
	if not failed: print("PORT FACILITY PLAN PASS")
	get_tree().quit(1 if failed else 0)

func verify_road_union() -> void:
	var root := Node3D.new()
	add_child(root)
	preload("res://scripts/port/harbour_road_surface.gd").build(root,[
		{"a":Vector3(-20,.03,0),"b":Vector3(20,.03,0),"width":7.0},
		{"a":Vector3(0,.03,-20),"b":Vector3(0,.03,20),"width":7.0}])
	var joined := root.find_children("JoinedRoadSurface","MeshInstance3D",false,false)
	check(joined.size()==1,"Crossroads has one joined surface")
	if joined.size()==1:
		var arrays: Array=joined[0].mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var area := 0.0
		for i in range(0,indices.size(),3):
			var a := vertices[indices[i]]; var b := vertices[indices[i+1]]; var c := vertices[indices[i+2]]
			area+=(b-a).cross(c-a).length()*.5
		check(absf(area-511.0)<.01,"Crossroad triangles cover the union exactly, without doubled junction faces")
	root.free()

func validate(plan: Dictionary) -> void:
	var polygon := PortFacilityPlan.points(plan.boundary)
	var rectangles: Array[Rect2] = []
	for f in plan.facilities:
		var size := Vector2(f.size_m[0],f.size_m[1])
		var rect := Rect2(Vector2(f.origin[0],f.origin[1])-size*.5,size)
		check(PortFacilityPlan.rectangle_fits(rect,polygon),"Parcel entirely supported by apron")
		for other in rectangles: check(not rect.intersects(other),"Parcels do not overlap")
		for r in plan.routes:
			# Its own connection stops on the parcel boundary.
			if r.id==f.id: continue
			check(not PortFacilityPlan.segment_rect(Vector2(r.a[0],r.a[1]),Vector2(r.b[0],r.b[1]),rect.grow(r.width*.5)),"Route clear of facility footprint")
		rectangles.append(rect)
